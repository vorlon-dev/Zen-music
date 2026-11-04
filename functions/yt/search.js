// ZenMusic · vorlon-dev
//
// Cloudflare Pages Function: GET /yt/search?q=...
// Asks YouTube Music for song results and returns a small JSON list:
//   { results: [{ id, title, artist, album, image, duration }] }
// Only search metadata passes through here. Audio is NOT proxied: the web
// player plays tracks with the official YouTube embedded player.

import { parseSearch, parseVideos } from '../_lib/yt.js';

const ENDPOINT = 'https://music.youtube.com/youtubei/v1/search?prettyPrint=false';
const VIDEO_ENDPOINT = 'https://www.youtube.com/youtubei/v1/search?prettyPrint=false';
// "Videos" filter, so playlists/channels/shorts shelves are skipped.
const VIDEOS_FILTER = 'EgIQAQ==';
const SONGS_FILTER = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

export async function onRequest({ request }) {
  if (request.method !== 'GET') return json({ error: 'method not allowed' }, 405);

  const params = new URL(request.url).searchParams;
  const q = (params.get('q') || '').trim();
  const video = params.get('type') === 'video';
  if (!q || q.length > 200) return json({ results: [] });

  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const clientVersion = `1.${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}.01.00`;

  try {
    const res = await fetch(video ? VIDEO_ENDPOINT : ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Origin: video ? 'https://www.youtube.com' : 'https://music.youtube.com',
        Referer: video ? 'https://www.youtube.com/' : 'https://music.youtube.com/',
        'User-Agent': UA,
      },
      body: JSON.stringify({
        context: {
          client: video
            ? { clientName: 'WEB', clientVersion: `2.${clientVersion.slice(2, 10)}.00.00`, hl: 'en', gl: 'US' }
            : { clientName: 'WEB_REMIX', clientVersion, hl: 'en', gl: 'US' },
        },
        query: q,
        ...(video ? { params: VIDEOS_FILTER } : { params: SONGS_FILTER }),
      }),
      cf: { cacheTtl: 300, cacheEverything: true },
    });
    if (!res.ok) return json({ error: 'upstream ' + res.status }, 502);
    const data = await res.json();
    return json({ results: video ? parseVideos(data) : parseSearch(data) }, 200, 300);
  } catch (_) {
    return json({ error: 'upstream unavailable' }, 502);
  }
}

function json(body, status = 200, maxAge = 0) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': maxAge ? `public, max-age=${maxAge}` : 'no-store',
    },
  });
}

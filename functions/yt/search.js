// ZenMusic · vorlon-dev
//
// Cloudflare Pages Function: GET /yt/search?q=...
// Asks YouTube Music for song results and returns a small JSON list:
//   { results: [{ id, title, artist, album, image, duration }] }
// Only search metadata passes through here. Audio is NOT proxied: the web
// player plays tracks with the official YouTube embedded player.

const ENDPOINT = 'https://music.youtube.com/youtubei/v1/search?prettyPrint=false';
const SONGS_FILTER = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

export async function onRequest({ request }) {
  if (request.method !== 'GET') return json({ error: 'method not allowed' }, 405);

  const q = (new URL(request.url).searchParams.get('q') || '').trim();
  if (!q || q.length > 200) return json({ results: [] });

  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const clientVersion = `1.${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}.01.00`;

  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Origin: 'https://music.youtube.com',
        Referer: 'https://music.youtube.com/',
        'User-Agent': UA,
      },
      body: JSON.stringify({
        context: {
          client: { clientName: 'WEB_REMIX', clientVersion, hl: 'en', gl: 'US' },
        },
        query: q,
        params: SONGS_FILTER,
      }),
      cf: { cacheTtl: 300, cacheEverything: true },
    });
    if (!res.ok) return json({ error: 'upstream ' + res.status }, 502);
    return json({ results: parseSearch(await res.json()) }, 200, 300);
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

// ---- parsing (exported for tests; Pages ignores other exports) ----------

function* walk(node, key) {
  if (Array.isArray(node)) {
    for (const v of node) yield* walk(v, key);
  } else if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      if (k === key) yield v;
      else yield* walk(v, key);
    }
  }
}

function firstValue(node, key) {
  for (const v of walk(node, key)) return v;
  return undefined;
}

const text = (runs) => (runs || []).map((r) => r.text || '').join('');

function groupRuns(runs) {
  const groups = [[]];
  for (const r of runs || []) {
    if ((r.text || '').trim() === '•') groups.push([]);
    else groups[groups.length - 1].push(r);
  }
  return groups.map(text).map((s) => s.trim()).filter(Boolean);
}

function toSeconds(s) {
  const parts = s.split(':').map(Number);
  if (parts.some(Number.isNaN)) return 0;
  return parts.reduce((acc, n) => acc * 60 + n, 0);
}

export function parseSearch(data) {
  const out = [];
  const seen = new Set();
  for (const r of walk(data, 'musicResponsiveListItemRenderer')) {
    const id =
      (r.playlistItemData && r.playlistItemData.videoId) ||
      firstValue(r, 'videoId');
    if (!id || seen.has(id)) continue;

    const cols = (r.flexColumns || []).map(
      (c) =>
        (c.musicResponsiveListItemFlexColumnRenderer &&
          c.musicResponsiveListItemFlexColumnRenderer.text &&
          c.musicResponsiveListItemFlexColumnRenderer.text.runs) ||
        [],
    );
    const title = text(cols[0]).trim();
    if (!title) continue;

    let groups = groupRuns(cols[1]);
    if (groups.length && /^(song|video)$/i.test(groups[0])) groups = groups.slice(1);
    const last = groups[groups.length - 1] || '';
    const hasTime = /^\d{1,2}(:\d{2}){1,2}$/.test(last);
    const duration = hasTime ? toSeconds(last) : 0;
    if (hasTime) groups = groups.slice(0, -1);

    const thumbs = firstValue(r.thumbnail || {}, 'thumbnails') || [];
    let image = thumbs.length ? thumbs[thumbs.length - 1].url || '' : '';
    image = image.replace(/=w\d+-h\d+[^&]*$/, '=w512-h512');

    seen.add(id);
    out.push({
      id,
      title,
      artist: groups[0] || '',
      album: groups[1] || '',
      image,
      duration,
    });
  }
  return out;
}

// ZenMusic · vorlon-dev
//
// Public JSON API (Cloudflare Pages Function), mounted at /v1/*.
// One format for JioSaavn, YouTube Music and YouTube:
//
//   GET /v1                                  endpoint list
//   GET /v1/search?source=jio|ytm|yt&q=...&type=song|album|playlist
//   GET /v1/song?source=jio&id=...           (JioSaavn: direct stream links)
//   GET /v1/playlist?source=jio|ytm|yt&id=...
//   GET /v1/album?source=jio&id=...
//
// YouTube / YouTube Music items carry `playback.type = "youtube"` with the
// video id and the official embed URL. This API does not extract or proxy
// YouTube audio and does not mint PO tokens.
//
// Optional settings (Pages > Settings > Environment variables):
//   API_KEY       when set, requests need header `x-api-key` or `?key=`
//   JIO_UPSTREAM  base URL of the JioSaavn API worker

import {
  parsePlaylistTitle,
  parsePlaylistVideos,
  parseSearch,
  parseVideos,
} from '../_lib/yt.js';

const JIO_DEFAULT = 'https://jiosaavn-api.vorlon-revora.workers.dev';
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const SONGS_FILTER = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';
const VIDEOS_FILTER = 'EgIQAQ==';
const ID = /^[A-Za-z0-9_-]{1,64}$/;

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export async function onRequest({ request, env }) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: cors() });
  }
  if (request.method !== 'GET') return fail(405, 'Method not allowed');

  try {
    const url = new URL(request.url);
    const key = env && env.API_KEY;
    if (key) {
      const given = request.headers.get('x-api-key') || url.searchParams.get('key');
      if (given !== key) throw new ApiError(401, 'Missing or invalid API key');
    }
    const route = url.pathname.replace(/^\/v1\/?/, '').replace(/\/+$/, '');
    const q = url.searchParams;
    const jio = (env && env.JIO_UPSTREAM) || JIO_DEFAULT;

    switch (route) {
      case '':
        return ok(index());
      case 'search':
        return ok(await search(jio, source(q), q.get('q'), q.get('type') || 'song'), 300);
      case 'song':
        return ok(await song(jio, source(q), id(q)), 300);
      case 'playlist':
        return ok(await playlist(jio, source(q), id(q), false), 300);
      case 'album':
        return ok(await playlist(jio, source(q), id(q), true), 300);
      default:
        throw new ApiError(404, 'Unknown endpoint. See GET /v1');
    }
  } catch (e) {
    if (e instanceof ApiError) return fail(e.status, e.message);
    return fail(502, 'Upstream unavailable');
  }
}

// ---- responses ------------------------------------------------------------

function cors() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'x-api-key, content-type',
  };
}

function ok(data, maxAge = 0) {
  return new Response(JSON.stringify({ ok: true, data }), {
    headers: {
      ...cors(),
      'Content-Type': 'application/json',
      'Cache-Control': maxAge ? `public, max-age=${maxAge}` : 'no-store',
    },
  });
}

function fail(status, error) {
  return new Response(JSON.stringify({ ok: false, error }), {
    status,
    headers: { ...cors(), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function index() {
  return {
    name: 'ZenMusic API',
    version: 1,
    endpoints: {
      search: '/v1/search?source=jio|ytm|yt&q=QUERY&type=song|album|playlist (album/playlist: jio only)',
      song: '/v1/song?source=jio&id=ID',
      playlist: '/v1/playlist?source=jio|ytm|yt&id=ID',
      album: '/v1/album?source=jio&id=ID',
    },
    playback: {
      direct: 'JioSaavn: playback.url is a direct audio link (plus playback.streams by quality).',
      youtube: 'YouTube / YouTube Music: play videoId with the official YouTube embedded player (embedUrl).',
    },
  };
}

// ---- input ----------------------------------------------------------------

function source(q) {
  const s = (q.get('source') || '').toLowerCase();
  if (!['jio', 'ytm', 'yt'].includes(s)) {
    throw new ApiError(400, 'source must be jio, ytm or yt');
  }
  return s;
}

function id(q) {
  const v = q.get('id') || '';
  if (!ID.test(v)) throw new ApiError(400, 'id is missing or invalid');
  return v;
}

// ---- JioSaavn ---------------------------------------------------------------

async function getJson(url, init) {
  const res = await fetch(url, { ...init, cf: { cacheTtl: 300, cacheEverything: true } });
  if (!res.ok) throw new ApiError(502, `Upstream returned ${res.status}`);
  return res.json();
}

const decode = (s) =>
  String(s || '')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

const https = (u) => (u && u.startsWith('http://') ? 'https://' + u.slice(7) : u || '');

function bestImage(list) {
  if (!Array.isArray(list) || !list.length) return '';
  const size = (e) => parseInt(String(e.quality).split('x')[0], 10) || 0;
  return https([...list].sort((a, b) => size(a) - size(b)).pop().url);
}

function jioSong(o) {
  const artists = Array.isArray(o.artists)
    ? o.artists
    : (o.artists && o.artists.primary) || [];
  const streams = (Array.isArray(o.downloadUrl) ? o.downloadUrl : [])
    .filter((d) => d && d.url)
    .map((d) => ({ quality: String(d.quality), url: https(d.url) }));
  const rate = (s) => parseInt(s.quality, 10) || 0;
  const best = [...streams].sort((a, b) => rate(a) - rate(b)).pop();
  return {
    id: String(o.id),
    source: 'jio',
    title: decode(o.name || o.title),
    artist: artists.map((a) => decode(a.name)).filter(Boolean).join(', '),
    album: decode(o.album && o.album.name),
    image: bestImage(o.image),
    duration: parseInt(o.duration, 10) || 0,
    playback: { type: 'direct', url: best ? best.url : '', streams },
  };
}

function jioCollection(o, kind) {
  return {
    id: String(o.id),
    source: 'jio',
    kind,
    title: decode(o.name || o.title),
    subtitle: decode(o.subtitle || o.description || ''),
    image: bestImage(o.image),
  };
}

// ---- YouTube / YouTube Music --------------------------------------------------

function ytSong(item, src) {
  return {
    id: item.id,
    source: src,
    title: item.title,
    artist: item.artist,
    album: item.album,
    image: item.image,
    duration: item.duration,
    playback: {
      type: 'youtube',
      videoId: item.id,
      embedUrl: `https://www.youtube.com/embed/${item.id}`,
    },
  };
}

async function innertube(music, path, body) {
  const host = music ? 'https://music.youtube.com' : 'https://www.youtube.com';
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const date = `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`;
  const client = music
    ? { clientName: 'WEB_REMIX', clientVersion: `1.${date}.01.00`, hl: 'en', gl: 'US' }
    : { clientName: 'WEB', clientVersion: `2.${date}.00.00`, hl: 'en', gl: 'US' };
  return getJson(`${host}/youtubei/v1/${path}?prettyPrint=false`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Origin: host,
      Referer: host + '/',
      'User-Agent': UA,
    },
    body: JSON.stringify({ context: { client }, ...body }),
  });
}

// ---- operations ---------------------------------------------------------------

async function search(jio, src, query, type) {
  const q = (query || '').trim();
  if (!q || q.length > 200) throw new ApiError(400, 'q is missing or too long');
  if (!['song', 'album', 'playlist'].includes(type)) {
    throw new ApiError(400, 'type must be song, album or playlist');
  }
  if (src === 'jio') {
    const path = { song: 'songs', album: 'albums', playlist: 'playlists' }[type];
    const json = await getJson(
      `${jio}/api/search/${path}?` + new URLSearchParams({ query: q, limit: '20', page: '0' }),
    );
    const results = (json && json.data && json.data.results) || [];
    return {
      type,
      results: results.map((o) => (type === 'song' ? jioSong(o) : jioCollection(o, type))),
    };
  }
  if (type !== 'song') throw new ApiError(400, 'YouTube sources only support type=song');
  if (src === 'ytm') {
    const json = await innertube(true, 'search', { query: q, params: SONGS_FILTER });
    return { type, results: parseSearch(json).map((i) => ytSong(i, 'ytm')) };
  }
  const json = await innertube(false, 'search', { query: q, params: VIDEOS_FILTER });
  return { type, results: parseVideos(json).map((i) => ytSong(i, 'yt')) };
}

async function song(jio, src, songId) {
  if (src !== 'jio') {
    throw new ApiError(400, 'song lookup supports source=jio; for YouTube use the video id from search');
  }
  const json = await getJson(`${jio}/api/songs/${encodeURIComponent(songId)}`);
  const list = json && json.data;
  if (!Array.isArray(list) || !list.length) throw new ApiError(404, 'Song not found');
  return jioSong(list[0]);
}

async function playlist(jio, src, listId, album) {
  if (src === 'jio') {
    const json = await getJson(
      `${jio}/api/${album ? 'albums' : 'playlists'}?` +
        new URLSearchParams({ id: listId, limit: '100' }),
    );
    const d = json && json.data;
    if (!d) throw new ApiError(404, 'Not found');
    return {
      ...jioCollection(d, album ? 'album' : 'playlist'),
      songs: (Array.isArray(d.songs) ? d.songs : []).map(jioSong),
    };
  }
  if (album) throw new ApiError(400, 'album lookup supports source=jio');
  const browseId = listId.startsWith('VL') ? listId : 'VL' + listId;
  if (src === 'ytm') {
    const json = await innertube(true, 'browse', { browseId });
    return {
      id: listId,
      source: 'ytm',
      kind: 'playlist',
      title: parsePlaylistTitle(json),
      songs: parseSearch(json).map((i) => ytSong(i, 'ytm')),
    };
  }
  const json = await innertube(false, 'browse', { browseId });
  return {
    id: listId,
    source: 'yt',
    kind: 'playlist',
    title: parsePlaylistTitle(json),
    songs: parsePlaylistVideos(json).map((i) => ytSong(i, 'yt')),
  };
}

import { onRequest } from '../../functions/v1/[[path]].js';
import assert from 'node:assert';
const jioSong = { id: 'j1', name: 'A &amp; B', artists: { primary: [{ name: 'X' }, { name: 'Y' }] }, album: { name: 'Alb' }, duration: '200',
  image: [{ quality: '50x50', url: 'http://i/50' }, { quality: '500x500', url: 'http://i/500' }],
  downloadUrl: [{ quality: '96kbps', url: 'http://c/96' }, { quality: '320kbps', url: 'http://c/320' }, { quality: '160kbps', url: 'http://c/160' }] };
const run = (t) => ({ text: t });
const ytmItem = { musicResponsiveListItemRenderer: { playlistItemData: { videoId: 'm1' },
  flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [run('Song M')] } } }, { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [run('Art')] } } }, { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [run('Album M')] } } }],
  fixedColumns: [{ musicResponsiveListItemFixedColumnRenderer: { text: { runs: [run('3:10')] } } }] } };
const calls = [];
globalThis.fetch = async (url, init) => {
  const u = String(url); calls.push(u);
  const j = (o) => new Response(JSON.stringify(o), { status: 200 });
  if (u.includes('/api/search/songs')) return j({ data: { results: [jioSong] } });
  if (u.includes('/api/songs/j1')) return j({ data: [jioSong] });
  if (u.includes('/api/playlists')) return j({ data: { id: 'p1', name: 'PL', image: [], songs: [jioSong] } });
  if (u.includes('music.youtube.com') && u.includes('/browse')) return j({ header: { title: { runs: [run('YTM PL')] } }, c: [ytmItem] });
  if (u.includes('music.youtube.com') && u.includes('/search')) return j({ c: [ytmItem] });
  if (u.includes('www.youtube.com') && u.includes('/browse')) return j({ title: { simpleText: 'YT PL' }, c: [{ playlistVideoRenderer: { videoId: 'y1', title: { runs: [run('Vid')] }, shortBylineText: { runs: [run('Chan')] }, lengthSeconds: '99', thumbnail: { thumbnails: [{ url: 't' }] } } }] });
  if (u.includes('www.youtube.com') && u.includes('/search')) return j({ c: [{ videoRenderer: { videoId: 'y2', title: { runs: [run('V2')] }, ownerText: { runs: [run('C')] }, lengthText: { simpleText: '1:00' } } }] });
  return new Response('{}', { status: 404 });
};
const get = async (path, env = {}, headers = {}) => { const r = await onRequest({ request: new Request('https://x.dev' + path, { headers }), env }); return { s: r.status, b: await r.json() }; };

let r = await get('/v1'); assert(r.b.ok && r.b.data.endpoints.search);
r = await get('/v1/search?source=zzz&q=a'); assert.equal(r.s, 400);
r = await get('/v1/search?source=jio&q=hello'); assert.equal(r.b.data.results[0].title, 'A & B'); assert.equal(r.b.data.results[0].playback.url, 'https://c/320'); assert.equal(r.b.data.results[0].artist, 'X, Y'); assert.equal(r.b.data.results[0].image, 'https://i/500');
r = await get('/v1/song?source=jio&id=j1'); assert.equal(r.b.data.id, 'j1');
r = await get('/v1/song?source=ytm&id=m1'); assert.equal(r.s, 400);
r = await get('/v1/playlist?source=jio&id=p1'); assert.equal(r.b.data.songs.length, 1); assert.equal(r.b.data.title, 'PL');
r = await get('/v1/search?source=ytm&q=x'); assert.equal(r.b.data.results[0].playback.type, 'youtube'); assert.equal(r.b.data.results[0].playback.embedUrl, 'https://www.youtube.com/embed/m1');
r = await get('/v1/playlist?source=ytm&id=PLabc'); assert.equal(r.b.data.songs[0].duration, 190); assert.equal(r.b.data.songs[0].album, 'Album M'); assert.equal(r.b.data.title, 'YTM PL');
assert(calls.some(c => c.includes('/youtubei/v1/browse')));
r = await get('/v1/playlist?source=yt&id=PLxyz'); assert.equal(r.b.data.songs[0].id, 'y1'); assert.equal(r.b.data.songs[0].duration, 99); assert.equal(r.b.data.title, 'YT PL');
r = await get('/v1/search?source=yt&q=x'); assert.equal(r.b.data.results[0].duration, 60);
r = await get('/v1/search?source=yt&q=x&type=album'); assert.equal(r.s, 400);
r = await get('/v1/playlist?source=jio&id=bad%20id'); assert.equal(r.s, 400);
r = await get('/v1/nope'); assert.equal(r.s, 404);
r = await get('/v1/search?source=jio&q=a', { API_KEY: 'k' }); assert.equal(r.s, 401);
r = await get('/v1/search?source=jio&q=a', { API_KEY: 'k' }, { 'x-api-key': 'k' }); assert.equal(r.s, 200);
console.log('ALL API TESTS PASSED');

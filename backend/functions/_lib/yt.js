// ZenMusic · vorlon-dev
//
// Shared parsers for YouTube / YouTube Music InnerTube responses.
// Pure functions, no network: used by functions/yt and functions/v1.


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
    let duration = hasTime ? toSeconds(last) : 0;
    if (hasTime) groups = groups.slice(0, -1);
    // Playlist pages keep the length in a separate fixed column.
    if (!duration) {
      const fixed = r.fixedColumns && r.fixedColumns[0] &&
        r.fixedColumns[0].musicResponsiveListItemFixedColumnRenderer;
      const t = fixed && fixed.text && text(fixed.text.runs).trim();
      if (t && /^\d{1,2}(:\d{2}){1,2}$/.test(t)) duration = toSeconds(t);
    }

    const thumbs = firstValue(r.thumbnail || {}, 'thumbnails') || [];
    let image = thumbs.length ? thumbs[thumbs.length - 1].url || '' : '';
    image = image.replace(/=w\d+-h\d+[^&]*$/, '=w512-h512');

    seen.add(id);
    out.push({
      id,
      title,
      artist: groups[0] || '',
      album: groups[1] || text(cols[2]).trim(),
      image,
      duration,
    });
  }
  return out;
}

// Plain YouTube video results (videoRenderer).
export function parseVideos(data) {
  const out = [];
  const seen = new Set();
  for (const v of walk(data, 'videoRenderer')) {
    const id = v && v.videoId;
    if (!id || seen.has(id)) continue;
    const title = text(v.title && v.title.runs).trim();
    if (!title) continue;
    const owner = text(v.ownerText && v.ownerText.runs).trim() ||
      text(v.longBylineText && v.longBylineText.runs).trim();
    const length = (v.lengthText && v.lengthText.simpleText) || '';
    const duration = /^\d{1,2}(:\d{2}){1,2}$/.test(length) ? toSeconds(length) : 0;
    const thumbs = (v.thumbnail && v.thumbnail.thumbnails) || [];
    const image = thumbs.length ? thumbs[thumbs.length - 1].url || '' : '';
    seen.add(id);
    out.push({ id, title, artist: owner, album: '', image, duration });
  }
  return out;
}

// Videos inside a YouTube playlist page (playlistVideoRenderer).
export function parsePlaylistVideos(data) {
  const out = [];
  const seen = new Set();
  for (const v of walk(data, 'playlistVideoRenderer')) {
    const id = v && v.videoId;
    if (!id || seen.has(id)) continue;
    const title = text(v.title && v.title.runs).trim();
    if (!title) continue;
    const thumbs = (v.thumbnail && v.thumbnail.thumbnails) || [];
    seen.add(id);
    out.push({
      id,
      title,
      artist: text(v.shortBylineText && v.shortBylineText.runs).trim(),
      album: '',
      image: thumbs.length ? thumbs[thumbs.length - 1].url || '' : '',
      duration: parseInt(v.lengthSeconds, 10) || 0,
    });
  }
  return out;
}

/** Title of a playlist page, if present. */
export function parsePlaylistTitle(data) {
  const t = firstValue(data, 'title');
  if (t && t.runs) return text(t.runs).trim();
  if (t && t.simpleText) return String(t.simpleText).trim();
  return '';
}

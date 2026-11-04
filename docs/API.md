# ZenMusic API (v1)

A small JSON API served by the Cloudflare Pages Function in `backend/functions/v1`, so other apps can search and read playlists from **JioSaavn**, **YouTube Music** and **YouTube** in one format.

Base URL: `https://<your-pages-domain>/v1`

Every response is `{ "ok": true, "data": ... }` or `{ "ok": false, "error": "..." }`. CORS is open.

| Endpoint | Description |
|---|---|
| `GET /v1` | List of endpoints |
| `GET /v1/search?source=jio\|ytm\|yt&q=QUERY&type=song\|album\|playlist` | Search. `album` and `playlist` are JioSaavn only |
| `GET /v1/song?source=jio&id=ID` | One JioSaavn song with stream links |
| `GET /v1/playlist?source=jio\|ytm\|yt&id=ID` | Playlist with its songs (first page, ~100) |
| `GET /v1/album?source=jio&id=ID` | JioSaavn album with its songs |

## Song object

```json
{
  "id": "…", "source": "jio|ytm|yt", "title": "…", "artist": "A, B",
  "album": "…", "image": "https://…", "duration": 215,
  "playback": { }
}
```

`playback` depends on the source:

- **JioSaavn:** `{ "type": "direct", "url": "https://…", "streams": [{ "quality": "320kbps", "url": "…" }] }`. Play `url` with any audio player.
- **YouTube / YouTube Music:** `{ "type": "youtube", "videoId": "…", "embedUrl": "https://www.youtube.com/embed/…" }`. Play it with the official YouTube player (IFrame API, or a WebView in an app).

## Not included

The API does not extract or proxy YouTube audio and does not generate PO tokens. Doing that circumvents YouTube's protections, breaks its terms, uses large amounts of bandwidth and can get the hosting account suspended. Use the embedded player for YouTube items.

## Optional protection

Set `API_KEY` in the Pages project's environment variables to require `x-api-key: <key>` (or `?key=`) on every request. Set `JIO_UPSTREAM` to use a different JioSaavn API worker.

## Notes

- Results are cached for 5 minutes at the edge.
- YouTube parsing uses undocumented web endpoints and can break when YouTube changes them.
- Self-hosting guide: [SELF_HOSTING.md](SELF_HOSTING.md). Kotlin client: [`zen-kit`](../zen-kit/README.md).
- Tests: `node test/api/v1.test.mjs` (mocked network).
- Please respect the rights of artists and the terms of the services you connect to.

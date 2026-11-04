# ZenMusic backend (self-hosted)

The folder you deploy to your own Cloudflare account. It serves **data only** (search, playlists, albums, song metadata and JioSaavn links) as JSON. Stream resolving, signature solving and the PO token run on the device, inside [`zen-kit`](../zen-kit/README.md).

```
backend/
  functions/      Cloudflare Pages Functions
    v1/           public API  (docs/API.md)
    api/          JioSaavn proxy used by the web player
    yt/           YouTube search used by the web player
    _lib/         shared parsers
  public/         landing page
  wrangler.toml
```

## Deploy on its own (about 5 minutes)

1. Install Node.js, then log in: `npx wrangler login`
2. From this folder: `npx wrangler pages deploy public --project-name=my-zen-music`
3. In the Cloudflare dashboard open **Workers & Pages > my-zen-music > Settings > Variables and Secrets** and add a **secret** `API_KEY` (a long random value). Optional variable `JIO_UPSTREAM`.
4. Deploy again so the variables apply, then test:

```bash
curl -H "x-api-key: YOUR_KEY" "https://my-zen-music.pages.dev/v1/search?source=jio&q=arijit"
```

Deploying the whole repository through GitHub Actions instead: [docs/SELF_HOSTING.md](../docs/SELF_HOSTING.md).

## Use it from the app

Put the URL (and key) in `MainActivity.kt`:

```kotlin
private const val ZEN_BACKEND_URL = "https://my-zen-music.pages.dev"
private const val ZEN_BACKEND_KEY = "YOUR_KEY"
```

Then use `ZenKit.api` from Kotlin ([zen-kit README](../zen-kit/README.md)).

## Tests

`node test/api/v1.test.mjs` from the repository root (mocked network).

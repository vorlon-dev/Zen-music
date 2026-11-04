# Self-hosting the ZenMusic API on Cloudflare

You can run your own copy of the API (`/v1/...`, see [API.md](API.md)) on a free Cloudflare account. Then your apps only talk to **your** endpoint and you do not depend on anyone else's public server.

Everything on the client side is Kotlin: see [`zen-kit`](../zen-kit/README.md).

## What you need

- A GitHub account and a Cloudflare account (the free plans are enough)
- About 10 minutes

## 1. Fork the repository

Fork `vorlon-dev/Zen-music` on GitHub. The API lives in the [`backend/`](../backend/README.md) folder and is deployed together with the web player by `.github/workflows/web.yml`. You can also deploy `backend/` on its own (see its README).

## 2. Create the Cloudflare token and find the account ID

1. Cloudflare dashboard > **My Profile > API Tokens > Create Token** > template **Edit Cloudflare Workers** (it includes Pages edit). Create it and copy it once.
2. Your **Account ID** is in the dashboard URL (`dash.cloudflare.com/<ACCOUNT_ID>/...`) and in the Workers & Pages sidebar.

Never paste the token anywhere except the GitHub secret below.

## 3. Add the GitHub secrets

In your fork: **Settings > Secrets and variables > Actions**.

| Name | Type | Value |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | secret | the token |
| `CLOUDFLARE_ACCOUNT_ID` | secret | your account ID |
| `CLOUDFLARE_PROJECT` | variable | a unique project name, for example `my-zen-music` |

The site and API will be at `https://<CLOUDFLARE_PROJECT>.pages.dev`.

## 4. Deploy

Open **Actions > Web Player > Run workflow**. The workflow runs the tests, builds the web player and deploys everything, including `backend/functions`. If the Pages project does not exist yet, it is created.

Prefer the command line? After `flutter build web -t lib/web/web_main.dart --release`, copy `backend/functions` to `functions` in the repository root and run `npx wrangler pages deploy build/web --project-name=<name>`.

## 5. Protect it with an API key (recommended)

Cloudflare dashboard > **Workers & Pages > your project > Settings > Variables and Secrets > Add** a **secret** named `API_KEY` with a long random value (for example `openssl rand -hex 24`). Redeploy (run the workflow again).

From then on every request needs the header `x-api-key: <value>` (or `?key=<value>`). The web player on the same site is not affected because it uses `/api` and `/yt`, not `/v1`.

Optional variable `JIO_UPSTREAM`: base URL of your own JioSaavn API worker, if you do not want to use the default one.

## 6. Test

```bash
curl -H "x-api-key: YOUR_KEY" "https://my-zen-music.pages.dev/v1/search?source=jio&q=arijit"
curl -H "x-api-key: YOUR_KEY" "https://my-zen-music.pages.dev/v1/search?source=ytm&q=arijit"
curl -H "x-api-key: YOUR_KEY" "https://my-zen-music.pages.dev/v1/playlist?source=yt&id=PLxxxxxxxx"
```

You should get `{"ok":true,"data":...}`.

## 7. Connect your app

Copy `zen-kit/` and `innertube/` into your project, add the Gradle lines and put your URL in `MainActivity`. Step by step: [`zen-kit/README.md`](../zen-kit/README.md).

```kotlin
ZenKit.init(this, backendUrl = "https://my-zen-music.pages.dev", apiKey = "YOUR_KEY")
val songs = ZenKit.api.searchSongs(Source.JIO, "arijit")   // off the main thread
```

## What about PO tokens?

Your backend has **no** PO token files and never returns raw YouTube audio URLs. Everything that needs a token runs in the app:

- The PO token is minted on the device by the bundled bridge in `zen-kit` (a hidden WebView). You do not place any token file anywhere.
- Stream resolving and signature solving also run on the device, so the stream link is valid for that device's IP address.
- The backend only fetches data: search results, playlists, albums, song details and JioSaavn links.

Why not on the server: tokens expire within minutes, YouTube stream links are tied to the IP that requested them (a link resolved on Cloudflare would not play on a phone), and relaying YouTube audio through Cloudflare breaks its terms and can get the account suspended.

Apps that do not use `zen-kit` can play YouTube items with the official embedded player: the API returns `embedUrl` for them.

## Costs and limits

The Cloudflare free plan allows 100,000 function requests per day. Responses are cached for 5 minutes, which helps. Only small JSON passes through your project; no audio does.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Project not found` in the workflow | Make sure `CLOUDFLARE_PROJECT` is set; the workflow creates the project on first run. If the name is taken, choose another. |
| `401 Missing or invalid API key` | Send the `x-api-key` header with the value of `API_KEY`. |
| `502 Upstream unavailable` | JioSaavn or YouTube did not answer; try again. YouTube pages can change and break parsing; open an issue with the request you made. |
| Empty YouTube results | Cloudflare IPs are sometimes rate limited by YouTube. Try again later. |

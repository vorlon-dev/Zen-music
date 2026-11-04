# Self-hosting the ZenMusic API on Cloudflare

You can run your own copy of the API (`/v1/...`, see [API.md](API.md)) on a free Cloudflare account. Then your apps only talk to **your** endpoint and you do not depend on anyone else's public server.

Everything on the client side is Kotlin: see [`zen-api-client`](../zen-api-client/README.md).

## What you need

- A GitHub account and a Cloudflare account (the free plans are enough)
- About 10 minutes

## 1. Fork the repository

Fork `vorlon-dev/Zen-music` on GitHub. The API lives in the `functions/` folder and is deployed together with the web player by `.github/workflows/web.yml`.

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

Open **Actions > Web Player > Run workflow**. The workflow runs the tests, builds the web player and deploys everything, including `functions/`. If the Pages project does not exist yet, it is created.

Prefer the command line? After `flutter build web -t lib/web/web_main.dart --release`, run `npx wrangler pages deploy build/web --project-name=<name>` from the repository root (the `functions/` folder is picked up automatically).

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

## 7. Use it from Kotlin

```kotlin
val api = ZenApi("https://my-zen-music.pages.dev", apiKey = "YOUR_KEY")

// run off the main thread
val songs = api.searchSongs(Source.JIO, "arijit")
when (val p = songs.first().playback) {
  is Playback.Direct -> player.play(p.url)            // any audio player (ExoPlayer, MediaPlayer...)
  is Playback.YouTube -> youtubePlayer.load(p.videoId) // official YouTube player
}

val playlist = api.playlist(Source.YTM, "PLxxxxxxxx")
```

Setup of the client module: [`zen-api-client/README.md`](../zen-api-client/README.md).

## What about PO tokens?

The API does **not** use, store or accept PO token files, and it does not return raw YouTube audio URLs. Reasons:

- A PO token is minted for a specific client and expires within minutes. A token "file" placed on a server is stale almost immediately.
- YouTube stream links are tied to the IP address that requested them. A link resolved on Cloudflare cannot be played from your phone.
- Resolving and relaying YouTube audio for other apps circumvents YouTube's protections and its terms, and Cloudflare's terms restrict proxying large amounts of audio and video, so the account could be suspended.

What to do instead:

- **YouTube / YouTube Music items:** the API returns `videoId` and an `embedUrl`. Play them with the official YouTube player (IFrame API or a WebView). No PO token is needed.
- **ZenMusic Android app:** the app handles its own YouTube playback on the device in Kotlin (`potoken/ZenPoTokenBridge.kt`). You do not place any files anywhere.
- **JioSaavn:** `playback.url` is a direct link; any player can use it.

## Costs and limits

The Cloudflare free plan allows 100,000 function requests per day. Responses are cached for 5 minutes, which helps. Only small JSON passes through your project; no audio does.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Project not found` in the workflow | Make sure `CLOUDFLARE_PROJECT` is set; the workflow creates the project on first run. If the name is taken, choose another. |
| `401 Missing or invalid API key` | Send the `x-api-key` header with the value of `API_KEY`. |
| `502 Upstream unavailable` | JioSaavn or YouTube did not answer; try again. YouTube pages can change and break parsing; open an issue with the request you made. |
| Empty YouTube results | Cloudflare IPs are sometimes rate limited by YouTube. Try again later. |

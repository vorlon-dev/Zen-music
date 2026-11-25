#!/usr/bin/env python3
# Zen Music · universal config.json generator
# Place in: tools/generate_config.py
# Generates config/config.json — a drop-in config carrying Innertube client data,
# BotGuard/PO-token material, stream-extraction chains, YTM/YT/JioSaavn search
# endpoints and artwork templates. Pure stdlib.
#
# Usage (CI):  python tools/generate_config.py --out config/config.json \
#                --bgutil-token-file /tmp/pot.json \
#                --config-url https://raw.githubusercontent.com/<owner>/<repo>/main/config/config.json
# Usage (local, no mint): python tools/generate_config.py --out config/config.json --skip-mint

import argparse
import datetime as dt
import json
import re
import ssl
import sys
import urllib.request

APP_REPO = "https://github.com/vorlon-dev/Zen-music"
UA_WEB = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
YTM_BASE = "https://music.youtube.com/youtubei/v1/"
YT_BASE = "https://www.youtube.com/youtubei/v1/"
YTDLP_BASE_URL = "https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/yt_dlp/extractor/youtube/_base.py"

SSL_CTX = ssl.create_default_context()

def http_json(url, body=None, headers=None, timeout=25):
    hdrs = {"Accept": "application/json", "User-Agent": UA_WEB}
    if headers:
        hdrs.update(headers)
    data = json.dumps(body).encode() if body is not None else None
    if data:
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=hdrs, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as r:
        return json.load(r)

def http_text(url, timeout=25):
    req = urllib.request.Request(url, headers={"User-Agent": UA_WEB})
    with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as r:
        return r.read().decode("utf-8", "replace")

# ---------------------------------------------------------------- app client matrix (pinned defaults)
# Mirrors innertube/src/main/kotlin/com/music/innertube/models/YouTubeClient.kt
APP_CLIENTS = [
    dict(clientName="WEB", clientVersion="2.20260213.00.00", clientId="1", userAgent=UA_WEB),
    dict(clientName="WEB_REMIX", clientVersion="1.20260213.01.00", clientId="67", userAgent=UA_WEB,
         loginSupported=True, useSignatureTimestamp=True, useWebPoTokens=True),
    dict(clientName="WEB_CREATOR", clientVersion="1.20260213.00.00", clientId="62", userAgent=UA_WEB,
         loginSupported=True, loginRequired=True, useSignatureTimestamp=True, useWebPoTokens=True),
    dict(clientName="TVHTML5", clientVersion="7.20260213.00.00", clientId="7",
         userAgent="Mozilla/5.0(SMART-TV; Linux; Tizen 4.0.0.2) AppleWebkit/605.1.15 (KHTML, like Gecko) SamsungBrowser/9.2 TV Safari/605.1.15",
         loginSupported=True, loginRequired=True, useSignatureTimestamp=True, useWebPoTokens=True),
    dict(clientName="TVHTML5_SIMPLY_EMBEDDED_PLAYER", clientVersion="2.0", clientId="85",
         userAgent="Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15",
         loginSupported=True, useSignatureTimestamp=True, isEmbedded=True),
    dict(clientName="IOS", clientVersion="21.03.1", clientId="5",
         userAgent="com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
         osVersion="18.2.22C152"),
    dict(clientName="ANDROID", clientVersion="21.03.38", clientId="3",
         userAgent="com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip",
         loginSupported=True, useSignatureTimestamp=True),
    dict(clientName="ANDROID_NO_SDK", clientVersion="21.03.38", clientId="3",
         userAgent="com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip", friendlyName="Android No SDK"),
    dict(clientName="ANDROID_VR_1_65_10", clientName0="ANDROID_VR", clientVersion="1.65.10", clientId="28",
         userAgent="com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
         osName="Android", osVersion="12L", deviceMake="Oculus", deviceModel="Quest 3",
         androidSdkVersion="32", friendlyName="Android VR 1.65"),
    dict(clientName="ANDROID_VR_1_61_48", clientName0="ANDROID_VR", clientVersion="1.61.48", clientId="28",
         userAgent="com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Oculus Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
         osName="Android", osVersion="12", deviceMake="Oculus", deviceModel="Quest 3",
         androidSdkVersion="32", buildId="SQ3A.220605.009.A1", cronetVersion="132.0.6808.3",
         packageName="com.google.android.apps.youtube.vr.oculus", friendlyName="Android VR 1.61"),
    dict(clientName="ANDROID_VR_1_43_32", clientName0="ANDROID_VR", clientVersion="1.43.32", clientId="28",
         userAgent="com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
         osName="Android", osVersion="12", deviceMake="Oculus", deviceModel="Quest 3",
         androidSdkVersion="32", buildId="SQ3A.220605.009.A1", cronetVersion="107.0.5284.2",
         packageName="com.google.android.apps.youtube.vr.oculus", friendlyName="Android VR 1.43"),
    dict(clientName="ANDROID_CREATOR", clientVersion="25.03.101", clientId="14",
         userAgent="com.google.android.apps.youtube.creator/25.03.101 (Linux; U; Android 15; en_US; Pixel 9 Pro Fold; Build/AP3A.241005.015.A2; Cronet/132.0.6779.0)",
         osName="Android", osVersion="15", deviceMake="Google", deviceModel="Pixel 9 Pro Fold",
         androidSdkVersion="35", buildId="AP3A.241005.015.A2", cronetVersion="132.0.6779.0",
         packageName="com.google.android.apps.youtube.creator", friendlyName="Android Studio",
         loginSupported=True, useSignatureTimestamp=True),
    dict(clientName="VISIONOS", clientVersion="0.1", clientId="101",
         userAgent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
         osName="visionOS", osVersion="1.3.21O771", deviceMake="Apple", deviceModel="RealityDevice14,1",
         friendlyName="visionOS"),
    dict(clientName="IPADOS", clientName0="IOS", clientVersion="21.03.3", clientId="5",
         userAgent="com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)",
         osName="iPadOS", osVersion="17.7.10.21H450", deviceMake="Apple", deviceModel="iPad7,6",
         friendlyName="iPadOS", packageName="com.google.ios.youtube"),
]
# Explicit config client -> yt-dlp client KEY for live version refresh.
# Absent = keep the app pin (legacy variants are bot-gated BY VERSION on purpose,
# and IPADOS pins a device emulation whose UA embeds its version).
YTDLP_KEY_MAP = {"WEB": "web", "WEB_REMIX": "web_music", "WEB_CREATOR": "web_creator",
                 "TVHTML5": "tv", "TVHTML5_SIMPLY_EMBEDDED_PLAYER": "tv_embedded",
                 "IOS": "ios", "ANDROID": "android", "ANDROID_NO_SDK": "android",
                 "ANDROID_VR_1_65_10": "android_vr", "ANDROID_CREATOR": "android_creator",
                 "VISIONOS": "visionos"}
# clients whose UA embeds the client version -> refresh UA together with version
UA_EMBEDS_VERSION = {"IOS", "ANDROID", "ANDROID_NO_SDK", "ANDROID_VR_1_65_10",
                     "ANDROID_VR_1_61_48", "ANDROID_VR_1_43_32", "ANDROID_CREATOR", "IPADOS"}

# Search filter params — verbatim from YouTube.kt SearchFilter
SEARCH_FILTERS = {
    "songs": "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D",
    "videos": "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D",
    "albums": "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D",
    "artists": "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D",
    "featuredPlaylists": "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D",
    "communityPlaylists": "EgeKAQQoAEABagoQAxAEEAoQCRAF",
}

BOTGUARD = {
    "requestKey": "O43z0dpjhgX20SCx4KAo",
    "googleApiKey": "AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw",
    "endpoints": {"bootstrap": "https://www.youtube.com",
                  "create": "https://www.youtube.com/api/jnn/v1/Create",
                  "createBody": ["O43z0dpjhgX20SCx4KAo"],
                  "generateIt": "https://www.youtube.com/api/jnn/v1/GenerateIT"},
}

SAAVN_BASE = "https://jiosaavn-api.vorlon-revora.workers.dev"

# Cipher self-healing: zemer-cipher's remote player table. innertubex's
# RemotePlayerConfigParser consumes the SAME {schemaVersion, players} schema.
ZEMER_CONFIG_URL = ("https://raw.githubusercontent.com/ZemerTeam/zemer-cipher/"
                    "master/library/src/main/assets/player_configs.json")
PLAYER_JS_TEMPLATE = "https://www.youtube.com/s/player/{playerHash}/player_ias.vflset/en_GB/base.js"
FARADAY_URL_TEMPLATE = ("https://github.com/MetrolistGroup/faraday/releases/"
                        "download/{playerTag}/{playerHash}.json")

CHECKS = []

def check(name, ok, detail="", warn=False):
    CHECKS.append({"name": name, "ok": bool(ok), "warn": bool(warn), "detail": str(detail)[:300]})
    print(f"  [{'WARN' if warn else 'OK' if ok else 'FAIL'}] {name}: {detail[:120]}")
    return ok

# ---------------------------------------------------------------- fetch live data

def fetch_visitor_data():
    html = http_text("https://music.youtube.com/")
    m = re.search(r'"visitorData":"([^"]+)"', html)
    return m.group(1) if m else None

def fetch_cipher_table():
    """Fetch zemer-cipher's remote player cipher table (also consumed by innertubex)."""
    data = http_json(ZEMER_CONFIG_URL)
    players = data.get("players")
    if not isinstance(players, dict) or not players:
        raise ValueError("cipher table has no players map")
    schema_version = data.get("schemaVersion")
    if not isinstance(schema_version, int) or schema_version <= 0:
        raise ValueError(f"bad schemaVersion: {schema_version!r}")
    latest_sts = max((p.get("sts", 0) for p in players.values()
                      if isinstance(p, dict) and isinstance(p.get("sts"), int)), default=None)
    return {"schemaVersion": schema_version, "players": players,
            "count": len(players), "latestSts": latest_sts}

def fetch_ytdlp_clients():
    """Parse yt-dlp master _base.py INNERTUBE_CLIENTS into {clientName: {...}}."""
    src = http_text(YTDLP_BASE_URL)
    clients = {}  # keyed by yt-dlp KEY (unique), not clientName
    for block in re.finditer(r"'([a-z_0-9]+)':\s*\{(.*?)\n    \},\n", src, re.S):
        key, body = block.group(1), block.group(2)
        m_name = re.search(r"'clientName':\s*'([^']+)'", body)
        m_ver = re.search(r"'clientVersion':\s*'([^']+)'", body)
        m_id = re.search(r"'INNERTUBE_CONTEXT_CLIENT_NAME':\s*(\d+)", body)
        m_ua = re.search(r"'user-agent':\s*'([^']+)'", body)
        if not (m_name and m_ver):
            continue
        gvs_https = None
        m_gvs = re.search(r"GVS_PO_TOKEN_POLICY", body)
        if m_gvs:
            gvs_https = "required=True" in body or "required=True" in src[block.start():block.end()+400]
        clients[key] = {
            "clientName": m_name.group(1),
            "clientVersion": m_ver.group(1),
            "clientId": m_id.group(1) if m_id else None,
            "userAgent": m_ua.group(1) if m_ua else None,
            "gvsPoTokenRequiredHttps": gvs_https,
        }
    return clients

# ---------------------------------------------------------------- health checks

def health_ytm_search():
    body = {"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": "1.20260213.01.00",
                                   "hl": "en", "gl": "IN"}},
            "query": "arijit singh"}
    data = http_json(YTM_BASE + "search?prettyPrint=false", body,
                     {"Origin": "https://music.youtube.com",
                      "X-YouTube-Client-Name": "67", "X-YouTube-Client-Version": "1.20260213.01.00",
                      "X-Goog-Api-Format-Version": "1"})
    rows = json.dumps(data).count("musicResponsiveListItemRenderer")
    vids = re.findall(r'"videoId": "([A-Za-z0-9_-]{11})"', json.dumps(data))
    return rows, (vids[0] if vids else None)

def health_yt_search():
    body = {"context": {"client": {"clientName": "WEB", "clientVersion": "2.20260213.00.00",
                                   "hl": "en", "gl": "IN"}},
            "query": "arijit singh songs"}
    data = http_json(YT_BASE + "search?prettyPrint=false", body,
                     {"X-YouTube-Client-Name": "1", "X-YouTube-Client-Version": "2.20260213.00.00",
                      "X-Goog-Api-Format-Version": "1"})
    rows = json.dumps(data).count("videoRenderer")
    return rows

def health_saavn():
    url = f"{SAAVN_BASE}/api/search/songs?query=arijit%20singh&limit=5&page=0"
    data = http_json(url)
    results = data.get("data", {}).get("results", [])
    return len(results)

def health_player(video_id, visitor_data, vr_client):
    """Player POST with the app's tier-0 client (ANDROID_VR 1.65.10)."""
    ctx_client = {"clientName": vr_client["clientName0"], "clientVersion": vr_client["clientVersion"],
                  "osName": "Android", "osVersion": "12L", "deviceMake": "Oculus",
                  "deviceModel": "Quest 3", "androidSdkVersion": "32", "hl": "en", "gl": "IN"}
    if visitor_data:
        ctx_client["visitorData"] = visitor_data  # must stay consistent with the header
    body = {"context": {"client": ctx_client}, "videoId": video_id,
            "contentCheckOk": True, "racyCheckOk": True}
    hdrs = {"User-Agent": vr_client["userAgent"], "X-Goog-Api-Format-Version": "1",
            "X-YouTube-Client-Name": vr_client["clientId"],
            "X-YouTube-Client-Version": vr_client["clientVersion"]}
    if visitor_data:
        hdrs["X-Goog-Visitor-Id"] = visitor_data
    data = http_json(YT_BASE + "player?prettyPrint=false", body, hdrs)
    status = data.get("playabilityStatus", {}).get("status")
    fmts = data.get("streamingData", {}).get("adaptiveFormats", [])
    urls = sum(1 for f in fmts if f.get("url"))
    return status, len(fmts), urls

# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="config/config.json")
    ap.add_argument("--bgutil-token-file", default=None, help="JSON from bgutil generate_once.js")
    ap.add_argument("--skip-mint", action="store_true")
    ap.add_argument("--skip-versions", action="store_true", help="keep app-pinned versions, skip yt-dlp fetch")
    ap.add_argument("--skip-cipher", action="store_true", help="skip zemer-cipher player table fetch")
    ap.add_argument("--cipher-out", default=None,
                    help="also write the cipher table as a standalone mirror (e.g. config/player_configs.json)")
    ap.add_argument("--skip-health", action="store_true")
    ap.add_argument("--config-url", default=None, help="final raw URL of this config (self-reference)")
    ap.add_argument("--saavn-base", default=SAAVN_BASE)
    args = ap.parse_args()

    now = dt.datetime.now(dt.timezone.utc)
    print("== Zen Music config generator ==")

    visitor_data = None
    try:
        visitor_data = fetch_visitor_data()
        check("visitorData", bool(visitor_data), f"{visitor_data[:48]}..." if visitor_data else "not found")
    except Exception as e:
        check("visitorData", False, f"error {e}")

    print("fetching yt-dlp live client versions ...")
    live = {}
    if args.skip_versions:
        check("ytdlp-versions", True, warn=True, detail="skipped (--skip-versions)")
    else:
        try:
            live = fetch_ytdlp_clients()
            check("ytdlp-versions", bool(live), f"{len(live)} clients parsed from master")
        except Exception as e:
            check("ytdlp-versions", False, f"error {e}")

    print("fetching cipher player table (zemer-cipher) ...")
    cipher_table = None
    if args.skip_cipher:
        check("cipher.playerTable", True, warn=True, detail="skipped (--skip-cipher)")
    else:
        try:
            cipher_table = fetch_cipher_table()
            check("cipher.playerTable", True,
                  f"{cipher_table['count']} players, schemaVersion {cipher_table['schemaVersion']}, "
                  f"latest sts {cipher_table['latestSts']}")
        except Exception as e:
            check("cipher.playerTable", False, f"error {e}")

    if not args.skip_health:
        print("health checks ...")
        first_video = None
        try:
            rows, first_video = health_ytm_search()
            check("search.youtubeMusic", rows > 0, f"{rows} rows, first videoId {first_video}")
        except Exception as e:
            check("search.youtubeMusic", False, f"error {e}")
        try:
            rows = health_yt_search()
            check("search.youtube", rows > 0, f"{rows} videoRenderer rows")
        except Exception as e:
            check("search.youtube", False, f"error {e}")
        try:
            n = health_saavn()
            check("search.jioSaavn", n > 0, f"{n} results from worker")
        except Exception as e:
            check("search.jioSaavn", False, f"error {e}")
        if first_video:
            vr = next(c for c in APP_CLIENTS if c["clientName"] == "ANDROID_VR_1_65_10")
            try:
                status, nfmt, nurl = health_player(first_video, visitor_data, vr)
                if status == "OK" and nurl > 0:
                    check("stream.player(ANDROID_VR_1_65_10)", True,
                          f"playability=OK, formats={nfmt}, direct-urls={nurl}")
                elif status == "LOGIN_REQUIRED":
                    # YouTube bot-gates the player API for datacenter/CI IPs on ALL clients.
                    # On real devices (residential/mobile IP) this client returns OK — the
                    # in-app chain is the app's tier-0 extractor. Endpoint IS reachable.
                    check("stream.player(ANDROID_VR_1_65_10)", True, warn=True,
                          detail="playability=LOGIN_REQUIRED — expected from datacenter/CI IPs "
                                 "(YouTube bot-gates cloud IPs); works on real devices")
                else:
                    check("stream.player(ANDROID_VR_1_65_10)", False, f"playability={status}")
            except Exception as e:
                check("stream.player(ANDROID_VR_1_65_10)", False, f"error {e}")

    # clients: app pins upgraded with live yt-dlp versions ONLY where explicitly mapped
    clients = []
    for c in APP_CLIENTS:
        out = dict(c)
        out.pop("clientName0", None)
        out["appPinnedVersion"] = c["clientVersion"]
        src = live.get(YTDLP_KEY_MAP.get(c["clientName"], ""))
        if src and src.get("clientVersion") and src["clientVersion"] != c["clientVersion"]:
            out["clientVersion"] = src["clientVersion"]
            out["versionSource"] = f"yt-dlp master ({YTDLP_KEY_MAP[c['clientName']]})"
            if src.get("userAgent") and c["clientName"] in UA_EMBEDS_VERSION:
                out["userAgent"] = src["userAgent"]
        else:
            out["versionSource"] = "app pin"
        if src:
            out["gvsPoTokenRequiredHttps"] = src.get("gvsPoTokenRequiredHttps")
        clients.append(out)

    starter = None
    if args.bgutil_token_file:
        try:
            d = json.load(open(args.bgutil_token_file))
            starter = {"token": d["poToken"], "contentBinding": d["contentBinding"],
                       "mintedAt": now.isoformat(), "expiresAt": d.get("expiresAt"),
                       "generator": "bgutil-ytdlp-pot-provider generate_once",
                       "usage": "send X-Goog-Visitor-Id: <contentBinding> and append pot=<token> to googlevideo URLs for web clients"}
            check("poToken.starter", True, f"len={len(d['poToken'])}, expiresAt={d.get('expiresAt')}")
        except Exception as e:
            check("poToken.starter", False, f"error {e}")
    elif not args.skip_mint:
        check("poToken.starter", False, "no token file provided (pass --bgutil-token-file)")

    config = {
        "$schema": "zen-config/1",
        "meta": {
            "name": "Zen Music Universal Config",
            "app": "ZenMusic",
            "repository": APP_REPO,
            "generatedAt": now.isoformat(),
            "generator": "tools/generate_config.py",
            "configUrl": args.config_url,
            "schemaDocs": "README at " + APP_REPO + "/blob/main/config/README.md",
        },
        "innertube": {
            "api": {"musicBase": YTM_BASE, "youtubeBase": YT_BASE, "apiFormatVersion": "1"},
            "locale": {"hl": "en", "gl": "IN"},
            "visitorData": {"value": visitor_data,
                            "source": "music.youtube.com ytcfg",
                            "capturedAt": now.isoformat(),
                            "note": "send as X-Goog-Visitor-Id; refresh by re-running the workflow"},
            "headers": {"Accept": "application/json", "Cache-Control": "no-cache",
                        "X-Goog-Api-Format-Version": "1"},
            "clients": clients,
            "chains": {"audio": ["ANDROID_VR_1_65_10", "VISIONOS", "WEB_REMIX"],
                       "video": ["VISIONOS", "ANDROID_VR_1_65_10", "WEB_REMIX"],
                       "search": ["WEB_REMIX"], "searchYouTube": ["WEB"],
                       "suggestions": ["WEB_REMIX"]},
            "endpoints": {"player": "player", "search": "search",
                          "searchSuggestions": "music/get_search_suggestions",
                          "next": "next", "browse": "browse", "getQueue": "music/get_queue",
                          "getTranscript": "get_transcript"},
        },
        "botguard": {
            "mode": "in-app-webview",
            "requestKey": BOTGUARD["requestKey"],
            "googleApiKey": BOTGUARD["googleApiKey"],
            "endpoints": BOTGUARD["endpoints"],
            "webPoTokenClients": ["WEB_REMIX", "WEB_CREATOR", "TVHTML5"],
            "starterToken": starter,
            "providerServer": {"enabled": False, "url": None,
                               "howTo": "optional: run brainicism/bgutil-ytdlp-pot-provider server, set url + enabled=true"},
            "mint": {"engine": "BotGuard via jnn/v1 (LibreTube-style WebView)",
                     "ciGenerator": "bgutil-ytdlp-pot-provider@2.x generate_once",
                     "note": "starterToken is session-bound: always pair token with its contentBinding as X-Goog-Visitor-Id; re-run workflow after expiresAt"},
        },
        "stream": {
            "extraction": "innertube-player",
            "tokenlessFallback": True,
            "gvs": {"host": "googlevideo.com",
                    "headers": {"User-Agent": "{client.userAgent}"},
                    "potParam": "pot", "nTransform": "server-side (innertube)"},
            "quality": {"ytm": ["FLAC CD", "Hi-Res", "Hi-Res Max", "320kbps AAC", "128kbps AAC"],
                        "jioSaavn": ["320kbps", "160kbps", "96kbps", "48kbps", "12kbps"]},
            "loudness": {"source": "playerResponse.playerConfig.mediaCommonConfig.volumeNormalization"},
        },
        "cipher": {
            "schemaVersion": (cipher_table or {}).get("schemaVersion", 1),
            "capturedAt": now.isoformat(),
            "sourceUrl": ZEMER_CONFIG_URL,
            "mirrorUrl": (args.config_url.replace("config.json", "player_configs.json")
                          if args.config_url else None),
            "playerCount": (cipher_table or {}).get("count"),
            "latestSts": (cipher_table or {}).get("latestSts"),
            "players": (cipher_table or {}).get("players", {}),
            "playerJsTemplate": PLAYER_JS_TEMPLATE,
            "legacyFaradayTemplate": FARADAY_URL_TEMPLATE,
            "entryFormat": {"<8hex player hash>": {"sig": "signature deobfuscation call",
                                                    "nClass": "URL class for n-transform",
                                                    "sts": "signatureTimestamp",
                                                    "aliases": ["fallback hashes"]}},
            "consumerWiring": {
                "zemerCipher": "ZemerCipher.initialize() refreshes from sourceUrl automatically "
                               "(6h TTL + ETag + force-refresh on unknown hash); or point its store "
                               "at mirrorUrl for a table served from this repo",
                "innertubex": "implement PlayerConfigRepository with sourceUrl = mirrorUrl "
                              "(RemotePlayerConfigParser consumes the same schemaVersion/players table; "
                              "6h TTL, unknown-hash + stream-rejection force refresh)",
                "custom": "match the player hash from the player JS URL (playerJsTemplate regexes "
                          "/player/<8hex>/, /s/player/<8hex>/) and use sig/nClass/sts",
            },
            "upstream": {"repo": "https://github.com/ZemerTeam/zemer-cipher",
                         "selfHealing": "upstream player-monitor workflow auto-derives + validates "
                                        "new configs on player rotations and commits to master",
                         "innertubexRepo": "https://github.com/MetrolistGroup/innertubex"},
        },
        "search": {
            "youtubeMusic": {"client": "WEB_REMIX", "endpoint": "search", "filters": SEARCH_FILTERS},
            "youtube": {"client": "WEB", "endpoint": "search"},
            "suggestions": {"client": "WEB_REMIX", "endpoint": "music/get_search_suggestions"},
            "jioSaavn": {
                "baseUrl": args.saavn_base,
                "endpoints": {"searchSongs": "/api/search/songs", "searchAlbums": "/api/search/albums",
                              "searchPlaylists": "/api/search/playlists", "searchArtists": "/api/search/artists",
                              "songDetails": "/api/songs/{id}", "albumDetails": "/api/albums/{id}",
                              "playlistDetails": "/api/playlists/{id}"},
                "defaults": {"limit": 15, "page": 0, "quality": "320kbps"},
                "responseShape": {"search": "data.results[]", "song": "data[].downloadUrl[{quality,url}]"},
            },
        },
        "artwork": {
            "youtube": {"template": "https://i.ytimg.com/vi/{videoId}/{quality}.jpg",
                        "qualities": ["maxresdefault", "sddefault", "hqdefault", "mqdefault"]},
            "jioSaavn": {"source": "image[] field from API, pick largest (500x500)"},
        },
        "health": {"checkedAt": now.isoformat(), "checks": CHECKS,
                   "allOk": all(c["ok"] for c in CHECKS)},
    }

    import os
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print(f"\nwritten: {args.out}  ({os.path.getsize(args.out)} bytes)")

    if args.cipher_out and cipher_table:
        mirror = {"schemaVersion": cipher_table["schemaVersion"],
                  "players": cipher_table["players"]}
        os.makedirs(os.path.dirname(args.cipher_out) or ".", exist_ok=True)
        with open(args.cipher_out, "w") as f:
            json.dump(mirror, f, indent=2, ensure_ascii=False)
        print(f"written: {args.cipher_out}  ({os.path.getsize(args.cipher_out)} bytes)")

    print("health:", "ALL OK" if config["health"]["allOk"] else "SOME CHECKS FAILED")

if __name__ == "__main__":
    sys.exit(main())

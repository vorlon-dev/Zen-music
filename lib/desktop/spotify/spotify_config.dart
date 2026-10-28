// ZenMusic — spotify Web Player protocol constants.
// Ported from Stopify (MIT License) — Copyright (c) Shashwat.
// ZenMusic remains GPL-3.0. Protocol reference:
// https://github.com/Anattana-Labs/Stopify (Web Player reverse engineering).

class SpotifyConfig {
  SpotifyConfig._();

  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36';
  static const appPlatform = 'WebPlayer';
  static const spotifyAppVersion = '1.3.6.121.g2b2ea800fe12';
  static const clientId = 'd8a5ed958d274c2e8ee717e6a4b0971d';

  /// Captured Web Player client token (public constant from Stopify).
  static const clientToken =
      'AAGCCRiw7WlW3Oy33uN5L1dI2knSs986nqFaI1YTbq66MFLs0oeinjyYUbv2zo9+9kleXdls6EnujpM6OElxp5zJtj+0ZP9RU9I0ApWvFeXJwZRYmCVMWBngB3AN6Ux1imVm+8ImYf9OvVc3mJJBjxLH4S3k77qOsXB6EekBL9hZQgx8umkPOLZZEfolSOP8wURVuQX5sZjnwIfPmLf/8ydY/LeeqBGTvkyZwV4InPyVxMlOI7DQViCkvmXQ2ZkpQASm2NrJ40wdF+BcpIDZV0YA+czHR2bx2K+tTKIaNMa7GUTB/By4+ls8IO6TL4zLlLoKGWnXa8N0xzthzHW9B2zdsW/kTD7JttelP1GHt/1lDuiRvvqtp2WGx6ZeArHvStJTLeO+sZHGs6IxJBY=';

  static const defaultDeviceId =
      'af6fd454eccef1714bc99a09a10c119366e8da1c';

  // Pathfinder persisted query hashes (spotify Web Player).
  static const searchTopResultsHash =
      'dd78eaff943eba629ed70ee25517b9cea0dcaa41193e2592ae2727660b21892c';
  static const searchTracksHash =
      'b02683192a98dde7966b5e6655a79eeb62713eab703eda9902c932818dd52751';
  static const searchAlbumsHash =
      '202cb3305e31e5a0767ba7925f28bd728cf8f8b0217e6da43909056071cd70e9';
  static const searchArtistsHash =
      '7bf95d754fdbe32c8b161fbbe54d1ae50974900df4dce4c8f1afcbcad153224d';
  static const searchPlaylistsHash =
      'd520014e748f9ea44f7707d8df1819867ac1205e8b7f3e28f22fe5fc858921b1';
  static const fetchPlaylistHash =
      '8964e8eafb21aa992a7d951d256d83285c04be2105d209262901de70cb97584a';
  static const getAlbumHash =
      '11c9cad9cb24c4f9e25ef9456f68621cfd6006a90f679e729c1d2f2fd70dfe16';
  static const homeHash =
      '5fb7da7a03ee2776c0670856609cb85a189a3cecc36cc160b91cde79063b9cf1';
  static const libraryHash =
      '973e511ca44261fda7eebac8b653155e7caee3675abb4fb110cc1b8c78b091c3';
  static const addToPlaylistHash =
      '47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990';
  static const addToLibraryHash =
      '7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d';
  static const profileAttributesHash =
      '53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced';
  static const recentsHash =
      '698be5892a3cc95331deebeff463d05dfdd5febf5254bea30b895b5a93dfb584';

  // Endpoints
  static const pathfinderUrl =
      'https://api-partner.spotify.com/pathfinder/v2/query';
  // SP-71: official Web API — used for the user's liked songs, which the
  // pathfinder libraryV3 query answers with an empty LikedSongs node for
  // many accounts. The Bearer minted from sp_dc carries the
  // user-library-read scope, so /v1/me/tracks answers reliably.
  static const restApiBase = 'https://api.spotify.com/v1';
  static const serverTimeUrl = 'https://open.spotify.com/api/server-time';
  static const tokenUrlBase =
      'https://open.spotify.com/api/token?reason=transport&productType=web-player';
  static const clientTokenUrl =
      'https://clienttoken.spotify.com/v1/clienttoken';
  static const totpGistUrl =
      'https://api.github.com/gists/22ed9c6ba463899e933427f7de1f0eef';
  static const dealerWsUrl = 'wss://dealer.spotify.com/';
  static const spclientBase = 'https://gae2-spclient.spotify.com';

  /// Parses a user-pasted cookie blob: raw sp_dc token, key=value pairs, or
  /// Netscape cookies.txt format. Returns a normalized Cookie header string.
  static String parseCookieInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    // Raw sp_dc token pasted directly (20+ chars, no '=').
    if (!trimmed.contains('=') &&
        !trimmed.contains('\t') &&
        trimmed.length >= 20) {
      return 'sp_dc=$trimmed';
    }

    final cookieMap = <String, String>{};

    // Netscape cookies.txt (tab-separated).
    var isNetscape = false;
    for (final line in trimmed.split('\n')) {
      final t = line.trim();
      if (t.startsWith('#') || t.isEmpty) continue;
      final parts = t.split('\t');
      if (parts.length >= 7) {
        isNetscape = true;
        if (parts[6].trim().isNotEmpty) {
          cookieMap[parts[5].trim()] = parts[6].trim();
        }
      }
    }
    if (isNetscape && cookieMap.isNotEmpty) {
      return cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }

    // Semicolon / newline key=value pairs.
    for (final segment in trimmed.split(RegExp(r';|\n'))) {
      final seg = segment.trim();
      if (seg.isEmpty || seg.startsWith('#')) continue;
      final eq = seg.indexOf('=');
      if (eq > 0) {
        final key = seg.substring(0, eq).trim();
        final value = seg.substring(eq + 1).trim();
        if (value.isNotEmpty) cookieMap[key] = value;
      }
    }

    return cookieMap.isNotEmpty
        ? cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ')
        : trimmed;
  }

  static bool hasValidSpDc(String? cookies) {
    if (cookies == null || cookies.isEmpty) return false;
    return RegExp(r'\bsp_dc=([^;\s]{20,})').hasMatch(cookies);
  }

  static String? extractSpDc(String? cookies) {
    if (cookies == null || cookies.isEmpty) return null;
    return RegExp(r'\bsp_dc=([^;\s]{20,})').firstMatch(cookies)?.group(1);
  }
}
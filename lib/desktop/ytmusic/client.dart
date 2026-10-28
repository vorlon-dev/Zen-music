// ZenMusic Desktop — ported from Echo Music (GPL-3.0), ytmusic/client.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zenmusic/desktop/ytmusic/helpers.dart';
import 'package:zenmusic/desktop/ytmusic/modals/yt_config.dart';
import 'package:http/http.dart';

// SP-62/SP-65: YouTube Music account auth — cookie session (SAPISIDHASH;
// the OAuth Bearer path died server-side, see ytm_auth.dart). Merged into
// every POST so browse() and friends return the signed-in user's
// personalized feed, with failures now visible in the log.
import 'package:zenmusic/desktop/ytmusic/ytm_auth.dart';

class YTClient {
  YTClient({required this.config, this.onIdUpdate}) {
    init();
  }
  Map<String, String> headers = {};
  Map<String, dynamic> context = {};
  int? signatureTimestamp;
  YTConfig? config;
  void Function(String visitorId)? onIdUpdate;

  static const ytmDomain = 'music.youtube.com';
  static const httpsYtmDomain = 'https://music.youtube.com';
  static const baseApiEndpoint = '/youtubei/v1/';
  static const String ytmParams =
      '?alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:88.0) Gecko/20100101 Firefox/88.0';

  static final ValueNotifier<int> lastConnectionErrorTime =
  ValueNotifier<int>(0);
  ValueNotifier<int> get lastConnectionError => lastConnectionErrorTime;

  Future<void> init() async {
    headers = initializeHeaders();
    context = initializeContext();

    if (config?.visitorData != null) {
      headers['X-Goog-Visitor-Id'] = config!.visitorData;
    }
  }

  void refreshContext() {
    context = initializeContext();
  }

  Future<void> refreshHeaders() async {
    headers = initializeHeaders();
    if (config?.visitorData != null) {
      headers['X-Goog-Visitor-Id'] = config!.visitorData;
    }
  }

  Future<void> resetVisitorId() async {
    Map<String, String> newHeaders = Map.from(headers);
    newHeaders.remove('X-Goog-Visitor-Id');
    // SP-62: when an account is connected, fetch the session-scoped visitor
    // id (same cookies/authorization) instead of an anonymous one.
    final auth = await YtmAuth.instance.authHeaders();
    if (auth != null) {
      newHeaders.addAll(auth);
    }
    final response = await sendGetRequest(httpsYtmDomain, newHeaders);
    final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
    RegExpMatch? matches = reg.firstMatch(response.body);
    String? visitorId;
    if (matches != null) {
      final ytcfg = json.decode(matches.group(1).toString());
      visitorId = ytcfg['VISITOR_DATA']?.toString();
      config ??= YTConfig(visitorData: '', language: 'en', location: 'IN');
      config = config!.copyWith(visitorData: visitorId);
      if (onIdUpdate != null && visitorId != null) {
        onIdUpdate!(visitorId);
      }
    }
    refreshHeaders();
  }

  static Future<String?> getVisitorid() async {
    Map<String, String> newHeaders = initializeHeaders();
    newHeaders.remove('X-Goog-Visitor-Id');
    final response = await _sendGetRequest(httpsYtmDomain, newHeaders);
    final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
    RegExpMatch? matches = reg.firstMatch(response.body);
    String? visitorId;
    if (matches != null) {
      final ytcfg = json.decode(matches.group(1).toString());
      visitorId = ytcfg['VISITOR_DATA']?.toString();
      return visitorId;
    }
    return null;
  }

  Future<Response> sendGetRequest(
      String url,
      Map<String, String>? headers,
      ) async {
    try {
      final Uri uri = Uri.parse(url);
      final Response response = await get(uri, headers: headers);
      return response;
    } catch (e) {
      debugPrint("Exception in YTClient::sendGetReques: $e");
      lastConnectionErrorTime.value = DateTime.now().millisecondsSinceEpoch;
      return Response.bytes([], 503);
    }
  }

  static Future<Response> _sendGetRequest(
      String url,
      Map<String, String>? headers,
      ) async {
    try {
      final Uri uri = Uri.parse(url);
      final Response response = await get(uri, headers: headers);
      return response;
    } catch (e) {
      debugPrint("Exception in YTClient::_sendGetRequest: $e");
      lastConnectionErrorTime.value = DateTime.now().millisecondsSinceEpoch;
      return Response.bytes([], 503);
    }
  }

  Future<Response> addPlayingStats(String videoId, Duration time) async {
    try {
      final Uri uri = Uri.parse(
          'https://music.youtube.com/api/stats/watchtime?ns=yt&ver=2&c=WEB_REMIX&cmt=${(time.inMilliseconds / 1000)}&docid=$videoId');
      final Response response = await get(uri, headers: headers);
      return response;
    } catch (e) {
      debugPrint("Exception in YTClient::addPlayingStats: $e");
      lastConnectionErrorTime.value = DateTime.now().millisecondsSinceEpoch;
      return Response.bytes([], 503);
    }
  }

  Future<Map> sendRequest(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? headers, String additionalParams = ''}) async {
    //
    try {
      body = {...body, ...context};

      this.headers.addAll(headers ?? {});

      // SP-62/SP-65: merge the YouTube Music account credentials — a cookie
      // session (SAPISIDHASH) captured by the sign-in window or pasted
      // manually. Google removed OAuth support from the YTM API (HTTP 400
      // "invalid argument" on every authed request), so Bearer is gone; the
      // same browse() endpoint (FEmusic_home) returns the signed-in user's
      // taste-based home feed with these headers. When anonymous (logged
      // out), strip any stale auth headers so a logout truly returns the
      // app to the public feed.
      final auth = await YtmAuth.instance.authHeaders();
      if (auth != null) {
        this.headers.addAll(auth);
      } else {
        this.headers.remove('Authorization');
        this.headers.remove('X-Goog-Request-Time');
        this.headers.remove('X-Origin');
        this.headers['cookie'] = 'CONSENT=YES+1';
      }

      if (config?.visitorData == null || config!.visitorData.isEmpty) {
        await resetVisitorId();
      }
      if (this.headers['X-Goog-Visitor-Id'] == null &&
          config?.visitorData != null) {
        this.headers['X-Goog-Visitor-Id'] = config!.visitorData;
      }
      final Uri uri = Uri.parse(httpsYtmDomain +
          baseApiEndpoint +
          endpoint +
          ytmParams +
          additionalParams);
      final response =
      await post(uri, headers: this.headers, body: jsonEncode(body));

      // SP-65: make HTTP failures visible — the SP-62 era swallowed them,
      // so a dead session looked exactly like an empty feed.
      if (response.statusCode != 200) {
        debugPrint('YTClient.sendRequest: HTTP ${response.statusCode} '
            '${response.body.length}B '
            '${auth != null ? "(authed)" : "(anonymous)"}');
      }
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map;
      }
      // SP-65: HTTP 401 on an authed request is definitive — the cookie
      // session is dead. Drop it so the home feed falls back to the public
      // one instead of failing on every call. A 400/403 is treated as
      // request-specific and must NOT kill the session.
      if (auth != null && response.statusCode == 401) {
        await YtmAuth.instance.sessionRejected('HTTP 401');
      }
      return {};
    } catch (e) {
      debugPrint("Exception in YTClient::sendRequest: $e");
      lastConnectionErrorTime.value = DateTime.now().millisecondsSinceEpoch;
      return {};
    }
  }
}
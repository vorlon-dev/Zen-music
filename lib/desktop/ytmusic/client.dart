// ZenMusic · vorlon-dev

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zenmusic/desktop/ytmusic/helpers.dart';
import 'package:zenmusic/desktop/ytmusic/modals/yt_config.dart';
import 'package:http/http.dart';

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

  // Short-lived in-memory cache for read-only requests (home, albums,
  // artists, playlists, search, up-next). Reopening a page or going back to
  // one answers instantly instead of hitting the network again; the user's
  // own library/history/likes are never cached so they stay current.
  static const Duration _cacheTtl = Duration(minutes: 3);
  static const int _cacheMax = 60;
  final Map<String, (DateTime, Map)> _requestCache = {};

  void clearRequestCache() => _requestCache.clear();

  bool _cacheable(String endpoint, Map<String, dynamic> body) {
    if (endpoint == 'search' || endpoint == 'next') return true;
    if (endpoint != 'browse') return false;
    final id = body['browseId']?.toString() ?? '';
    if (id.isEmpty) return body.containsKey('continuation') == false;
    return !(id.startsWith('FEmusic_library') ||
        id.startsWith('FEmusic_liked') ||
        id.startsWith('FEmusic_history') ||
        id.startsWith('FEmusic_offline'));
  }

  Future<Map> sendRequest(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? headers, String additionalParams = ''}) async {
    if (!_cacheable(endpoint, body)) {
      return _sendRequestUncached(endpoint, body,
          headers: headers, additionalParams: additionalParams);
    }
    final key =
        '$endpoint|$additionalParams|${YtmAuth.instance.hasSession}|${jsonEncode(body)}';
    final hit = _requestCache[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _cacheTtl) {
      return hit.$2;
    }
    final result = await _sendRequestUncached(endpoint, body,
        headers: headers, additionalParams: additionalParams);
    if (result.isNotEmpty) {
      if (_requestCache.length >= _cacheMax) {
        _requestCache.remove(_requestCache.keys.first);
      }
      _requestCache[key] = (DateTime.now(), result);
    }
    return result;
  }

  Future<Map> _sendRequestUncached(
      String endpoint, Map<String, dynamic> body,
      {Map<String, String>? headers, String additionalParams = ''}) async {
    //
    try {
      body = {...body, ...context};

      this.headers.addAll(headers ?? {});

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

      if (response.statusCode != 200) {
        debugPrint('YTClient.sendRequest: HTTP ${response.statusCode} '
            '${response.body.length}B '
            '${auth != null ? "(authed)" : "(anonymous)"}');
      }
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map;
      }
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

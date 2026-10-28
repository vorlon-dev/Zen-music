// ZenMusic Desktop — ported from Echo Music (GPL-3.0), ytmusic/mixins/browsing.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// FIX (Spotify songs crash): addYoutubeHistory guarded. Non-YouTube ids
// (Spotify/JioSaavn song maps routed in by add_history) get a player
// response WITHOUT playbackTracking, so the unguarded
// playbackTracking.videostatsPlaybackUrl.baseUrl read threw
// NoSuchMethodError on every Spotify song change. Now null-safe and
// wrapped: history is best-effort telemetry and must never crash playback.

import 'dart:core';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../client.dart';

import '../helpers.dart';
import '../ytm_auth.dart';
import 'utils.dart';

mixin BrowsingMixin on YTClient {
  Future<Map<String, dynamic>> browse(
      {Map<String, dynamic>? body,
        int limit = 2,
        String additionalParams = ''}) async {
    if (additionalParams != '') {
      return browseContinuation(
          body: body, limit: limit, additionalParams: additionalParams);
    }
    String endpoint = 'browse';
    body ??= {"browseId": "FEmusic_home"};

    var response =
    await sendRequest(endpoint, body, additionalParams: additionalParams);

    Map<String, dynamic> result = {};
    Map<String, dynamic>? contents = response['contents'];

    Map<String, dynamic>? header = response['header'] ??
        nav(response, [
          'contents',
          'twoColumnBrowseResultsRenderer',
          'tabs',
          0,
          'tabRenderer',
          'content',
          'sectionListRenderer',
          'contents',
          0
        ]);

    if (header != null) {
      result['header'] = handlePageHeader(
          header['musicDetailHeaderRenderer'] ??
              header['musicImmersiveHeaderRenderer'] ??
              header['musicResponsiveHeaderRenderer'] ??
              header['musicVisualHeaderRenderer'] ??
              header['musicHeaderRenderer'] ??
              header['musicEditablePlaylistDetailHeaderRenderer']?['header']
              ?['musicResponsiveHeaderRenderer'] ??
              header['musicEditablePlaylistDetailHeaderRenderer']?['header'],
          editHeader: header['musicEditablePlaylistDetailHeaderRenderer']
          ?['editHeader']?['musicPlaylistEditHeaderRenderer']);
    }

    if (contents != null) {
      Map? tabRenderer = nav(contents,
          ['singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer']);
      Map? sectionListRenderer =
          nav(tabRenderer, ['content', 'sectionListRenderer']) ??
              nav(contents, [
                'twoColumnBrowseResultsRenderer',
                'secondaryContents',
                'sectionListRenderer'
              ]);
      List? chips =
      nav(sectionListRenderer, ['header', 'chipCloudRenderer', 'chips']);
      if (chips != null) {
        result['chips'] = [];
        result['chips'].addAll(handleChips(chips));
      }
      String? cont = nav(sectionListRenderer,
          ['continuations', 0, 'nextContinuationData', 'continuation']) ??
          nav(sectionListRenderer, [
            'contents',
            0,
            'musicShelfRenderer',
            'continuations',
            0,
            'nextContinuationData',
            'continuation'
          ]);

      String? continuationparams;
      if (cont != null) {
        continuationparams = getContinuationString(cont);
        result['continuation'] = continuationparams;
      } else {
        result['continuation'] = null;
      }

      List finalContents = nav(sectionListRenderer, ['contents']);

      result['sections'] = handleOuterContents(finalContents,
          thumbnails: result['header']?['thumbnails']);
      (result['sections'] as List).removeWhere((el) => el['contents'].isEmpty);
      if (limit > 1 && continuationparams != null) {
        limit = limit - 1;

        var data = await browseContinuation(
            body: body, limit: limit, additionalParams: continuationparams);
        if (data['sections'] != null) {
          if (data['addToLast'] == true) {
            result['sections']
                .last['contents']
                .addAll(data['sections'].first['contents']);
          } else {
            result['sections']
                .addAll(data['sections'].cast<Map<String, dynamic>>());
          }
        }
        result['continuation'] = data['continuation'];
      }
    } else {
      result['sections'] = List<Map<String, dynamic>>.empty();
    }
    return result;
  }

  Future<Map<String, dynamic>> browseContinuation(
      {Map<String, dynamic>? body,
        int limit = 1,
        String additionalParams = ''}) async {
    String endpoint = 'browse';
    body ??= {"browseId": "FEmusic_home"};

    var response =
    await sendRequest(endpoint, body, additionalParams: additionalParams);
    Map<String, dynamic> result = {'sections': []};

    List? contents = nav(response,
        ['continuationContents', 'sectionListContinuation', 'contents']) ??
        nav(response,
            ['continuationContents', 'musicShelfContinuation', 'contents']);

    if (contents == null) return {};
    if (nav(response,
        ['continuationContents', 'musicShelfContinuation', 'contents']) !=
        null) {
      result['sections'].add({'contents': handleContents(contents)});
      result['addToLast'] = true;
    } else {
      result['sections'] = handleOuterContents(contents);
    }

    String? continuations = nav(response, [
      'continuationContents',
      'sectionListContinuation',
      'continuations',
      0,
      'nextContinuationData',
      'continuation'
    ]) ??
        nav(response, [
          'continuationContents',
          'musicShelfContinuation',
          'continuations',
          0,
          'nextContinuationData',
          'continuation'
        ]);
    if (continuations != null) {
      String? continuationparams = getContinuationString(continuations);
      result['continuation'] = continuationparams;
    } else {
      result['continuation'] = null;
    }

    if (limit > 1 && result['continuation'] != null) {
      limit = limit - 1;
      var data = await browse(
          body: body, limit: limit, additionalParams: result['continuation']);
      if (data['sections'] != null) {
        result['sections'].addAll(data['sections']);
      }
      result['continuation'] = data['continuation'];
    }

    return result;
  }

  Future<Map<String, dynamic>> getMoreItems({continuation = ''}) async {
    String endpoint = 'browse';
    Map<String, dynamic>? body = {"browseId": "FEmusic_home"};

    var response =
    await sendRequest(endpoint, body, additionalParams: continuation);
    String? continuationString = nav(response, [
      'continuationContents',
      'musicPlaylistShelfContinuation',
      'continuations',
      0,
      'nextContinuationData',
      'continuation'
    ]);
    List contents = nav(response, [
      'continuationContents',
      'musicPlaylistShelfContinuation',
      'contents'
    ]) ??
        [];
    return {
      'items': handleContents(contents),
      'continuation': continuationString != null
          ? getContinuationString(continuationString)
          : null,
    };
  }

  int getDatestamp() {
    final DateTime now = DateTime.now();
    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final Duration difference = now.difference(epoch);
    final int days = difference.inDays;
    return days;
  }

  Future addYoutubeHistory(String videoId) async {
    try {
      // SP-71: only worth a round-trip when an account is connected — an
      // anonymous ping attributes to nobody and just burns a request.
      if (!YtmAuth.instance.loggedIn.value) return;
      signatureTimestamp = signatureTimestamp ?? getDatestamp() - 1;
      Map<String, dynamic> body = {};
      body['playbackContext'] = {
        'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
      };
      body['video_id'] = videoId;

      final Map response = await sendRequest('player', body);
      if (response.isEmpty) return;
      // Non-YouTube ids (Spotify/JioSaavn songs routed here) return a
      // player response without playbackTracking — bail instead of
      // crashing on a null [] (NoSuchMethodError "videostatsPlaybackUrl").
      final tracking = response['playbackTracking'];
      dynamic baseUrl;
      if (tracking is Map) {
        baseUrl = tracking['videostatsPlaybackUrl']?['baseUrl'];
      }
      if (baseUrl is! String || baseUrl.isEmpty) {
        // SP-71: say WHY nothing was recorded — the old silent bail made
        // "Listen again stays empty" undiagnosable from a run log.
        debugPrint('[ytm-history] no playbackTracking for $videoId');
        return;
      }
      String url = baseUrl;
      const String cpna =
          "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_";
      Random rand = Random();

      String generateCpn() {
        return List.generate(16, (index) => cpna[rand.nextInt(64)]).join();
      }

      String cpn = generateCpn();
      Map<String, dynamic> params = {"ver": 2, "c": "WEB_REMIX", "cpn": cpn};
      params.forEach((k, v) {
        url += '&$k=$v';
      });
      // SP-71: one visible line per recorded play — the next run log must
      // prove that in-app listening actually lands in the account history.
      final res = await sendGetRequest(url, headers);
      debugPrint('[ytm-history] recorded $videoId (HTTP ${res.statusCode})');
    } catch (e) {
      // History is best-effort telemetry: never let it crash playback.
      print('[addYoutubeHistory] skipped: $e');
    }
  }

  Future<Map<String, dynamic>?> getSongDetails(String videoId) async {
    Map<String, dynamic> body = {"videoId": videoId};
    final Map response = await sendRequest('player', body);
    Map? videoDetails = response['videoDetails'];
    if (videoDetails != null) {
      return {
        'videoId': videoDetails['videoId'],
        'channelId': videoDetails['channelId'],
        'title': videoDetails['title'],
        'subtitle': videoDetails['author'],
        'length': videoDetails['lengthSeconds'],
        'viewCount': videoDetails['viewCount'],
        'thumbnails': videoDetails['thumbnail']['thumbnails'],
        'type': itemCategory[videoDetails['musicVideoType']],
      };
    }
    return null;
  }

  Future<List> getNextSongList({
    String? videoId,
    String? playlistId,
    String? params,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
  }) async {
    try {
      Map<String, dynamic> body = Map.from(context);
      body['enablePersistentPlaylistPanel'] = true;
      body['isAudioOnly'] = true;
      body['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';

      if (videoId == null && playlistId == null) {
        return [];
      }
      if (videoId != null) {
        body['videoId'] = videoId;
        playlistId ??= 'RDAMVM$videoId';
        if (!(radio || shuffle)) {
          body['watchEndpointMusicSupportedConfigs'] = {
            'watchEndpointMusicConfig': {
              'hasPersistentPlaylistPanel': true,
              'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV;',
            }
          };
        }
      }

      body['playlistId'] = playlistIdTrimmer(playlistId!);

      if (shuffle) body['params'] = 'wAEB8gECKAE%3D';
      if (radio) body['params'] = 'wAEB';
      if (params != null) body['params'] = params;
      final Map response = await sendRequest('next', body);
      dynamic contents = nav(response, [
        'contents',
        'singleColumnMusicWatchNextResultsRenderer',
        'tabbedRenderer',
        'watchNextTabbedResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer',
        'contents'
      ]);

      List result = handleContents(contents);
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<List> getPlaylistSongs(String playlistId) async {
    Map<String, dynamic> body = {
      "browseId": playlistId.startsWith('VL') ? playlistId : 'VL$playlistId'
    };
    var response = await sendRequest('browse', body);

    List contents = nav(response, [
      'contents',
      'singleColumnBrowseResultsRenderer',
      'tabs',
      0,
      'tabRenderer',
      'content',
      'sectionListRenderer',
      'contents',
      0,
      'musicPlaylistShelfRenderer',
      'contents'
    ]) ??
        nav(response, [
          'contents',
          'twoColumnBrowseResultsRenderer',
          'secondaryContents',
          'sectionListRenderer',
          'contents',
          0,
          'musicPlaylistShelfRenderer',
          'contents'
        ]);

    List result = handleContents(contents);

    return result;
  }
}

List handleChips(chips) {
  List resultChips = [];
  for (Map chip in chips) {
    chip = chip['chipCloudChipRenderer'];
    resultChips.add({
      'title': nav(chip, ['text', 'runs', 0, 'text']),
      'selected': nav(chip, ['isSelected']) ?? false,
      'endpoint': nav(chip, ['navigationEndpoint', 'browseEndpoint']),
    });
  }
  return resultChips;
}

List<Map<String, dynamic>> handleOuterContents(List contents,
    {List? thumbnails}) {
  List<Map<String, dynamic>> results = [];
  for (Map content in contents) {
    Map<String, dynamic> result = {};
    result['contents'] = [];
    Map? musicPlaylistShelfRenderer =
    nav(content, ['musicPlaylistShelfRenderer']);
    Map? musicShelfRenderer = nav(content, ['musicShelfRenderer']);
    Map? musicCarouselShelfRenderer =
    nav(content, ['musicCarouselShelfRenderer']);
    Map? gridRenderer = nav(content, ['gridRenderer']);
    if (musicCarouselShelfRenderer != null) {
      results.add(handleMusicCarouselShelfRenderer(musicCarouselShelfRenderer));
    } else if (musicPlaylistShelfRenderer != null) {
      results.add(handleMusicPlaylistShelfRenderer(musicPlaylistShelfRenderer));
    } else if (musicShelfRenderer != null) {
      results.add(
          handleMusicShelfRenderer(musicShelfRenderer, thumbnails: thumbnails));
    } else if (gridRenderer != null) {
      results.add(handleGridRenderer(gridRenderer));
    } else {}
    results.add(result);
  }

  return results;
}

handleMusicCarouselShelfRenderer(Map item) {
  Map<String, dynamic> section = {};
  section.addAll(handleHeader(
      nav(item, ['header', 'musicCarouselShelfBasicHeaderRenderer'])));
  if (item['numItemsPerColumn'] != null &&
      (int.parse(item['numItemsPerColumn'] ?? 0)) >= 4) {
    section['viewType'] = 'COLUMN';
  } else {
    section['viewType'] = 'ROW';
  }
  section['thumbnails'] = nav(item, [
    'header',
    'musicCarouselShelfBasicHeaderRenderer',
    'thumbnail',
    'musicThumbnailRenderer',
    'thumbnail',
    'thumbnails'
  ]);
  section['contents'] = [];
  List? contents = nav(item, ['contents']);

  if (contents != null) {
    section['contents'].addAll(handleContents(contents));
  }

  return section;
}

Map<String, dynamic> handleHeader(Map header) {
  Map<String, dynamic> res = {
    'title': nav(header, ['title', 'runs', 0, 'text']),
    'strapline': nav(header, ['strapline', 'runs', 0, 'text']),
    'trailing': nav(header, ['moreContentButton']) != null
        ? {
      'text': nav(header, [
        'moreContentButton',
        'buttonRenderer',
        'text',
        'runs',
        0,
        'text'
      ]),
      'playable': nav(header, [
        'moreContentButton',
        'buttonRenderer',
        'navigationEndpoint',
        'watchPlaylistEndpoint'
      ]) !=
          null,
      'endpoint': nav(header, [
        'moreContentButton',
        'buttonRenderer',
        'navigationEndpoint',
        'watchPlaylistEndpoint'
      ]) ??
          nav(header, [
            'moreContentButton',
            'buttonRenderer',
            'navigationEndpoint',
            'browseEndpoint'
          ]),
    }
        : null,
  };

  res.removeWhere((key, val) => val == null);
  return res;
}

String playlistIdTrimmer(String playlistId) {
  if (playlistId.startsWith('VL')) {
    return playlistId.substring(2);
  } else {
    return playlistId;
  }
}
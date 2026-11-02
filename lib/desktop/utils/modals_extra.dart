// ZenMusic · vorlon-dev

import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:zenmusic/desktop/core/extensions.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/themes/colors.dart';
import 'package:zenmusic/desktop/themes/text_styles.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/playlist_thumbnail.dart';

class DownloadModals {
  static void showDownloadBottomModal(BuildContext context) {
    showModalBottomSheet(
      useRootNavigator: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      isScrollControlled: true,
      context: context,
      builder: (context) => _downloadBottomModal(context),
    );
  }

  static void showDownloadDetailsBottomModal(
      BuildContext context, Map playlist) {
    showModalBottomSheet(
      useRootNavigator: false,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      context: context,
      builder: (context) => _downloadDetailsBottomModal(context, playlist),
    );
  }
}

class AccentModals {
  static void showAccentSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _accentSelector(context),
    );
  }
}

BottomModalLayout _downloadBottomModal(BuildContext context) {
  return BottomModalLayout(
    title: AdaptiveListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Downloads',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: greyColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          AdaptiveIcons.download,
          color: context.isDarkMode ? Colors.white : Colors.black,
        ),
      ),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdaptiveListTile(
            dense: true,
            title: const Text('Downloading'),
            leading: Icon(AdaptiveIcons.downloading),
            onTap: () async {
              context.push('/saved/downloads_page/downloading_page');
              Navigator.pop(context);
            },
          ),
          AdaptiveListTile(
            dense: true,
            title: const Text('Restore Missing Songs'),
            leading: Icon(AdaptiveIcons.sync),
            onTap: () async {
              Navigator.pop(context);
              BottomMessage.showText(context, 'Restoring missing songs');
              GetIt.I<DownloadManager>().restoreDownloads();
            },
          ),
          AdaptiveListTile(
            dense: true,
            title: const Text('Delete All Songs'),
            leading: Icon(AdaptiveIcons.delete),
            onTap: () async {
              bool shouldDelete = await Modals.showConfirmBottomModal(context,
                  message: 'Delete ALL downloaded songs? This cannot be undone.',
                  isDanger: true,
                  doneText: 'Yes',
                  cancelText: 'No');
              if (shouldDelete) {
                Navigator.pop(context);
                BottomMessage.showText(context, 'Deleting songs');
                List songs = Hive.box('DOWNLOADS').values.toList();
                for (var song in songs) {
                  await Hive.box('DOWNLOADS').delete(song['videoId']);
                  if (song.containsKey('path')) {
                    String path = song['path'];
                    try {
                      File(path).delete();
                    } catch (e) {
                      debugPrint(e.toString());
                    }
                  }
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}

BottomModalLayout _downloadDetailsBottomModal(
    BuildContext context, Map playlist) {
  return BottomModalLayout(
    title: AdaptiveListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(playlist['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: (playlist['songs']?.length > 0)
          ? PlaylistThumbnail(playslist: playlist['songs'], size: 50, radius: 8)
          : Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: greyColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          CupertinoIcons.music_note_list,
          color: Colors.white,
        ),
      ),
      subtitle: playlist['subtitle'] != null
          ? Text(playlist['subtitle'],
          maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdaptiveListTile(
            dense: true,
            title: const Text('Restore Missing Songs'),
            leading: const Icon(Icons.restore),
            onTap: () async {
              Navigator.pop(context);
              BottomMessage.showText(context, 'Restoring missing songs');
              GetIt.I<DownloadManager>()
                  .restoreDownloads(songs: playlist['songs']);
            },
          ),
          AdaptiveListTile(
            dense: true,
            title: const Text('Delete All Songs'),
            leading: Icon(AdaptiveIcons.delete),
            onTap: () async {
              Modals.showConfirmBottomModal(
                context,
                message: 'Delete ALL songs in this playlist?',
                isDanger: true,
              ).then(
                    (bool confirm) async {
                  if (confirm) {
                    Navigator.pop(context);
                    BottomMessage.showText(context, 'Deleting songs');
                    for (var song in playlist['songs']) {
                      await GetIt.I<DownloadManager>().deleteSong(
                        key: song['videoId'],
                        path: song['path'],
                        playlistId: playlist['id'],
                      );
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}

BottomModalLayout _accentSelector(BuildContext context) {
  Color? accentColor = GetIt.I<SettingsManager>().accentColor;
  return BottomModalLayout(
    title: Center(
      child: Text('Select Color', style: mediumTextStyle(context)),
    ),
    actions: [
      AdaptiveButton(
        onPressed: () {
          Navigator.pop(context);
          GetIt.I<SettingsManager>().accentColor = null;
        },
        child: const Text('Reset'),
      ),
      AdaptiveFilledButton(
        child: const Text('Done'),
        onPressed: () => Navigator.pop(context),
      ),
    ],
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColorPicker(
          pickerColor: accentColor ?? Colors.white,
          onColorChanged: (color) {
            GetIt.I<SettingsManager>().accentColor = color;
          },
          labelTypes: const [],
          portraitOnly: true,
          colorPickerWidth: min(300, MediaQuery.of(context).size.width - 32),
          pickerAreaHeightPercent: 0.7,
          enableAlpha: false,
          displayThumbColor: false,
          paletteType: PaletteType.hueWheel,
        ),
      ],
    ),
  );
}

// ZenMusic · vorlon-dev

import 'dart:io';

import 'package:easy_folder_picker/FolderPicker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenmusic/desktop/screens/settings/backup_storage/cubit/backup_storage_cubit.dart';
import 'package:zenmusic/desktop/screens/settings/widgets/setting_item.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';

class BackupStoragePage extends StatelessWidget {
  const BackupStoragePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BackupStorageCubit(),
      child: BlocListener<BackupStorageCubit, BackupStorageState>(
        listenWhen: (_, state) => state.lastResult != null,
        listener: (context, state) {
          final result = state.lastResult;
          if (result == null) return;

          if (result is BackupSuccess) {
            BottomMessage.showText(
              context,
              'Backup saved: ${result.path}',
            );
          } else if (result is BackupFailure) {
            BottomMessage.showText(
              context,
              'Backup failed',
            );
          } else if (result is RestoreSuccess) {
            BottomMessage.showText(
              context,
              'Restore successful',
            );
          } else if (result is RestoreFailure) {
            BottomMessage.showText(
              context,
              'Restore failed',
            );
          }
        },
        child: const _BackupStoragePage(),
      ),
    );
  }
}

class _BackupStoragePage extends StatelessWidget {
  const _BackupStoragePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup and Restore'),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: BlocBuilder<BackupStorageCubit, BackupStorageState>(
            builder: (context, state) {
              final cubit = context.read<BackupStorageCubit>();

              return ListView(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  if (Platform.isAndroid) ...[
                    const GroupTitle(title: "Storage"),
                    SettingTile(
                      title: "App Folder",
                      leading: const Icon(CupertinoIcons.folder),
                      isFirst: true,
                      isLast: true,
                      subtitle: state.appFolder,
                      trailing: AdaptiveOutlinedButton(
                        child: const Text('Change'),
                        onPressed: () async {
                          final dir = await FolderPicker.pick(
                            context: context,
                            allowFolderCreation: true,
                            rootDirectory: Directory(state.appFolder),
                          );
                          if (dir != null) {
                            cubit.setAppFolder(dir.path);
                          }
                        },
                      ),
                    ),
                  ],

                  const GroupTitle(title: "Backup and Restore"),

                  /// BACKUP
                  SettingTile(
                    title: 'Backup',
                    leading: const Icon(Icons.backup_outlined),
                    isFirst: true,
                    onTap: () async {
                      final result = await showBackupSelector(context);
                      if (result == null) return;

                      cubit.backup(
                        action: result.$1,
                        items: result.$2,
                      );
                    },
                  ),

                  /// RESTORE
                  SettingTile(
                    title: 'Restore',
                    leading: const Icon(Icons.restore_outlined),
                    isLast: true,
                    onTap: cubit.restore,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}


Future<(String, List)?> showBackupSelector(BuildContext context) async {
  return await showCupertinoModalPopup<(String, List)?>(
    useRootNavigator: false,
    context: context,
    builder: (context) {
      final items = ValueNotifier<List<Map<String, dynamic>>>([
        {'name': 'Favourites', 'selected': false},
        {'name': 'Playlists', 'selected': false},
        {'name': 'Settings', 'selected': false},
        {'name': 'Song History', 'selected': false},
        {'name': 'Downloads', 'selected': false},
      ]);

      return BottomModalLayout(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Select Backup'),
                centerTitle: true,
                automaticallyImplyLeading: false,
              ),
              const Divider(),
              ValueListenableBuilder(
                valueListenable: items,
                builder: (_, backups, __) {
                  return Column(
                    children: backups.indexed.map((el) {
                      final index = el.$1;
                      final item = el.$2;

                      return CheckboxListTile(
                        title: Text(item['name']),
                        value: item['selected'],
                        onChanged: (val) {
                          final newItems = List<Map<String, dynamic>>.from(
                            items.value,
                          );
                          newItems[index]['selected'] = val;
                          items.value = newItems;
                        },
                      );
                    }).toList(),
                  );
                },
              ),
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _backupActionButton(
                      context,
                      label: 'Share',
                      action: 'Share',
                      items: items,
                    ),
                    const SizedBox(width: 20),
                    _backupActionButton(
                      context,
                      label: 'Save',
                      action: 'Save',
                      items: items,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _backupActionButton(
    BuildContext context, {
      required String label,
      required String action,
      required ValueNotifier<List<Map<String, dynamic>>> items,
    }) {
  return MaterialButton(
    color: Theme.of(context).colorScheme.primary,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
    onPressed: () {
      final selected = items.value
          .where((e) => e['selected'] == true)
          .map((e) => e['name'].toLowerCase())
          .toList();

      Navigator.pop(
        context,
        selected.isEmpty ? null : (action, selected),
      );
    },
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
    ),
  );
}

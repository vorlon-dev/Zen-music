import 'package:hive_flutter/hive_flutter.dart';

class LocalCacheService {
  static const _boxName = 'SETTINGS';
  static const _kQueue = 'CACHE_QUEUE';
  static const _kIndex = 'CACHE_INDEX';
  static const _kPosition = 'CACHE_POSITION';

  static Future<void> saveState({
    required List<Map<String, dynamic>> queue,
    required int index,
    required Duration position,
  }) async {
    final box = Hive.box(_boxName);
    await box.put(_kQueue, queue);
    await box.put(_kIndex, index);
    await box.put(_kPosition, position.inMilliseconds);
  }

  static (List<Map<String, dynamic>>?, int, Duration) loadState() {
    final box = Hive.box(_boxName);
    final queue = box.get(_kQueue) as List?;
    final index = box.get(_kIndex, defaultValue: 0) as int;
    final posMs = box.get(_kPosition, defaultValue: 0) as int;

    if (queue == null) return (null, 0, Duration.zero);

    final typedQueue = queue
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return (typedQueue, index, Duration(milliseconds: posMs));
  }

  static Future<void> clearState() async {
    final box = Hive.box(_boxName);
    await box.delete(_kQueue);
    await box.delete(_kIndex);
    await box.delete(_kPosition);
  }
}
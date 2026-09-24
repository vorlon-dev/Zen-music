// This is a generated file - do not edit.
//
// Generated from listentogether.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Message envelope with type and payload
class Envelope extends $pb.GeneratedMessage {
  factory Envelope({
    $core.String? type,
    $core.List<$core.int>? payload,
    $core.bool? compressed,
  }) {
    final result = Envelope._();
    if (type != null) result.type = type;
    if (payload != null) result.payload = payload;
    if (compressed != null) result.compressed = compressed;
    return result;
  }

  Envelope._();

  factory Envelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Envelope()..mergeFromBuffer(data, registry);
  factory Envelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Envelope()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Envelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: Envelope.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'type')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'compressed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope copyWith(void Function(Envelope) updates) =>
      super.copyWith((message) => updates(message as Envelope)) as Envelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Envelope() / Envelope.new instead')
  static Envelope create() => Envelope._();
  static $pb.GeneratedMessage $_createMessage() => Envelope._();
  @$core.override
  Envelope createEmptyInstance() => Envelope._();
  @$core.pragma('dart2js:noInline')
  static Envelope getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Envelope>(Envelope.$_createMessage);
  static Envelope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get type => $_getSZ(0);
  @$pb.TagNumber(1)
  set type($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get payload => $_getN(1);
  @$pb.TagNumber(2)
  set payload($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPayload() => $_has(1);
  @$pb.TagNumber(2)
  void clearPayload() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get compressed => $_getBF(2);
  @$pb.TagNumber(3)
  set compressed($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCompressed() => $_has(2);
  @$pb.TagNumber(3)
  void clearCompressed() => $_clearField(3);
}

/// Track information
class TrackInfo extends $pb.GeneratedMessage {
  factory TrackInfo({
    $core.String? id,
    $core.String? title,
    $core.String? artist,
    $core.String? album,
    $fixnum.Int64? duration,
    $core.String? thumbnail,
    $core.String? suggestedBy,
  }) {
    final result = TrackInfo._();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (artist != null) result.artist = artist;
    if (album != null) result.album = album;
    if (duration != null) result.duration = duration;
    if (thumbnail != null) result.thumbnail = thumbnail;
    if (suggestedBy != null) result.suggestedBy = suggestedBy;
    return result;
  }

  TrackInfo._();

  factory TrackInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrackInfo()..mergeFromBuffer(data, registry);
  factory TrackInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TrackInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TrackInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: TrackInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'artist')
    ..aOS(4, _omitFieldNames ? '' : 'album')
    ..aInt64(5, _omitFieldNames ? '' : 'duration')
    ..aOS(6, _omitFieldNames ? '' : 'thumbnail')
    ..aOS(7, _omitFieldNames ? '' : 'suggestedBy')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrackInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TrackInfo copyWith(void Function(TrackInfo) updates) =>
      super.copyWith((message) => updates(message as TrackInfo)) as TrackInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TrackInfo() / TrackInfo.new instead')
  static TrackInfo create() => TrackInfo._();
  static $pb.GeneratedMessage $_createMessage() => TrackInfo._();
  @$core.override
  TrackInfo createEmptyInstance() => TrackInfo._();
  @$core.pragma('dart2js:noInline')
  static TrackInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TrackInfo>(TrackInfo.$_createMessage);
  static TrackInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get artist => $_getSZ(2);
  @$pb.TagNumber(3)
  set artist($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasArtist() => $_has(2);
  @$pb.TagNumber(3)
  void clearArtist() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get album => $_getSZ(3);
  @$pb.TagNumber(4)
  set album($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAlbum() => $_has(3);
  @$pb.TagNumber(4)
  void clearAlbum() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get duration => $_getI64(4);
  @$pb.TagNumber(5)
  set duration($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDuration() => $_has(4);
  @$pb.TagNumber(5)
  void clearDuration() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get thumbnail => $_getSZ(5);
  @$pb.TagNumber(6)
  set thumbnail($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasThumbnail() => $_has(5);
  @$pb.TagNumber(6)
  void clearThumbnail() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get suggestedBy => $_getSZ(6);
  @$pb.TagNumber(7)
  set suggestedBy($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSuggestedBy() => $_has(6);
  @$pb.TagNumber(7)
  void clearSuggestedBy() => $_clearField(7);
}

/// User information
class UserInfo extends $pb.GeneratedMessage {
  factory UserInfo({
    $core.String? userId,
    $core.String? username,
    $core.bool? isHost,
    $core.bool? isConnected,
  }) {
    final result = UserInfo._();
    if (userId != null) result.userId = userId;
    if (username != null) result.username = username;
    if (isHost != null) result.isHost = isHost;
    if (isConnected != null) result.isConnected = isConnected;
    return result;
  }

  UserInfo._();

  factory UserInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserInfo()..mergeFromBuffer(data, registry);
  factory UserInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: UserInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOB(3, _omitFieldNames ? '' : 'isHost')
    ..aOB(4, _omitFieldNames ? '' : 'isConnected')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserInfo copyWith(void Function(UserInfo) updates) =>
      super.copyWith((message) => updates(message as UserInfo)) as UserInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UserInfo() / UserInfo.new instead')
  static UserInfo create() => UserInfo._();
  static $pb.GeneratedMessage $_createMessage() => UserInfo._();
  @$core.override
  UserInfo createEmptyInstance() => UserInfo._();
  @$core.pragma('dart2js:noInline')
  static UserInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UserInfo>(UserInfo.$_createMessage);
  static UserInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isHost => $_getBF(2);
  @$pb.TagNumber(3)
  set isHost($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIsHost() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsHost() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isConnected => $_getBF(3);
  @$pb.TagNumber(4)
  set isConnected($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsConnected() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsConnected() => $_clearField(4);
}

/// Room state
class RoomState extends $pb.GeneratedMessage {
  factory RoomState({
    $core.String? roomCode,
    $core.String? hostId,
    $core.Iterable<UserInfo>? users,
    TrackInfo? currentTrack,
    $core.bool? isPlaying,
    $fixnum.Int64? position,
    $fixnum.Int64? lastUpdate,
    $core.double? volume,
    $core.Iterable<TrackInfo>? queue,
    $fixnum.Int64? revision,
  }) {
    final result = RoomState._();
    if (roomCode != null) result.roomCode = roomCode;
    if (hostId != null) result.hostId = hostId;
    if (users != null) result.users.addAll(users);
    if (currentTrack != null) result.currentTrack = currentTrack;
    if (isPlaying != null) result.isPlaying = isPlaying;
    if (position != null) result.position = position;
    if (lastUpdate != null) result.lastUpdate = lastUpdate;
    if (volume != null) result.volume = volume;
    if (queue != null) result.queue.addAll(queue);
    if (revision != null) result.revision = revision;
    return result;
  }

  RoomState._();

  factory RoomState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RoomState()..mergeFromBuffer(data, registry);
  factory RoomState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RoomState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RoomState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: RoomState.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'roomCode')
    ..aOS(2, _omitFieldNames ? '' : 'hostId')
    ..pPM<UserInfo>(3, _omitFieldNames ? '' : 'users',
        subBuilder: UserInfo.$_createMessage)
    ..aOM<TrackInfo>(4, _omitFieldNames ? '' : 'currentTrack',
        subBuilder: TrackInfo.$_createMessage)
    ..aOB(5, _omitFieldNames ? '' : 'isPlaying')
    ..aInt64(6, _omitFieldNames ? '' : 'position')
    ..aInt64(7, _omitFieldNames ? '' : 'lastUpdate')
    ..aD(8, _omitFieldNames ? '' : 'volume', fieldType: $pb.PbFieldType.OF)
    ..pPM<TrackInfo>(9, _omitFieldNames ? '' : 'queue',
        subBuilder: TrackInfo.$_createMessage)
    ..a<$fixnum.Int64>(
        10, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RoomState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RoomState copyWith(void Function(RoomState) updates) =>
      super.copyWith((message) => updates(message as RoomState)) as RoomState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RoomState() / RoomState.new instead')
  static RoomState create() => RoomState._();
  static $pb.GeneratedMessage $_createMessage() => RoomState._();
  @$core.override
  RoomState createEmptyInstance() => RoomState._();
  @$core.pragma('dart2js:noInline')
  static RoomState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RoomState>(RoomState.$_createMessage);
  static RoomState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get roomCode => $_getSZ(0);
  @$pb.TagNumber(1)
  set roomCode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRoomCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearRoomCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get hostId => $_getSZ(1);
  @$pb.TagNumber(2)
  set hostId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHostId() => $_has(1);
  @$pb.TagNumber(2)
  void clearHostId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<UserInfo> get users => $_getList(2);

  @$pb.TagNumber(4)
  TrackInfo get currentTrack => $_getN(3);
  @$pb.TagNumber(4)
  set currentTrack(TrackInfo value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrentTrack() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrentTrack() => $_clearField(4);
  @$pb.TagNumber(4)
  TrackInfo ensureCurrentTrack() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.bool get isPlaying => $_getBF(4);
  @$pb.TagNumber(5)
  set isPlaying($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIsPlaying() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsPlaying() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get position => $_getI64(5);
  @$pb.TagNumber(6)
  set position($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPosition() => $_has(5);
  @$pb.TagNumber(6)
  void clearPosition() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get lastUpdate => $_getI64(6);
  @$pb.TagNumber(7)
  set lastUpdate($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLastUpdate() => $_has(6);
  @$pb.TagNumber(7)
  void clearLastUpdate() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get volume => $_getN(7);
  @$pb.TagNumber(8)
  set volume($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasVolume() => $_has(7);
  @$pb.TagNumber(8)
  void clearVolume() => $_clearField(8);

  @$pb.TagNumber(9)
  $pb.PbList<TrackInfo> get queue => $_getList(8);

  @$pb.TagNumber(10)
  $fixnum.Int64 get revision => $_getI64(9);
  @$pb.TagNumber(10)
  set revision($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRevision() => $_has(9);
  @$pb.TagNumber(10)
  void clearRevision() => $_clearField(10);
}

class CreateRoomPayload extends $pb.GeneratedMessage {
  factory CreateRoomPayload({
    $core.String? username,
  }) {
    final result = CreateRoomPayload._();
    if (username != null) result.username = username;
    return result;
  }

  CreateRoomPayload._();

  factory CreateRoomPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateRoomPayload()..mergeFromBuffer(data, registry);
  factory CreateRoomPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateRoomPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateRoomPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: CreateRoomPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRoomPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRoomPayload copyWith(void Function(CreateRoomPayload) updates) =>
      super.copyWith((message) => updates(message as CreateRoomPayload))
          as CreateRoomPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CreateRoomPayload() / CreateRoomPayload.new instead')
  static CreateRoomPayload create() => CreateRoomPayload._();
  static $pb.GeneratedMessage $_createMessage() => CreateRoomPayload._();
  @$core.override
  CreateRoomPayload createEmptyInstance() => CreateRoomPayload._();
  @$core.pragma('dart2js:noInline')
  static CreateRoomPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateRoomPayload>(
          CreateRoomPayload.$_createMessage);
  static CreateRoomPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get username => $_getSZ(0);
  @$pb.TagNumber(1)
  set username($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUsername() => $_has(0);
  @$pb.TagNumber(1)
  void clearUsername() => $_clearField(1);
}

class JoinRoomPayload extends $pb.GeneratedMessage {
  factory JoinRoomPayload({
    $core.String? roomCode,
    $core.String? username,
  }) {
    final result = JoinRoomPayload._();
    if (roomCode != null) result.roomCode = roomCode;
    if (username != null) result.username = username;
    return result;
  }

  JoinRoomPayload._();

  factory JoinRoomPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinRoomPayload()..mergeFromBuffer(data, registry);
  factory JoinRoomPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinRoomPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JoinRoomPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: JoinRoomPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'roomCode')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinRoomPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinRoomPayload copyWith(void Function(JoinRoomPayload) updates) =>
      super.copyWith((message) => updates(message as JoinRoomPayload))
          as JoinRoomPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JoinRoomPayload() / JoinRoomPayload.new instead')
  static JoinRoomPayload create() => JoinRoomPayload._();
  static $pb.GeneratedMessage $_createMessage() => JoinRoomPayload._();
  @$core.override
  JoinRoomPayload createEmptyInstance() => JoinRoomPayload._();
  @$core.pragma('dart2js:noInline')
  static JoinRoomPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<JoinRoomPayload>(
          JoinRoomPayload.$_createMessage);
  static JoinRoomPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get roomCode => $_getSZ(0);
  @$pb.TagNumber(1)
  set roomCode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRoomCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearRoomCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);
}

class LeaveRoomPayload extends $pb.GeneratedMessage {
  factory LeaveRoomPayload() => LeaveRoomPayload._();

  LeaveRoomPayload._();

  factory LeaveRoomPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LeaveRoomPayload()..mergeFromBuffer(data, registry);
  factory LeaveRoomPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LeaveRoomPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LeaveRoomPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: LeaveRoomPayload.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LeaveRoomPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LeaveRoomPayload copyWith(void Function(LeaveRoomPayload) updates) =>
      super.copyWith((message) => updates(message as LeaveRoomPayload))
          as LeaveRoomPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LeaveRoomPayload() / LeaveRoomPayload.new instead')
  static LeaveRoomPayload create() => LeaveRoomPayload._();
  static $pb.GeneratedMessage $_createMessage() => LeaveRoomPayload._();
  @$core.override
  LeaveRoomPayload createEmptyInstance() => LeaveRoomPayload._();
  @$core.pragma('dart2js:noInline')
  static LeaveRoomPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LeaveRoomPayload>(
          LeaveRoomPayload.$_createMessage);
  static LeaveRoomPayload? _defaultInstance;
}

class ApproveJoinPayload extends $pb.GeneratedMessage {
  factory ApproveJoinPayload({
    $core.String? userId,
  }) {
    final result = ApproveJoinPayload._();
    if (userId != null) result.userId = userId;
    return result;
  }

  ApproveJoinPayload._();

  factory ApproveJoinPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApproveJoinPayload()..mergeFromBuffer(data, registry);
  factory ApproveJoinPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApproveJoinPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApproveJoinPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: ApproveJoinPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApproveJoinPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApproveJoinPayload copyWith(void Function(ApproveJoinPayload) updates) =>
      super.copyWith((message) => updates(message as ApproveJoinPayload))
          as ApproveJoinPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ApproveJoinPayload() / ApproveJoinPayload.new instead')
  static ApproveJoinPayload create() => ApproveJoinPayload._();
  static $pb.GeneratedMessage $_createMessage() => ApproveJoinPayload._();
  @$core.override
  ApproveJoinPayload createEmptyInstance() => ApproveJoinPayload._();
  @$core.pragma('dart2js:noInline')
  static ApproveJoinPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ApproveJoinPayload>(
          ApproveJoinPayload.$_createMessage);
  static ApproveJoinPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);
}

class RejectJoinPayload extends $pb.GeneratedMessage {
  factory RejectJoinPayload({
    $core.String? userId,
    $core.String? reason,
  }) {
    final result = RejectJoinPayload._();
    if (userId != null) result.userId = userId;
    if (reason != null) result.reason = reason;
    return result;
  }

  RejectJoinPayload._();

  factory RejectJoinPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RejectJoinPayload()..mergeFromBuffer(data, registry);
  factory RejectJoinPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RejectJoinPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RejectJoinPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: RejectJoinPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RejectJoinPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RejectJoinPayload copyWith(void Function(RejectJoinPayload) updates) =>
      super.copyWith((message) => updates(message as RejectJoinPayload))
          as RejectJoinPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RejectJoinPayload() / RejectJoinPayload.new instead')
  static RejectJoinPayload create() => RejectJoinPayload._();
  static $pb.GeneratedMessage $_createMessage() => RejectJoinPayload._();
  @$core.override
  RejectJoinPayload createEmptyInstance() => RejectJoinPayload._();
  @$core.pragma('dart2js:noInline')
  static RejectJoinPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RejectJoinPayload>(
          RejectJoinPayload.$_createMessage);
  static RejectJoinPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class PlaybackActionPayload extends $pb.GeneratedMessage {
  factory PlaybackActionPayload({
    $core.String? action,
    $core.String? trackId,
    $fixnum.Int64? position,
    TrackInfo? trackInfo,
    $core.bool? insertNext,
    $core.Iterable<TrackInfo>? queue,
    $core.String? queueTitle,
    $core.double? volume,
    $fixnum.Int64? serverTime,
    $fixnum.Int64? revision,
    $fixnum.Int64? capturedAtServerTime,
  }) {
    final result = PlaybackActionPayload._();
    if (action != null) result.action = action;
    if (trackId != null) result.trackId = trackId;
    if (position != null) result.position = position;
    if (trackInfo != null) result.trackInfo = trackInfo;
    if (insertNext != null) result.insertNext = insertNext;
    if (queue != null) result.queue.addAll(queue);
    if (queueTitle != null) result.queueTitle = queueTitle;
    if (volume != null) result.volume = volume;
    if (serverTime != null) result.serverTime = serverTime;
    if (revision != null) result.revision = revision;
    if (capturedAtServerTime != null)
      result.capturedAtServerTime = capturedAtServerTime;
    return result;
  }

  PlaybackActionPayload._();

  factory PlaybackActionPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlaybackActionPayload()..mergeFromBuffer(data, registry);
  factory PlaybackActionPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PlaybackActionPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlaybackActionPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: PlaybackActionPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'action')
    ..aOS(2, _omitFieldNames ? '' : 'trackId')
    ..aInt64(3, _omitFieldNames ? '' : 'position')
    ..aOM<TrackInfo>(4, _omitFieldNames ? '' : 'trackInfo',
        subBuilder: TrackInfo.$_createMessage)
    ..aOB(5, _omitFieldNames ? '' : 'insertNext')
    ..pPM<TrackInfo>(6, _omitFieldNames ? '' : 'queue',
        subBuilder: TrackInfo.$_createMessage)
    ..aOS(7, _omitFieldNames ? '' : 'queueTitle')
    ..aD(8, _omitFieldNames ? '' : 'volume', fieldType: $pb.PbFieldType.OF)
    ..aInt64(9, _omitFieldNames ? '' : 'serverTime')
    ..a<$fixnum.Int64>(
        10, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(11, _omitFieldNames ? '' : 'capturedAtServerTime')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackActionPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackActionPayload copyWith(
          void Function(PlaybackActionPayload) updates) =>
      super.copyWith((message) => updates(message as PlaybackActionPayload))
          as PlaybackActionPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PlaybackActionPayload() / PlaybackActionPayload.new instead')
  static PlaybackActionPayload create() => PlaybackActionPayload._();
  static $pb.GeneratedMessage $_createMessage() => PlaybackActionPayload._();
  @$core.override
  PlaybackActionPayload createEmptyInstance() => PlaybackActionPayload._();
  @$core.pragma('dart2js:noInline')
  static PlaybackActionPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlaybackActionPayload>(
          PlaybackActionPayload.$_createMessage);
  static PlaybackActionPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get action => $_getSZ(0);
  @$pb.TagNumber(1)
  set action($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAction() => $_has(0);
  @$pb.TagNumber(1)
  void clearAction() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get trackId => $_getSZ(1);
  @$pb.TagNumber(2)
  set trackId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTrackId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTrackId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get position => $_getI64(2);
  @$pb.TagNumber(3)
  set position($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPosition() => $_has(2);
  @$pb.TagNumber(3)
  void clearPosition() => $_clearField(3);

  @$pb.TagNumber(4)
  TrackInfo get trackInfo => $_getN(3);
  @$pb.TagNumber(4)
  set trackInfo(TrackInfo value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasTrackInfo() => $_has(3);
  @$pb.TagNumber(4)
  void clearTrackInfo() => $_clearField(4);
  @$pb.TagNumber(4)
  TrackInfo ensureTrackInfo() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.bool get insertNext => $_getBF(4);
  @$pb.TagNumber(5)
  set insertNext($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasInsertNext() => $_has(4);
  @$pb.TagNumber(5)
  void clearInsertNext() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<TrackInfo> get queue => $_getList(5);

  @$pb.TagNumber(7)
  $core.String get queueTitle => $_getSZ(6);
  @$pb.TagNumber(7)
  set queueTitle($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasQueueTitle() => $_has(6);
  @$pb.TagNumber(7)
  void clearQueueTitle() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get volume => $_getN(7);
  @$pb.TagNumber(8)
  set volume($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasVolume() => $_has(7);
  @$pb.TagNumber(8)
  void clearVolume() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get serverTime => $_getI64(8);
  @$pb.TagNumber(9)
  set serverTime($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasServerTime() => $_has(8);
  @$pb.TagNumber(9)
  void clearServerTime() => $_clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get revision => $_getI64(9);
  @$pb.TagNumber(10)
  set revision($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRevision() => $_has(9);
  @$pb.TagNumber(10)
  void clearRevision() => $_clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get capturedAtServerTime => $_getI64(10);
  @$pb.TagNumber(11)
  set capturedAtServerTime($fixnum.Int64 value) => $_setInt64(10, value);
  @$pb.TagNumber(11)
  $core.bool hasCapturedAtServerTime() => $_has(10);
  @$pb.TagNumber(11)
  void clearCapturedAtServerTime() => $_clearField(11);
}

class PingPayload extends $pb.GeneratedMessage {
  factory PingPayload({
    $fixnum.Int64? clientTime,
    $fixnum.Int64? sequence,
  }) {
    final result = PingPayload._();
    if (clientTime != null) result.clientTime = clientTime;
    if (sequence != null) result.sequence = sequence;
    return result;
  }

  PingPayload._();

  factory PingPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PingPayload()..mergeFromBuffer(data, registry);
  factory PingPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PingPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PingPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: PingPayload.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'clientTime')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PingPayload copyWith(void Function(PingPayload) updates) =>
      super.copyWith((message) => updates(message as PingPayload))
          as PingPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PingPayload() / PingPayload.new instead')
  static PingPayload create() => PingPayload._();
  static $pb.GeneratedMessage $_createMessage() => PingPayload._();
  @$core.override
  PingPayload createEmptyInstance() => PingPayload._();
  @$core.pragma('dart2js:noInline')
  static PingPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PingPayload>(
          PingPayload.$_createMessage);
  static PingPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get clientTime => $_getI64(0);
  @$pb.TagNumber(1)
  set clientTime($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClientTime() => $_has(0);
  @$pb.TagNumber(1)
  void clearClientTime() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sequence => $_getI64(1);
  @$pb.TagNumber(2)
  set sequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequence() => $_clearField(2);
}

class BufferReadyPayload extends $pb.GeneratedMessage {
  factory BufferReadyPayload({
    $core.String? trackId,
  }) {
    final result = BufferReadyPayload._();
    if (trackId != null) result.trackId = trackId;
    return result;
  }

  BufferReadyPayload._();

  factory BufferReadyPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BufferReadyPayload()..mergeFromBuffer(data, registry);
  factory BufferReadyPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BufferReadyPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BufferReadyPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: BufferReadyPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'trackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferReadyPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferReadyPayload copyWith(void Function(BufferReadyPayload) updates) =>
      super.copyWith((message) => updates(message as BufferReadyPayload))
          as BufferReadyPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BufferReadyPayload() / BufferReadyPayload.new instead')
  static BufferReadyPayload create() => BufferReadyPayload._();
  static $pb.GeneratedMessage $_createMessage() => BufferReadyPayload._();
  @$core.override
  BufferReadyPayload createEmptyInstance() => BufferReadyPayload._();
  @$core.pragma('dart2js:noInline')
  static BufferReadyPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BufferReadyPayload>(
          BufferReadyPayload.$_createMessage);
  static BufferReadyPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set trackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrackId() => $_clearField(1);
}

class KickUserPayload extends $pb.GeneratedMessage {
  factory KickUserPayload({
    $core.String? userId,
    $core.String? reason,
  }) {
    final result = KickUserPayload._();
    if (userId != null) result.userId = userId;
    if (reason != null) result.reason = reason;
    return result;
  }

  KickUserPayload._();

  factory KickUserPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KickUserPayload()..mergeFromBuffer(data, registry);
  factory KickUserPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KickUserPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KickUserPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: KickUserPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KickUserPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KickUserPayload copyWith(void Function(KickUserPayload) updates) =>
      super.copyWith((message) => updates(message as KickUserPayload))
          as KickUserPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use KickUserPayload() / KickUserPayload.new instead')
  static KickUserPayload create() => KickUserPayload._();
  static $pb.GeneratedMessage $_createMessage() => KickUserPayload._();
  @$core.override
  KickUserPayload createEmptyInstance() => KickUserPayload._();
  @$core.pragma('dart2js:noInline')
  static KickUserPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KickUserPayload>(
          KickUserPayload.$_createMessage);
  static KickUserPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class TransferHostPayload extends $pb.GeneratedMessage {
  factory TransferHostPayload({
    $core.String? newHostId,
  }) {
    final result = TransferHostPayload._();
    if (newHostId != null) result.newHostId = newHostId;
    return result;
  }

  TransferHostPayload._();

  factory TransferHostPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TransferHostPayload()..mergeFromBuffer(data, registry);
  factory TransferHostPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TransferHostPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TransferHostPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: TransferHostPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'newHostId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransferHostPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TransferHostPayload copyWith(void Function(TransferHostPayload) updates) =>
      super.copyWith((message) => updates(message as TransferHostPayload))
          as TransferHostPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use TransferHostPayload() / TransferHostPayload.new instead')
  static TransferHostPayload create() => TransferHostPayload._();
  static $pb.GeneratedMessage $_createMessage() => TransferHostPayload._();
  @$core.override
  TransferHostPayload createEmptyInstance() => TransferHostPayload._();
  @$core.pragma('dart2js:noInline')
  static TransferHostPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TransferHostPayload>(
          TransferHostPayload.$_createMessage);
  static TransferHostPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get newHostId => $_getSZ(0);
  @$pb.TagNumber(1)
  set newHostId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNewHostId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNewHostId() => $_clearField(1);
}

class SuggestTrackPayload extends $pb.GeneratedMessage {
  factory SuggestTrackPayload({
    TrackInfo? trackInfo,
  }) {
    final result = SuggestTrackPayload._();
    if (trackInfo != null) result.trackInfo = trackInfo;
    return result;
  }

  SuggestTrackPayload._();

  factory SuggestTrackPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestTrackPayload()..mergeFromBuffer(data, registry);
  factory SuggestTrackPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestTrackPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SuggestTrackPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: SuggestTrackPayload.$_createMessage)
    ..aOM<TrackInfo>(1, _omitFieldNames ? '' : 'trackInfo',
        subBuilder: TrackInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestTrackPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestTrackPayload copyWith(void Function(SuggestTrackPayload) updates) =>
      super.copyWith((message) => updates(message as SuggestTrackPayload))
          as SuggestTrackPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use SuggestTrackPayload() / SuggestTrackPayload.new instead')
  static SuggestTrackPayload create() => SuggestTrackPayload._();
  static $pb.GeneratedMessage $_createMessage() => SuggestTrackPayload._();
  @$core.override
  SuggestTrackPayload createEmptyInstance() => SuggestTrackPayload._();
  @$core.pragma('dart2js:noInline')
  static SuggestTrackPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SuggestTrackPayload>(
          SuggestTrackPayload.$_createMessage);
  static SuggestTrackPayload? _defaultInstance;

  @$pb.TagNumber(1)
  TrackInfo get trackInfo => $_getN(0);
  @$pb.TagNumber(1)
  set trackInfo(TrackInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTrackInfo() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrackInfo() => $_clearField(1);
  @$pb.TagNumber(1)
  TrackInfo ensureTrackInfo() => $_ensure(0);
}

class ApproveSuggestionPayload extends $pb.GeneratedMessage {
  factory ApproveSuggestionPayload({
    $core.String? suggestionId,
  }) {
    final result = ApproveSuggestionPayload._();
    if (suggestionId != null) result.suggestionId = suggestionId;
    return result;
  }

  ApproveSuggestionPayload._();

  factory ApproveSuggestionPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApproveSuggestionPayload()..mergeFromBuffer(data, registry);
  factory ApproveSuggestionPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApproveSuggestionPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApproveSuggestionPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: ApproveSuggestionPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'suggestionId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApproveSuggestionPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApproveSuggestionPayload copyWith(
          void Function(ApproveSuggestionPayload) updates) =>
      super.copyWith((message) => updates(message as ApproveSuggestionPayload))
          as ApproveSuggestionPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ApproveSuggestionPayload() / ApproveSuggestionPayload.new instead')
  static ApproveSuggestionPayload create() => ApproveSuggestionPayload._();
  static $pb.GeneratedMessage $_createMessage() => ApproveSuggestionPayload._();
  @$core.override
  ApproveSuggestionPayload createEmptyInstance() =>
      ApproveSuggestionPayload._();
  @$core.pragma('dart2js:noInline')
  static ApproveSuggestionPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ApproveSuggestionPayload>(
          ApproveSuggestionPayload.$_createMessage);
  static ApproveSuggestionPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get suggestionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set suggestionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuggestionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuggestionId() => $_clearField(1);
}

class RejectSuggestionPayload extends $pb.GeneratedMessage {
  factory RejectSuggestionPayload({
    $core.String? suggestionId,
    $core.String? reason,
  }) {
    final result = RejectSuggestionPayload._();
    if (suggestionId != null) result.suggestionId = suggestionId;
    if (reason != null) result.reason = reason;
    return result;
  }

  RejectSuggestionPayload._();

  factory RejectSuggestionPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RejectSuggestionPayload()..mergeFromBuffer(data, registry);
  factory RejectSuggestionPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RejectSuggestionPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RejectSuggestionPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: RejectSuggestionPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'suggestionId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RejectSuggestionPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RejectSuggestionPayload copyWith(
          void Function(RejectSuggestionPayload) updates) =>
      super.copyWith((message) => updates(message as RejectSuggestionPayload))
          as RejectSuggestionPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RejectSuggestionPayload() / RejectSuggestionPayload.new instead')
  static RejectSuggestionPayload create() => RejectSuggestionPayload._();
  static $pb.GeneratedMessage $_createMessage() => RejectSuggestionPayload._();
  @$core.override
  RejectSuggestionPayload createEmptyInstance() => RejectSuggestionPayload._();
  @$core.pragma('dart2js:noInline')
  static RejectSuggestionPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RejectSuggestionPayload>(
          RejectSuggestionPayload.$_createMessage);
  static RejectSuggestionPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get suggestionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set suggestionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuggestionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuggestionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class ReconnectPayload extends $pb.GeneratedMessage {
  factory ReconnectPayload({
    $core.String? sessionToken,
  }) {
    final result = ReconnectPayload._();
    if (sessionToken != null) result.sessionToken = sessionToken;
    return result;
  }

  ReconnectPayload._();

  factory ReconnectPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconnectPayload()..mergeFromBuffer(data, registry);
  factory ReconnectPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconnectPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReconnectPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: ReconnectPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sessionToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconnectPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconnectPayload copyWith(void Function(ReconnectPayload) updates) =>
      super.copyWith((message) => updates(message as ReconnectPayload))
          as ReconnectPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReconnectPayload() / ReconnectPayload.new instead')
  static ReconnectPayload create() => ReconnectPayload._();
  static $pb.GeneratedMessage $_createMessage() => ReconnectPayload._();
  @$core.override
  ReconnectPayload createEmptyInstance() => ReconnectPayload._();
  @$core.pragma('dart2js:noInline')
  static ReconnectPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReconnectPayload>(
          ReconnectPayload.$_createMessage);
  static ReconnectPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionToken => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionToken($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionToken() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionToken() => $_clearField(1);
}

class RoomCreatedPayload extends $pb.GeneratedMessage {
  factory RoomCreatedPayload({
    $core.String? roomCode,
    $core.String? userId,
    $core.String? sessionToken,
  }) {
    final result = RoomCreatedPayload._();
    if (roomCode != null) result.roomCode = roomCode;
    if (userId != null) result.userId = userId;
    if (sessionToken != null) result.sessionToken = sessionToken;
    return result;
  }

  RoomCreatedPayload._();

  factory RoomCreatedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RoomCreatedPayload()..mergeFromBuffer(data, registry);
  factory RoomCreatedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RoomCreatedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RoomCreatedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: RoomCreatedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'roomCode')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'sessionToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RoomCreatedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RoomCreatedPayload copyWith(void Function(RoomCreatedPayload) updates) =>
      super.copyWith((message) => updates(message as RoomCreatedPayload))
          as RoomCreatedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RoomCreatedPayload() / RoomCreatedPayload.new instead')
  static RoomCreatedPayload create() => RoomCreatedPayload._();
  static $pb.GeneratedMessage $_createMessage() => RoomCreatedPayload._();
  @$core.override
  RoomCreatedPayload createEmptyInstance() => RoomCreatedPayload._();
  @$core.pragma('dart2js:noInline')
  static RoomCreatedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RoomCreatedPayload>(
          RoomCreatedPayload.$_createMessage);
  static RoomCreatedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get roomCode => $_getSZ(0);
  @$pb.TagNumber(1)
  set roomCode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRoomCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearRoomCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sessionToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set sessionToken($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessionToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionToken() => $_clearField(3);
}

class JoinRequestPayload extends $pb.GeneratedMessage {
  factory JoinRequestPayload({
    $core.String? userId,
    $core.String? username,
  }) {
    final result = JoinRequestPayload._();
    if (userId != null) result.userId = userId;
    if (username != null) result.username = username;
    return result;
  }

  JoinRequestPayload._();

  factory JoinRequestPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinRequestPayload()..mergeFromBuffer(data, registry);
  factory JoinRequestPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinRequestPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JoinRequestPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: JoinRequestPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinRequestPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinRequestPayload copyWith(void Function(JoinRequestPayload) updates) =>
      super.copyWith((message) => updates(message as JoinRequestPayload))
          as JoinRequestPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use JoinRequestPayload() / JoinRequestPayload.new instead')
  static JoinRequestPayload create() => JoinRequestPayload._();
  static $pb.GeneratedMessage $_createMessage() => JoinRequestPayload._();
  @$core.override
  JoinRequestPayload createEmptyInstance() => JoinRequestPayload._();
  @$core.pragma('dart2js:noInline')
  static JoinRequestPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<JoinRequestPayload>(
          JoinRequestPayload.$_createMessage);
  static JoinRequestPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);
}

class JoinApprovedPayload extends $pb.GeneratedMessage {
  factory JoinApprovedPayload({
    $core.String? roomCode,
    $core.String? userId,
    $core.String? sessionToken,
    RoomState? state,
  }) {
    final result = JoinApprovedPayload._();
    if (roomCode != null) result.roomCode = roomCode;
    if (userId != null) result.userId = userId;
    if (sessionToken != null) result.sessionToken = sessionToken;
    if (state != null) result.state = state;
    return result;
  }

  JoinApprovedPayload._();

  factory JoinApprovedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinApprovedPayload()..mergeFromBuffer(data, registry);
  factory JoinApprovedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinApprovedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JoinApprovedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: JoinApprovedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'roomCode')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..aOS(3, _omitFieldNames ? '' : 'sessionToken')
    ..aOM<RoomState>(4, _omitFieldNames ? '' : 'state',
        subBuilder: RoomState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinApprovedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinApprovedPayload copyWith(void Function(JoinApprovedPayload) updates) =>
      super.copyWith((message) => updates(message as JoinApprovedPayload))
          as JoinApprovedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use JoinApprovedPayload() / JoinApprovedPayload.new instead')
  static JoinApprovedPayload create() => JoinApprovedPayload._();
  static $pb.GeneratedMessage $_createMessage() => JoinApprovedPayload._();
  @$core.override
  JoinApprovedPayload createEmptyInstance() => JoinApprovedPayload._();
  @$core.pragma('dart2js:noInline')
  static JoinApprovedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<JoinApprovedPayload>(
          JoinApprovedPayload.$_createMessage);
  static JoinApprovedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get roomCode => $_getSZ(0);
  @$pb.TagNumber(1)
  set roomCode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRoomCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearRoomCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sessionToken => $_getSZ(2);
  @$pb.TagNumber(3)
  set sessionToken($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSessionToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearSessionToken() => $_clearField(3);

  @$pb.TagNumber(4)
  RoomState get state => $_getN(3);
  @$pb.TagNumber(4)
  set state(RoomState value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasState() => $_has(3);
  @$pb.TagNumber(4)
  void clearState() => $_clearField(4);
  @$pb.TagNumber(4)
  RoomState ensureState() => $_ensure(3);
}

class JoinRejectedPayload extends $pb.GeneratedMessage {
  factory JoinRejectedPayload({
    $core.String? reason,
  }) {
    final result = JoinRejectedPayload._();
    if (reason != null) result.reason = reason;
    return result;
  }

  JoinRejectedPayload._();

  factory JoinRejectedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinRejectedPayload()..mergeFromBuffer(data, registry);
  factory JoinRejectedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      JoinRejectedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'JoinRejectedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: JoinRejectedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinRejectedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  JoinRejectedPayload copyWith(void Function(JoinRejectedPayload) updates) =>
      super.copyWith((message) => updates(message as JoinRejectedPayload))
          as JoinRejectedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use JoinRejectedPayload() / JoinRejectedPayload.new instead')
  static JoinRejectedPayload create() => JoinRejectedPayload._();
  static $pb.GeneratedMessage $_createMessage() => JoinRejectedPayload._();
  @$core.override
  JoinRejectedPayload createEmptyInstance() => JoinRejectedPayload._();
  @$core.pragma('dart2js:noInline')
  static JoinRejectedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<JoinRejectedPayload>(
          JoinRejectedPayload.$_createMessage);
  static JoinRejectedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reason => $_getSZ(0);
  @$pb.TagNumber(1)
  set reason($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);
}

class UserJoinedPayload extends $pb.GeneratedMessage {
  factory UserJoinedPayload({
    $core.String? userId,
    $core.String? username,
  }) {
    final result = UserJoinedPayload._();
    if (userId != null) result.userId = userId;
    if (username != null) result.username = username;
    return result;
  }

  UserJoinedPayload._();

  factory UserJoinedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserJoinedPayload()..mergeFromBuffer(data, registry);
  factory UserJoinedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserJoinedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserJoinedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: UserJoinedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserJoinedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserJoinedPayload copyWith(void Function(UserJoinedPayload) updates) =>
      super.copyWith((message) => updates(message as UserJoinedPayload))
          as UserJoinedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UserJoinedPayload() / UserJoinedPayload.new instead')
  static UserJoinedPayload create() => UserJoinedPayload._();
  static $pb.GeneratedMessage $_createMessage() => UserJoinedPayload._();
  @$core.override
  UserJoinedPayload createEmptyInstance() => UserJoinedPayload._();
  @$core.pragma('dart2js:noInline')
  static UserJoinedPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UserJoinedPayload>(
          UserJoinedPayload.$_createMessage);
  static UserJoinedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);
}

class UserLeftPayload extends $pb.GeneratedMessage {
  factory UserLeftPayload({
    $core.String? userId,
    $core.String? username,
  }) {
    final result = UserLeftPayload._();
    if (userId != null) result.userId = userId;
    if (username != null) result.username = username;
    return result;
  }

  UserLeftPayload._();

  factory UserLeftPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserLeftPayload()..mergeFromBuffer(data, registry);
  factory UserLeftPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserLeftPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserLeftPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: UserLeftPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserLeftPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserLeftPayload copyWith(void Function(UserLeftPayload) updates) =>
      super.copyWith((message) => updates(message as UserLeftPayload))
          as UserLeftPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UserLeftPayload() / UserLeftPayload.new instead')
  static UserLeftPayload create() => UserLeftPayload._();
  static $pb.GeneratedMessage $_createMessage() => UserLeftPayload._();
  @$core.override
  UserLeftPayload createEmptyInstance() => UserLeftPayload._();
  @$core.pragma('dart2js:noInline')
  static UserLeftPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UserLeftPayload>(
          UserLeftPayload.$_createMessage);
  static UserLeftPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);
}

class BufferWaitPayload extends $pb.GeneratedMessage {
  factory BufferWaitPayload({
    $core.String? trackId,
    $core.Iterable<$core.String>? waitingFor,
  }) {
    final result = BufferWaitPayload._();
    if (trackId != null) result.trackId = trackId;
    if (waitingFor != null) result.waitingFor.addAll(waitingFor);
    return result;
  }

  BufferWaitPayload._();

  factory BufferWaitPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BufferWaitPayload()..mergeFromBuffer(data, registry);
  factory BufferWaitPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BufferWaitPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BufferWaitPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: BufferWaitPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'trackId')
    ..pPS(2, _omitFieldNames ? '' : 'waitingFor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferWaitPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferWaitPayload copyWith(void Function(BufferWaitPayload) updates) =>
      super.copyWith((message) => updates(message as BufferWaitPayload))
          as BufferWaitPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BufferWaitPayload() / BufferWaitPayload.new instead')
  static BufferWaitPayload create() => BufferWaitPayload._();
  static $pb.GeneratedMessage $_createMessage() => BufferWaitPayload._();
  @$core.override
  BufferWaitPayload createEmptyInstance() => BufferWaitPayload._();
  @$core.pragma('dart2js:noInline')
  static BufferWaitPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BufferWaitPayload>(
          BufferWaitPayload.$_createMessage);
  static BufferWaitPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set trackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrackId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get waitingFor => $_getList(1);
}

class BufferCompletePayload extends $pb.GeneratedMessage {
  factory BufferCompletePayload({
    $core.String? trackId,
  }) {
    final result = BufferCompletePayload._();
    if (trackId != null) result.trackId = trackId;
    return result;
  }

  BufferCompletePayload._();

  factory BufferCompletePayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BufferCompletePayload()..mergeFromBuffer(data, registry);
  factory BufferCompletePayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BufferCompletePayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BufferCompletePayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: BufferCompletePayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'trackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferCompletePayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BufferCompletePayload copyWith(
          void Function(BufferCompletePayload) updates) =>
      super.copyWith((message) => updates(message as BufferCompletePayload))
          as BufferCompletePayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use BufferCompletePayload() / BufferCompletePayload.new instead')
  static BufferCompletePayload create() => BufferCompletePayload._();
  static $pb.GeneratedMessage $_createMessage() => BufferCompletePayload._();
  @$core.override
  BufferCompletePayload createEmptyInstance() => BufferCompletePayload._();
  @$core.pragma('dart2js:noInline')
  static BufferCompletePayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BufferCompletePayload>(
          BufferCompletePayload.$_createMessage);
  static BufferCompletePayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get trackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set trackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTrackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTrackId() => $_clearField(1);
}

class ErrorPayload extends $pb.GeneratedMessage {
  factory ErrorPayload({
    $core.String? code,
    $core.String? message,
  }) {
    final result = ErrorPayload._();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    return result;
  }

  ErrorPayload._();

  factory ErrorPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorPayload()..mergeFromBuffer(data, registry);
  factory ErrorPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: ErrorPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'code')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorPayload copyWith(void Function(ErrorPayload) updates) =>
      super.copyWith((message) => updates(message as ErrorPayload))
          as ErrorPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ErrorPayload() / ErrorPayload.new instead')
  static ErrorPayload create() => ErrorPayload._();
  static $pb.GeneratedMessage $_createMessage() => ErrorPayload._();
  @$core.override
  ErrorPayload createEmptyInstance() => ErrorPayload._();
  @$core.pragma('dart2js:noInline')
  static ErrorPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErrorPayload>(
          ErrorPayload.$_createMessage);
  static ErrorPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get code => $_getSZ(0);
  @$pb.TagNumber(1)
  set code($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
}

class HostChangedPayload extends $pb.GeneratedMessage {
  factory HostChangedPayload({
    $core.String? newHostId,
    $core.String? newHostName,
  }) {
    final result = HostChangedPayload._();
    if (newHostId != null) result.newHostId = newHostId;
    if (newHostName != null) result.newHostName = newHostName;
    return result;
  }

  HostChangedPayload._();

  factory HostChangedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HostChangedPayload()..mergeFromBuffer(data, registry);
  factory HostChangedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HostChangedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HostChangedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: HostChangedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'newHostId')
    ..aOS(2, _omitFieldNames ? '' : 'newHostName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HostChangedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HostChangedPayload copyWith(void Function(HostChangedPayload) updates) =>
      super.copyWith((message) => updates(message as HostChangedPayload))
          as HostChangedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HostChangedPayload() / HostChangedPayload.new instead')
  static HostChangedPayload create() => HostChangedPayload._();
  static $pb.GeneratedMessage $_createMessage() => HostChangedPayload._();
  @$core.override
  HostChangedPayload createEmptyInstance() => HostChangedPayload._();
  @$core.pragma('dart2js:noInline')
  static HostChangedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HostChangedPayload>(
          HostChangedPayload.$_createMessage);
  static HostChangedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get newHostId => $_getSZ(0);
  @$pb.TagNumber(1)
  set newHostId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNewHostId() => $_has(0);
  @$pb.TagNumber(1)
  void clearNewHostId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get newHostName => $_getSZ(1);
  @$pb.TagNumber(2)
  set newHostName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNewHostName() => $_has(1);
  @$pb.TagNumber(2)
  void clearNewHostName() => $_clearField(2);
}

class KickedPayload extends $pb.GeneratedMessage {
  factory KickedPayload({
    $core.String? reason,
  }) {
    final result = KickedPayload._();
    if (reason != null) result.reason = reason;
    return result;
  }

  KickedPayload._();

  factory KickedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KickedPayload()..mergeFromBuffer(data, registry);
  factory KickedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      KickedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KickedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: KickedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KickedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KickedPayload copyWith(void Function(KickedPayload) updates) =>
      super.copyWith((message) => updates(message as KickedPayload))
          as KickedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use KickedPayload() / KickedPayload.new instead')
  static KickedPayload create() => KickedPayload._();
  static $pb.GeneratedMessage $_createMessage() => KickedPayload._();
  @$core.override
  KickedPayload createEmptyInstance() => KickedPayload._();
  @$core.pragma('dart2js:noInline')
  static KickedPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<KickedPayload>(
          KickedPayload.$_createMessage);
  static KickedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reason => $_getSZ(0);
  @$pb.TagNumber(1)
  set reason($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);
}

class SyncStatePayload extends $pb.GeneratedMessage {
  factory SyncStatePayload({
    TrackInfo? currentTrack,
    $core.bool? isPlaying,
    $fixnum.Int64? position,
    $fixnum.Int64? lastUpdate,
    $core.Iterable<TrackInfo>? queue,
    $core.double? volume,
    $fixnum.Int64? revision,
  }) {
    final result = SyncStatePayload._();
    if (currentTrack != null) result.currentTrack = currentTrack;
    if (isPlaying != null) result.isPlaying = isPlaying;
    if (position != null) result.position = position;
    if (lastUpdate != null) result.lastUpdate = lastUpdate;
    if (queue != null) result.queue.addAll(queue);
    if (volume != null) result.volume = volume;
    if (revision != null) result.revision = revision;
    return result;
  }

  SyncStatePayload._();

  factory SyncStatePayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncStatePayload()..mergeFromBuffer(data, registry);
  factory SyncStatePayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SyncStatePayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SyncStatePayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: SyncStatePayload.$_createMessage)
    ..aOM<TrackInfo>(1, _omitFieldNames ? '' : 'currentTrack',
        subBuilder: TrackInfo.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'isPlaying')
    ..aInt64(3, _omitFieldNames ? '' : 'position')
    ..aInt64(4, _omitFieldNames ? '' : 'lastUpdate')
    ..pPM<TrackInfo>(5, _omitFieldNames ? '' : 'queue',
        subBuilder: TrackInfo.$_createMessage)
    ..aD(6, _omitFieldNames ? '' : 'volume', fieldType: $pb.PbFieldType.OF)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncStatePayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SyncStatePayload copyWith(void Function(SyncStatePayload) updates) =>
      super.copyWith((message) => updates(message as SyncStatePayload))
          as SyncStatePayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SyncStatePayload() / SyncStatePayload.new instead')
  static SyncStatePayload create() => SyncStatePayload._();
  static $pb.GeneratedMessage $_createMessage() => SyncStatePayload._();
  @$core.override
  SyncStatePayload createEmptyInstance() => SyncStatePayload._();
  @$core.pragma('dart2js:noInline')
  static SyncStatePayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SyncStatePayload>(
          SyncStatePayload.$_createMessage);
  static SyncStatePayload? _defaultInstance;

  @$pb.TagNumber(1)
  TrackInfo get currentTrack => $_getN(0);
  @$pb.TagNumber(1)
  set currentTrack(TrackInfo value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrentTrack() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrentTrack() => $_clearField(1);
  @$pb.TagNumber(1)
  TrackInfo ensureCurrentTrack() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get isPlaying => $_getBF(1);
  @$pb.TagNumber(2)
  set isPlaying($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIsPlaying() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsPlaying() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get position => $_getI64(2);
  @$pb.TagNumber(3)
  set position($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPosition() => $_has(2);
  @$pb.TagNumber(3)
  void clearPosition() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get lastUpdate => $_getI64(3);
  @$pb.TagNumber(4)
  set lastUpdate($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLastUpdate() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastUpdate() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<TrackInfo> get queue => $_getList(4);

  @$pb.TagNumber(6)
  $core.double get volume => $_getN(5);
  @$pb.TagNumber(6)
  set volume($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasVolume() => $_has(5);
  @$pb.TagNumber(6)
  void clearVolume() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get revision => $_getI64(6);
  @$pb.TagNumber(7)
  set revision($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRevision() => $_has(6);
  @$pb.TagNumber(7)
  void clearRevision() => $_clearField(7);
}

class PongPayload extends $pb.GeneratedMessage {
  factory PongPayload({
    $fixnum.Int64? clientTime,
    $fixnum.Int64? serverReceiveTime,
    $fixnum.Int64? serverSendTime,
    $fixnum.Int64? sequence,
  }) {
    final result = PongPayload._();
    if (clientTime != null) result.clientTime = clientTime;
    if (serverReceiveTime != null) result.serverReceiveTime = serverReceiveTime;
    if (serverSendTime != null) result.serverSendTime = serverSendTime;
    if (sequence != null) result.sequence = sequence;
    return result;
  }

  PongPayload._();

  factory PongPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PongPayload()..mergeFromBuffer(data, registry);
  factory PongPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PongPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PongPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: PongPayload.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'clientTime')
    ..aInt64(2, _omitFieldNames ? '' : 'serverReceiveTime')
    ..aInt64(3, _omitFieldNames ? '' : 'serverSendTime')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PongPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PongPayload copyWith(void Function(PongPayload) updates) =>
      super.copyWith((message) => updates(message as PongPayload))
          as PongPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PongPayload() / PongPayload.new instead')
  static PongPayload create() => PongPayload._();
  static $pb.GeneratedMessage $_createMessage() => PongPayload._();
  @$core.override
  PongPayload createEmptyInstance() => PongPayload._();
  @$core.pragma('dart2js:noInline')
  static PongPayload getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PongPayload>(
          PongPayload.$_createMessage);
  static PongPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get clientTime => $_getI64(0);
  @$pb.TagNumber(1)
  set clientTime($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClientTime() => $_has(0);
  @$pb.TagNumber(1)
  void clearClientTime() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get serverReceiveTime => $_getI64(1);
  @$pb.TagNumber(2)
  set serverReceiveTime($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasServerReceiveTime() => $_has(1);
  @$pb.TagNumber(2)
  void clearServerReceiveTime() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get serverSendTime => $_getI64(2);
  @$pb.TagNumber(3)
  set serverSendTime($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasServerSendTime() => $_has(2);
  @$pb.TagNumber(3)
  void clearServerSendTime() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get sequence => $_getI64(3);
  @$pb.TagNumber(4)
  set sequence($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSequence() => $_has(3);
  @$pb.TagNumber(4)
  void clearSequence() => $_clearField(4);
}

class ReconnectedPayload extends $pb.GeneratedMessage {
  factory ReconnectedPayload({
    $core.String? roomCode,
    $core.String? userId,
    RoomState? state,
    $core.bool? isHost,
  }) {
    final result = ReconnectedPayload._();
    if (roomCode != null) result.roomCode = roomCode;
    if (userId != null) result.userId = userId;
    if (state != null) result.state = state;
    if (isHost != null) result.isHost = isHost;
    return result;
  }

  ReconnectedPayload._();

  factory ReconnectedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconnectedPayload()..mergeFromBuffer(data, registry);
  factory ReconnectedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReconnectedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReconnectedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: ReconnectedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'roomCode')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..aOM<RoomState>(3, _omitFieldNames ? '' : 'state',
        subBuilder: RoomState.$_createMessage)
    ..aOB(4, _omitFieldNames ? '' : 'isHost')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconnectedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReconnectedPayload copyWith(void Function(ReconnectedPayload) updates) =>
      super.copyWith((message) => updates(message as ReconnectedPayload))
          as ReconnectedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReconnectedPayload() / ReconnectedPayload.new instead')
  static ReconnectedPayload create() => ReconnectedPayload._();
  static $pb.GeneratedMessage $_createMessage() => ReconnectedPayload._();
  @$core.override
  ReconnectedPayload createEmptyInstance() => ReconnectedPayload._();
  @$core.pragma('dart2js:noInline')
  static ReconnectedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReconnectedPayload>(
          ReconnectedPayload.$_createMessage);
  static ReconnectedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get roomCode => $_getSZ(0);
  @$pb.TagNumber(1)
  set roomCode($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRoomCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearRoomCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  RoomState get state => $_getN(2);
  @$pb.TagNumber(3)
  set state(RoomState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasState() => $_has(2);
  @$pb.TagNumber(3)
  void clearState() => $_clearField(3);
  @$pb.TagNumber(3)
  RoomState ensureState() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get isHost => $_getBF(3);
  @$pb.TagNumber(4)
  set isHost($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsHost() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsHost() => $_clearField(4);
}

class UserReconnectedPayload extends $pb.GeneratedMessage {
  factory UserReconnectedPayload({
    $core.String? userId,
    $core.String? username,
  }) {
    final result = UserReconnectedPayload._();
    if (userId != null) result.userId = userId;
    if (username != null) result.username = username;
    return result;
  }

  UserReconnectedPayload._();

  factory UserReconnectedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserReconnectedPayload()..mergeFromBuffer(data, registry);
  factory UserReconnectedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserReconnectedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserReconnectedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: UserReconnectedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserReconnectedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserReconnectedPayload copyWith(
          void Function(UserReconnectedPayload) updates) =>
      super.copyWith((message) => updates(message as UserReconnectedPayload))
          as UserReconnectedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use UserReconnectedPayload() / UserReconnectedPayload.new instead')
  static UserReconnectedPayload create() => UserReconnectedPayload._();
  static $pb.GeneratedMessage $_createMessage() => UserReconnectedPayload._();
  @$core.override
  UserReconnectedPayload createEmptyInstance() => UserReconnectedPayload._();
  @$core.pragma('dart2js:noInline')
  static UserReconnectedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UserReconnectedPayload>(
          UserReconnectedPayload.$_createMessage);
  static UserReconnectedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);
}

class UserDisconnectedPayload extends $pb.GeneratedMessage {
  factory UserDisconnectedPayload({
    $core.String? userId,
    $core.String? username,
  }) {
    final result = UserDisconnectedPayload._();
    if (userId != null) result.userId = userId;
    if (username != null) result.username = username;
    return result;
  }

  UserDisconnectedPayload._();

  factory UserDisconnectedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserDisconnectedPayload()..mergeFromBuffer(data, registry);
  factory UserDisconnectedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UserDisconnectedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UserDisconnectedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: UserDisconnectedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserDisconnectedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UserDisconnectedPayload copyWith(
          void Function(UserDisconnectedPayload) updates) =>
      super.copyWith((message) => updates(message as UserDisconnectedPayload))
          as UserDisconnectedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use UserDisconnectedPayload() / UserDisconnectedPayload.new instead')
  static UserDisconnectedPayload create() => UserDisconnectedPayload._();
  static $pb.GeneratedMessage $_createMessage() => UserDisconnectedPayload._();
  @$core.override
  UserDisconnectedPayload createEmptyInstance() => UserDisconnectedPayload._();
  @$core.pragma('dart2js:noInline')
  static UserDisconnectedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UserDisconnectedPayload>(
          UserDisconnectedPayload.$_createMessage);
  static UserDisconnectedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => $_clearField(2);
}

class SuggestionReceivedPayload extends $pb.GeneratedMessage {
  factory SuggestionReceivedPayload({
    $core.String? suggestionId,
    $core.String? fromUserId,
    $core.String? fromUsername,
    TrackInfo? trackInfo,
  }) {
    final result = SuggestionReceivedPayload._();
    if (suggestionId != null) result.suggestionId = suggestionId;
    if (fromUserId != null) result.fromUserId = fromUserId;
    if (fromUsername != null) result.fromUsername = fromUsername;
    if (trackInfo != null) result.trackInfo = trackInfo;
    return result;
  }

  SuggestionReceivedPayload._();

  factory SuggestionReceivedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestionReceivedPayload()..mergeFromBuffer(data, registry);
  factory SuggestionReceivedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestionReceivedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SuggestionReceivedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: SuggestionReceivedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'suggestionId')
    ..aOS(2, _omitFieldNames ? '' : 'fromUserId')
    ..aOS(3, _omitFieldNames ? '' : 'fromUsername')
    ..aOM<TrackInfo>(4, _omitFieldNames ? '' : 'trackInfo',
        subBuilder: TrackInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestionReceivedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestionReceivedPayload copyWith(
          void Function(SuggestionReceivedPayload) updates) =>
      super.copyWith((message) => updates(message as SuggestionReceivedPayload))
          as SuggestionReceivedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SuggestionReceivedPayload() / SuggestionReceivedPayload.new instead')
  static SuggestionReceivedPayload create() => SuggestionReceivedPayload._();
  static $pb.GeneratedMessage $_createMessage() =>
      SuggestionReceivedPayload._();
  @$core.override
  SuggestionReceivedPayload createEmptyInstance() =>
      SuggestionReceivedPayload._();
  @$core.pragma('dart2js:noInline')
  static SuggestionReceivedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SuggestionReceivedPayload>(
          SuggestionReceivedPayload.$_createMessage);
  static SuggestionReceivedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get suggestionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set suggestionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuggestionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuggestionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get fromUserId => $_getSZ(1);
  @$pb.TagNumber(2)
  set fromUserId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFromUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFromUserId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fromUsername => $_getSZ(2);
  @$pb.TagNumber(3)
  set fromUsername($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFromUsername() => $_has(2);
  @$pb.TagNumber(3)
  void clearFromUsername() => $_clearField(3);

  @$pb.TagNumber(4)
  TrackInfo get trackInfo => $_getN(3);
  @$pb.TagNumber(4)
  set trackInfo(TrackInfo value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasTrackInfo() => $_has(3);
  @$pb.TagNumber(4)
  void clearTrackInfo() => $_clearField(4);
  @$pb.TagNumber(4)
  TrackInfo ensureTrackInfo() => $_ensure(3);
}

class SuggestionApprovedPayload extends $pb.GeneratedMessage {
  factory SuggestionApprovedPayload({
    $core.String? suggestionId,
    TrackInfo? trackInfo,
  }) {
    final result = SuggestionApprovedPayload._();
    if (suggestionId != null) result.suggestionId = suggestionId;
    if (trackInfo != null) result.trackInfo = trackInfo;
    return result;
  }

  SuggestionApprovedPayload._();

  factory SuggestionApprovedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestionApprovedPayload()..mergeFromBuffer(data, registry);
  factory SuggestionApprovedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestionApprovedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SuggestionApprovedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: SuggestionApprovedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'suggestionId')
    ..aOM<TrackInfo>(2, _omitFieldNames ? '' : 'trackInfo',
        subBuilder: TrackInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestionApprovedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestionApprovedPayload copyWith(
          void Function(SuggestionApprovedPayload) updates) =>
      super.copyWith((message) => updates(message as SuggestionApprovedPayload))
          as SuggestionApprovedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SuggestionApprovedPayload() / SuggestionApprovedPayload.new instead')
  static SuggestionApprovedPayload create() => SuggestionApprovedPayload._();
  static $pb.GeneratedMessage $_createMessage() =>
      SuggestionApprovedPayload._();
  @$core.override
  SuggestionApprovedPayload createEmptyInstance() =>
      SuggestionApprovedPayload._();
  @$core.pragma('dart2js:noInline')
  static SuggestionApprovedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SuggestionApprovedPayload>(
          SuggestionApprovedPayload.$_createMessage);
  static SuggestionApprovedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get suggestionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set suggestionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuggestionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuggestionId() => $_clearField(1);

  @$pb.TagNumber(2)
  TrackInfo get trackInfo => $_getN(1);
  @$pb.TagNumber(2)
  set trackInfo(TrackInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasTrackInfo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTrackInfo() => $_clearField(2);
  @$pb.TagNumber(2)
  TrackInfo ensureTrackInfo() => $_ensure(1);
}

class SuggestionRejectedPayload extends $pb.GeneratedMessage {
  factory SuggestionRejectedPayload({
    $core.String? suggestionId,
    $core.String? reason,
  }) {
    final result = SuggestionRejectedPayload._();
    if (suggestionId != null) result.suggestionId = suggestionId;
    if (reason != null) result.reason = reason;
    return result;
  }

  SuggestionRejectedPayload._();

  factory SuggestionRejectedPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestionRejectedPayload()..mergeFromBuffer(data, registry);
  factory SuggestionRejectedPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SuggestionRejectedPayload()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SuggestionRejectedPayload',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: SuggestionRejectedPayload.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'suggestionId')
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestionRejectedPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SuggestionRejectedPayload copyWith(
          void Function(SuggestionRejectedPayload) updates) =>
      super.copyWith((message) => updates(message as SuggestionRejectedPayload))
          as SuggestionRejectedPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SuggestionRejectedPayload() / SuggestionRejectedPayload.new instead')
  static SuggestionRejectedPayload create() => SuggestionRejectedPayload._();
  static $pb.GeneratedMessage $_createMessage() =>
      SuggestionRejectedPayload._();
  @$core.override
  SuggestionRejectedPayload createEmptyInstance() =>
      SuggestionRejectedPayload._();
  @$core.pragma('dart2js:noInline')
  static SuggestionRejectedPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SuggestionRejectedPayload>(
          SuggestionRejectedPayload.$_createMessage);
  static SuggestionRejectedPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get suggestionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set suggestionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuggestionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuggestionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

/// Capability negotiation (first message from client)
class ClientCapabilities extends $pb.GeneratedMessage {
  factory ClientCapabilities({
    $core.bool? supportsProtobuf,
    $core.bool? supportsCompression,
    $core.String? clientVersion,
  }) {
    final result = ClientCapabilities._();
    if (supportsProtobuf != null) result.supportsProtobuf = supportsProtobuf;
    if (supportsCompression != null)
      result.supportsCompression = supportsCompression;
    if (clientVersion != null) result.clientVersion = clientVersion;
    return result;
  }

  ClientCapabilities._();

  factory ClientCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientCapabilities()..mergeFromBuffer(data, registry);
  factory ClientCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClientCapabilities()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClientCapabilities',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: ClientCapabilities.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'supportsProtobuf')
    ..aOB(2, _omitFieldNames ? '' : 'supportsCompression')
    ..aOS(3, _omitFieldNames ? '' : 'clientVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClientCapabilities copyWith(void Function(ClientCapabilities) updates) =>
      super.copyWith((message) => updates(message as ClientCapabilities))
          as ClientCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ClientCapabilities() / ClientCapabilities.new instead')
  static ClientCapabilities create() => ClientCapabilities._();
  static $pb.GeneratedMessage $_createMessage() => ClientCapabilities._();
  @$core.override
  ClientCapabilities createEmptyInstance() => ClientCapabilities._();
  @$core.pragma('dart2js:noInline')
  static ClientCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ClientCapabilities>(
          ClientCapabilities.$_createMessage);
  static ClientCapabilities? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get supportsProtobuf => $_getBF(0);
  @$pb.TagNumber(1)
  set supportsProtobuf($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSupportsProtobuf() => $_has(0);
  @$pb.TagNumber(1)
  void clearSupportsProtobuf() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get supportsCompression => $_getBF(1);
  @$pb.TagNumber(2)
  set supportsCompression($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSupportsCompression() => $_has(1);
  @$pb.TagNumber(2)
  void clearSupportsCompression() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get clientVersion => $_getSZ(2);
  @$pb.TagNumber(3)
  set clientVersion($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClientVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearClientVersion() => $_clearField(3);
}

class ServerCapabilities extends $pb.GeneratedMessage {
  factory ServerCapabilities({
    $core.bool? supportsProtobuf,
    $core.bool? supportsCompression,
    $core.String? serverVersion,
  }) {
    final result = ServerCapabilities._();
    if (supportsProtobuf != null) result.supportsProtobuf = supportsProtobuf;
    if (supportsCompression != null)
      result.supportsCompression = supportsCompression;
    if (serverVersion != null) result.serverVersion = serverVersion;
    return result;
  }

  ServerCapabilities._();

  factory ServerCapabilities.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerCapabilities()..mergeFromBuffer(data, registry);
  factory ServerCapabilities.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ServerCapabilities()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ServerCapabilities',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'listentogether'),
      createEmptyInstance: ServerCapabilities.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'supportsProtobuf')
    ..aOB(2, _omitFieldNames ? '' : 'supportsCompression')
    ..aOS(3, _omitFieldNames ? '' : 'serverVersion')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerCapabilities clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ServerCapabilities copyWith(void Function(ServerCapabilities) updates) =>
      super.copyWith((message) => updates(message as ServerCapabilities))
          as ServerCapabilities;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ServerCapabilities() / ServerCapabilities.new instead')
  static ServerCapabilities create() => ServerCapabilities._();
  static $pb.GeneratedMessage $_createMessage() => ServerCapabilities._();
  @$core.override
  ServerCapabilities createEmptyInstance() => ServerCapabilities._();
  @$core.pragma('dart2js:noInline')
  static ServerCapabilities getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ServerCapabilities>(
          ServerCapabilities.$_createMessage);
  static ServerCapabilities? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get supportsProtobuf => $_getBF(0);
  @$pb.TagNumber(1)
  set supportsProtobuf($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSupportsProtobuf() => $_has(0);
  @$pb.TagNumber(1)
  void clearSupportsProtobuf() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get supportsCompression => $_getBF(1);
  @$pb.TagNumber(2)
  set supportsCompression($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSupportsCompression() => $_has(1);
  @$pb.TagNumber(2)
  void clearSupportsCompression() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get serverVersion => $_getSZ(2);
  @$pb.TagNumber(3)
  set serverVersion($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasServerVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearServerVersion() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');

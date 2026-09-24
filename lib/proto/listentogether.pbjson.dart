// This is a generated file - do not edit.
//
// Generated from listentogether.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use envelopeDescriptor instead')
const Envelope$json = {
  '1': 'Envelope',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 9, '10': 'type'},
    {'1': 'payload', '3': 2, '4': 1, '5': 12, '10': 'payload'},
    {'1': 'compressed', '3': 3, '4': 1, '5': 8, '10': 'compressed'},
  ],
};

/// Descriptor for `Envelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List envelopeDescriptor = $convert.base64Decode(
    'CghFbnZlbG9wZRISCgR0eXBlGAEgASgJUgR0eXBlEhgKB3BheWxvYWQYAiABKAxSB3BheWxvYW'
    'QSHgoKY29tcHJlc3NlZBgDIAEoCFIKY29tcHJlc3NlZA==');

@$core.Deprecated('Use trackInfoDescriptor instead')
const TrackInfo$json = {
  '1': 'TrackInfo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'artist', '3': 3, '4': 1, '5': 9, '10': 'artist'},
    {'1': 'album', '3': 4, '4': 1, '5': 9, '10': 'album'},
    {'1': 'duration', '3': 5, '4': 1, '5': 3, '10': 'duration'},
    {'1': 'thumbnail', '3': 6, '4': 1, '5': 9, '10': 'thumbnail'},
    {'1': 'suggested_by', '3': 7, '4': 1, '5': 9, '10': 'suggestedBy'},
  ],
};

/// Descriptor for `TrackInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List trackInfoDescriptor = $convert.base64Decode(
    'CglUcmFja0luZm8SDgoCaWQYASABKAlSAmlkEhQKBXRpdGxlGAIgASgJUgV0aXRsZRIWCgZhcn'
    'Rpc3QYAyABKAlSBmFydGlzdBIUCgVhbGJ1bRgEIAEoCVIFYWxidW0SGgoIZHVyYXRpb24YBSAB'
    'KANSCGR1cmF0aW9uEhwKCXRodW1ibmFpbBgGIAEoCVIJdGh1bWJuYWlsEiEKDHN1Z2dlc3RlZF'
    '9ieRgHIAEoCVILc3VnZ2VzdGVkQnk=');

@$core.Deprecated('Use userInfoDescriptor instead')
const UserInfo$json = {
  '1': 'UserInfo',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'is_host', '3': 3, '4': 1, '5': 8, '10': 'isHost'},
    {'1': 'is_connected', '3': 4, '4': 1, '5': 8, '10': 'isConnected'},
  ],
};

/// Descriptor for `UserInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userInfoDescriptor = $convert.base64Decode(
    'CghVc2VySW5mbxIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSGgoIdXNlcm5hbWUYAiABKAlSCH'
    'VzZXJuYW1lEhcKB2lzX2hvc3QYAyABKAhSBmlzSG9zdBIhCgxpc19jb25uZWN0ZWQYBCABKAhS'
    'C2lzQ29ubmVjdGVk');

@$core.Deprecated('Use roomStateDescriptor instead')
const RoomState$json = {
  '1': 'RoomState',
  '2': [
    {'1': 'room_code', '3': 1, '4': 1, '5': 9, '10': 'roomCode'},
    {'1': 'host_id', '3': 2, '4': 1, '5': 9, '10': 'hostId'},
    {
      '1': 'users',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.listentogether.UserInfo',
      '10': 'users'
    },
    {
      '1': 'current_track',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'currentTrack'
    },
    {'1': 'is_playing', '3': 5, '4': 1, '5': 8, '10': 'isPlaying'},
    {'1': 'position', '3': 6, '4': 1, '5': 3, '10': 'position'},
    {'1': 'last_update', '3': 7, '4': 1, '5': 3, '10': 'lastUpdate'},
    {'1': 'volume', '3': 8, '4': 1, '5': 2, '10': 'volume'},
    {
      '1': 'queue',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'queue'
    },
    {'1': 'revision', '3': 10, '4': 1, '5': 4, '10': 'revision'},
  ],
};

/// Descriptor for `RoomState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List roomStateDescriptor = $convert.base64Decode(
    'CglSb29tU3RhdGUSGwoJcm9vbV9jb2RlGAEgASgJUghyb29tQ29kZRIXCgdob3N0X2lkGAIgAS'
    'gJUgZob3N0SWQSLgoFdXNlcnMYAyADKAsyGC5saXN0ZW50b2dldGhlci5Vc2VySW5mb1IFdXNl'
    'cnMSPgoNY3VycmVudF90cmFjaxgEIAEoCzIZLmxpc3RlbnRvZ2V0aGVyLlRyYWNrSW5mb1IMY3'
    'VycmVudFRyYWNrEh0KCmlzX3BsYXlpbmcYBSABKAhSCWlzUGxheWluZxIaCghwb3NpdGlvbhgG'
    'IAEoA1IIcG9zaXRpb24SHwoLbGFzdF91cGRhdGUYByABKANSCmxhc3RVcGRhdGUSFgoGdm9sdW'
    '1lGAggASgCUgZ2b2x1bWUSLwoFcXVldWUYCSADKAsyGS5saXN0ZW50b2dldGhlci5UcmFja0lu'
    'Zm9SBXF1ZXVlEhoKCHJldmlzaW9uGAogASgEUghyZXZpc2lvbg==');

@$core.Deprecated('Use createRoomPayloadDescriptor instead')
const CreateRoomPayload$json = {
  '1': 'CreateRoomPayload',
  '2': [
    {'1': 'username', '3': 1, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `CreateRoomPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createRoomPayloadDescriptor = $convert.base64Decode(
    'ChFDcmVhdGVSb29tUGF5bG9hZBIaCgh1c2VybmFtZRgBIAEoCVIIdXNlcm5hbWU=');

@$core.Deprecated('Use joinRoomPayloadDescriptor instead')
const JoinRoomPayload$json = {
  '1': 'JoinRoomPayload',
  '2': [
    {'1': 'room_code', '3': 1, '4': 1, '5': 9, '10': 'roomCode'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `JoinRoomPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List joinRoomPayloadDescriptor = $convert.base64Decode(
    'Cg9Kb2luUm9vbVBheWxvYWQSGwoJcm9vbV9jb2RlGAEgASgJUghyb29tQ29kZRIaCgh1c2Vybm'
    'FtZRgCIAEoCVIIdXNlcm5hbWU=');

@$core.Deprecated('Use leaveRoomPayloadDescriptor instead')
const LeaveRoomPayload$json = {
  '1': 'LeaveRoomPayload',
};

/// Descriptor for `LeaveRoomPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List leaveRoomPayloadDescriptor =
    $convert.base64Decode('ChBMZWF2ZVJvb21QYXlsb2Fk');

@$core.Deprecated('Use approveJoinPayloadDescriptor instead')
const ApproveJoinPayload$json = {
  '1': 'ApproveJoinPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `ApproveJoinPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List approveJoinPayloadDescriptor =
    $convert.base64Decode(
        'ChJBcHByb3ZlSm9pblBheWxvYWQSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklk');

@$core.Deprecated('Use rejectJoinPayloadDescriptor instead')
const RejectJoinPayload$json = {
  '1': 'RejectJoinPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `RejectJoinPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rejectJoinPayloadDescriptor = $convert.base64Decode(
    'ChFSZWplY3RKb2luUGF5bG9hZBIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSFgoGcmVhc29uGA'
    'IgASgJUgZyZWFzb24=');

@$core.Deprecated('Use playbackActionPayloadDescriptor instead')
const PlaybackActionPayload$json = {
  '1': 'PlaybackActionPayload',
  '2': [
    {'1': 'action', '3': 1, '4': 1, '5': 9, '10': 'action'},
    {'1': 'track_id', '3': 2, '4': 1, '5': 9, '10': 'trackId'},
    {'1': 'position', '3': 3, '4': 1, '5': 3, '10': 'position'},
    {
      '1': 'track_info',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'trackInfo'
    },
    {'1': 'insert_next', '3': 5, '4': 1, '5': 8, '10': 'insertNext'},
    {
      '1': 'queue',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'queue'
    },
    {'1': 'queue_title', '3': 7, '4': 1, '5': 9, '10': 'queueTitle'},
    {'1': 'volume', '3': 8, '4': 1, '5': 2, '10': 'volume'},
    {'1': 'server_time', '3': 9, '4': 1, '5': 3, '10': 'serverTime'},
    {'1': 'revision', '3': 10, '4': 1, '5': 4, '10': 'revision'},
    {
      '1': 'captured_at_server_time',
      '3': 11,
      '4': 1,
      '5': 3,
      '10': 'capturedAtServerTime'
    },
  ],
};

/// Descriptor for `PlaybackActionPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List playbackActionPayloadDescriptor = $convert.base64Decode(
    'ChVQbGF5YmFja0FjdGlvblBheWxvYWQSFgoGYWN0aW9uGAEgASgJUgZhY3Rpb24SGQoIdHJhY2'
    'tfaWQYAiABKAlSB3RyYWNrSWQSGgoIcG9zaXRpb24YAyABKANSCHBvc2l0aW9uEjgKCnRyYWNr'
    'X2luZm8YBCABKAsyGS5saXN0ZW50b2dldGhlci5UcmFja0luZm9SCXRyYWNrSW5mbxIfCgtpbn'
    'NlcnRfbmV4dBgFIAEoCFIKaW5zZXJ0TmV4dBIvCgVxdWV1ZRgGIAMoCzIZLmxpc3RlbnRvZ2V0'
    'aGVyLlRyYWNrSW5mb1IFcXVldWUSHwoLcXVldWVfdGl0bGUYByABKAlSCnF1ZXVlVGl0bGUSFg'
    'oGdm9sdW1lGAggASgCUgZ2b2x1bWUSHwoLc2VydmVyX3RpbWUYCSABKANSCnNlcnZlclRpbWUS'
    'GgoIcmV2aXNpb24YCiABKARSCHJldmlzaW9uEjUKF2NhcHR1cmVkX2F0X3NlcnZlcl90aW1lGA'
    'sgASgDUhRjYXB0dXJlZEF0U2VydmVyVGltZQ==');

@$core.Deprecated('Use pingPayloadDescriptor instead')
const PingPayload$json = {
  '1': 'PingPayload',
  '2': [
    {'1': 'client_time', '3': 1, '4': 1, '5': 3, '10': 'clientTime'},
    {'1': 'sequence', '3': 2, '4': 1, '5': 4, '10': 'sequence'},
  ],
};

/// Descriptor for `PingPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pingPayloadDescriptor = $convert.base64Decode(
    'CgtQaW5nUGF5bG9hZBIfCgtjbGllbnRfdGltZRgBIAEoA1IKY2xpZW50VGltZRIaCghzZXF1ZW'
    '5jZRgCIAEoBFIIc2VxdWVuY2U=');

@$core.Deprecated('Use bufferReadyPayloadDescriptor instead')
const BufferReadyPayload$json = {
  '1': 'BufferReadyPayload',
  '2': [
    {'1': 'track_id', '3': 1, '4': 1, '5': 9, '10': 'trackId'},
  ],
};

/// Descriptor for `BufferReadyPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bufferReadyPayloadDescriptor =
    $convert.base64Decode(
        'ChJCdWZmZXJSZWFkeVBheWxvYWQSGQoIdHJhY2tfaWQYASABKAlSB3RyYWNrSWQ=');

@$core.Deprecated('Use kickUserPayloadDescriptor instead')
const KickUserPayload$json = {
  '1': 'KickUserPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `KickUserPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List kickUserPayloadDescriptor = $convert.base64Decode(
    'Cg9LaWNrVXNlclBheWxvYWQSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEhYKBnJlYXNvbhgCIA'
    'EoCVIGcmVhc29u');

@$core.Deprecated('Use transferHostPayloadDescriptor instead')
const TransferHostPayload$json = {
  '1': 'TransferHostPayload',
  '2': [
    {'1': 'new_host_id', '3': 1, '4': 1, '5': 9, '10': 'newHostId'},
  ],
};

/// Descriptor for `TransferHostPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transferHostPayloadDescriptor = $convert.base64Decode(
    'ChNUcmFuc2Zlckhvc3RQYXlsb2FkEh4KC25ld19ob3N0X2lkGAEgASgJUgluZXdIb3N0SWQ=');

@$core.Deprecated('Use suggestTrackPayloadDescriptor instead')
const SuggestTrackPayload$json = {
  '1': 'SuggestTrackPayload',
  '2': [
    {
      '1': 'track_info',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'trackInfo'
    },
  ],
};

/// Descriptor for `SuggestTrackPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List suggestTrackPayloadDescriptor = $convert.base64Decode(
    'ChNTdWdnZXN0VHJhY2tQYXlsb2FkEjgKCnRyYWNrX2luZm8YASABKAsyGS5saXN0ZW50b2dldG'
    'hlci5UcmFja0luZm9SCXRyYWNrSW5mbw==');

@$core.Deprecated('Use approveSuggestionPayloadDescriptor instead')
const ApproveSuggestionPayload$json = {
  '1': 'ApproveSuggestionPayload',
  '2': [
    {'1': 'suggestion_id', '3': 1, '4': 1, '5': 9, '10': 'suggestionId'},
  ],
};

/// Descriptor for `ApproveSuggestionPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List approveSuggestionPayloadDescriptor =
    $convert.base64Decode(
        'ChhBcHByb3ZlU3VnZ2VzdGlvblBheWxvYWQSIwoNc3VnZ2VzdGlvbl9pZBgBIAEoCVIMc3VnZ2'
        'VzdGlvbklk');

@$core.Deprecated('Use rejectSuggestionPayloadDescriptor instead')
const RejectSuggestionPayload$json = {
  '1': 'RejectSuggestionPayload',
  '2': [
    {'1': 'suggestion_id', '3': 1, '4': 1, '5': 9, '10': 'suggestionId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `RejectSuggestionPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rejectSuggestionPayloadDescriptor =
    $convert.base64Decode(
        'ChdSZWplY3RTdWdnZXN0aW9uUGF5bG9hZBIjCg1zdWdnZXN0aW9uX2lkGAEgASgJUgxzdWdnZX'
        'N0aW9uSWQSFgoGcmVhc29uGAIgASgJUgZyZWFzb24=');

@$core.Deprecated('Use reconnectPayloadDescriptor instead')
const ReconnectPayload$json = {
  '1': 'ReconnectPayload',
  '2': [
    {'1': 'session_token', '3': 1, '4': 1, '5': 9, '10': 'sessionToken'},
  ],
};

/// Descriptor for `ReconnectPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reconnectPayloadDescriptor = $convert.base64Decode(
    'ChBSZWNvbm5lY3RQYXlsb2FkEiMKDXNlc3Npb25fdG9rZW4YASABKAlSDHNlc3Npb25Ub2tlbg'
    '==');

@$core.Deprecated('Use roomCreatedPayloadDescriptor instead')
const RoomCreatedPayload$json = {
  '1': 'RoomCreatedPayload',
  '2': [
    {'1': 'room_code', '3': 1, '4': 1, '5': 9, '10': 'roomCode'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'session_token', '3': 3, '4': 1, '5': 9, '10': 'sessionToken'},
  ],
};

/// Descriptor for `RoomCreatedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List roomCreatedPayloadDescriptor = $convert.base64Decode(
    'ChJSb29tQ3JlYXRlZFBheWxvYWQSGwoJcm9vbV9jb2RlGAEgASgJUghyb29tQ29kZRIXCgd1c2'
    'VyX2lkGAIgASgJUgZ1c2VySWQSIwoNc2Vzc2lvbl90b2tlbhgDIAEoCVIMc2Vzc2lvblRva2Vu');

@$core.Deprecated('Use joinRequestPayloadDescriptor instead')
const JoinRequestPayload$json = {
  '1': 'JoinRequestPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `JoinRequestPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List joinRequestPayloadDescriptor = $convert.base64Decode(
    'ChJKb2luUmVxdWVzdFBheWxvYWQSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEhoKCHVzZXJuYW'
    '1lGAIgASgJUgh1c2VybmFtZQ==');

@$core.Deprecated('Use joinApprovedPayloadDescriptor instead')
const JoinApprovedPayload$json = {
  '1': 'JoinApprovedPayload',
  '2': [
    {'1': 'room_code', '3': 1, '4': 1, '5': 9, '10': 'roomCode'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'session_token', '3': 3, '4': 1, '5': 9, '10': 'sessionToken'},
    {
      '1': 'state',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.listentogether.RoomState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `JoinApprovedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List joinApprovedPayloadDescriptor = $convert.base64Decode(
    'ChNKb2luQXBwcm92ZWRQYXlsb2FkEhsKCXJvb21fY29kZRgBIAEoCVIIcm9vbUNvZGUSFwoHdX'
    'Nlcl9pZBgCIAEoCVIGdXNlcklkEiMKDXNlc3Npb25fdG9rZW4YAyABKAlSDHNlc3Npb25Ub2tl'
    'bhIvCgVzdGF0ZRgEIAEoCzIZLmxpc3RlbnRvZ2V0aGVyLlJvb21TdGF0ZVIFc3RhdGU=');

@$core.Deprecated('Use joinRejectedPayloadDescriptor instead')
const JoinRejectedPayload$json = {
  '1': 'JoinRejectedPayload',
  '2': [
    {'1': 'reason', '3': 1, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `JoinRejectedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List joinRejectedPayloadDescriptor =
    $convert.base64Decode(
        'ChNKb2luUmVqZWN0ZWRQYXlsb2FkEhYKBnJlYXNvbhgBIAEoCVIGcmVhc29u');

@$core.Deprecated('Use userJoinedPayloadDescriptor instead')
const UserJoinedPayload$json = {
  '1': 'UserJoinedPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `UserJoinedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userJoinedPayloadDescriptor = $convert.base64Decode(
    'ChFVc2VySm9pbmVkUGF5bG9hZBIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSGgoIdXNlcm5hbW'
    'UYAiABKAlSCHVzZXJuYW1l');

@$core.Deprecated('Use userLeftPayloadDescriptor instead')
const UserLeftPayload$json = {
  '1': 'UserLeftPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `UserLeftPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userLeftPayloadDescriptor = $convert.base64Decode(
    'Cg9Vc2VyTGVmdFBheWxvYWQSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEhoKCHVzZXJuYW1lGA'
    'IgASgJUgh1c2VybmFtZQ==');

@$core.Deprecated('Use bufferWaitPayloadDescriptor instead')
const BufferWaitPayload$json = {
  '1': 'BufferWaitPayload',
  '2': [
    {'1': 'track_id', '3': 1, '4': 1, '5': 9, '10': 'trackId'},
    {'1': 'waiting_for', '3': 2, '4': 3, '5': 9, '10': 'waitingFor'},
  ],
};

/// Descriptor for `BufferWaitPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bufferWaitPayloadDescriptor = $convert.base64Decode(
    'ChFCdWZmZXJXYWl0UGF5bG9hZBIZCgh0cmFja19pZBgBIAEoCVIHdHJhY2tJZBIfCgt3YWl0aW'
    '5nX2ZvchgCIAMoCVIKd2FpdGluZ0Zvcg==');

@$core.Deprecated('Use bufferCompletePayloadDescriptor instead')
const BufferCompletePayload$json = {
  '1': 'BufferCompletePayload',
  '2': [
    {'1': 'track_id', '3': 1, '4': 1, '5': 9, '10': 'trackId'},
  ],
};

/// Descriptor for `BufferCompletePayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bufferCompletePayloadDescriptor =
    $convert.base64Decode(
        'ChVCdWZmZXJDb21wbGV0ZVBheWxvYWQSGQoIdHJhY2tfaWQYASABKAlSB3RyYWNrSWQ=');

@$core.Deprecated('Use errorPayloadDescriptor instead')
const ErrorPayload$json = {
  '1': 'ErrorPayload',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 9, '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `ErrorPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorPayloadDescriptor = $convert.base64Decode(
    'CgxFcnJvclBheWxvYWQSEgoEY29kZRgBIAEoCVIEY29kZRIYCgdtZXNzYWdlGAIgASgJUgdtZX'
    'NzYWdl');

@$core.Deprecated('Use hostChangedPayloadDescriptor instead')
const HostChangedPayload$json = {
  '1': 'HostChangedPayload',
  '2': [
    {'1': 'new_host_id', '3': 1, '4': 1, '5': 9, '10': 'newHostId'},
    {'1': 'new_host_name', '3': 2, '4': 1, '5': 9, '10': 'newHostName'},
  ],
};

/// Descriptor for `HostChangedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hostChangedPayloadDescriptor = $convert.base64Decode(
    'ChJIb3N0Q2hhbmdlZFBheWxvYWQSHgoLbmV3X2hvc3RfaWQYASABKAlSCW5ld0hvc3RJZBIiCg'
    '1uZXdfaG9zdF9uYW1lGAIgASgJUgtuZXdIb3N0TmFtZQ==');

@$core.Deprecated('Use kickedPayloadDescriptor instead')
const KickedPayload$json = {
  '1': 'KickedPayload',
  '2': [
    {'1': 'reason', '3': 1, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `KickedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List kickedPayloadDescriptor = $convert
    .base64Decode('Cg1LaWNrZWRQYXlsb2FkEhYKBnJlYXNvbhgBIAEoCVIGcmVhc29u');

@$core.Deprecated('Use syncStatePayloadDescriptor instead')
const SyncStatePayload$json = {
  '1': 'SyncStatePayload',
  '2': [
    {
      '1': 'current_track',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'currentTrack'
    },
    {'1': 'is_playing', '3': 2, '4': 1, '5': 8, '10': 'isPlaying'},
    {'1': 'position', '3': 3, '4': 1, '5': 3, '10': 'position'},
    {'1': 'last_update', '3': 4, '4': 1, '5': 3, '10': 'lastUpdate'},
    {
      '1': 'queue',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'queue'
    },
    {'1': 'volume', '3': 6, '4': 1, '5': 2, '10': 'volume'},
    {'1': 'revision', '3': 7, '4': 1, '5': 4, '10': 'revision'},
  ],
};

/// Descriptor for `SyncStatePayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List syncStatePayloadDescriptor = $convert.base64Decode(
    'ChBTeW5jU3RhdGVQYXlsb2FkEj4KDWN1cnJlbnRfdHJhY2sYASABKAsyGS5saXN0ZW50b2dldG'
    'hlci5UcmFja0luZm9SDGN1cnJlbnRUcmFjaxIdCgppc19wbGF5aW5nGAIgASgIUglpc1BsYXlp'
    'bmcSGgoIcG9zaXRpb24YAyABKANSCHBvc2l0aW9uEh8KC2xhc3RfdXBkYXRlGAQgASgDUgpsYX'
    'N0VXBkYXRlEi8KBXF1ZXVlGAUgAygLMhkubGlzdGVudG9nZXRoZXIuVHJhY2tJbmZvUgVxdWV1'
    'ZRIWCgZ2b2x1bWUYBiABKAJSBnZvbHVtZRIaCghyZXZpc2lvbhgHIAEoBFIIcmV2aXNpb24=');

@$core.Deprecated('Use pongPayloadDescriptor instead')
const PongPayload$json = {
  '1': 'PongPayload',
  '2': [
    {'1': 'client_time', '3': 1, '4': 1, '5': 3, '10': 'clientTime'},
    {
      '1': 'server_receive_time',
      '3': 2,
      '4': 1,
      '5': 3,
      '10': 'serverReceiveTime'
    },
    {'1': 'server_send_time', '3': 3, '4': 1, '5': 3, '10': 'serverSendTime'},
    {'1': 'sequence', '3': 4, '4': 1, '5': 4, '10': 'sequence'},
  ],
};

/// Descriptor for `PongPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pongPayloadDescriptor = $convert.base64Decode(
    'CgtQb25nUGF5bG9hZBIfCgtjbGllbnRfdGltZRgBIAEoA1IKY2xpZW50VGltZRIuChNzZXJ2ZX'
    'JfcmVjZWl2ZV90aW1lGAIgASgDUhFzZXJ2ZXJSZWNlaXZlVGltZRIoChBzZXJ2ZXJfc2VuZF90'
    'aW1lGAMgASgDUg5zZXJ2ZXJTZW5kVGltZRIaCghzZXF1ZW5jZRgEIAEoBFIIc2VxdWVuY2U=');

@$core.Deprecated('Use reconnectedPayloadDescriptor instead')
const ReconnectedPayload$json = {
  '1': 'ReconnectedPayload',
  '2': [
    {'1': 'room_code', '3': 1, '4': 1, '5': 9, '10': 'roomCode'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '10': 'userId'},
    {
      '1': 'state',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.listentogether.RoomState',
      '10': 'state'
    },
    {'1': 'is_host', '3': 4, '4': 1, '5': 8, '10': 'isHost'},
  ],
};

/// Descriptor for `ReconnectedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reconnectedPayloadDescriptor = $convert.base64Decode(
    'ChJSZWNvbm5lY3RlZFBheWxvYWQSGwoJcm9vbV9jb2RlGAEgASgJUghyb29tQ29kZRIXCgd1c2'
    'VyX2lkGAIgASgJUgZ1c2VySWQSLwoFc3RhdGUYAyABKAsyGS5saXN0ZW50b2dldGhlci5Sb29t'
    'U3RhdGVSBXN0YXRlEhcKB2lzX2hvc3QYBCABKAhSBmlzSG9zdA==');

@$core.Deprecated('Use userReconnectedPayloadDescriptor instead')
const UserReconnectedPayload$json = {
  '1': 'UserReconnectedPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `UserReconnectedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userReconnectedPayloadDescriptor =
    $convert.base64Decode(
        'ChZVc2VyUmVjb25uZWN0ZWRQYXlsb2FkEhcKB3VzZXJfaWQYASABKAlSBnVzZXJJZBIaCgh1c2'
        'VybmFtZRgCIAEoCVIIdXNlcm5hbWU=');

@$core.Deprecated('Use userDisconnectedPayloadDescriptor instead')
const UserDisconnectedPayload$json = {
  '1': 'UserDisconnectedPayload',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `UserDisconnectedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userDisconnectedPayloadDescriptor =
    $convert.base64Decode(
        'ChdVc2VyRGlzY29ubmVjdGVkUGF5bG9hZBIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSGgoIdX'
        'Nlcm5hbWUYAiABKAlSCHVzZXJuYW1l');

@$core.Deprecated('Use suggestionReceivedPayloadDescriptor instead')
const SuggestionReceivedPayload$json = {
  '1': 'SuggestionReceivedPayload',
  '2': [
    {'1': 'suggestion_id', '3': 1, '4': 1, '5': 9, '10': 'suggestionId'},
    {'1': 'from_user_id', '3': 2, '4': 1, '5': 9, '10': 'fromUserId'},
    {'1': 'from_username', '3': 3, '4': 1, '5': 9, '10': 'fromUsername'},
    {
      '1': 'track_info',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'trackInfo'
    },
  ],
};

/// Descriptor for `SuggestionReceivedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List suggestionReceivedPayloadDescriptor = $convert.base64Decode(
    'ChlTdWdnZXN0aW9uUmVjZWl2ZWRQYXlsb2FkEiMKDXN1Z2dlc3Rpb25faWQYASABKAlSDHN1Z2'
    'dlc3Rpb25JZBIgCgxmcm9tX3VzZXJfaWQYAiABKAlSCmZyb21Vc2VySWQSIwoNZnJvbV91c2Vy'
    'bmFtZRgDIAEoCVIMZnJvbVVzZXJuYW1lEjgKCnRyYWNrX2luZm8YBCABKAsyGS5saXN0ZW50b2'
    'dldGhlci5UcmFja0luZm9SCXRyYWNrSW5mbw==');

@$core.Deprecated('Use suggestionApprovedPayloadDescriptor instead')
const SuggestionApprovedPayload$json = {
  '1': 'SuggestionApprovedPayload',
  '2': [
    {'1': 'suggestion_id', '3': 1, '4': 1, '5': 9, '10': 'suggestionId'},
    {
      '1': 'track_info',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.listentogether.TrackInfo',
      '10': 'trackInfo'
    },
  ],
};

/// Descriptor for `SuggestionApprovedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List suggestionApprovedPayloadDescriptor = $convert.base64Decode(
    'ChlTdWdnZXN0aW9uQXBwcm92ZWRQYXlsb2FkEiMKDXN1Z2dlc3Rpb25faWQYASABKAlSDHN1Z2'
    'dlc3Rpb25JZBI4Cgp0cmFja19pbmZvGAIgASgLMhkubGlzdGVudG9nZXRoZXIuVHJhY2tJbmZv'
    'Ugl0cmFja0luZm8=');

@$core.Deprecated('Use suggestionRejectedPayloadDescriptor instead')
const SuggestionRejectedPayload$json = {
  '1': 'SuggestionRejectedPayload',
  '2': [
    {'1': 'suggestion_id', '3': 1, '4': 1, '5': 9, '10': 'suggestionId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `SuggestionRejectedPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List suggestionRejectedPayloadDescriptor =
    $convert.base64Decode(
        'ChlTdWdnZXN0aW9uUmVqZWN0ZWRQYXlsb2FkEiMKDXN1Z2dlc3Rpb25faWQYASABKAlSDHN1Z2'
        'dlc3Rpb25JZBIWCgZyZWFzb24YAiABKAlSBnJlYXNvbg==');

@$core.Deprecated('Use clientCapabilitiesDescriptor instead')
const ClientCapabilities$json = {
  '1': 'ClientCapabilities',
  '2': [
    {
      '1': 'supports_protobuf',
      '3': 1,
      '4': 1,
      '5': 8,
      '10': 'supportsProtobuf'
    },
    {
      '1': 'supports_compression',
      '3': 2,
      '4': 1,
      '5': 8,
      '10': 'supportsCompression'
    },
    {'1': 'client_version', '3': 3, '4': 1, '5': 9, '10': 'clientVersion'},
  ],
};

/// Descriptor for `ClientCapabilities`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List clientCapabilitiesDescriptor = $convert.base64Decode(
    'ChJDbGllbnRDYXBhYmlsaXRpZXMSKwoRc3VwcG9ydHNfcHJvdG9idWYYASABKAhSEHN1cHBvcn'
    'RzUHJvdG9idWYSMQoUc3VwcG9ydHNfY29tcHJlc3Npb24YAiABKAhSE3N1cHBvcnRzQ29tcHJl'
    'c3Npb24SJQoOY2xpZW50X3ZlcnNpb24YAyABKAlSDWNsaWVudFZlcnNpb24=');

@$core.Deprecated('Use serverCapabilitiesDescriptor instead')
const ServerCapabilities$json = {
  '1': 'ServerCapabilities',
  '2': [
    {
      '1': 'supports_protobuf',
      '3': 1,
      '4': 1,
      '5': 8,
      '10': 'supportsProtobuf'
    },
    {
      '1': 'supports_compression',
      '3': 2,
      '4': 1,
      '5': 8,
      '10': 'supportsCompression'
    },
    {'1': 'server_version', '3': 3, '4': 1, '5': 9, '10': 'serverVersion'},
  ],
};

/// Descriptor for `ServerCapabilities`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serverCapabilitiesDescriptor = $convert.base64Decode(
    'ChJTZXJ2ZXJDYXBhYmlsaXRpZXMSKwoRc3VwcG9ydHNfcHJvdG9idWYYASABKAhSEHN1cHBvcn'
    'RzUHJvdG9idWYSMQoUc3VwcG9ydHNfY29tcHJlc3Npb24YAiABKAhSE3N1cHBvcnRzQ29tcHJl'
    'c3Npb24SJQoOc2VydmVyX3ZlcnNpb24YAyABKAlSDXNlcnZlclZlcnNpb24=');

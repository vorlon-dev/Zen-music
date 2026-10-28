// ZenMusic Desktop — ported from Echo Music (GPL-3.0), ytmusic/ytmusic.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).

import 'client.dart';

import 'mixins/browsing.dart';
import 'mixins/library.dart';
import 'mixins/search.dart';

// SP-62.1: re-export the account session service so every barrel importer
// (both main.dart entrypoints restore the session at boot with
// YtmAuth.instance.load()) sees YtmAuth without a second import.
export 'ytm_auth.dart';

class YTMusic extends YTClient with BrowsingMixin, LibraryMixin, SearchMixin {
  YTMusic({super.config, super.onIdUpdate});
}
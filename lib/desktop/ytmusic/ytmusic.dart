// ZenMusic · vorlon-dev

import 'client.dart';

import 'mixins/browsing.dart';
import 'mixins/library.dart';
import 'mixins/search.dart';

export 'ytm_auth.dart';

class YTMusic extends YTClient with BrowsingMixin, LibraryMixin, SearchMixin {
  YTMusic({super.config, super.onIdUpdate});
}

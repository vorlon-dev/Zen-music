// SP-42: the body's wheel scrolling is smooth now. The SingleChildScrollView
// content is wrapped in SmoothScroll (same controller) — every mouse-wheel
// notch becomes one short eased glide instead of an instant pointerScroll
// teleport, in the correct direction, on the whole feed. See
// lib/desktop/utils/smooth_scroll.dart for the mechanism.

import 'dart:io';

import 'package:expressive_refresh/expressive_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:zenmusic/desktop/screens/home/cubit/home_cubit.dart';
import 'package:zenmusic/desktop/core/widgets/section_item.dart';
import 'package:zenmusic/desktop/utils/internet_guard.dart';
import 'package:zenmusic/desktop/utils/smooth_scroll.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart'; // SP-62.1: barrel now also exports YtmAuth (ytm_auth.dart)
import '../../themes/text_styles.dart';
import '../../utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:get_it/get_it.dart';
// SP-46 (restores SP-36 wiring dropped by the SP-42 rewrite): the signed-in
// user's Spotify account (playlists + liked songs + real Spotify home
// shelves) rendered as a section on Home, above the YouTube sections.
import 'package:zenmusic/desktop/spotify/spotify_home_section.dart';
// SP-68: the signed-in YouTube Music account as a Home section — last
// listening (history), liked music and the user's playlists, mirroring
// the YTM app's Library surfaces.
import 'package:zenmusic/desktop/ytmusic/ytm_account_section.dart';
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(GetIt.I<YTMusic>())..fetch(),
      child: _HomePage(),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  late ScrollController _scrollController;

  // SP-46 (SP-36): pull-to-refresh also re-fetches the Spotify section
  // through its public state (SpotifyHomeSectionState.reload()).
  final GlobalKey<SpotifyHomeSectionState> _spotifySectionKey =
      GlobalKey<SpotifyHomeSectionState>();

  // SP-68: same hook for the YouTube Music account shelves.
  final GlobalKey<YtmAccountSectionState> _ytmSectionKey =
      GlobalKey<YtmAccountSectionState>();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_scrollListener);
    // SP-62: when a YouTube Music account connects (settings login), the
    // feed re-fetches so taste-based shelves (Quick picks, Listen again,
    // Mixed for you) appear without an app restart.
    YtmAuth.instance.loggedIn.addListener(_onYtmAuthChanged);
  }

  void _onYtmAuthChanged() {
    if (!mounted) return;
    // SP-65: re-fetch on login AND logout — the feed follows the session in
    // both directions without a restart. When a session is invalidated
    // server-side (YtmAuth.sessionRejected), the public feed returns by
    // itself instead of the page staying broken.
    context.read<HomeCubit>().fetch();
  }

  @override
  void dispose() {
    YtmAuth.instance.loggedIn.removeListener(_onYtmAuthChanged);
    _scrollController.dispose();
    super.dispose();
  }

  // PORT: Echo's _checkFirstLaunch/_showSupportDialog removed — see header.

  Future<void> _scrollListener() async {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      await context.read<HomeCubit>().fetchNext();
    }
  }

  Widget _horizontalChipsRow(List data) {
    var list = <Widget>[const SizedBox(width: 16)];
    for (var element in data) {
      list.add(
        AdaptiveInkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.go('/chip', extra: element),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10)),
            child: Text(element['title']),
          ),
        ),
      );
      list.add(const SizedBox(
        width: 8,
      ));
    }
    list.add(const SizedBox(
      width: 8,
    ));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: list,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InternetGuard(
      onInternetRestored: context.read<HomeCubit>().fetch,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: AppBar().preferredSize,
          child: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              'ZenMusic',
              style: appBarTitleStyle(),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Listen Together',
                onPressed: () => context.push('/listen'),
                icon: const Icon(Icons.groups_rounded),
              ),
            ],
          ),
        ),
        body: ExpressiveRefreshIndicator(
          // SP-46 (SP-36): the refresh closure also nudges the Spotify
          // section; its cubit re-fetches only when a session is active.
          onRefresh: () async {
            _spotifySectionKey.currentState?.reload();
            _ytmSectionKey.currentState?.reload();
            await context.read<HomeCubit>().refresh();
          },
          child: BlocBuilder<HomeCubit, HomeState>(
            builder: (context, state) {
              switch (state) {
                case HomeLoading():
                  return Center(
                    child: LoadingIndicatorM3E(),
                  );
                case HomeError():
                  return Center(
                    child: Text(state.message ?? ''),
                  );
                case HomeSuccess():
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    controller: _scrollController,
                    // SP-42: SmoothScroll sits INSIDE the viewport (deeper
                    // than the Scrollable), so it wins the PointerSignal
                    // resolution and converts wheel notches into smooth
                    // glides. Pull-to-refresh, pagination and drag all
                    // behave exactly as before.
                    child: SmoothScroll(
                      controller: _scrollController,
                      child: SafeArea(
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _horizontalChipsRow(state.chips),
                            // SP-46 (SP-36): the signed-in user's Spotify
                            // account leads the page. Logged out = slim
                            // connect banner; failures never touch the
                            // YT feed below.
                            SpotifyHomeSection(key: _spotifySectionKey),
                            // SP-68: the signed-in YTM account — Listen
                            // again / Liked music / Your playlists. Slim
                            // connect banner when logged out; silent per-
                            // tier failures never touch the feed below.
                            YtmAccountSection(key: _ytmSectionKey),
                            Column(
                              children: [
                                ...state.sections.map((section) {
                                  return SectionItem(section: section);
                                }),
                                if (!state.loadingMore &&
                                    state.continuation != null)
                                  const SizedBox(height: 50),
                                if (state.loadingMore)
                                  const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: ExpressiveLoadingIndicator()),
                              ],
                            ),
                          ],
                        )),
                    ),
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}
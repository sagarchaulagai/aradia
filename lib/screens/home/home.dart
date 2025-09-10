// lib/screens/home/home.dart
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/designs/theme_notifier.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/screens/home/bloc/home_bloc.dart';
import 'package:aradia/screens/home/widgets/my_audiobooks.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:aradia/utils/permission_helper.dart';

import '../../resources/latest_version_fetch.dart';
import '../../resources/models/latest_version_fetch_model.dart';
import '../../resources/services/recommendation_service.dart';
import 'widgets/history_section.dart';
import 'widgets/update_prompt_dialog.dart';
import 'widgets/app_bar_actions.dart';
import 'widgets/welcome_section.dart';
import 'constants/home_constants.dart';
import 'widgets/genre_grid.dart'; // keep Option A

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // Update & version
  final LatestVersionFetch _latestVersionFetch = LatestVersionFetch();
  final String currentVersion = "3.0.0";

  // Recommendation machinery
  late final RecommendationService _recommendationService;
  Future<String>? _recommendedGenresFuture;

  // Keep blocs/controllers stable across theme rebuilds
  late final HomeBloc _popularBloc;
  late final HomeBloc _trendingBloc;
  late final HomeBloc _recommendedBloc;

  late final ScrollController _popularCtrl;
  late final ScrollController _trendingCtrl;
  late final ScrollController _recommendedCtrl;

  // NEW: prevent repeated page-1 fetches caused by visibility changes while scrolling
  bool _didRequestRecommended = false;

  @override
  void initState() {
    super.initState();

    _recommendationService = RecommendationService();
    _recommendedGenresFuture = _recommendationService
        .getRecommendedGenres()
        .then((genres) => genres.map((g) => '"$g"').join(' OR '));

    _popularBloc = HomeBloc();
    _trendingBloc = HomeBloc();
    _recommendedBloc = HomeBloc();

    _popularCtrl = ScrollController();
    _trendingCtrl = ScrollController();
    _recommendedCtrl = ScrollController();

    _checkForUpdates();
  }

  @override
  void dispose() {
    _popularBloc.close();
    _trendingBloc.close();
    _recommendedBloc.close();

    _popularCtrl.dispose();
    _trendingCtrl.dispose();
    _recommendedCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    final result = await _latestVersionFetch.getLatestVersion();

    result.fold(
          (error) => AppLogger.debug(error),
          (latestVersionModel) async {
        if (latestVersionModel.latestVersion != null &&
            latestVersionModel.latestVersion!.compareTo(currentVersion) > 0) {
          await _handleUpdateAvailable(latestVersionModel);
        }
      },
    );
  }

  Future<void> _handleUpdateAvailable(
      LatestVersionFetchModel versionModel,
      ) async {
    final permissionGranted =
    await PermissionHelper.handleUpdatePermission(context);

    if (permissionGranted) {
      _proceedWithUpdate(versionModel);
    }
  }

  Future<void> _proceedWithUpdate(
      LatestVersionFetchModel versionModel,
      ) async {
    final existingApk =
    await _latestVersionFetch.getApkPath(versionModel.latestVersion!);

    if (existingApk != null) {
      _showUpdatePrompt(versionModel);
    } else {
      final success =
      await _latestVersionFetch.downloadUpdate(versionModel.latestVersion!);
      if (success) {
        _showUpdatePrompt(versionModel);
      }
    }
  }

  void _showUpdatePrompt(LatestVersionFetchModel versionModel) {
    showDialog(
      context: context,
      builder: (BuildContext context) => UpdatePromptDialog(
        currentVersion: currentVersion,
        newVersion: versionModel.latestVersion!,
        changelogs: versionModel.changelogs ?? [],
        onUpdate: () =>
            _latestVersionFetch.installUpdate(versionModel.latestVersion!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Aradia',
          style: GoogleFonts.ubuntu(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          AppBarActions(
            themeNotifier: themeNotifier,
            onSettingsPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: WelcomeSection(theme: theme),
          ),
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 290),
              child: const HistorySection(),
            ),
          ),

          // --- Recommended for you (memoized future) ---
          SliverToBoxAdapter(
            child: FutureBuilder<String>(
              future: _recommendedGenresFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData &&
                    snapshot.data != null &&
                    snapshot.data!.isNotEmpty) {
                  return _buildLazyLoadSection(
                    context,
                    'Recommended for you',
                    snapshot.data!,
                  );
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
                  ),
                );
              },
            ),
          ),

          // --- Featured sections (stable blocs/controllers) ---
          SliverToBoxAdapter(
            child: _buildFeaturedSections(),
          ),

          // --- Genres ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Browse Genres',
                style: GoogleFonts.ubuntu(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: GenreGrid(genres: HomeConstants.genres),
          ),

          // --- Footer / guidance ---
          SliverToBoxAdapter(
            child: FutureBuilder<Widget>(
              future: _buildGenreSections(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return snapshot.data!;
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedSections() {
    return Column(
      children: [
        MyAudiobooks(
          title: 'Popular All Time',
          homeBloc: _popularBloc,
          fetchType: AudiobooksFetchType.popular,
          scrollController: _popularCtrl,
        ),
        MyAudiobooks(
          title: 'Trending This Week',
          homeBloc: _trendingBloc,
          fetchType: AudiobooksFetchType.popularOfWeek,
          scrollController: _trendingCtrl,
        ),
      ],
    );
  }

  Future<Widget> _buildGenreSections() async {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Or Go To Search, Choose Subjects button And Search Your Favorite Genre/s',
            style: GoogleFonts.ubuntu(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLazyLoadSection(BuildContext context, String title, String genre) {
    return VisibilityDetector(
      key: Key('rec-$genre'),
      onVisibilityChanged: (VisibilityInfo info) {
        // Fire ONCE: prevents reloading/clearing while scrolling
        if (info.visibleFraction > 0.5 && !_didRequestRecommended) {
          _didRequestRecommended = true;
          _recommendedBloc.add(FetchAudiobooksByGenre(1, 15, genre, 'week'));
        }
      },
      child: MyAudiobooks(
        title: title,
        homeBloc: _recommendedBloc,
        fetchType: AudiobooksFetchType.genre,
        genre: genre,
        scrollController: _recommendedCtrl,
      ),
    );
  }
}

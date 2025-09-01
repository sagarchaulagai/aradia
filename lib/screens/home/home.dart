import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/designs/theme_notifier.dart';
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
import '../../services/recommendation_service.dart';
import 'widgets/history_section.dart';
import 'widgets/update_prompt_dialog.dart';
import 'widgets/app_bar_actions.dart';
import 'widgets/welcome_section.dart';
import 'widgets/genre_grid.dart';
import 'constants/home_constants.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late RecommendationService recommendationService;
  late List<String> recommendedGenres;
  final LatestVersionFetch _latestVersionFetch = LatestVersionFetch();
  final String currentVersion = "2.0.0";

  @override
  void initState() {
    super.initState();
    initRecommendedGenres();
    checkForUpdates();
  }

  Future<void> checkForUpdates() async {
    final permissionGranted = await PermissionHelper.handleUpdatePermission(context);
    
    if (permissionGranted) {
      await proceedWithUpdateCheck();
    }
  }

  Future<void> proceedWithUpdateCheck() async {
    final result = await _latestVersionFetch.getLatestVersion();

    result.fold(
      (error) => debugPrint(error),
      (latestVersionModel) async {
        if (latestVersionModel.latestVersion != null &&
            latestVersionModel.latestVersion!.compareTo(currentVersion) > 0) {
          await _handleUpdateAvailable(latestVersionModel);
        }
      },
    );
  }

  Future<void> _handleUpdateAvailable(
      LatestVersionFetchModel versionModel) async {
    final permissionGranted = await PermissionHelper.handleUpdatePermission(context);
    
    if (permissionGranted) {
      proceedWithUpdate(versionModel);
    }
  }

  Future<void> proceedWithUpdate(LatestVersionFetchModel versionModel) async {
    final existingApk =
        await _latestVersionFetch.getApkPath(versionModel.latestVersion!);

    if (existingApk != null) {
      if (mounted) {
        showUpdatePrompt(versionModel);
      }
    } else {
      final success =
          await _latestVersionFetch.downloadUpdate(versionModel.latestVersion!);
      if (success) {
        if (mounted) {
          showUpdatePrompt(versionModel);
        }
      }
    }
  }

  void showUpdatePrompt(LatestVersionFetchModel versionModel) {
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

  void initRecommendedGenres() async {
    recommendationService = RecommendationService();
    recommendedGenres = await recommendationService.getRecommendedGenres();
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
          const SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 290),
              child: HistorySection(),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<String>(
              future: RecommendationService().getRecommendedGenres().then(
                  (genres) => genres.map((genre) => '"$genre"').join(' OR ')),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return _buildLazyLoadSection(
                      context, 'Recommended for you', snapshot.data!);
                }
                return const CircularProgressIndicator(
                  color: AppColors.primaryColor,
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _buildFeaturedSections(),
          ),
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
          SliverToBoxAdapter(
            child: FutureBuilder<Widget>(
              future: _buildGenreSections(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return snapshot.data!;
                }
                return const CircularProgressIndicator(
                  color: AppColors.primaryColor,
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
          homeBloc: HomeBloc(),
          fetchType: AudiobooksFetchType.popular,
          scrollController: ScrollController(),
        ),
        MyAudiobooks(
          title: 'Trending This Week',
          homeBloc: HomeBloc(),
          fetchType: AudiobooksFetchType.popularOfWeek,
          scrollController: ScrollController(),
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

  Widget _buildLazyLoadSection(
      BuildContext context, String title, String genre) {
    return VisibilityDetector(
      key: Key(genre),
      onVisibilityChanged: (VisibilityInfo info) {
        if (info.visibleFraction > 0.5) {
          HomeBloc().add(FetchAudiobooksByGenre(1, 15, genre, 'week'));
        }
      },
      child: MyAudiobooks(
        title: title,
        homeBloc: HomeBloc(),
        fetchType: AudiobooksFetchType.genre,
        genre: genre,
        scrollController: ScrollController(),
      ),
    );
  }
}
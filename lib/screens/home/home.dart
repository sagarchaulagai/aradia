import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/designs/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/screens/home/bloc/home_bloc.dart';
import 'package:aradia/screens/home/widgets/my_audiobooks.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../resources/latest_version_fetch.dart';
import '../../resources/models/latest_version_fetch_model.dart';
import '../../resources/services/recommendation_service.dart';
import 'widgets/history_section.dart';
import 'widgets/update_prompt_dialog.dart';

class Home extends StatefulWidget {
  const Home({
    super.key,
  });

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final List<String> genres = [
    'Adventure',
    'Biography',
    'Children',
    'Comedy',
    'Crime',
    'Fantasy',
    'Horror',
    'Humor',
    'Love',
    'Mystery',
    'Philosophy',
    'Poem',
    'Romance',
    'Sci-Fi',
    'War',
  ];

  late RecommendationService recommendationService;
  late List<String> recommendedGenres;
  final LatestVersionFetch _latestVersionFetch = LatestVersionFetch();
  String currentVersion = "2.0.0";

  @override
  void initState() {
    super.initState();
    initRecommendedGenres();
    checkForUpdates();
  }

  Future<void> checkForUpdates() async {
    final result = await _latestVersionFetch.getLatestVersion();

    result.fold(
      (error) => print(error),
      (latestVersionModel) async {
        print('latest version is ${latestVersionModel.latestVersion}');
        print('current version is $currentVersion');
        if (latestVersionModel.latestVersion != null &&
            latestVersionModel.latestVersion!.compareTo(currentVersion) > 0) {
          // Only request permission if there's an update available
          final permissionStatus =
              await Permission.requestInstallPackages.status;

          if (permissionStatus.isGranted) {
            proceedWithUpdate(latestVersionModel);
          } else {
            final shouldRequestPermission = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return PermissionDialog(
                  onContinue: () => Navigator.of(context).pop(true),
                  onNotNow: () => Navigator.of(context).pop(false),
                );
              },
            );

            if (shouldRequestPermission == true) {
              final newPermissionStatus =
                  await Permission.requestInstallPackages.request();
              if (newPermissionStatus.isGranted) {
                proceedWithUpdate(latestVersionModel);
              } else if (newPermissionStatus.isDenied ||
                  newPermissionStatus.isPermanentlyDenied) {
                if (!mounted) return;
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return PermissionDialog(
                      onContinue: () async {
                        Navigator.of(context).pop();
                        await openAppSettings();
                      },
                      onNotNow: () => Navigator.of(context).pop(),
                    );
                  },
                );
              }
            }
          }
        }
      },
    );
  }

  Future<void> proceedWithUpdate(LatestVersionFetchModel versionModel) async {
    // Check if we already have the APK
    final existingApk =
        await _latestVersionFetch.getApkPath(versionModel.latestVersion!);

    if (existingApk != null) {
      // We already have the APK, show install prompt
      showUpdatePrompt(versionModel);
    } else {
      // Download the update silently
      final success =
          await _latestVersionFetch.downloadUpdate(versionModel.latestVersion!);
      if (success) {
        // Show install prompt after successful download
        showUpdatePrompt(versionModel);
      }
    }
  }

  void showUpdatePrompt(LatestVersionFetchModel versionModel) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return UpdatePromptDialog(
          currentVersion: currentVersion,
          newVersion: versionModel.latestVersion!,
          changelogs: versionModel.changelogs ?? [],
          onUpdate: () =>
              _latestVersionFetch.installUpdate(versionModel.latestVersion!),
        );
      },
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
          AnimatedIconButton(
            onPressed: themeNotifier.toggleTheme,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return RotationTransition(
                  turns: animation,
                  child: child,
                );
              },
              child: Icon(
                themeNotifier.themeMode == ThemeMode.light
                    ? Icons.nightlight_round
                    : Icons.wb_sunny,
                key: ValueKey<bool>(themeNotifier.themeMode == ThemeMode.light),
              ),
            ),
            tooltip: 'Toggle theme mode',
          ),
          AnimatedIconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back!',
                    style: GoogleFonts.ubuntu(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Discover your next favorite audiobook',
                    style: GoogleFonts.ubuntu(
                      fontSize: 16,
                      color: theme.textTheme.bodyMedium?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 290,
              ),
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
                } else {
                  return CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  );
                }
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
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildGenreChip(context, genres[index]),
                childCount: genres.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<Widget>(
              future: _buildGenreSections(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return snapshot.data!;
                } else {
                  return CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  );
                }
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

  Widget _buildGenreChip(BuildContext context, String genre) {
    return Material(
      color: AppColors.primaryColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push('/genre_audiobooks', extra: genre);
        },
        child: Container(
          alignment: Alignment.center,
          child: Text(
            genre,
            style: GoogleFonts.ubuntu(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  // Implementing later in another version with better recommendation algorithm
  // TODO: Implement this
  Future<Widget> _buildGenreSections() async {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          SizedBox(height: 16),

          Text(
            'Or Go To Search, Choose Subjects button And Search Your Favorite Genre/s',
            style: GoogleFonts.ubuntu(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          // for top 5 genres in RecommendationService().getRecommendedGenres()
          // but it can be less than 5 too
          // for (String genre in recommendedGenres.take(5))
          //   _buildLazyLoadSection(
          //       context, capitalize(genre) + "'s Audiobooks", genre),
        ],
      ),
    );
  }

  String capitalize(String s) =>
      s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}' : s;

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

class AnimatedIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const AnimatedIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 24,
    );
  }
}

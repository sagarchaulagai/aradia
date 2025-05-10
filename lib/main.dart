import 'package:aradia/resources/designs/theme_notifier.dart';
import 'package:aradia/resources/designs/themes.dart';
import 'package:aradia/screens/import/import_audiobook.dart';
import 'package:aradia/screens/recommendation/recommendation_screen.dart';
import 'package:aradia/screens/setting/settings.dart';
import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/screens/audiobook_details/audiobook_details.dart';
import 'package:aradia/screens/audiobook_details/bloc/audiobook_details_bloc.dart';
import 'package:aradia/screens/audiobook_player.dart/audiobook_player.dart';
import 'package:aradia/screens/download_audiobook/downloads_page.dart';
import 'package:aradia/screens/favourite/favourite.dart';
import 'package:aradia/screens/genre_audiobooks/genre_audiobooks.dart';
import 'package:aradia/screens/home/home.dart';
import 'package:aradia/screens/search/bloc/search_bloc.dart';
import 'package:aradia/screens/search/search_audiobook.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';

import 'package:aradia/widgets/scaffold_with_nav_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initHive();

  final audioHandlerProvider = AudioHandlerProvider();
  await audioHandlerProvider.initialize();

  WeSlideController weSlideController = WeSlideController();
  ThemeNotifier themeNotifier = ThemeNotifier();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => audioHandlerProvider),
        ChangeNotifierProvider(create: (_) => weSlideController),
        ChangeNotifierProvider(create: (_) => themeNotifier),
      ],
      child: const MyApp(),
    ),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
}

int isRecommendScreen = 0;

Future<void> initHive() async {
  final documentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(documentDir.path);
  await Hive.openBox('favourite_audiobooks_box');
  await Hive.openBox('download_status_box');
  await Hive.openBox('playing_audiobook_details_box');
  await Hive.openBox('theme_mode_box');
  await Hive.openBox('history_of_audiobook_box');
  await Hive.openBox('recommened_audiobooks_box');
  Box recommendedAudiobooksBox = Hive.box('recommened_audiobooks_box');
  isRecommendScreen = recommendedAudiobooksBox.isEmpty ? 1 : 0;
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _sectionNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: isRecommendScreen == 1 ? '/recommendation_screen' : '/home',
  routes: [
    GoRoute(
      path: '/recommendation_screen',
      name: 'recommendation_screen',
      builder: ((context, state) {
        return const RecommendationScreen();
      }),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ScaffoldWithNavBar(navigationShell);
      },
      branches: [
        StatefulShellBranch(
          navigatorKey: _sectionNavigatorKey,
          routes: [
            GoRoute(
              path: '/home',
              name: 'home',
              builder: ((context, state) {
                return const Home();
              }),
            ),
            // for the settings page
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) {
                return const Settings();
              },
            ),

            GoRoute(
              path: '/genre_audiobooks',
              name: 'genre_audiobooks',
              builder: ((context, state) {
                return GenreAudiobooksScreen(
                  genre: state.extra as String,
                );
              }),
            ),

            // for the audiobook details
            GoRoute(
              path: '/audiobook-details',
              builder: (context, state) {
                final extras = state.extra as Map<String, dynamic>;
                final audiobook = extras['audiobook'] as Audiobook;
                final isDownload = extras['isDownload'] as bool;
                final isYoutube = extras['isYoutube'] as bool;
                final isLocal = extras['isLocal'] as bool;

                return AudiobookDetails(
                  audiobook: audiobook,
                  isDownload: isDownload,
                  isYoutube: isYoutube,
                  isLocal: isLocal,
                );
              },
            ),
            // for the audiobook player
            GoRoute(
              path: '/player',
              name: 'player',
              builder: ((context, state) {
                return const AudiobookPlayer();
              }),
            ),
          ],
        ),
        // for the favourite tab
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/favourite',
              name: 'favourite',
              builder: ((context, state) {
                return const Favourite();
              }),
            ),
          ],
        ),
        // for the search tab
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              name: 'search',
              builder: ((context, state) {
                return const SearchAudiobook();
              }),
            ),
          ],
        ),
        // for the download tab
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/download',
              name: 'download',
              builder: ((context, state) {
                return const DownloadsPage();
              }),
            ),
          ],
        ),
        //for import tab
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/import',
              name: 'import',
              builder: (context, state) {
                return const ImportAudiobookScreen();
              },
            )
          ],
        )
      ],
    ),
  ],
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _backButtonInterceptor(bool stopDefaultButtonEvent, RouteInfo info) {
    print('initialized back button interceptor');
    WeSlideController weSlideController =
        Provider.of<WeSlideController>(context, listen: false);
    if (weSlideController.isOpened) {
      print('closing');
      weSlideController.hide();
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    BackButtonInterceptor.add(_backButtonInterceptor);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => AudiobookDetailsBloc(),
        ),
        BlocProvider(
          create: (context) => SearchBloc(),
        ),
      ],
      child: MaterialApp.router(
        theme: Themes().lightTheme,
        darkTheme: ThemeData.dark(),
        themeMode: Provider.of<ThemeNotifier>(context).themeMode,
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

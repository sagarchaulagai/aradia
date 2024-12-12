import 'package:aradia/screens/setting/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/resources/designs/app_colors.dart';
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
import 'package:aradia/services/audio_handler_provider.dart';

import 'package:aradia/widgets/scaffold_with_nav_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

import 'screens/genre/genre.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initHive();

  final audioHandlerProvider = AudioHandlerProvider();
  await audioHandlerProvider.initialize();

  WeSlideController weSlideController = WeSlideController();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => audioHandlerProvider),
        ChangeNotifierProvider(create: (_) => weSlideController),
      ],
      child: const MyApp(),
    ),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
}

Future<void> initHive() async {
  final documentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(documentDir.path);
  await Hive.openBox('favourite_audiobooks_box');
  await Hive.openBox('download_status_box');
  await Hive.openBox('playing_audiobook_details_box');
  await Hive.openBox('history_audiobooks_index_box');
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _sectionNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ScaffoldWithNavBar(navigationShell);
      },
      branches: [
        // for the home tab
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

            // for the audiobook details
            GoRoute(
              path: '/audiobook/:isOffline',
              name: 'audiobook',
              builder: ((context, state) {
                return AudiobookDetails(
                  audiobook: state.extra as Audiobook,
                  isOffline: state.pathParameters['isOffline'] == 'true',
                );
              }),
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

        // for the genre tab
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/genre',
            name: 'genre',
            builder: ((context, state) {
              return const Genre();
            }),
          ),
          // for the genre audiobooks
          GoRoute(
            path: '/genre_audiobooks',
            name: 'genre_audiobooks',
            builder: ((context, state) {
              return GenreAudiobooksScreen(
                genre: state.extra as String,
              );
            }),
          ),
        ]),

        // for the download tab
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/download',
            name: 'download',
            builder: ((context, state) {
              return const DownloadsPage();
            }),
          ),
        ]),

        // for the settings tab
      ],
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
        theme: ThemeData(
          textTheme: GoogleFonts.ubuntuTextTheme(),
          scaffoldBackgroundColor: AppColors.scaffoldBackgroundColor,
          primaryColor: AppColors.primaryColor,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.scaffoldBackgroundColor,
            elevation: 0,
          ),
        ),
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

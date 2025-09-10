import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
import 'package:aradia/widgets/mini_audio_player.dart';

class ScaffoldWithNavBar extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar(this.navigationShell, {super.key});

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar> {
  late Box<dynamic> playingAudiobookDetailsBox;
  late Stream<BoxEvent> _boxEventStream;

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    _boxEventStream = playingAudiobookDetailsBox.watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BoxEvent>(
      stream: _boxEventStream,
      builder: (context, snapshot) {
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

        // define the nav bar once
        final navBar = BottomNavigationBar(
          showSelectedLabels: false,
          showUnselectedLabels: false,
          // 👇 prevents the tiny reserved label height that causes the 2–4px overflow
          selectedFontSize: 0,
          unselectedFontSize: 0,

          type: BottomNavigationBarType.fixed,
          unselectedItemColor: Colors.grey,
          selectedItemColor: const Color.fromRGBO(204, 119, 34, 1),
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
            BottomNavigationBarItem(icon: Icon(Icons.favorite), label: ''),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: ''),
            BottomNavigationBarItem(icon: Icon(Ionicons.download), label: ''),
            BottomNavigationBarItem(icon: Icon(Ionicons.caret_down_circle_outline), label: ''),
          ],
          currentIndex: widget.navigationShell.currentIndex,
          onTap: _onTap,
        );

        if (playingAudiobookDetailsBox.isEmpty) {
          return Scaffold(
            body: widget.navigationShell,
            bottomNavigationBar: navBar,
          );
        }

        return Scaffold(
          // While typing → don't render MiniAudioPlayer at all
          body: keyboardOpen
              ? widget.navigationShell
              : MiniAudioPlayer(
            playingAudiobookDetailsBox: playingAudiobookDetailsBox,
            navigationShell: widget.navigationShell,
            bottomNavigationBar: navBar,
            bottomNavBarSize: const NavigationBarThemeData().height ?? 70,
          ),
        );
      },
    );
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }
}

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
        if (playingAudiobookDetailsBox.isEmpty) {
          return Scaffold(
            body: widget.navigationShell,
            bottomNavigationBar: BottomNavigationBar(
              showSelectedLabels: false,
              showUnselectedLabels: false,
              type: BottomNavigationBarType.fixed,
              unselectedItemColor: Colors.grey,
              selectedItemColor: const Color.fromRGBO(204, 119, 34, 1),
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.favorite),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Ionicons.download),
                  label: '',
                ),
              ],
              currentIndex: widget.navigationShell.currentIndex,
              onTap: _onTap,
            ),
          );
        }
        return Scaffold(
          body: MiniAudioPlayer(
            playingAudiobookDetailsBox: playingAudiobookDetailsBox,
            navigationShell: widget.navigationShell,
            bottomNavigationBar: BottomNavigationBar(
              showSelectedLabels: false,
              showUnselectedLabels: false,
              type: BottomNavigationBarType.fixed,
              unselectedItemColor: Colors.grey,
              selectedItemColor: const Color.fromRGBO(204, 119, 34, 1),
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.favorite),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Ionicons.download),
                  label: '',
                ),
              ],
              currentIndex: widget.navigationShell.currentIndex,
              onTap: _onTap,
            ),
            bottomNavBarSize: const NavigationBarThemeData().height ?? 70,
          ),
        );
      },
    );
  }

  void _onTap(index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }
}

import 'package:aradia/main.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/screens/home/bloc/home_bloc.dart';
import 'package:aradia/screens/home/widgets/my_audiobooks.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final HomeBloc _homeBloc = HomeBloc();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Aradia',
          style: GoogleFonts.ubuntu(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              context.push('/settings');
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            MyAudiobooks(
              title: 'Popular Audiobooks',
              homeBloc: _homeBloc,
              fetchType: AudiobooksFetchType.popular,
              scrollController: ScrollController(),
            ),
            MyAudiobooks(
              title: 'Popular Audiobooks of the Week',
              homeBloc: _homeBloc,
              fetchType: AudiobooksFetchType.popularOfWeek,
              scrollController: ScrollController(),
            ),
            MyAudiobooks(
              title: 'Latest Audiobooks',
              homeBloc: _homeBloc,
              fetchType: AudiobooksFetchType.latest,
              scrollController: ScrollController(),
            ),
          ],
        ),
      ),
    );
  }
}

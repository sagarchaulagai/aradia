import 'package:aradia/resources/designs/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/screens/genre_audiobooks/bloc/genre_audiobooks_bloc.dart';
import 'package:aradia/widgets/audiobook_item.dart';

class GenreAudiobooksScreen extends StatelessWidget {
  final String genre;

  const GenreAudiobooksScreen({
    super.key,
    required this.genre,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GenreAudiobooksBloc(archiveApi: ArchiveApi()),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text('${_capitalizeFirstLetter(genre)} Audiobooks'),
            bottom: TabBar(
              indicatorColor: AppColors.primaryColor,
              labelColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black,
              tabs: const [
                Tab(text: 'Popular'),
                Tab(text: 'Weekly'),
                Tab(text: 'Latest'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _AudiobookListView(
                genre: genre,
                listType: 'popular',
              ),
              _AudiobookListView(
                genre: genre,
                listType: 'popularWeekly',
              ),
              _AudiobookListView(
                genre: genre,
                listType: 'latest',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to capitalize first letter
  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    debugPrint(text);
    return text[0].toUpperCase() +
        (text.length > 1 ? text.substring(1).toLowerCase() : '');
  }
}

// Audiobook List View
class _AudiobookListView extends StatefulWidget {
  final String genre;
  final String listType;

  const _AudiobookListView({
    required this.genre,
    required this.listType,
  });

  @override
  State<_AudiobookListView> createState() => _AudiobookListViewState();
}

class _AudiobookListViewState extends State<_AudiobookListView>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Trigger initial load only if no audiobooks exist for this list type
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bloc = context.read<GenreAudiobooksBloc>();
      if (bloc.state.getAudiobooksForListType(widget.listType).isEmpty) {
        bloc.add(
          LoadInitialAudiobooksEvent(
            genre: widget.genre,
            listType: widget.listType,
          ),
        );
      }
    });
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<GenreAudiobooksBloc>().add(
            LoadMoreAudiobooksEvent(
              genre: widget.genre,
              listType: widget.listType,
            ),
          );
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return BlocBuilder<GenreAudiobooksBloc, GenreAudiobooksState>(
        builder: (context, state) {
      final audiobooks = state.getAudiobooksForListType(widget.listType);
      final isLoading = state.isLoadingListType(widget.listType);
      final error = state.getErrorForListType(widget.listType);

      // Error state
      if (error != null) {
        return Center(
          child: Text('Error: $error'),
        );
      }

      // Initial loading
      if (audiobooks.isEmpty && isLoading) {
        return const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryColor,
          ),
        );
      }

      // No audiobooks
      if (audiobooks.isEmpty) {
        return const Center(
          child: Text('No audiobooks found'),
        );
      }

      // Audiobooks grid
      return GridView.builder(
        controller: _scrollController,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.6,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        padding: const EdgeInsets.all(8),
        itemCount: audiobooks.length + (isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          // Loading indicator at the end
          if (index >= audiobooks.length) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Audiobook item
          return AudiobookItem(
            audiobook: audiobooks[index],
            width: 175,
          );
        },
      );
    });
  }
}

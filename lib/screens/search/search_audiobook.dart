import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/screens/search/bloc/search_bloc.dart';
import 'package:aradia/widgets/low_and_high_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class SearchAudiobook extends StatefulWidget {
  const SearchAudiobook({super.key});

  @override
  State<SearchAudiobook> createState() => _SearchAudiobookState();
}

class _SearchAudiobookState extends State<SearchAudiobook> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late SearchBloc searchBloc;

  String searchFilter = 'title'; // 'title' | 'author' | 'subject'
  bool isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    searchBloc = BlocProvider.of<SearchBloc>(context);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent &&
          !isLoadingMore) {
        final state = searchBloc.state;
        if (state is SearchSuccess && state.audiobooks.isNotEmpty) {
          setState(() => isLoadingMore = true);
          // We no longer pass the current text; paging sticks to the last submitted query
          searchBloc.add(EventLoadMoreResults(searchBloc.lastQuery ?? ''));
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Build raw Archive.org advancedsearch "q=" fragments, WITHOUT URL-encoding.
  // ArchiveApi will handle encoding.
  String _buildSearchQuery(String searchText) {
    final terms = searchText
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // If multiple terms, OR them. Keep it raw (no %3A)
    final joined = terms.length > 1
        ? terms.join(' OR ')
        : (terms.isEmpty ? '' : terms.first);

    switch (searchFilter) {
      case 'author':
        return joined.isEmpty ? '' : 'creator:($joined)';
      case 'subject':
        return joined.isEmpty ? '' : 'subject:($joined)';
      default:
        return joined.isEmpty ? '' : 'title:($joined)';
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0, // optional: keeps it flat like the rest of the page
        title: Text(
          'Search Audiobooks',
          style: GoogleFonts.ubuntu(
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                          decoration: InputDecoration(
                            hintText: _getHintText(),
                            hintStyle: TextStyle(
                                color: Colors.grey.shade600, fontSize: 14),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) {
                            FocusScope.of(context).unfocus();
                            final q = _buildSearchQuery(value);
                            if (q.isNotEmpty) {
                              searchBloc.add(EventSearchIconClicked(q));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          final q = _buildSearchQuery(_searchController.text);
                          if (q.isNotEmpty) {
                            searchBloc.add(EventSearchIconClicked(q));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryColor
                                    .withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.search,
                              color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Filters
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LibriVox filters
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 8, top: 8, bottom: 4),
                      child: Text(
                        'LibriVox',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          children: [
                            _buildFilterChip(
                              icon: Icons.book,
                              label: 'Title',
                              selected: searchFilter == 'title',
                              onSelected: (_) =>
                                  setState(() => searchFilter = 'title'),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              icon: Icons.person,
                              label: 'Author',
                              selected: searchFilter == 'author',
                              onSelected: (_) =>
                                  setState(() => searchFilter = 'author'),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              icon: Icons.category,
                              label: 'Subjects',
                              selected: searchFilter == 'subject',
                              onSelected: (_) =>
                                  setState(() => searchFilter = 'subject'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  ],
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: BlocConsumer<SearchBloc, SearchState>(
                    listener: (context, state) {
                      if (state is SearchFailure) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(state.errorMessage),
                            backgroundColor: Colors.red.shade300,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else if (state is SearchSuccess) {
                        setState(() => isLoadingMore = false);
                      }
                    },
                    builder: (context, state) {
                      if (state is SearchLoading && !isLoadingMore) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primaryColor),
                        );
                      } else if (state is SearchSuccess) {
                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: state.audiobooks.length + 1,
                          itemBuilder: (context, index) {
                            if (index == state.audiobooks.length) {
                              return isLoadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.primaryColor,
                                        ),
                                      ),
                                    )
                                  : const SizedBox();
                            }
                            final audiobook = state.audiobooks[index];
                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(8),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LowAndHighImage(
                                    lowQImage: audiobook.lowQCoverImage,
                                    highQImage: audiobook.lowQCoverImage,
                                    width: 60,
                                    height: 60,
                                  ),
                                ),
                                title: Text(
                                  audiobook.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  audiobook.author ?? 'Unknown Author',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                onTap: () {
                                  context.push(
                                    '/audiobook-details',
                                    extra: {
                                      'audiobook': audiobook,
                                      'isDownload': false,
                                      'isYoutube': false,
                                      'isLocal': false,
                                    },
                                  );
                                },
                              ),
                            );
                          },
                        );
                      }
                      return const SizedBox();
                    },
                  ),
          ),
        ],
      ),
    );
  }


  String _getHintText() {
    switch (searchFilter) {
      case 'author':
        return 'Search by author...';
      case 'subject':
        return 'Search by subject...';
      default:
        return 'Search by title...';
    }
  }

  Widget _buildFilterChip({
    required IconData icon,
    required String label,
    required bool selected,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppColors.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey),
    );
  }
}

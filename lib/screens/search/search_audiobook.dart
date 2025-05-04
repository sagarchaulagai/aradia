import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/screens/search/bloc/search_bloc.dart';
import 'package:aradia/widgets/low_and_high_image.dart';
import 'package:go_router/go_router.dart';

class SearchAudiobook extends StatefulWidget {
  const SearchAudiobook({super.key});

  @override
  State<SearchAudiobook> createState() => _SearchAudiobookState();
}

class _SearchAudiobookState extends State<SearchAudiobook> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late SearchBloc searchBloc;
  String searchFilter = 'title'; // Default to search by title
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
          setState(() {
            isLoadingMore = true;
          });
          searchBloc.add(
              EventLoadMoreResults(_buildSearchQuery(_searchController.text)));
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

  String _buildSearchQuery(String searchText) {
    final terms = searchText.split(',').map((term) => term.trim()).toList();
    final joinedTerms = terms.join(' OR ');

    switch (searchFilter) {
      case 'author':
        return 'creator%3A($joinedTerms)';
      case 'subject':
        return 'subject%3A($joinedTerms)';
      default:
        return 'title%3A($joinedTerms)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Audiobooks'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
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
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) {
                            FocusScope.of(context).unfocus();
                            final query = _buildSearchQuery(value);
                            searchBloc.add(EventSearchIconClicked(query));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          final query =
                              _buildSearchQuery(_searchController.text);
                          searchBloc.add(EventSearchIconClicked(query));
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
                          child: const Icon(
                            Icons.search,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFilterChip(
                      icon: Icons.book,
                      label: 'Title',
                      selected: searchFilter == 'title',
                      onSelected: (selected) =>
                          setState(() => searchFilter = 'title'),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      icon: Icons.person,
                      label: 'Author',
                      selected: searchFilter == 'author',
                      onSelected: (selected) =>
                          setState(() => searchFilter = 'author'),
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      icon: Icons.category,
                      label: 'Subjects',
                      selected: searchFilter == 'subject',
                      onSelected: (selected) =>
                          setState(() => searchFilter = 'subject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                  setState(() {
                    isLoadingMore = false;
                  });
                }
              },
              builder: (context, state) {
                if (state is SearchLoading && !isLoadingMore) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
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
                          vertical: 4,
                          horizontal: 8,
                        ),
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
        return '✍️ Search by author...';
      case 'subject':
        return '🗂️ Search by subject...';
      default:
        return '🔍 Search by title...';
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
          Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppColors.primaryColor,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.grey,
      ),
    );
  }
}

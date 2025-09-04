import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:go_router/go_router.dart';

class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({super.key});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  final Map<String, List<String>> genresMap = {
    "Childrens": [
      'Childrens',
      'Animals & Nature',
      'Action & Adventure',
      'Myths & Legends',
      'Fairy Tales',
      'Bedtime Stories',
      'Princess',
      'Magic',
      'Friendship',
      'Fairies',
      'Unicorns',
      'Dragons',
      'Cartoons',
      'Superheroes',
      'Pirates',
      'Dinosaurs',
      'Drawing',
      'Coloring',
      'Dolls',
    ],
    "Crime & Thriller": [
      'Crime',
      'Mystery',
      'Detective',
      'Suspense',
      'Thriller',
      'True Crime'
    ],
    "Culture & Heritage": [
      'Culture',
      'Heritage',
      'History',
      'Biography',
      'Religion',
      'Philosophy',
      'Spirituality'
    ],
    "Fantasy & Sci-Fi": [
      'Fantasy',
      'Science Fiction',
      'Dystopian',
      'Time Travel',
      'Superhero'
    ],
    "Health & Wellness": [
      'Diet',
      'Nutrition',
      'Exercise',
      'Fitness',
      'Mental Health',
      'Self-Help',
      'Personal Development'
    ],
    "History & Politics": [
      'History',
      'Politic',
      'World History',
      'Political Science',
      'Military History',
      'Historical Fiction',
      'Historical Romance'
    ],
    "Horror": [
      'Horror',
      'Gothic',
      'Supernatural',
      'Psychological',
      'Monsters',
      'Zombies'
    ],
    "Humor": [
      'Humor',
      'Satire',
      'Parody',
      'Comedy',
      'Jokes',
      'Puns',
    ],
    "Lifestyle": [
      'Fashion',
      'Beauty',
      'Home & Garden',
      'Crafts',
      'Travel',
      'Food',
      'Cooking',
      'Baking',
    ],
    "Love & Romance": [
      'Love',
      'Romance',
      'Erotica',
      'Shakespeare',
      'Romantic Comedy',
      'Romantic Suspense'
    ],
    "Mystery & Suspense": [
      'Mystery',
      'Suspense',
      'Thriller',
      'Spy Thriller',
      'Cozy Mystery',
      'Police Procedural',
      'Psychological Thriller',
      'Legal Thriller',
      'Medical Thriller'
    ],
    "Non-Fiction": [
      'Biography',
      'Memoir',
      'Self-Help',
      'History',
      'Science',
      'Business',
      'Health',
      'Cooking',
      'Travel',
      'Art',
      'Crafts',
    ],
    "Science & Technology": [
      'Science',
      'Technology',
      'Engineering',
      'Mathematics',
      'Astronomy',
      'Chemistry',
      'Space',
      'Physics',
      'Biology',
      'Computer',
      'Programming',
    ],
    "Sports & Outdoors": [
      'Sports',
      'Outdoors',
      'Fitness',
      'Exercise',
      'Yoga',
      'Running',
      'Cycling',
      'Swimming',
      'Golf',
      'Tennis',
      'Skiing',
      'Snowboarding',
      'Skating',
      'Surfing',
      'Camping',
      'Hiking',
      'Fishing',
      'Hunting',
      'Football',
      'Basketball',
      'Baseball',
      'Soccer'
    ],
  };

  // Color mapping for main categories
  final Map<String, Color> categoryColors = {
    "Childrens": Colors.pink,
    "Crime & Thriller": Colors.red,
    "Culture & Heritage": Colors.orange,
    "Fantasy & Sci-Fi": Colors.purple,
    "Health & Wellness": Colors.green,
    "History & Politics": Colors.blue,
    "Horror": Colors.black,
    "Humor": Colors.yellow,
    "Lifestyle": Colors.teal,
    "Love & Romance": Colors.pink,
    "Mystery & Suspense": Colors.red,
    "Non-Fiction": Colors.orange,
    "Science & Technology": Colors.purple,
    "Sports & Outdoors": Colors.green,
  };

  Set<String> expandedCategories = {};
  Set<String> selectedGenres = {};

  // Hive box name
  final String _hiveBoxName = 'recommened_audiobooks_box';

  // Save selected genres to Hive
  Future<void> _saveSelectedGenres() async {
    final box = Hive.box(_hiveBoxName);
    await box.put('selectedGenres', selectedGenres.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Header Section
            Container(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to\nAradia Audiobooks!',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose at least 3 genres to personalize your experience:',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // Genres List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: genresMap.entries.expand((entry) {
                      final category = entry.key;
                      final genres = entry.value;
                      final categoryColor =
                          categoryColors[category] ?? Colors.grey;
                      final isExpanded = expandedCategories.contains(category);

                      // Create a list that starts with the main genre chip
                      // and includes subgenres if expanded
                      return [
                        // Main genre chip
                        FilterChip(
                          label: Text(
                            '$category +',
                            style: TextStyle(
                              color: isExpanded ? Colors.white : categoryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          selected: isExpanded,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                expandedCategories.add(category);
                              } else {
                                expandedCategories.remove(category);
                              }
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: categoryColor,
                          side: BorderSide(
                            color: categoryColor.withValues(
                                alpha: isExpanded ? 1 : 0.3),
                            width: isExpanded ? 2 : 1,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          showCheckmark: false,
                          elevation: isExpanded ? 2 : 0,
                        ),
                        // If expanded, add all subgenres immediately after
                        if (isExpanded)
                          ...genres.map((genre) {
                            final isSelected = selectedGenres.contains(genre);
                            return FilterChip(
                              label: Text(
                                genre,
                                style: TextStyle(
                                  color:
                                      isSelected ? Colors.white : categoryColor,
                                  fontSize: 13,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    selectedGenres.add(genre);
                                  } else {
                                    selectedGenres.remove(genre);
                                  }
                                });
                              },
                              backgroundColor: Colors.white,
                              selectedColor: categoryColor,
                              side: BorderSide(
                                color: categoryColor.withValues(
                                    alpha: isSelected ? 1 : 0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              showCheckmark: false,
                              elevation: isSelected ? 2 : 0,
                            );
                          }),
                      ];
                    }).toList(),
                  ),
                ],
              ),
            ),
            // Selected Genres Section
            if (selectedGenres.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bookmark_added, color: theme.primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Selected Genres (${selectedGenres.length})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (selectedGenres.isNotEmpty)
                      Container(
                        height: 50,
                        margin: const EdgeInsets.only(top: 12),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: selectedGenres.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final genre = selectedGenres.elementAt(index);
                            final category = genresMap.entries
                                .firstWhere(
                                    (entry) => entry.value.contains(genre))
                                .key;
                            final categoryColor =
                                categoryColors[category] ?? Colors.grey;

                            return Chip(
                              label: Text(
                                genre,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              onDeleted: () {
                                setState(() {
                                  selectedGenres.remove(genre);
                                });
                              },
                              backgroundColor: categoryColor,
                              deleteIconColor: Colors.white,
                              elevation: 2,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: selectedGenres.length >= 3
                          ? () async {
                              await _saveSelectedGenres();
                              if (mounted && context.mounted) {
                                context.go('/home');
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        selectedGenres.length >= 3
                            ? 'Continue to Homepage'
                            : 'Select ${3 - selectedGenres.length} more genre${3 - selectedGenres.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/widgets/audiobook_item.dart';

class FavouriteSection extends StatefulWidget {
  const FavouriteSection({super.key});

  @override
  State<FavouriteSection> createState() => _FavouriteSectionState();
}

class _FavouriteSectionState extends State<FavouriteSection> {
  late Box<dynamic> box;
  late Stream<BoxEvent> _boxEventStream;

  @override
  void initState() {
    super.initState();
    box = Hive.box('favourite_audiobooks_box');
    _boxEventStream = box.watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BoxEvent>(
      stream: _boxEventStream,
      builder: (context, snapshot) {
        if (box.length == 0) {
          return const SizedBox
              .shrink(); // Let us not show this section if there are no favourites
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Text(
                    'Favourites',
                    style: GoogleFonts.ubuntu(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 250,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                scrollDirection: Axis.horizontal,
                itemCount: box.length,
                itemBuilder: (context, index) {
                  var key = box.keyAt(index);
                  final audiobook = Audiobook.fromMap(box.get(key)!);

                  return AudiobookItem(
                    audiobook: audiobook,
                    onLongPressed: () {
                      _showDeleteConfirmation(context, index);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Remove from Favourites"),
          content: const Text(
              "Are you sure you want to remove this audiobook from favourites?"),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(), // Dismiss the dialog
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                box.deleteAt(index); // Delete the item
                Navigator.of(context).pop(); // Dismiss the dialog
              },
              child: const Text("Remove"),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

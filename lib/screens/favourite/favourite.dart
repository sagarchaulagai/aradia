import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/widgets/audiobook_item.dart';

class Favourite extends StatefulWidget {
  const Favourite({super.key});

  @override
  State<Favourite> createState() => _FavouriteState();
}

class _FavouriteState extends State<Favourite> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourite'),
      ),
      body: StreamBuilder<BoxEvent>(
        stream: _boxEventStream,
        builder: (context, snapshot) {
          final width = MediaQuery.of(context).size.width / 2 - 20;
          const double desiredHeight = 220;
          final double crossAspectRatio = width / desiredHeight;
          if (box.length == 0) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite,
                    size: 100,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No favourite audiobooks',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }
          return GridView.builder(
            itemCount: box.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: crossAspectRatio,
              crossAxisSpacing: 10,
              mainAxisSpacing: 0,
            ),
            itemBuilder: (context, index) {
              var key = box.keyAt(index);
              final audiobook = Audiobook.fromMap(box.get(key)!);

              return AudiobookItem(
                audiobook: audiobook,
                width: width,
                height: desiredHeight,
                onLongPressed: () {
                  _showDeleteConfirmation(context, index);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete Audiobook"),
          content: const Text(
              "Are you sure you want to delete this audiobook from favourites?"),
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
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    box.close();
    super.dispose();
  }
}

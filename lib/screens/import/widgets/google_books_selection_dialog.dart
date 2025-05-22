import 'dart:math';
import 'package:aradia/resources/models/google_book_result.dart'; // Adjust path
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GoogleBooksSelectionDialog extends StatelessWidget {
  final List<GoogleBookResult> results;

  const GoogleBooksSelectionDialog({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Select Book Info',
          style: GoogleFonts.ubuntu(color: theme.colorScheme.onSurface)),
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width * 0.9, 400),
        child: results.isEmpty
            ? Center(
                child: Text("No results to display.",
                    style:
                        TextStyle(color: theme.colorScheme.onSurfaceVariant)))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: results.length,
                separatorBuilder: (context, index) =>
                    Divider(color: theme.dividerColor.withOpacity(0.5)),
                itemBuilder: (context, index) {
                  final book = results[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 4.0, horizontal: 8.0),
                    leading: book.thumbnailUrl != null
                        ? SizedBox(
                            width: 40,
                            height: 60,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                book.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(
                                    Icons.broken_image_outlined,
                                    size: 30),
                                loadingBuilder: (c, child, progress) =>
                                    progress == null
                                        ? child
                                        : const Center(
                                            child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))),
                              ),
                            ))
                        : Container(
                            width: 40,
                            height: 60,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: theme.colorScheme.surfaceVariant),
                            child: const Icon(Icons.book_outlined, size: 30)),
                    title: Text(book.title,
                        style: GoogleFonts.ubuntu(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface)),
                    subtitle: Text(book.authors,
                        style: GoogleFonts.ubuntu(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant)),
                    onTap: () => Navigator.of(context).pop(book),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          child: Text('Cancel',
              style: TextStyle(color: theme.colorScheme.primary)),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
    );
  }
}
import 'dart:convert';
import 'package:aradia/resources/models/google_book_result.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show immutable;

@immutable
class GoogleBooksService {
  const GoogleBooksService._();

  static Future<List<GoogleBookResult>> fetchBooks(String query) async {
    if (query.isEmpty) {
      return [];
    }
    try {
      final url = Uri.parse(
          'https://www.googleapis.com/books/v1/volumes?q=${Uri.encodeComponent(query)}&maxResults=5&printType=books&fields=items(id,volumeInfo/title,volumeInfo/authors,volumeInfo/description,volumeInfo/imageLinks)');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          return (data['items'] as List)
              .map((item) =>
                  GoogleBookResult.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } else {
        AppLogger.debug('Google Books API Error: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.debug("Google Books API Exception: $e");
    }
    return [];
  }
}

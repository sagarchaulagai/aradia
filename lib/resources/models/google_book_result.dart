class GoogleBookResult {
  final String id;
  final String title;
  final String authors;
  final String? description;
  final String? thumbnailUrl;
  GoogleBookResult({
    required this.id,
    required this.title,
    required this.authors,
    this.description,
    this.thumbnailUrl,
  });

  factory GoogleBookResult.fromJson(Map<String, dynamic> json) {
    final volumeInfo = json['volumeInfo'] as Map<String, dynamic>? ?? {};
    return GoogleBookResult(
      id: json['id'] as String? ?? '',
      title: volumeInfo['title'] as String? ?? 'No Title',
      authors: (volumeInfo['authors'] as List<dynamic>?)?.join(', ') ??
          'Unknown Author',
      description: volumeInfo['description'] as String?,
      thumbnailUrl: (volumeInfo['imageLinks']
              as Map<String, dynamic>?)?['thumbnail'] as String? ??
          (volumeInfo['imageLinks'] as Map<String, dynamic>?)?['smallThumbnail']
              as String?,
    );
  }
}

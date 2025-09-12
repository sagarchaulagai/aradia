class LocalAudiobook {
  String title;
  String author;
  String folderPath;
  String? coverImagePath;
  List<String> audioFiles;
  Duration? totalDuration;
  DateTime dateAdded;
  DateTime lastModified;
  String? description;
  String? genre;
  double? rating;
  String id; // Unique identifier for each audiobook

  LocalAudiobook({
    required this.title,
    required this.author,
    required this.folderPath,
    this.coverImagePath,
    required this.audioFiles,
    this.totalDuration,
    required this.dateAdded,
    required this.lastModified,
    this.description,
    this.genre,
    this.rating,
    required this.id,
  });

  // Helper method to get the first audio file
  String? get firstAudioFile {
    return audioFiles.isNotEmpty ? audioFiles.first : null;
  }

  // Helper method to check if cover image exists
  bool get hasCoverImage {
    return coverImagePath != null && coverImagePath!.isNotEmpty;
  }

  // Helper method to get formatted duration
  String get formattedDuration {
    if (totalDuration == null) return 'Unknown';

    final hours = totalDuration!.inHours;
    final minutes = totalDuration!.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  // Create a copy with updated fields
  LocalAudiobook copyWith({
    String? title,
    String? author,
    String? folderPath,
    String? coverImagePath,
    List<String>? audioFiles,
    Duration? totalDuration,
    DateTime? dateAdded,
    DateTime? lastModified,
    String? description,
    String? genre,
    double? rating,
    String? id,
  }) {
    return LocalAudiobook(
      title: title ?? this.title,
      author: author ?? this.author,
      folderPath: folderPath ?? this.folderPath,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      audioFiles: audioFiles ?? this.audioFiles,
      totalDuration: totalDuration ?? this.totalDuration,
      dateAdded: dateAdded ?? this.dateAdded,
      lastModified: lastModified ?? this.lastModified,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      rating: rating ?? this.rating,
      id: id ?? this.id,
    );
  }

  // Convert to Map for Hive storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'folderPath': folderPath,
      'coverImagePath': coverImagePath,
      'audioFiles': audioFiles,
      'totalDuration': totalDuration?.inMilliseconds,
      'dateAdded': dateAdded.millisecondsSinceEpoch,
      'lastModified': lastModified.millisecondsSinceEpoch,
      'description': description,
      'genre': genre,
      'rating': rating,
    };
  }

  // Create from Map for Hive retrieval
  static LocalAudiobook fromMap(Map<String, dynamic> map) {
    return LocalAudiobook(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      author: map['author'] ?? 'Unknown',
      folderPath: map['folderPath'] ?? '',
      coverImagePath: map['coverImagePath'],
      audioFiles: List<String>.from(map['audioFiles'] ?? []),
      totalDuration: map['totalDuration'] != null
          ? Duration(milliseconds: map['totalDuration'])
          : null,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(map['dateAdded'] ?? 0),
      lastModified:
          DateTime.fromMillisecondsSinceEpoch(map['lastModified'] ?? 0),
      description: map['description'],
      genre: map['genre'],
      rating: map['rating']?.toDouble(),
    );
  }

  @override
  String toString() {
    return 'LocalAudiobook(id: $id, title: $title, author: $author, folderPath: $folderPath)';
  }
}

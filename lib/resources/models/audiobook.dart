class Audiobook {
  final String title;
  final String id;
  final String? description;
  final String? totalTime;
  final String? author;
  final DateTime? date;
  final int? downloads;
  final List<dynamic>? subject;
  final int? size;
  final double? rating;
  final int? reviews;
  final String lowQCoverImage;
  final String? language;
  final String? origin;

  Audiobook.empty()
      : title = '',
        id = '',
        description = '',
        totalTime = '',
        author = '',
        date = null,
        downloads = 0,
        subject = [],
        size = 0,
        rating = 0,
        reviews = 0,
        lowQCoverImage = '',
        language = '',
        origin = '';

  Audiobook.fromJson(Map jsonAudiobook)
      : id = jsonAudiobook["identifier"] ?? '',
        title = jsonAudiobook["title"] ?? '',
        totalTime = jsonAudiobook["runtime"],
        author = jsonAudiobook["creator"] ?? 'Unknown',
        date = jsonAudiobook['date'] != null
            ? DateTime.parse(jsonAudiobook["date"])
            : null,
        downloads = jsonAudiobook["downloads"] ?? 0,
        subject = jsonAudiobook["subject"] is String
            ? [jsonAudiobook["subject"]]
            : (jsonAudiobook["subject"] as List)
                .where((s) => !["librivox", "audiobooks", "audiobook"]
                    .contains(s.toLowerCase()))
                .toList(),
        size = jsonAudiobook["item_size"],
        rating = jsonAudiobook["avg_rating"] != null
            ? double.parse(jsonAudiobook["avg_rating"].toString())
            : null,
        reviews = jsonAudiobook["num_reviews"],
        description = jsonAudiobook["description"],
        language = jsonAudiobook["language"],
        lowQCoverImage =
            "https://archive.org/services/get-item-image.php?identifier=${jsonAudiobook['identifier']}",
        origin = "librivox";

  static List<Audiobook> fromJsonArray(List jsonAudiobook) {
    List<Audiobook> audiobooks = <Audiobook>[];
    for (var book in jsonAudiobook) {
      if (book["title"] != null && book["creator"] != null) {
        String title = book["title"].toString();
        String creator = book["creator"].toString();

        if (!title.toLowerCase().contains("thumbs") &&
            !creator.toLowerCase().contains("librivox") &&
            title != 'null') {
          audiobooks.add(Audiobook.fromJson(book));
        }
      }
    }
    return audiobooks;
  }

  Map<dynamic, dynamic> toMap() {
    return {
      "title": title,
      "id": id,
      "description": description ?? '',
      "totalTime": totalTime ?? '',
      "author": author ?? '',
      "date": date?.toIso8601String(),
      "downloads": downloads ?? 0,
      "subject": subject ?? [],
      "size": size ?? 0,
      "rating": rating ?? 0.0,
      "reviews": reviews ?? 0,
      "lowQCoverImage": lowQCoverImage,
      "language": language ?? '',
      "origin": origin ?? '',
    };
  }

  Audiobook.fromMap(Map<dynamic, dynamic> map)
      : title = map["title"] ?? '',
        id = map["id"] ?? '',
        description = map["description"] ?? '',
        totalTime = map["totalTime"] ?? '',
        author = map["author"] ?? '',
        date = map["date"] != null ? DateTime.tryParse(map["date"]) : null,
        downloads = map["downloads"] ?? 0,
        subject = map["subject"] ?? [],
        size = map["size"] ?? 0,
        rating = map["rating"] != null
            ? double.parse(map["rating"].toString())
            : 0.0,
        reviews = map["reviews"] ?? 0,
        lowQCoverImage = map["lowQCoverImage"] ?? '',
        language = map["language"] ?? '',
        origin = map["origin"] ?? '';

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "id": id,
      "description": description,
      "totalTime": totalTime,
      "author": author,
      "date": date.toString(),
      "downloads": downloads,
      "subject": subject,
      "size": size,
      "rating": rating,
      "reviews": reviews,
      "lowQCoverImage": lowQCoverImage,
      "language": language,
      "origin": origin,
    };
  }
}

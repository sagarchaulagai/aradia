class Character {
  final String id;
  final String audiobookId;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  Character({
    required this.id,
    required this.audiobookId,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert Character to Map for Hive storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'audiobookId': audiobookId,
      'name': name,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  // Create Character from Map (Hive retrieval)
  factory Character.fromMap(Map<String, dynamic> map) {
    return Character(
      id: map['id'] ?? '',
      audiobookId: map['audiobookId'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] ?? 0),
    );
  }

  // Create a copy with updated fields
  Character copyWith({
    String? id,
    String? audiobookId,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Character(
      id: id ?? this.id,
      audiobookId: audiobookId ?? this.audiobookId,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'Character(id: $id, audiobookId: $audiobookId, name: $name, description: $description, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Character && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

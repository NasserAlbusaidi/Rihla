/// A photo memory from a trip
class Memory {
  final String id;
  final String tripId;
  final String uploadedBy;
  final String? uploaderName;
  final String storagePath;
  final String? caption;
  final DateTime createdAt;
  final String? signedUrl;

  const Memory({
    required this.id,
    required this.tripId,
    required this.uploadedBy,
    this.uploaderName,
    required this.storagePath,
    this.caption,
    required this.createdAt,
    this.signedUrl,
  });

  factory Memory.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;

    return Memory(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      uploadedBy: json['uploaded_by'] as String,
      uploaderName: profile?['display_name'] as String?,
      storagePath: json['storage_path'] as String,
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Deserialize a [Memory] from a Firestore document map.
  ///
  /// Field names are camelCase. [eventId] in Firestore maps to [tripId]
  /// for backward compatibility with existing UI code.
  factory Memory.fromFirestore(Map<String, dynamic> data) {
    return Memory(
      id: data['id'] as String,
      tripId: data['eventId'] as String? ?? data['tripId'] as String? ?? '',
      uploadedBy: data['uploadedBy'] as String,
      storagePath: data['storagePath'] as String,
      caption: data['caption'] as String?,
      createdAt: DateTime.parse(data['createdAt'] as String),
    );
  }

  /// Serialize this [Memory] to a Firestore document map.
  ///
  /// Field names are camelCase per Firestore convention.
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'eventId': tripId,
      'uploadedBy': uploadedBy,
      'storagePath': storagePath,
      'caption': caption,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'trip_id': tripId,
      'uploaded_by': uploadedBy,
      'storage_path': storagePath,
      'caption': caption,
    };
  }

  Memory copyWith({String? signedUrl, String? caption}) {
    return Memory(
      id: id,
      tripId: tripId,
      uploadedBy: uploadedBy,
      uploaderName: uploaderName,
      storagePath: storagePath,
      caption: caption ?? this.caption,
      createdAt: createdAt,
      signedUrl: signedUrl ?? this.signedUrl,
    );
  }
}

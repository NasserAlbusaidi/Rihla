/// Document model for trip files
class Document {
  final String id;
  final String tripId;
  final String? uploaderId;
  final String fileUrl;
  final String fileName;
  final int? fileSize;
  final String? mimeType;
  final DateTime? createdAt;
  final String? uploaderName;

  const Document({
    required this.id,
    required this.tripId,
    this.uploaderId,
    required this.fileUrl,
    required this.fileName,
    this.fileSize,
    this.mimeType,
    this.createdAt,
    this.uploaderName,
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'] as Map<String, dynamic>?;

    return Document(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      uploaderId: json['uploader_id'] as String?,
      fileUrl: json['file_url'] as String,
      fileName: json['file_name'] as String,
      fileSize: json['file_size'] as int?,
      mimeType: json['mime_type'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      uploaderName: profiles?['display_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'uploader_id': uploaderId,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'mime_type': mimeType,
    };
  }

  /// Get the file type category based on mime type
  DocumentType get type {
    if (mimeType == null) return DocumentType.other;

    if (mimeType!.startsWith('image/')) return DocumentType.image;
    if (mimeType!.contains('pdf')) return DocumentType.pdf;
    if (mimeType!.contains('word') || mimeType!.contains('document')) {
      return DocumentType.document;
    }
    if (mimeType!.contains('sheet') || mimeType!.contains('excel')) {
      return DocumentType.spreadsheet;
    }
    return DocumentType.other;
  }

  /// Get human-readable file size
  String get formattedSize {
    if (fileSize == null) return '';

    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Get file extension
  String get extension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toUpperCase() : '';
  }
}

/// Document type enum for categorization
enum DocumentType {
  image,
  pdf,
  document,
  spreadsheet,
  other;

  String get displayName {
    switch (this) {
      case DocumentType.image:
        return 'Image';
      case DocumentType.pdf:
        return 'PDF';
      case DocumentType.document:
        return 'Document';
      case DocumentType.spreadsheet:
        return 'Spreadsheet';
      case DocumentType.other:
        return 'File';
    }
  }
}

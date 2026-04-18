/// Domain-level storage errors.
///
/// Sealed so callers can switch exhaustively on the variant. All trip-bucket
/// storage operations flow through [StorageGateway], which maps
/// [FirebaseFunctionsException] codes onto these variants.
sealed class StorageException implements Exception {
  const StorageException(this.message);
  final String message;

  const factory StorageException.notSignedIn() = _NotSignedIn;
  const factory StorageException.notMember() = _NotMember;
  const factory StorageException.missing() = _Missing;
  const factory StorageException.invalidInput(String detail) = _InvalidInput;
  const factory StorageException.uploadFailed(int statusCode, String body) =
      _UploadFailed;
  const factory StorageException.unknown(String detail) = _Unknown;

  @override
  String toString() => 'StorageException: $message';
}

final class _NotSignedIn extends StorageException {
  const _NotSignedIn() : super('Sign-in required.');
}

final class _NotMember extends StorageException {
  const _NotMember() : super('Not a member of this group.');
}

final class _Missing extends StorageException {
  const _Missing() : super('Resource not found.');
}

final class _InvalidInput extends StorageException {
  final String detail;
  const _InvalidInput(this.detail) : super('Invalid input: $detail');
}

final class _UploadFailed extends StorageException {
  final int statusCode;
  final String body;
  const _UploadFailed(this.statusCode, this.body)
      : super('Upload failed with HTTP $statusCode');
}

final class _Unknown extends StorageException {
  final String detail;
  const _Unknown(this.detail) : super('Unknown storage error: $detail');
}

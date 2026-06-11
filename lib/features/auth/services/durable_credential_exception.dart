/// Thrown by money-adjacent write paths when the current user is still
/// anonymous (#441 PR2). Screens pre-empt it with the Google gate sheet;
/// reaching this exception means the UI gate was bypassed (offline replay,
/// programmatic call) — the write must not proceed.
class DurableCredentialRequiredException implements Exception {
  const DurableCredentialRequiredException();

  @override
  String toString() => 'A linked account is required for this action.';
}

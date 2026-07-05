/// Case-insensitive substring match — the pinned v1 predicate (PR-5b spec).
///
/// No diacritic folding: Arabic has no case, so exact substring applies as-is
/// on both scripts. Used by [SearchResults] and pinned directly by unit tests.
bool matchesSearchQuery(String haystack, String query) {
  return haystack.toLowerCase().contains(query.toLowerCase());
}

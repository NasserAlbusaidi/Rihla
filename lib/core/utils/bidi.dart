/// Unicode bidirectional isolation for user-controlled strings that are
/// interpolated into a directional sentence which drives or confirms money, or
/// is rendered by the OS (#1216b).
///
/// Wraps [s] in FSI (U+2068, First Strong Isolate) … PDI (U+2069, Pop
/// Directional Isolate). FSI — not LRI — so an Arabic name keeps its own base
/// direction inside the RTL app; the isolate stops an unterminated RLO/LRO
/// carried by legacy data or free text from visually reordering the sentence
/// around the name.
///
/// DISPLAY-ONLY. This must NEVER reach a persist, share, or derive boundary
/// (avatar hashing, share payloads, callables). Apply it to the l10n call
/// ARGUMENT or the render-span text — never to the source name variable.
String bidiIsolate(String s) => '\u{2068}$s\u{2069}';

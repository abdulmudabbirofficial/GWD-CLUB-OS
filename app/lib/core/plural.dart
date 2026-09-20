/// Counting things in a sentence.
///
/// "1 people" is the kind of mistake that makes an app feel unfinished, and a
/// club app says "N people" on nearly every screen — departments, teams,
/// recognition, the alert reach warning. Each of those grew its own inline
/// ternary, several were missed, and the Recognition screen listed four
/// departments as "1 people".
///
/// Most of English is regular enough that a rule covers it, and the ones that
/// are not take their plural explicitly.
String countOf(int n, String singular, [String? plural]) =>
    '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

/// The same, for the handful of words with an irregular plural.
String people(int n) => countOf(n, 'person', 'people');

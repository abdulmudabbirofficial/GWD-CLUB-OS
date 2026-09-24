/// The short form of a name the **server** has already rendered.
///
/// Rows too narrow for a full name show the first word — "Nishta" rather than
/// "Nishta Rao". But the server renders a Director as "Director Mudabbir"
/// (see `displayNameOf` in backend/src/people.js), and cutting that to its
/// first word leaves only the title: every upload, helper and assignee chip a
/// Director appeared on read "Director", as if it were a person.
///
/// This matches the server's own output, never a name somebody typed, so it is
/// not guessing who anybody is. For a [Member] in hand, use `Member.shortName`,
/// which works from the flags instead.
String shortNameOf(String rendered) {
  final name = rendered.trim();
  if (name.isEmpty) return name;
  if (name == 'No name set') return name;
  if (name.startsWith('Director ')) return name;
  return name.split(RegExp(r'\s+')).first;
}

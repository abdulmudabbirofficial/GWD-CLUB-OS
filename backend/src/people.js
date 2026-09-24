'use strict';

/**
 * How a person is named in anything the server writes for other people to
 * read: notification text, broadcast signatures, audit sentences.
 *
 * The client has the same rules in `Member.displayName`. They live in two
 * places because the server renders notification copy itself (the same words
 * go over the socket and over push), and a notification that said "Abdul
 * Mudabbir assigned you a task" while every screen said "Director Mudabbir"
 * would read as two different people.
 */

/**
 * The name to print.
 *
 * - An account still carrying a placeholder reads "No name set", never the
 *   placeholder — "Creative Lead assigned you a task" names a job, not a person.
 * - A Director with a `knownAs` reads "Director Rehman", and the Super Admin
 *   reads "Club Director Mudabbir". The club addresses
 *   its Directors by title and the name it knows them by, and that short name
 *   cannot be derived from the full one: it is the last word of "Abdul
 *   Mudabbir" but the first of "Rehman Pasha". So it is stored, not guessed.
 */
function displayNameOf(user) {
  if (!user) return 'Somebody';
  if (user.mustSetName) return 'No name set';
  const knownAs = typeof user.knownAs === 'string' ? user.knownAs.trim() : '';
  // The Super Admin is *the* Club Director; the other two are Directors.
  if (user.role === 'clubDirector' && knownAs) {
    return user.superAdmin === true ? `Club Director ${knownAs}` : `Director ${knownAs}`;
  }
  return user.name || 'Somebody';
}

/** Role titles for sentences the server writes. Mirrors `ClubRole.title`. */
const ROLE_TITLES = {
  clubDirector: 'Director',
  facultyCoordinator: 'Faculty Coordinator',
  president: 'President',
  vicePresident: 'Vice President',
  secretaryGeneral: 'General Secretary',
  clubLead: 'Club Lead',
  clubMember: 'Club Member',
};

const roleTitle = (role) => ROLE_TITLES[role] ?? 'Member';

module.exports = { displayNameOf, roleTitle, ROLE_TITLES };

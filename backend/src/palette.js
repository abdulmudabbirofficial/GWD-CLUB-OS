'use strict';

/**
 * The colours that tell one person, department or category from another.
 *
 * One list, because there were four: this file's contents were copy-pasted
 * into `seed.js`, `routes/auth.js` and `routes/categories.js`, which meant the
 * two colours in it that could not be read were shipped four times and had to
 * be fixed four times.
 *
 * These are a distinguisher, not a brand statement. The reader needs to see
 * that Marketing and Creative are different at a glance and nothing more, so
 * they are held to one band of lightness, and the brand crimson leads.
 *
 * Two were removed from the set this replaces:
 *
 *   `#0B0B0F` — near-black. The client paints an avatar tint as the *text* on
 *   a 12% wash of itself, so anyone who hashed to this got black initials on a
 *   black circle. Invisible on the light theme and doubly so on the dark one.
 *
 *   `#6D28D9` / `#7C3AED` — violet. In an app built on crimson it reads as
 *   something borrowed from another product.
 *
 * Colours already stored against a member or a category still come back from
 * the database, so changing this list does not repair them. The client lifts
 * any tint into a readable range at paint time; this just stops new ones being
 * created badly.
 */
const ACCENTS = [
  '#DC2626', // crimson — the brand, first so it is the most common
  '#E11D48', // rose
  '#EA580C', // orange
  '#CA8A04', // amber
  '#16A34A', // green
  '#0D9488', // teal
  '#2563EB', // blue
  '#64748B', // slate
];

/**
 * A wider set for the schedule, where somebody is choosing by hand and a
 * handful of near-identical reds would be no choice at all.
 */
const CATEGORY_PALETTE = [
  ...ACCENTS,
  '#BE123C', // deep rose
  '#0F766E', // deep teal
  '#A16207', // bronze
  '#0891B2', // cyan
];

/**
 * The same colour for the same person every time, so an avatar does not change
 * between screens or between sessions.
 */
function accentFor(seed) {
  let hash = 0;
  for (let i = 0; i < String(seed).length; i += 1) {
    hash = (hash * 31 + String(seed).charCodeAt(i)) >>> 0;
  }
  return ACCENTS[hash % ACCENTS.length];
}

module.exports = { ACCENTS, CATEGORY_PALETTE, accentFor };

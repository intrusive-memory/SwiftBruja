# Personaje prompt fixtures

Test input for `PersonajeAcceptanceTests`. Nine prompts, one character each,
built from the Granville script `granville-2026SEP08.highland` (draft dated
September 8, 2026). The original nine prompts were not kept, so this set is a
reconstruction. Do not edit the `.txt` files by hand.

## Files

- `01`-`05`: majors HUNTER, SHANE, ARCHER, CLARK, KEVIN.
- `06`-`07`: minors TOBY, IOLA.
- `08`-`09`: the two remaining characters with the most dialogue blocks (LEROY, DUKE).
- `schema.json`: the single source the tests build their `BrujaJSONSchema` from.
  `propertyOrder` arrays are the order of record (key order does not survive
  JSON parsing in Swift). `relationships` and `canonFacts` items carry their own.

## Bounds

`schema.json` bounds every free-text value: `"maxLength": 500` on each top-level
string, `"maxLength": 200` on the strings inside `relationships` and `canonFacts`
items (`with`, `nature`, `fact`, `quote`), and `"maxItems": 8` on both arrays.
The acceptance tests generate with `maxTokens: 4096`. These bounds are Personaje's
choice, kept in this fixture. They are not a SwiftBruja library default; the
library applies a bound only when the schema carries one.

## Context rules (Personaje REQUIREMENTS-APP-UI.md 11.3)

- Major: every scene the character speaks in, complete (all dialogue, narrator and action lines).
- Minor: each of the character's lines with the 3 elements before and after it,
  clipped to the scene and merged where the windows overlap.

An element is one dialogue block, narrator block or action paragraph, each
labelled with its speaker. Every file starts with the same instruction block,
then a line reading `=== EXCERPTS ===`, then `CHARACTER: <NAME>` and the excerpts.
Inline production notes such as `[[ <breath/> ]]` are removed.

## Regenerate

    python3 Fixtures/Personaje/build-fixtures.py /Users/stovak/Projects/podcasts/granville/granville-2026SEP08.highland

Python 3, standard library only. Output is deterministic.

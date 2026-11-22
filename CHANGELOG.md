# Changelog

All notable changes to RaceCosmetic. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

Baldur's Gate 3 data version referenced: patch 8.

---

## [1.1.0] — 2026-11-22

### Added

- **Second variant: "Look and identity".** The spell is now a container with two variants:
  **Look only** (appearance, body type, voice) and **Look and identity** (the same, plus the
  **race name and tags**, including dialogue options). Racial traits, class, ability scores,
  background and the Dream Guardian stay the original ones in both variants.
- `RaceCosmetic_origin.txt` records the race each character had before its first reshape.

### Changed

- The two spells are merged into one spellbook entry with variants, instead of two separate spells.
- Characters that received the standalone spells from 1.0.1 have them removed on load; the container
  is granted instead, so no duplicate icons are left behind.
- Respec repair now uses the recorded original race instead of the live `Race` component, so the
  identity variant cannot confuse it.

### Verified

- look-only variant: name, tags and traits stay original
- identity variant: name and tags change, traits stay original
- respec after both variants still grants the original race's traits

---

## [1.0.1] — 2026-11-22

### Fixed

- **Withers' respec no longer grants the borrowed race's racial traits.** Respeccing used to replay
  the racial progression of the race you borrowed the *look* from, so a reshaped character ended up
  with e.g. drow traits while keeping the original race name and tags. The respec screen now shows
  your original race and the traits granted match it.
- Characters converted with **1.0.0** are repaired automatically when the save is loaded: the race
  stored in the character's creation data is put back in sync with the real race. The **next** respec
  then grants the correct traits — traits already granted are not revoked retroactively.

### Changed

- The `Race` component and `CharacterCreationStats.Race/SubRace` are **no longer written**. The model
  is carried by `GameObjectVisual`, the appearance data, `AppearanceOverride` and the template fields
  (`EquipmentRace` / `CharacterVisualResourceID` / `VisualTemplate`) instead. Verified in game: the
  world model, level up screen and character sheet all still render correctly.
- Removed the respec-watch code. `DB_InCharacterRespec` turned out to belong to the paladin
  oathbreaker flow only, so polling it never fired for Withers.

### Added

- `src/…/RaceData.lua` — vanilla race-parent table generated from the game's own `Races.lsx`.
- `tools/gen-race-data.py` — regenerates that table (run it after a game patch that adds races).

### Verified

- appearance, body type and voice change correctly in the world
- level up screen and character sheet are correct, including armour fit
- race name, tags, traits, class, ability scores and background stay original
- respec grants the original race's traits, respec screen shows the original race
- repeated reshapes work

---

## [1.0.0] — 2026-11-20

### Added

- Spell **Reshape Form**, granted automatically to the main character. Casting it opens the vanilla
  character creation screen.
- Permanent conversion of appearance, body type and voice, written into character data so it survives
  saves, loads, long rests and respecs.
- Race name, racial tags, racial traits, class, subclass, ability scores, background and the Dream
  Guardian stay untouched.
- English and Simplified Chinese localisation.
- Build and install scripts (`build.ps1`, `install.ps1`).
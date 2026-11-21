# RaceCosmetic — Reshape Form

**A Baldur's Gate 3 mod that lets you permanently change how your character looks, sounds and is built — using the game's own character creation screen — without touching your race mechanics.**

![RaceCosmetic](promo/cover-char-1920x1080.png)

---

## What it does

Adds a single spell, **Reshape Form**, to your main character's spellbook. Casting it opens the
**vanilla character creation screen**: pick the look of any vanilla race, sculpt the face, hair,
skin, tattoos, horns and tail, and choose a voice.

When you confirm, that look is written onto your character **permanently** — it becomes part of the
character data, so it survives saving, loading, long rests and respecs. There is no transform to keep
active and no toggle to maintain.

**Your race mechanics stay yours:** race name, racial tags, racial traits, class, subclass,
ability scores, background and the Dream Guardian are untouched.

So you can play a duergar for the traits and look like a drow, or mix any other race's appearance
with any other race's mechanics.

Unlike most shapeshift mods, the result is also correct in the **level up screen and the character
sheet**, which rebuild the model from character data rather than from the live world model.

---

## Features

| | |
| --- | --- |
| **Vanilla UI** | Uses the game's own character creation screen — no custom interface |
| **Permanent** | Written into character data; survives saves, loads and respecs |
| **Consistent** | World model, level up screen and character sheet all agree |
| **Mechanics preserved** | Race name, tags, traits, class, ability scores, background |
| **Voice included** | Body type and voice are part of the swap |
| **Any vanilla race** | Including cross-body-type combinations |
| **Bilingual** | English and Simplified Chinese |
| **Lightweight** | No ImpUI, no MCM, no third-party assets |

---

## Requirements

- **BG3 Script Extender** (Norbyte) — required
- Baldur's Gate 3, patch 8 tested
- Single player, main character only

---

## Installation (players)

The built `.pak` is distributed through **Releases** and **Nexus Mods** — this repository holds the
source.

1. Install [BG3 Script Extender](https://github.com/Norbyte/bg3se).
2. Copy `RaceCosmetic.pak` into `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods\`.
3. Enable **RaceCosmetic** in BG3 Mod Manager and move it to the **bottom** of the load order.
4. Load your save, open the spellbook (`K`), find **Reshape Form**.

**Usage:**

1. Make sure the party has a **free slot** (max 4) — the mod briefly adds a temporary character.
2. Cast **Reshape Form** outside combat.
3. Create the look you want and confirm.
4. Wait 2–3 seconds; the temporary character is removed and control returns to you.

To change your look again later, simply cast the spell again.

---

## Building from source

Requires [LSLib](https://github.com/Norbyte/lslib) (`Divine.exe`).

```powershell
# default: looks for ..\modtools\Packed\Tools\Divine.exe next to this folder
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1

# or point at Divine explicitly
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Divine "C:\path\to\Divine.exe"
```

`install.ps1` copies the built package into the game's `Mods` folder and registers it in
`modsettings.lsx` (it refuses to run while the game is open, and backs up `modsettings.lsx` first).

---

## How it works

The interesting part is not the shapeshift — it is that **the game draws a character from five
independent layers**, and a preview screen (level up, character sheet) rebuilds the model from those
layers instead of reusing the live one:

| Layer | Component / field | What breaks if it is missing |
| --- | --- | --- |
| Appearance parts | `CharacterCreationAppearance` | Old head, hair, tattoos |
| Body | `BodyType` | Old body type |
| Skeleton / race | `Race` component | New head cannot anchor to the old skeleton — detached hair, mismatched limbs |
| Visual template | `GameObjectVisual` | Wrong model resource |
| Creation data | `CharacterCreationStats` | Wrong race resolution in previews |
| Applied look cache | `AppearanceOverride` | Previews render a stale look |

Writing only *some* of them produces the classic "new head on an old body" mess, so the mod writes
all of them together and **aborts the whole write** if `AppearanceOverride` cannot be created — a
half-applied write is worse than none.

Armour was the last piece: which race's and gender's mesh variant is worn is decided by template
fields, not components:

```
EquipmentRace, CharacterVisualResourceID, VisualTemplate   (ServerCharacter.Template)
```

Those are copied as well, which is what finally made the level up preview correct.

What is **deliberately not** copied: the template's `Race` / `Id` fields, class, feats,
attributes, background. That is why the race name, tags and traits stay the player's own. Tags that
the shapeshift rule strips are restored right after the swap.

---

## Known limitations

- **Free party slot required.** The mod briefly adds a temporary character (max party 4). If the
  party is full the reshape is cancelled and the log says so.
- **Portraits do not refresh automatically.** Use the magic mirror or reload the save.
- **The game logs a "dream visitor died" combat log line** while the temporary character is cleaned
  up. Engine-side, cannot be suppressed (Appearance Edit Enhanced shows the same). Harmless.
- **No revert spell by design.** The change is permanent — reshape again to pick a new look.
- **Do not use it together with Appearance Edit Enhanced's mirror entry.** Both open character
  creation; pick one.

---

## Credits

The approach is inspired by **[Appearance Edit Enhanced](https://www.nexusmods.com/baldursgate3/mods/899)**
by **Eralyne** — specifically how the game caches the applied look in `AppearanceOverride`, and how
template fields such as `EquipmentRace` select armour variants.

This is an **independent implementation**: the code was written with AI coding assistance, guided and
tested in game by the author. No Lua code, data tables or art assets from AAE are reused, and the
package contains no third-party assets.

---

## License

MIT — see [LICENSE](LICENSE). Redistribution of the built package is fine as long as Larian's mod
policy is respected (no paywalls).
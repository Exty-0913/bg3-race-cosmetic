"""Regenerate RaceCosmetic/RaceData.lua from the game's own data files.

The mod needs one fact that the engine keeps in data files rather than exposing at
runtime: the parent race of every vanilla race. It is used to repair characters that
were converted by an older build, where CharacterCreationStats held the *looked* race
instead of the real one.

Usage (paths are the defaults for a Steam install):

    python gen-race-data.py
    python gen-race-data.py --data "D:\\Games\\BG3\\Data" --out src\\Mods\\...\\RaceData.lua

The two input files live inside Data\\Shared.pak:

    Public/Shared/Races/Races.lsx
    Public/Shared/Progressions/Progressions.lsx   (not needed for the parent table,
                                                   kept for the passives cross-check)

Extract them with LSLib first, e.g.:

    Divine.exe -g bg3 --action extract-package -s "%GAME%\\Data\\Shared.pak" -d <out> \
        -f "Public/Shared/Races/Races.lsx"
"""

import argparse
import os
import xml.etree.ElementTree as ET

DEFAULT_DATA = r"C:\Program Files (x86)\Steam\steamapps\common\Baldurs Gate 3\Data"
DEFAULT_OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "src", "Mods", "RaceCosmetic", "ScriptExtender", "Lua", "RaceCosmetic", "RaceData.lua",
)


def attributes(node):
    out = {}
    for attr in node.findall("attribute"):
        value = attr.get("value")
        out[attr.get("id")] = value if value is not None else attr.get("handle")
    return out


def collect_races(races_lsx):
    races = {}
    for node in ET.parse(races_lsx).iter("node"):
        if node.get("id") != "Race":
            continue
        attrs = attributes(node)
        uuid = (attrs.get("UUID") or "").lower()
        if not uuid:
            continue
        races[uuid] = {
            "name": attrs.get("Name") or "?",
            "parent": (attrs.get("ParentGuid") or "").lower() or None,
        }
    return races


def render(races):
    lines = [
        "-- Generated from the game data (Public/Shared/Races/Races.lsx).",
        "-- Do not edit by hand: run tools/gen-race-data.py instead.",
        "--",
        "-- parent: race guid -> parent race guid. Used to put CharacterCreationStats back in",
        "-- sync on characters converted by builds that wrote the looked race into it.",
        "return {",
        "    parent = {",
    ]
    for uuid in sorted(races):
        parent = races[uuid]["parent"]
        if parent:
            lines.append(f'        ["{uuid}"] = "{parent}", -- {races[uuid]["name"]}')
    lines += ["    },", "}", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", default=DEFAULT_DATA, help="game Data folder")
    parser.add_argument("--races", help="path to an already extracted Races.lsx")
    parser.add_argument("--out", default=DEFAULT_OUT, help="output Lua file")
    args = parser.parse_args()

    races_lsx = args.races or os.path.join(args.data, "Localization", "..", "Races", "Races.lsx")
    if not os.path.exists(races_lsx):
        raise SystemExit(
            f"Races.lsx not found at {races_lsx}\n"
            "Extract it out of Data\\Shared.pak first (see the docstring)."
        )

    races = collect_races(races_lsx)
    table = render(races)
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(table)
    print(f"wrote {args.out} ({len(races)} races)")


if __name__ == "__main__":
    main()
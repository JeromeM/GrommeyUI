"""Writes ActionBars/TravelSkills.lua, the travel skills and the mounts of the game for the travel bar.

    python3 tools/travel_skills.py

The data comes from LotroCompanion/lotro-data (https://github.com/LotroCompanion/lotro-data):
the <travelSkill> and <mount> entries of lore/skills.xml and their names in lore/labels/{en,fr,de}/skills.xml.
Run it again when the game adds travel skills.
"""

import os
import re
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = "https://raw.githubusercontent.com/LotroCompanion/lotro-data/master/lore/"
TARGET = os.path.join(ROOT, "ActionBars", "TravelSkills.lua")

# The older racial version of a skill that also exists for reputation, under the same name
RACE = {1879073480: "Hobbit", 1879073526: "Man", 1879073567: "Elf", 1879073606: "Dwarf"}

FAMILY_ORDER = ["home", "house", "regions", "hunter", "warden", "mariner", "mount", "other"]


def fetch(path):
    with urllib.request.urlopen(SOURCE + path) as response:
        return response.read().decode("utf-8")


def family(name):
    if name.startswith("Return Home"):
        return "home"
    if name.startswith("Travel to") and name.endswith("House"):
        return "house"
    if name.startswith("Guide to"):
        return "hunter"
    if name.startswith("Muster"):
        return "warden"
    if name.startswith("Sail to"):
        return "mariner"
    if name.startswith(("Return to Camp", "Smell the")):
        return "other"
    return "regions"


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    skills = fetch("skills.xml")
    labels = {}
    for language in ("en", "fr", "de"):
        labels[language] = dict(re.findall(r'<label key="(\d+)" value="([^"]*)"', fetch("labels/%s/skills.xml" % language)))

    entries = []
    for tag, attributes in re.findall(r"<(travelSkill|mount) ([^>]*)", skills):
        fields = dict(re.findall(r'(\w+)="([^"]*)"', attributes))
        number = int(fields["identifier"])
        english = labels["en"].get(fields["identifier"], fields["name"])
        entries.append({
            "id": "0x%08X" % number,
            "family": "mount" if tag == "mount" else family(fields["name"]),
            "icon": int(fields.get("iconId", "0")),
            "race": RACE.get(number),
            # A mount and its peer: the horse for tall races, the pony for the others
            "tall": (fields.get("tall") == "true") if (tag == "mount" and "peerId" in fields) else None,
            "en": english,
            "fr": labels["fr"].get(fields["identifier"], english),
            "de": labels["de"].get(fields["identifier"], english),
        })
    # Numbers in their natural order: Return Home 2 before Return Home 10
    natural = lambda text: re.sub(r"\d+", lambda number: number.group(0).zfill(4), text)
    entries.sort(key=lambda entry: (FAMILY_ORDER.index(entry["family"]), natural(entry["en"]), entry["id"]))

    lines = [
        "-- Travel skills and mounts of the game for the travel bar: id, family, icon and names in English, French and German.",
        "-- Written by tools/travel_skills.py from LotroCompanion/lotro-data (https://github.com/LotroCompanion/lotro-data),",
        "-- thanks to its authors. Do not edit by hand, run the script again.",
        "-- race: the racial version of a skill that also exists for reputation under the same name.",
        "-- tall: a mount with a peer, the horse (true) for tall races and the pony (false) for the others.",
        "",
        "Grommey.TravelSkills = {",
    ]
    for entry in entries:
        race = (' race = "%s";' % entry["race"]) if entry["race"] else ""
        if entry["tall"] is not None:
            race += " tall = %s;" % ("true" if entry["tall"] else "false")
        lines.append('    { id = "%s"; family = "%s"; icon = %d;%s en = %s; fr = %s; de = %s; };' % (
            entry["id"], entry["family"], entry["icon"], race,
            lua_string(entry["en"]), lua_string(entry["fr"]), lua_string(entry["de"])))
    lines.append("};")
    with open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print("%d travel skills written to %s" % (len(entries), os.path.relpath(TARGET, ROOT)))


if __name__ == "__main__":
    main()

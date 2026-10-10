"""Writes ActionBars/StanceSkills.lua, the stances of the classes for the stances bar.

    python3 tools/stance_skills.py

The data comes from LotroCompanion/lotro-data (https://github.com/LotroCompanion/lotro-data):
the skills of lore/skills.xml whose name says Stance or Posture, or whose description starts with
"This stance", with their names in lore/labels/{en,fr,de}/skills.xml. Skills without a class
category or with the blank icon are inner effects of the game, not stances a character learns.
Run it again when the game adds stances.
"""

import os
import re
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = "https://raw.githubusercontent.com/LotroCompanion/lotro-data/master/lore/"
TARGET = os.path.join(ROOT, "ActionBars", "StanceSkills.lua")

BLANK_ICON = "1090522259"
# Skill categories left out: monster play and skirmish soldiers (7), the scribe of the crafting (58)
SKIPPED_CATEGORIES = {"7", "58"}


def fetch(path):
    with urllib.request.urlopen(SOURCE + path) as response:
        return response.read().decode("utf-8")


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    skills = fetch("skills.xml")
    labels = {}
    for language in ("en", "fr", "de"):
        labels[language] = dict(re.findall(r'<label key="([^"]+)" value="([^"]*)"', fetch("labels/%s/skills.xml" % language)))

    entries = []
    for attributes in re.findall(r"<skill ([^>]*)>", skills):
        fields = dict(re.findall(r'(\w+)="([^"]*)"', attributes))
        category = fields.get("category")
        icon = fields.get("iconId", BLANK_ICON)
        if category is None or category in SKIPPED_CATEGORIES or icon == BLANK_ICON:
            continue
        description = labels["en"].get(fields.get("description", ""), "")
        if not (re.search(r"\b(Stance|Posture)\b", fields["name"]) or description.startswith("This stance")):
            continue
        identifier = fields["identifier"]
        english = labels["en"].get(identifier, fields["name"])
        entries.append({
            "id": "0x%08X" % int(identifier),
            "category": int(category),
            "icon": int(icon),
            "en": english,
            "fr": labels["fr"].get(identifier, english),
            "de": labels["de"].get(identifier, english),
        })
    # Grouped by class, in the order of the game
    entries.sort(key=lambda entry: (entry["category"], entry["id"]))

    lines = [
        "-- Stances of the classes for the stances bar: id, class category, icon and names in English, French and German.",
        "-- Written by tools/stance_skills.py from LotroCompanion/lotro-data (https://github.com/LotroCompanion/lotro-data),",
        "-- thanks to its authors. Do not edit by hand, run the script again.",
        "",
        "Grommey.StanceSkills = {",
    ]
    for entry in entries:
        lines.append('    { id = "%s"; category = %d; icon = %d; en = %s; fr = %s; de = %s; };' % (
            entry["id"], entry["category"], entry["icon"],
            lua_string(entry["en"]), lua_string(entry["fr"]), lua_string(entry["de"])))
    lines.append("};")
    with open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print("%d stances written to %s" % (len(entries), os.path.relpath(TARGET, ROOT)))


if __name__ == "__main__":
    main()

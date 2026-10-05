"""Checks the translation files of GrommeyUI (Locales/*.lua) against the texts of the code.

    python3 tools/check_translations.py

For each language it lists the texts of the code that have no translation yet, and the
translations no text uses any more. Texts given to L() as literals are found directly; texts
passed through a table (names of modules, of colours, drop down items...) are found from their
usual fields: name, text, title, label, description.
"""

import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRING = r'"((?:[^"\\]|\\.)*)"'

# Texts translated through a table the patterns below do not see
INDIRECT = {
    "Disease", "Fear", "Poison", "Wound", "Corruption",   # debuff types, UnitFrames/Effects.lua
    "General", "Theme", "Profiles", "Layout", "Modules",  # option pages named by their key, Core/Options.lua
    "Automatic (game language)",                          # Core/Locale.lua
}

def code_texts():
    texts = set()
    for path in glob.glob(os.path.join(ROOT, "**", "*.lua"), recursive=True):
        if os.sep + "Locales" + os.sep in path:
            continue
        source = open(path, encoding="utf-8").read()
        # Comments hold examples, not texts
        source = re.sub(r"--[^\n]*", "", source)
        texts.update(re.findall(r'\bL\(\s*' + STRING + r'\s*\)', source))
        for line in source.split("\n"):
            # Language names and font ids are shown as they are
            if "code =" in line or "label =" in line and "name =" in line:
                line = re.sub(r'\bname\s*=\s*' + STRING, "", line)
            texts.update(re.findall(r'\b(?:name|text|title|label|description)\s*=\s*' + STRING, line))
    return texts | INDIRECT

def translations(path):
    source = open(path, encoding="utf-8").read()
    return dict(re.findall(r'\[' + STRING + r'\]\s*=\s*' + STRING, source))

def main():
    texts = code_texts()
    problems = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "Locales", "*.lua"))):
        language = os.path.splitext(os.path.basename(path))[0]
        known = translations(path)
        # Field values that are not meant to be shown (ids, keys) are left out of "missing"
        missing = sorted(text for text in texts if text not in known and re.search(r"[a-z] |^[A-Z][a-z]", text))
        unused = sorted(text for text in known if text not in texts)
        print("== %s: %d translations, %d missing, %d unused" % (language, len(known), len(missing), len(unused)))
        for text in missing:
            print("   missing: " + text)
        for text in unused:
            print("   unused:  " + text)
        problems += len(missing)
    return 1 if problems else 0

if __name__ == "__main__":
    raise SystemExit(main())

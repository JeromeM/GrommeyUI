"""Writes Core/FontMetrics.lua: the width of each letter of Verdana, to lay out texts ourselves.

    python3 tools/font_metrics.py [path/to/verdana.ttf]

The game does not tell a plugin how wide a text is. With these widths the help notes wrap their
lines, space them and justify them. Needs fontTools (pip install fonttools) and the Verdana font
of Windows (C:\\Windows\\Fonts\\verdana.ttf by default).
"""

import os
import sys

from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "Core", "FontMetrics.lua")
DEFAULT_FONT = "/mnt/c/Windows/Fonts/verdana.ttf"

# Letters of English, French and German texts: printable ASCII, Latin-1 letters and a few signs
CHARACTERS = [chr(code) for code in range(32, 127)] + [chr(code) for code in range(160, 256)] + list("ŒœŸ‘’“”«»…–—€")


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    font = TTFont(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FONT)
    cmap = font.getBestCmap()
    advances = font["hmtx"]
    units = font["head"].unitsPerEm
    widths = {}
    for character in CHARACTERS:
        glyph = cmap.get(ord(character))
        if glyph is not None:
            widths[character] = advances[glyph][0]
    lines = [
        "-- Width of each letter of Verdana in font units (%d to the em), written by tools/font_metrics.py." % units,
        "-- Used to lay out the help notes ourselves (line wrapping, line spacing, justified text).",
        "",
        "Grommey.FontMetrics = {",
        "    unitsPerEm = %d;" % units,
        "    average = %d;" % round(sum(widths.values()) / len(widths)),
        "    widths = {",
    ]
    for character in CHARACTERS:
        if character in widths:
            lines.append("        [%s] = %d;" % (lua_string(character), widths[character]))
    lines += ["    };", "};"]
    with open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print("%d letters written to %s" % (len(widths), os.path.relpath(TARGET, ROOT)))


if __name__ == "__main__":
    main()

"""Releases a new version of GrommeyUI.

    python3 tools/release.py 1.0.1              checks, version numbers, commit, tag, push, GitHub release
    python3 tools/release.py 1.0.1 --dry-run    checks and ZIP only, nothing is committed or sent
    python3 tools/release.py 1.0.1 --id 1234    also sets the LoTROInterface id in the .plugincompendium

Before it: add the version at the top of Core/Changelog.lua (texts with L() and their translations).
The Changelog section at the end of docs/lotrointerface.txt is written again from it: copy the whole
file into the description of LoTROInterface (it has no changelog field).

    python3 tools/release.py --lotrointerface   only writes that section again
The ZIP (dist/GrommeyUI-<version>.zip) holds a single GrommeyUI folder to drop into
Documents/The Lord of the Rings Online/Plugins, nothing to rename. Upload it to LoTROInterface by hand.
"""

import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = "GrommeyUI"
# Not part of the plugin, same list as the export-ignore lines of .gitattributes
LEFT_OUT = (".github/", "docs/", "tools/", "dist/", ".gitattributes", ".gitignore")


def run(*command, check=True, capture=True):
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=capture)
    if check and result.returncode != 0:
        fail("%s\n%s" % (" ".join(command), (result.stderr or result.stdout or "").strip()))
    return (result.stdout or "").strip()


def fail(message):
    print("ERROR: " + message)
    sys.exit(1)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8", newline="") as handle:
        return handle.read()


def write(path, text):
    with open(os.path.join(ROOT, path), "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def plugin_files():
    """Files of the plugin: tracked or new, minus what is ignored or left out."""
    listed = run("git", "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    files = []
    for path in sorted(set(listed)):
        if path.startswith(LEFT_OUT) or not os.path.isfile(os.path.join(ROOT, path)):
            continue
        files.append(path)
    return files


def changelog_items(version):
    source = read("Core/Changelog.lua")
    match = re.search(r'version\s*=\s*"%s";\s*items\s*=\s*\{(.*?)\}\s*;\s*\}' % re.escape(version), source, re.S)
    if not match:
        return None
    return re.findall(r'L\("((?:[^"\\]|\\.)*)"\)', match.group(1))


LOTROINTERFACE = "docs/lotrointerface.txt"
CHANGELOG_TITLE = '[SIZE="3"][B]Changelog[/B][/SIZE]'


def all_changelog():
    """Every version of Core/Changelog.lua, newest first: [(version, [items])]."""
    source = read("Core/Changelog.lua")
    entries = re.findall(r'version\s*=\s*"([^"]+)";\s*items\s*=\s*\{(.*?)\}\s*;\s*\}', source, re.S)
    return [(version, [item.replace('\\"', '"') for item in re.findall(r'L\("((?:[^"\\]|\\.)*)"\)', body)])
            for version, body in entries]


def update_lotrointerface():
    """The description of LoTROInterface ends with the changelog, in BBCode."""
    text = read(LOTROINTERFACE)
    if CHANGELOG_TITLE in text:
        text = text[:text.index(CHANGELOG_TITLE)]
    lines = [text.rstrip("\n"), "", CHANGELOG_TITLE]
    for version, items in all_changelog():
        lines.append("[B]%s[/B]" % version)
        lines.append("[LIST]")
        lines += ["[*]" + item for item in items]
        lines.append("[/LIST]")
    write(LOTROINTERFACE, "\n".join(lines) + "\n")


def check(version):
    if not re.match(r"^\d+\.\d+\.\d+$", version):
        fail("the version must look like 1.0.1")
    if changelog_items(version) is None:
        fail('no entry for %s in Core/Changelog.lua (What\'s new window)' % version)
    if subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check_translations.py")], cwd=ROOT).returncode != 0:
        fail("translations are missing (see above)")
    if run("git", "tag", "--list", "v" + version):
        fail("the tag v%s already exists" % version)


def set_version(version, lotro_id):
    for path in ("GrommeyUI.plugin", "GrommeyUIReloader.plugin", "GrommeyUI.plugincompendium"):
        text = re.sub(r"<Version>[^<]*</Version>", "<Version>%s</Version>" % version, read(path), count=1)
        if path.endswith(".plugincompendium") and lotro_id:
            text = re.sub(r"<Id>[^<]*</Id>", "<Id>%s</Id>" % lotro_id, text, count=1)
            text = re.sub(r"info\d+", "info%s" % lotro_id, text)
            text = re.sub(r"download\d+", "download%s" % lotro_id, text)
        write(path, text)


def build_zip(version):
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    target = os.path.join(ROOT, "dist", "%s-%s.zip" % (FOLDER, version))
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in plugin_files():
            archive.write(os.path.join(ROOT, path), FOLDER + "/" + path)
    return target


def release_notes(version):
    lines = ["## What's new"] + ["- " + item for item in changelog_items(version)]
    lines += ["", "## Installation",
              "Download **%s-%s.zip** below and unzip it into `Documents\\The Lord of the Rings Online\\Plugins\\`." % (FOLDER, version),
              "It holds the `GrommeyUI` folder, nothing to rename. Then load GrommeyUI in the game plugin manager."]
    return "\n".join(lines)


def main():
    arguments = sys.argv[1:]
    if not arguments:
        print(__doc__)
        sys.exit(1)
    if arguments[0] == "--lotrointerface":
        update_lotrointerface()
        print("Written: " + LOTROINTERFACE)
        return
    version = arguments[0]
    dry_run = "--dry-run" in arguments
    lotro_id = arguments[arguments.index("--id") + 1] if "--id" in arguments else None

    check(version)
    if dry_run:
        print("ZIP: " + build_zip(version))
        print("Dry run: nothing committed or sent.")
        return

    # The release goes on top of what is on GitHub
    run("git", "fetch", "-q", "origin")
    if run("git", "rev-list", "--count", "HEAD..origin/master") != "0":
        fail("GitHub has commits you do not have: git pull --rebase first")

    set_version(version, lotro_id)
    update_lotrointerface()
    run("git", "add", "-A")
    run("git", "commit", "-q", "-m", "GrommeyUI %s" % version)
    run("git", "tag", "v" + version)
    archive = build_zip(version)
    run("git", "push", "-q", "origin", "master")
    run("git", "push", "-q", "origin", "v" + version)
    run("gh", "release", "create", "v" + version, archive, "--title", "GrommeyUI %s" % version, "--notes", release_notes(version))
    print("Released %s: %s" % (version, archive))
    print("Last step: upload this ZIP to LoTROInterface, with %s as the description." % LOTROINTERFACE)


if __name__ == "__main__":
    main()

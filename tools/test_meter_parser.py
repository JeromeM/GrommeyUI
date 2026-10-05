"""Runs the combat log reader (Meter/Parser.lua) on sample lines of the three clients.

    pip install lupa luaparser      (in a virtual environment)
    python3 tools/test_meter_parser.py [capture.plugindata]

Without argument it checks the samples below. With a capture file written by /gui combatlog
(PluginData/<account>/AllServers/GrommeyUI_CombatCapture.plugindata) it reads every saved line
again and lists the ones that are still not recognised.
Lupa runs Lua 5.4, the game runs 5.1: only the string functions are used, they behave the same.
"""

import os
import re
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YOU = "Grommey"

# language, line, expected fields
SAMPLES = [
    ("en", "Grommey scored a critical hit with Fiery Ridicule on the Boar for 1,234 Fire damage to Morale.",
     dict(kind="damage", source="Grommey", target="Boar", skill="Fiery Ridicule", amount=1234, crit="critical", damageType="fire", pool="morale")),
    ("en", "The Goblin scored a partially blocked hit with Stab on Grommey for 56 Common damage to Morale.",
     dict(kind="damage", source="Goblin", target="Grommey", skill="Stab", amount=56, partial="block", damageType="common")),
    ("en", "Grommey scored a hit on the Boar for 12 (Mounted) Common damage to Morale.",
     dict(kind="damage", skill=None, amount=12, damageType="common")),
    ("en", "Grommey scored a hit with Smite on the Boar.",
     dict(kind="damage", amount=0, noDamage=True, target="Boar")),
    ("en", "Bob applied a critical heal with Words of Healing to Grommey restoring 120 points to Morale.",
     dict(kind="heal", source="Bob", target="Grommey", skill="Words of Healing", amount=120, crit="critical")),
    ("en", "Fortifying Strike applied a heal to Grommey restoring 50 points to Morale.",
     dict(kind="heal", source="Grommey", target="Grommey", skill="Fortifying Strike", amount=50, fromEffect=True)),
    ("en", "Bob applied a heal with Inner Strength to Grommey restoring 30 points to Power.",
     dict(kind="power", amount=30, pool="power")),
    ("en", "The Berserker tried to use Cleave on Grommey but he parried the attempt.",
     dict(kind="damage", source="Berserker", target="Grommey", avoid="parry", amount=0)),
    ("en", "The Wight missed trying to use a melee attack on Grommey.",
     dict(kind="damage", avoid="miss", source="Wight")),
    ("en", "The Beorning reflected 1,106 Common damage to the Morale of the Goblin.",
     dict(kind="damage", amount=1106, reflect=True, damageType="common", target="Goblin")),
    ("en", "You have lost 11 points of temporary Morale!", dict(kind="tempMorale", target=YOU, amount=11)),
    ("en", "The Goblin was interrupted by Grommey!", dict(kind="interrupt", source="Grommey", target="Goblin")),
    ("en", "Grommey defeated the Boar.", dict(kind="death", source="Grommey", target="Boar")),
    ("en", "The Boar died.", dict(kind="death", target="Boar")),
    ("en", "The Troll incapacitated you.", dict(kind="death", source="Troll", target=YOU)),
    ("en", "You have been revived.", dict(kind="revive", target=YOU)),

    ("fr", "Grommeytta a infligé un coup avec Raillerie cuisante - Niveau 1 sur le Sanglier à défenses fendues balafré pour 29 points de type Feu à l'entité Moral.",
     dict(kind="damage", source="Grommeytta", target="Sanglier à défenses fendues balafré", skill="Raillerie cuisante - Niveau 1", amount=29, damageType="fire", pool="morale")),
    ("fr", "La Cible DPS factice a infligé un coup partiellement esquivé avec Attaque à distance sur Adragor pour 6,538 points de type Commun à l'entité Moral.",
     dict(kind="damage", source="Cible DPS factice", target="Adragor", skill="Attaque à distance", amount=6538, partial="evade", damageType="common")),
    ("fr", "Adragor a infligé un coup critique avec Rhétorique glaciale sur la Cible DPS factice pour 51,642 points de type Froid à l'entité Moral.",
     dict(kind="damage", crit="critical", target="Cible DPS factice", amount=51642, damageType="frost")),
    ("fr", "Eleria a appliqué un soin avec Paroles de guérison Ardicapde, redonnant 227 points à Moral.",
     dict(kind="heal", source="Eleria", target="Ardicapde", skill="Paroles de guérison", amount=227, pool="morale")),
    ("fr", "Arc du Juste a appliqué un soin critique à Ardichas, redonnant 52 points à l'entité Puissance.",
     dict(kind="power", source="Ardichas", target="Ardichas", skill="Arc du Juste", amount=52, crit="critical", fromEffect=True)),
    ("fr", "Guérison d'Attaque fortifiante a appliqué un soin à Adra, redonnant 314,802 points à l'entité Moral.",
     dict(kind="heal", target="Adra", amount=314802, fromEffect=True)),
    ("fr", "Osred a appliqué un bénéfice critique avec Cri de ralliement Osred.",
     dict(kind="benefit", source="Osred", target="Osred", skill="Cri de ralliement")),
    ("fr", "L' Berserker hante-jours a essayé d'utiliser une double attaque au corps à corps sur Eleria mais elle a paré la tentative.",
     dict(kind="damage", source="Berserker hante-jours", target="Eleria", avoid="parry", amount=0)),
    ("fr", "L' Eau sinistre redoutable a essayé d'utiliser Maladie sur Osred mais il a résisté la tentative.",
     dict(kind="damage", avoid="resist", skill="Maladie")),
    ("fr", "La Eau sinistre misérable n'a pas réussi à utiliser une double attaque au corps à corps sur le Osred.",
     dict(kind="damage", avoid="miss", source="Eau sinistre misérable", target="Osred")),
    ("fr", "Le Beorgal a renvoyé 1,106 Commun de dégâts au Moral de le Gobelin porteur de bombes.",
     dict(kind="damage", reflect=True, amount=1106, damageType="common", target="Gobelin porteur de bombes")),
    ("fr", "Le Sangsue gardienne a renvoyé 339 points redonnés au Moral de Eleria.",
     dict(kind="heal", reflect=True, amount=339, target="Eleria")),
    ("fr", "Vous avez perdu 11 points de Moral temporaire !", dict(kind="tempMorale", amount=11, target=YOU)),
    ("fr", "Hellokitting a vaincu la Racine invoquée.", dict(kind="death", source="Hellokitting", target="Racine invoquée")),
    ("fr", "Votre coup puissant a vaincu la Racine invoquée.", dict(kind="death", source=YOU, target="Racine invoquée")),
    ("fr", "L' Loup du crépuscule hurlant a marqué un coup avec Morsure invalidante sur le Duntguiff.",
     dict(kind="damage", source="Loup du crépuscule hurlant", target="Duntguiff", skill="Morsure invalidante", amount=0, noDamage=True)),
    ("fr", "Duntguiff a infligé un coup partiellement paré avec une attaque au corps à corps sur le Loup du crépuscule hurlant pour 2 points de type Commun à l'entité Moral.",
     dict(kind="damage", partial="parry", skill="une attaque au corps à corps", amount=2)),
    ("fr", "Le Crin-rêche malade a infligé un coup avec Maladie mineure sur Duntguiff pour 1 points de type Commun à l'entité Puissance.",
     dict(kind="damage", amount=1, pool="power")),
    ("fr", "Le Sanglier meurt.", dict(kind="death", target="Sanglier")),
    ("fr", "Vous revenez à la vie.", dict(kind="revive", target=YOU)),

    ("de", 'Grommey gelang ein kritischer Treffer mit "Feuriger Spott" gegen den Eber für 1.234 Punkte Schaden des Typs "Feuer" auf Moral.',
     dict(kind="damage", source="Grommey", target="Eber", skill="Feuriger Spott", amount=1234, crit="critical", damageType="fire", pool="morale")),
    ("de", 'Bob wandte "kritische Heilung" mit "Worte der Heilung" auf Grommey an, was 120 Punkte Moral wiederherstellte.',
     dict(kind="heal", source="Bob", target="Grommey", skill="Worte der Heilung", amount=120, crit="critical")),
    ("de", 'Kräftigender Schlag verursacht bei Grommey "Heilung" und stellt 50 Punkte Kraft wieder her.',
     dict(kind="power", source="Grommey", skill="Kräftigender Schlag", amount=50, fromEffect=True)),
    ("de", 'Der Berserker wollte Grommey mit "Spalten" treffen, aber er konterte den Versuch mit "Parieren".',
     dict(kind="damage", source="Berserker", target="Grommey", skill="Spalten", avoid="parry")),
    ("de", "Ihr habt 11 Punkte Moral (temporär) verloren!", dict(kind="tempMorale", amount=11, target=YOU)),
    ("de", "Der Eber ist gestorben.", dict(kind="death", target="Eber")),
]


def load_parser():
    lua = LuaRuntime(unpack_returned_tuples=True)
    source = open(os.path.join(ROOT, "Meter", "Parser.lua"), encoding="utf-8").read()
    lua.execute(source)
    return lua, lua.eval("Grommey.Meter.Parser")


def parse(parser, line, language):
    return parser.Parse(parser.Clean(line), language, YOU)


def check_samples(parser):
    failures = 0
    for language, line, expected in SAMPLES:
        event = parse(parser, line, language)
        if event is None:
            print(f"FAIL [{language}] not recognised: {line}")
            failures += 1
            continue
        wrong = {key: (value, event[key]) for key, value in expected.items() if event[key] != value}
        if wrong:
            failures += 1
            print(f"FAIL [{language}] {line}")
            for key, (want, got) in wrong.items():
                print(f"     {key}: expected {want!r}, got {got!r}")
    print(f"{len(SAMPLES) - failures}/{len(SAMPLES)} samples OK")
    return failures == 0


def check_capture(parser, path):
    text = open(path, encoding="utf-8").read()
    language = (re.search(r'\["language"\]\s*=\s*"(\w+)"', text) or [None, "en"])[1]
    lines = re.findall(r'"((?:player|enemy|death) \| (?:[^"\\]|\\.)*)"', text)
    unknown = 0
    for entry in lines:
        line = entry.split(" | ")[1]
        if parse(parser, line, language) is None:
            unknown += 1
            print("? " + line)
    print(f"{len(lines) - unknown}/{len(lines)} lines recognised ({language})")


if __name__ == "__main__":
    lua, parser = load_parser()
    if len(sys.argv) > 1:
        check_capture(parser, sys.argv[1])
    else:
        sys.exit(0 if check_samples(parser) else 1)

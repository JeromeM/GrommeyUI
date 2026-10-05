-- Combat log reader: turns one line of the combat chat into an event table, or nil.
-- Plain Lua without any game call, so it can be tested outside the game (tools/test_meter_parser.py).
-- The patterns follow the ones of Combat Analysis (public domain), one set per client language.
--
-- An event has:
--   kind        "damage", "heal", "power", "benefit", "tempMorale", "interrupt", "dispel", "death", "revive"
--   source      who did it, target who received it (names without article)
--   skill       name of the skill (nil for a hit without skill)
--   amount      number (0 for an avoided or absorbed attack)
--   crit        "critical" or "devastating", nil for a normal hit
--   avoid       "miss", "deflect", "block", "parry", "evade", "resist", "immune": the attack did nothing
--   partial     "block", "parry", "evade": partly avoided, damage still dealt
--   damageType  "common", "fire"... (nil when unknown), damageTypeName the text of the game
--   pool        "morale" or "power"
--   noDamage    true for a hit that did no damage (it only put an effect, or was absorbed)
--   reflect     true for reflected damage or heal
--   fromEffect  true for a heal whose line starts with the effect, not with who cast it

Grommey = Grommey or {};
Grommey.Meter = Grommey.Meter or {};

local Parser = {};
Grommey.Meter.Parser = Parser;

local match = string.match;
local find = string.find;
local gsub = string.gsub;
local unpack = unpack or table.unpack;

-- "1,234" "1.234" "1 234" all give 1234
local function Number(text)
    return tonumber((gsub(text or "", "[^%d]", ""))) or 0;
end

local function Trim(text)
    return (match(text or "", "^%s*(.-)%s*$"));
end

local function Contains(text, word)
    return text ~= nil and find(text, word, 1, true) ~= nil;
end

-- Damage types as the game writes them (mounted combat adds "(...)" in front, removed before)
local DAMAGE_TYPES = {
    en = {
        ["Common"] = "common"; ["Fire"] = "fire"; ["Lightning"] = "lightning"; ["Frost"] = "frost";
        ["Acid"] = "acid"; ["Shadow"] = "shadow"; ["Light"] = "light"; ["Beleriand"] = "beleriand";
        ["Westernesse"] = "westernesse"; ["Ancient Dwarf-make"] = "dwarf"; ["Orc-craft"] = "orc";
        ["Fell-wrought"] = "fell";
    };
    fr = {
        ["Commun"] = "common"; ["Feu"] = "fire"; ["Foudre"] = "lightning"; ["Froid"] = "frost";
        ["Acide"] = "acid"; ["Ombre"] = "shadow"; ["Lumière"] = "light"; ["Légère"] = "light";
        ["Beleriand"] = "beleriand"; ["Ouistrenesse"] = "westernesse"; ["Nain d'antan"] = "dwarf";
        ["de nain d'antan"] = "dwarf"; ["Orque"] = "orc"; ["Maléfique"] = "fell";
    };
    de = {
        ["Allgemein"] = "common"; ["Feuer"] = "fire"; ["Blitz"] = "lightning"; ["Frost"] = "frost";
        ["Säure"] = "acid"; ["Schatten"] = "shadow"; ["Licht"] = "light"; ["Beleriand"] = "beleriand";
        ["Westernis"] = "westernesse"; ["Uralte Zwergenart"] = "dwarf"; ["Ork-Waffe"] = "orc";
        ["Hass"] = "fell";
    };
};

local POOLS = {
    en = { ["Morale"] = "morale"; ["Power"] = "power"; };
    fr = { ["Moral"] = "morale"; ["Puissance"] = "power"; };
    de = { ["Moral"] = "morale"; ["Kraft"] = "power"; };
};

local ARTICLES = {
    en = { "^[Tt]he " };
    fr = { "^[Ll]es ", "^[Ll]e ", "^[Ll]a ", "^[Ll]'%s*" };
    de = { "^[Dd]ie ", "^[Dd]er ", "^[Dd]em ", "^[Dd]en ", "^[Dd]as ", "^[Dd]es " };
};

-- Everything that depends on the language, filled for each one below
local rules = {};

local function Builder(language)
    local articles = ARTICLES[language];
    local damageTypes = DAMAGE_TYPES[language];
    local pools = POOLS[language];
    local tools = {};

    function tools.Name(name)
        name = Trim(name);
        for _, article in ipairs(articles) do
            local stripped, count = gsub(name, article, "", 1);
            if (count > 0) then return stripped; end
        end
        return name;
    end

    function tools.DamageType(event, text)
        text = Trim(gsub(Trim(text), "^%b()%s*", ""));
        text = gsub(text, '^"(.*)"$', "%1");
        event.damageTypeName = text;
        event.damageType = damageTypes[text];
    end

    function tools.Pool(text)
        text = Trim(text);
        return pools[text] or pools[match(text, "(%S+)$") or ""];
    end

    return tools;
end

-- Event made of the parts every line has
local function Event(kind, source, target, skill, amount)
    return { kind = kind; source = source; target = target; skill = skill; amount = amount or 0; };
end

------------------------------------------------------------------------------------------------
-- English

do
    local T = Builder("en");
    local Name = T.Name;

    local function Modifiers(event, text)
        event.partial = Contains(text, "partially blocked") and "block" or Contains(text, "partially parried") and "parry"
            or Contains(text, "partially evaded") and "evade" or nil;
        event.crit = Contains(text, "critical") and "critical" or Contains(text, "devastating") and "devastating" or nil;
    end

    local function Avoid(text)
        return Contains(text, "blocked") and "block" or Contains(text, "parried") and "parry"
            or Contains(text, "evaded") and "evade" or Contains(text, "resisted") and "resist"
            or Contains(text, "immune") and "immune" or "other";
    end

    rules.en = {
        -- Grommey scored a critical hit with Fiery Ridicule on the Boar for 1,234 Fire damage to Morale.
        { "^(.-) scored an? (.-)hit(.*) on (.+)%.$", function(you, source, modifiers, skillPart, rest)
            local event = Event("damage", Name(source));
            Modifiers(event, modifiers);
            event.skill = match(skillPart, "^ with (.+)$");
            local target, amount, damageType, pool = match(rest, "^(.+) for ([%d,%.]+) (.-)damage to (.+)$");
            if (target == nil) then
                event.target = Name(rest);
                event.noDamage = true;
                return event;
            end
            event.target = Name(target);
            event.amount = Number(amount);
            T.DamageType(event, damageType);
            event.pool = T.Pool(pool);
            return event;
        end };
        -- Grommey applied a critical heal with Words of Healing to Bob restoring 120 points to Morale.
        -- Fortifying Strike applied a heal to Grommey restoring 50 points to Morale.  (the effect comes first)
        { "^(.-) applied an? (.-)heal (.+)%.$", function(you, source, crit, rest)
            local skill, target, amount, pool = match(rest, "^with (.+) to (.+) restoring ([%d,%.]+) points? to (.+)$");
            local event;
            if (skill ~= nil) then
                event = Event("heal", Name(source), Name(target), skill, Number(amount));
            else
                target, amount, pool = match(rest, "^to (.+) restoring ([%d,%.]+) points? to (.+)$");
                if (target == nil) then return nil; end
                event = Event("heal", Name(target), Name(target), source, Number(amount));
                event.fromEffect = true;
            end
            event.pool = T.Pool(pool);
            if (event.pool == "power") then event.kind = "power"; end
            Modifiers(event, crit);
            return event;
        end };
        -- Bob tried to use Cleave on Grommey but he parried the attempt.
        { "^(.-) tried to use (.+) on (.+) but (.-) the attempt%.$", function(you, source, skill, target, avoid)
            local event = Event("damage", Name(source), Name(target), skill, 0);
            event.avoid = Avoid(avoid);
            return event;
        end };
        { "^(.-) missed trying to use (.+) on (.+)%.$", function(you, source, skill, target)
            local event = Event("damage", Name(source), Name(target), skill, 0);
            event.avoid = "miss";
            return event;
        end };
        { "^(.-) was deflected trying to use (.+) on (.+)%.$", function(you, source, skill, target)
            local event = Event("damage", Name(source), Name(target), skill, 0);
            event.avoid = "deflect";
            return event;
        end };
        { "^(.-) applied an? (.-)benefit with (.+) on (.+)%.$", function(you, source, crit, skill, target)
            return Event("benefit", Name(source), Name(target), skill);
        end };
        -- The Beorning reflected 1,106 Common damage to the Morale of the Goblin.
        -- The Leech reflected 339 points restored to the Morale of Bob.
        { "^(.-) reflected ([%d,%.]+) (.-) to the Morale of (.+)%.$", function(you, source, amount, what, target)
            local damageType = match(what, "^(.-)%s*damage$");
            local event = Event(damageType and "damage" or "heal", Name(source), Name(target), nil, Number(amount));
            event.reflect = true;
            event.pool = "morale";
            if (damageType ~= nil) then T.DamageType(event, damageType); end
            return event;
        end };
        { "^You have lost ([%d,%.]+) points? of temporary Morale!$", function(you, amount)
            return Event("tempMorale", nil, you, nil, Number(amount));
        end };
        { "^(.+) was interrupted by (.+)!$", function(you, target, source)
            return Event("interrupt", Name(source), Name(target));
        end };
        { "^You have dispelled (.+) from (.+)%.$", function(you, effect, target)
            return Event("dispel", you, Name(target), effect);
        end };
        { "^(.+) has been defeated%.$", function(you, target) return Event("death", nil, Name(target)); end };
        { "^Your mighty blow topples (.+)%.$", function(you, target) return Event("death", you, Name(target)); end };
        { "^You have been incapacitated by misadventure%.$", function(you) return Event("death", nil, you); end };
        { "^(.+) incapacitated you%.$", function(you, source) return Event("death", Name(source), you); end };
        { "^(.+) defeated (.+)%.$", function(you, source, target) return Event("death", Name(source), Name(target)); end };
        { "^(.+) died%.$", function(you, target) return Event("death", nil, Name(target)); end };
        { "^You have been revived%.$", function(you) return Event("revive", nil, you); end };
        { "^You succumb to your wounds%.$", function(you) return Event("revive", nil, you); end };
        { "^(.+) has been revived%.$", function(you, target) return Event("revive", nil, Name(target)); end };
        { "^(.+) has succumbed to .+ wounds%.$", function(you, target) return Event("revive", nil, Name(target)); end };
    };
end

------------------------------------------------------------------------------------------------
-- French

do
    local T = Builder("fr");
    local Name = T.Name;

    local function Modifiers(event, text)
        event.partial = Contains(text, "partiellement bloqué") and "block" or Contains(text, "partiellement paré") and "parry"
            or Contains(text, "partiellement esquivé") and "evade" or nil;
        event.crit = Contains(text, "critique") and "critical" or Contains(text, "dévastateur") and "devastating" or nil;
    end

    local function Avoid(text)
        return Contains(text, "bloqué") and "block" or Contains(text, "paré") and "parry"
            or Contains(text, "esquivé") and "evade" or Contains(text, "résisté") and "resist"
            or Contains(text, "immunisé") and "immune" or Contains(text, "dévié") and "deflect" or "other";
    end

    rules.fr = {
        -- Grommey a infligé un coup critique avec Raillerie cuisante sur le Sanglier pour 1,234 points de type Feu à l'entité Moral.
        { "^(.-) a infligé un coup(.*) sur (.+)%.$", function(you, source, middle, rest)
            local event = Event("damage", Name(source));
            local modifiers, skill = match(middle, "^(.-)avec (.+)$");
            event.skill = skill;
            Modifiers(event, modifiers or middle);
            local target, amount, damageType, pool = match(rest, "^(.+) pour ([%d,%.]+) points? de type (.-) à (.+)$");
            if (target == nil) then
                target, amount, pool = match(rest, "^(.+) pour ([%d,%.]+) points? à (.+)$");
            end
            if (target == nil) then
                event.target = Name(rest);
                event.noDamage = true;
                return event;
            end
            event.target = Name(target);
            event.amount = Number(amount);
            if (damageType ~= nil) then T.DamageType(event, damageType); end
            event.pool = T.Pool(pool);
            return event;
        end };
        -- Le Loup a marqué un coup avec Morsure invalidante sur le Grommey.  (no damage, only the effect)
        { "^(.-) a marqué un coup(.*) sur (.+)%.$", function(you, source, middle, target)
            local event = Event("damage", Name(source), Name(target), nil, 0);
            local modifiers, skill = match(middle, "^(.-)avec (.+)$");
            event.skill = skill;
            Modifiers(event, modifiers or middle);
            event.noDamage = true;
            return event;
        end };
        -- Bob a appliqué un soin critique avec Paroles de guérison Grommey, redonnant 120 points à l'entité Moral.
        -- Guérison d'Attaque fortifiante a appliqué un soin à Grommey, redonnant 50 points à l'entité Moral.
        { "^(.-) a appliqué un soin(.*)%.$", function(you, source, rest)
            local crit = match(rest, "^ (critique)") or match(rest, "^ (dévastateur)");
            rest = Trim(gsub(gsub(rest, "^ critique", ""), "^ dévastateur", ""));
            local event;
            local target, amount, pool = match(rest, "^à (.+), redonnant ([%d,%.]+) points? à (.+)$");
            if (target ~= nil) then
                event = Event("heal", Name(target), Name(target), source, Number(amount));
                event.fromEffect = true;
            else
                local skill;
                skill, target, amount, pool = match(rest, "^avec (.+) sur (.+), redonnant ([%d,%.]+) points? à (.+)$");
                if (skill == nil) then
                    skill, target, amount, pool = match(rest, "^avec (.+) (%S+), redonnant ([%d,%.]+) points? à (.+)$");
                end
                if (skill == nil) then return nil; end
                event = Event("heal", Name(source), Name(target), skill, Number(amount));
            end
            event.pool = T.Pool(pool);
            if (event.pool == "power") then event.kind = "power"; end
            Modifiers(event, crit);
            return event;
        end };
        -- Le Berserker a essayé d'utiliser une double attaque sur Grommey mais il a paré la tentative.
        { "^(.-) a essayé d'utiliser (.+) sur (.+) mais (.-) la tentative%.$", function(you, source, skill, target, avoid)
            local event = Event("damage", Name(source), Name(target), skill, 0);
            event.avoid = Avoid(avoid);
            return event;
        end };
        { "^(.-) n'a pas réussi à utiliser (.+) sur (.+)%.$", function(you, source, skill, target)
            local event = Event("damage", Name(source), Name(target), skill, 0);
            event.avoid = "miss";
            return event;
        end };
        -- Bob a appliqué un bénéfice avec Cri de ralliement Grommey.
        { "^(.-) a appliqué un bénéfice(.-) avec (.+)%.$", function(you, source, crit, rest)
            local skill, target = match(rest, "^(.+) sur (.+)$");
            if (skill == nil) then skill, target = match(rest, "^(.+) (%S+)$"); end
            if (skill == nil) then return nil; end
            return Event("benefit", Name(source), Name(target), skill);
        end };
        -- Le Beorning a renvoyé 1,106 Commun de dégâts au Moral de le Gobelin.
        -- La Sangsue a renvoyé 339 points redonnés au Moral de Bob.
        { "^(.-) a renvoyé ([%d,%.]+) (.-) au Moral de (.+)%.$", function(you, source, amount, what, target)
            local damageType = match(what, "^(.-)%s*de dégâts$");
            local event = Event(damageType and "damage" or "heal", Name(source), Name(target), nil, Number(amount));
            event.reflect = true;
            event.pool = "morale";
            if (damageType ~= nil) then T.DamageType(event, damageType); end
            return event;
        end };
        { "^Vous avez perdu ([%d,%.]+) points? de Moral temporaire%s*!$", function(you, amount)
            return Event("tempMorale", nil, you, nil, Number(amount));
        end };
        { "^(.+) a été interrompue? par (.+)%s*!$", function(you, target, source)
            return Event("interrupt", Name(source), Name(target));
        end };
        { "^Vous avez dissipé l'effet (.+) affectant (.+)%.$", function(you, effect, target)
            return Event("dispel", you, Name(target), effect);
        end };
        { "^Votre coup puissant a vaincu (.+)%.$", function(you, target) return Event("death", you, Name(target)); end };
        { "^Un incident vous a réduit à l'impuissance%.$", function(you) return Event("death", nil, you); end };
        { "^(.+) a réussi à vous mettre hors de combat%.$", function(you, source) return Event("death", Name(source), you); end };
        { "^(.+) a vaincu (.+)%.$", function(you, source, target) return Event("death", Name(source), Name(target)); end };
        { "^(.+) meurt%.$", function(you, target) return Event("death", nil, Name(target)); end };
        { "^(.+) a péri%.$", function(you, target) return Event("death", nil, Name(target)); end };
        { "^Vous revenez à la vie%.$", function(you) return Event("revive", nil, you); end };
        { "^Vous avez succombé à vos blessures%.$", function(you) return Event("revive", nil, you); end };
        { "^(.+) revient à la vie%.$", function(you, target) return Event("revive", nil, Name(target)); end };
        { "^(.+) a succombé à ses blessures%.$", function(you, target) return Event("revive", nil, Name(target)); end };
    };
end

------------------------------------------------------------------------------------------------
-- German

do
    local T = Builder("de");
    local Name = T.Name;

    local function Unquote(text)
        return (gsub(Trim(text), '"', ""));
    end

    local function Modifiers(event, text)
        event.partial = Contains(text, "teilweise geblockt") and "block" or Contains(text, "teilweise pariert") and "parry"
            or Contains(text, "teilweise ausgewichen") and "evade" or nil;
        event.crit = Contains(text, "kritisch") and "critical" or Contains(text, "zerstörerisch") and "devastating" or nil;
    end

    local function Avoid(text)
        return Contains(text, "Blocken") and "block" or Contains(text, "Parieren") and "parry"
            or Contains(text, "Ausweichen") and "evade" or Contains(text, "Widerstehen") and "resist"
            or Contains(text, "Immunität") and "immune" or "other";
    end

    local function Damage(event, rest)
        local target, amount, damageType, pool = match(rest, '^(.+) für ([%d,%.]+) Punkte Schaden des Typs "(.-)" auf (.+)$');
        if (target == nil) then
            event.target = Name(rest);
            event.noDamage = true;
            return event;
        end
        event.target = Name(target);
        event.amount = Number(amount);
        T.DamageType(event, damageType);
        event.pool = T.Pool(pool);
        return event;
    end

    rules.de = {
        -- Grommey gelang ein kritischer Treffer mit "Feuriger Spott" gegen den Eber für 1.234 Punkte Schaden des Typs "Feuer" auf Moral.
        { '^(.-) gelang ein (.-)Treffer mit "(.+)" gegen (.+)%.$', function(you, source, modifiers, skill, rest)
            local event = Event("damage", Name(source), nil, skill);
            Modifiers(event, modifiers);
            return Damage(event, rest);
        end };
        { "^(.-) gelang ein (.-)Treffer gegen (.+)%.$", function(you, source, modifiers, rest)
            local event = Event("damage", Name(source));
            Modifiers(event, modifiers);
            return Damage(event, rest);
        end };
        -- Bob wandte "kritische Heilung" mit "Worte der Heilung" auf Grommey an, was 120 Punkte Moral wiederherstellte.
        { '^(.-) wandte "(.-)Heilung" mit "(.+)" auf (.+) an, was ([%d,%.]+) Punkte (.+) wiederherstellte%.$', function(you, source, crit, skill, target, amount, pool)
            local event = Event("heal", Name(source), Name(target), skill, Number(amount));
            event.pool = T.Pool(pool);
            if (event.pool == "power") then event.kind = "power"; end
            Modifiers(event, crit);
            return event;
        end };
        -- Kräftigender Schlag verursacht bei Grommey "Heilung" und stellt 50 Punkte Moral wieder her.
        { '^(.+) verursacht bei (.+) "(.-)Heilung" und stellt ([%d,%.]+) Punkte (.+) wieder her%.$', function(you, skill, target, crit, amount, pool)
            local event = Event("heal", Name(target), Name(target), skill, Number(amount));
            event.fromEffect = true;
            event.pool = T.Pool(pool);
            if (event.pool == "power") then event.kind = "power"; end
            Modifiers(event, crit);
            return event;
        end };
        -- Der Berserker wollte Grommey mit "Spalten" treffen, aber er konterte den Versuch mit "Parieren".
        { "^(.-) wollte (.+) mit (.+) treffen, aber (.-) ?konterte den Versuch mit (.+)%.$", function(you, source, target, skill, who, avoid)
            local event = Event("damage", Name(source), Name(target), Unquote(skill), 0);
            event.avoid = Avoid(avoid);
            return event;
        end };
        { "^(.-) verfehlte (.+) mit (.+)%.$", function(you, source, target, skill)
            local event = Event("damage", Name(source), Name(target), Unquote(skill), 0);
            event.avoid = "miss";
            return event;
        end };
        { '^(.-) wandte "(.-)Vorteil" mit "(.+)" auf (.+) an%.$', function(you, source, crit, skill, target)
            return Event("benefit", Name(source), Name(target), skill);
        end };
        { "^(.-) reflektierte ([%d,%.]+) Punkte (.+) von (.+)%.$", function(you, source, amount, what, target)
            local damageType = match(what, '^Schaden des Typs (.-) auf Moral$');
            local event = Event(damageType and "damage" or "heal", Name(source), Name(target), nil, Number(amount));
            event.reflect = true;
            event.pool = "morale";
            if (damageType ~= nil) then T.DamageType(event, damageType); end
            return event;
        end };
        { "^Ihr habt ([%d,%.]+) Punkte Moral %(temporär%) verloren!$", function(you, amount)
            return Event("tempMorale", nil, you, nil, Number(amount));
        end };
        { "^(.+) wurde durch (.+) unterbr?ochen!$", function(you, target, source)
            return Event("interrupt", Name(source), Name(target));
        end };
        { "^Von (.+) geheilt: (.+)$", function(you, effect, target)
            return Event("dispel", you, Name(gsub(target, "%.$", "")), effect);
        end };
        { "^Ihr wurdet durch ein Missgeschick außer Gefecht gesetzt%.$", function(you) return Event("death", nil, you); end };
        { "^(.+) hat Euch außer Gefecht gesetzt%.$", function(you, source) return Event("death", Name(source), you); end };
        { "^Durch (.+) besiegt: (.+)%.$", function(you, source, target) return Event("death", Name(source), Name(target)); end };
        { "^(.+) ist gestorben%.$", function(you, target) return Event("death", nil, Name(target)); end };
        { "^(.+) wurde besiegt%.$", function(you, target) return Event("death", nil, Name(target)); end };
        { "^Ihr wurdet wiederbelebt%.$", function(you) return Event("revive", nil, you); end };
        { "^Ihr erliegt Euren Verletzungen%.$", function(you) return Event("revive", nil, you); end };
        { "^(.+) wurde wiederbelebt%.$", function(you, target) return Event("revive", nil, Name(target)); end };
        { "^(.+) ist .+ Wunden erlegen%.$", function(you, target) return Event("revive", nil, Name(target)); end };
    };
end

------------------------------------------------------------------------------------------------

-- Colours and other tags of the chat removed, spaces trimmed
function Parser.Clean(message)
    local line = gsub(message or "", "<rgb=#%x+>", "");
    line = gsub(line, "</rgb>", "");
    return Trim(line);
end

-- language: "en", "fr" or "de" (the language of the game client, not the one of GrommeyUI)
-- you: name of the player, used by the lines that say "you"
function Parser.Parse(line, language, you)
    local list = rules[language] or rules.en;
    for _, rule in ipairs(list) do
        local parts = { match(line, rule[1]) };
        if (parts[1] ~= nil) then
            local ok, event = pcall(rule[2], you, unpack(parts));
            if (ok and event ~= nil) then return event; end
            -- A line that looks like this rule but does not fit is not one of the next rules either
            return nil;
        end
    end
    return nil;
end

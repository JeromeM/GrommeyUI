-- Combat meter: a compact window about the player's fights, as the main window of Combat Analysis.
-- At the top a band of key figures for the view (total, per second, critical hits, avoided...),
-- under it one bar per skill of the player (or per target, attacker, healer...), and a summary view
-- whose lines are chosen in the options. Hovering a bar shows its counters at the bottom, a click
-- opens the detail window on it. Click the title to change the view, the fight name to pick a fight.
-- The window has a fixed size (width and number of bars in the options) and is placed with the move mode.

local UI = Grommey.UI;
local Theme = Grommey.Theme;
local Combats = Grommey.Meter.Combats;
local Log = Grommey.Meter.Log;
local Align = Turbine.UI.ContentAlignment;

local HEADER = 24;
local STRIP = 38;
local FOOTER = 18;
-- Seconds the window stays after a fight when it is shown in combat only
local AFTER_COMBAT = 10;

local Meter = Grommey.Meter;

-- Views of the window, in the order of the menu, each with its ways of grouping the bars
Meter.VIEWS = {
    { key = "summary"; name = "My summary"; groups = {}; };
    { key = "damage"; name = "Damage done"; groups = {
        { key = "skills"; name = "by skill"; }, { key = "targets"; name = "by target"; }, { key = "pets"; name = "pets"; } }; };
    { key = "taken"; name = "Damage taken"; groups = {
        { key = "skills"; name = "by skill"; }, { key = "attackers"; name = "by attacker"; } }; };
    { key = "enemies"; name = "Enemies"; groups = {}; };
    { key = "heal"; name = "Healing"; groups = {
        { key = "skills"; name = "by skill"; }, { key = "targets"; name = "by target"; }, { key = "healers"; name = "by healer"; } }; };
    { key = "power"; name = "Power restored"; groups = {
        { key = "skills"; name = "by skill"; }, { key = "sources"; name = "by source"; } }; };
};

local function View(key)
    for _, view in ipairs(Meter.VIEWS) do
        if (view.key == key) then return view; end
    end
    return Meter.VIEWS[1];
end

function Meter.ViewName(key)
    return L(View(key).name);
end

local FIGHTS_FILE = "GrommeyUI_Meter";
local RESET_IMAGE = "GrommeyUI/Meter/Resources/reset.tga";
local RESET_HOVER = "GrommeyUI/Meter/Resources/reset_hover.tga";

local settingsRoot = nil;
local window = nil;
local player = nil;
local combatCallback = nil;
local eventListener = nil;
local lastCombat = -1000;
local offset = 0;

local function PetsWithMe()
    return settingsRoot ~= nil and settingsRoot.pets ~= "apart";
end

-- An actor of a view; the player has the pets added when the options say so
function Meter.ActorFor(fight, mode, name)
    if (fight == nil) then return nil; end
    if (name == Log.PlayerName() and PetsWithMe()) then return Combats.MergedActor(fight, mode, name, true); end
    return fight.data[mode][name];
end

-- Grouping chosen for a view, the first one by default
local function GroupOf(viewKey, settings)
    local view = View(viewKey);
    local chosen = (settings or settingsRoot).groups[viewKey];
    for _, group in ipairs(view.groups) do
        if (group.key == chosen) then return group; end
    end
    return view.groups[1];
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Texts, shared with the detail window

function Meter.Short(value)
    if (value >= 1000000) then return string.format("%.2fM", value / 1000000); end
    if (value >= 10000) then return string.format("%.1fK", value / 1000); end
    return tostring(math.floor(value + 0.5));
end
local Short = Meter.Short;

function Meter.PerSecond(value)
    if (value >= 1000) then return Short(value); end
    return string.format("%.1f", value);
end
local PerSecond = Meter.PerSecond;

function Meter.Clock(seconds)
    seconds = math.floor(seconds);
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60);
end
local Clock = Meter.Clock;

function Meter.Percent(part, whole)
    if (whole == nil or whole <= 0) then return "0%"; end
    return math.floor(part * 100 / whole + 0.5) .. "%";
end
local Percent = Meter.Percent;

function Meter.SkillName(name)
    if (name == nil or name == "" or name == Combats.NO_SKILL) then return L("Without skill"); end
    -- A pet skill added to the player's: "Raven : Peck"
    local pet, skill = string.match(name, "^(.-)" .. "%" .. Combats.PET_SEPARATOR .. "(.*)$");
    if (pet ~= nil) then return pet .. " : " .. Meter.SkillName(skill); end
    if (name == Meter.Parser.AUTO_ATTACK) then return L("Auto-attack"); end
    if (name == Meter.Parser.AUTO_ATTACK_RANGED) then return L("Ranged auto-attack"); end
    return name;
end

function Meter.FightText(fight, which)
    if (fight == nil) then return L("No fight yet"); end
    if (fight.preview) then return L("Preview") .. " · " .. Clock(Combats.Duration(fight)); end
    local now = Turbine.Engine.GetGameTime();
    if (which == "overall") then return L("Overall") .. " · " .. Clock(Combats.Duration(fight, now)); end
    local name = Combats.Name(fight);
    if (name == "") then name = L("Fight"); end
    return name .. " · " .. Clock(Combats.Duration(fight, now));
end

local function LandedWithDamage(stats)
    return stats.normal.count + stats.crit.count + stats.devastating.count;
end

local function CritRate(stats)
    if (stats == nil) then return "-"; end
    return Percent(stats.crit.count + stats.devastating.count, LandedWithDamage(stats));
end

local function AvoidRate(stats)
    if (stats == nil) then return "-"; end
    return Percent(stats.avoided, stats.count);
end

-- Counters of a skill or target in one line, for the bottom of the window
local function StatsLine(stats)
    local parts = { string.format(L("%d hits"), stats.hits) };
    local landed = LandedWithDamage(stats);
    if (landed > 0) then
        table.insert(parts, L("crit") .. " " .. CritRate(stats));
        table.insert(parts, L("avg") .. " " .. Short(stats.total / landed));
        table.insert(parts, L("max") .. " " .. Short((Combats.Extremes(stats))));
    end
    if (stats.avoided > 0) then table.insert(parts, L("avoided") .. " " .. AvoidRate(stats)); end
    return table.concat(parts, " · ");
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Summary lines: each can be shown or not (options), a click opens the view in "view"

Meter.SUMMARY = {
    { key = "duration"; name = "Fight length"; value = function(s) return Clock(s.duration); end; };
    { key = "damage"; name = "Damage done"; view = "damage"; value = function(s)
        local total = s.damage and s.damage.total or 0;
        return Short(total) .. "  (" .. PerSecond(total / s.duration) .. "/s)";
    end; };
    { key = "petDamage"; name = "Pet damage"; view = "damage"; value = function(s)
        return Short(s.petDamage) .. "  (" .. PerSecond(s.petDamage / s.duration) .. "/s)";
    end; };
    { key = "crit"; name = "Critical hits"; view = "damage"; value = function(s)
        if (s.damage == nil) then return "-"; end
        local all = s.damage.all;
        local landed = LandedWithDamage(all);
        return Percent(all.crit.count + all.devastating.count, landed) .. "  (" .. L("dev.") .. " " .. Percent(all.devastating.count, landed) .. ")";
    end; };
    { key = "bestHit"; name = "Biggest hit"; view = "damage"; value = function(s)
        if (s.bestHit <= 0) then return "-"; end
        return Short(s.bestHit) .. "  " .. Meter.SkillName(s.bestSkill);
    end; };
    { key = "enemyAvoid"; name = "Your attacks avoided"; view = "damage"; value = function(s)
        if (s.damage == nil) then return "-"; end
        local all = s.damage.all;
        return Percent(all.avoided, all.count) .. "  (" .. all.avoided .. "/" .. all.count .. ")";
    end; };
    { key = "taken"; name = "Damage taken"; view = "taken"; value = function(s)
        return Short(s.taken.total) .. "  (" .. PerSecond(s.taken.total / s.duration) .. "/s)";
    end; };
    { key = "avoided"; name = "Attacks you avoided"; view = "taken"; value = function(s)
        return Percent(s.taken.avoided, s.taken.count) .. "  (" .. s.taken.avoided .. "/" .. s.taken.count .. ")";
    end; };
    { key = "partial"; name = "Attacks partly avoided"; view = "taken"; value = function(s)
        return Percent(s.taken.partialCount, s.taken.count) .. "  (" .. s.taken.partialCount .. ")";
    end; };
    { key = "takenCrit"; name = "Critical hits taken"; view = "taken"; value = function(s) return CritRate(s.taken); end; };
    { key = "healDone"; name = "Healing done"; view = "heal"; value = function(s)
        local total = s.healDone and s.healDone.total or 0;
        return Short(total) .. "  (" .. PerSecond(total / s.duration) .. "/s)";
    end; };
    { key = "healReceived"; name = "Healing received"; view = "heal"; value = function(s)
        return Short(s.healReceived) .. "  (" .. PerSecond(s.healReceived / s.duration) .. "/s)";
    end; };
    { key = "power"; name = "Power received"; view = "power"; value = function(s) return Short(s.powerReceived); end; };
    { key = "bubble"; name = "Temporary morale lost"; value = function(s) return Short(s.counters.bubble); end; };
    { key = "interrupts"; name = "Interrupts (done / taken)"; value = function(s)
        return s.counters.interruptsDone .. " / " .. s.counters.interruptsTaken;
    end; };
    { key = "dispels"; name = "Corruptions removed"; value = function(s) return tostring(s.counters.dispels); end; };
    { key = "kills"; name = "Killing blows"; value = function(s) return tostring(s.counters.kills); end; };
    { key = "deaths"; name = "Deaths"; value = function(s) return tostring(s.counters.deaths); end; };
};

------------------------------------------------------------------------------------------------------------------------------------------
-- What the window shows

local function Now()
    return Turbine.Engine.GetGameTime();
end

local function InCombat()
    return player ~= nil and player:IsInCombat() == true;
end

-- Key figures of a view: { { label, value }, ... }
local function KeyFigures(fight, viewKey, summary)
    if (summary == nil) then return {}; end
    local d = summary.duration;
    if (viewKey == "damage") then
        local total = summary.damage and summary.damage.total or 0;
        return {
            { L("Damage"), Short(total) }, { L("DPS"), PerSecond(total / d) },
            { L("Critical"), CritRate(summary.damage and summary.damage.all) }, { L("Avoided"), AvoidRate(summary.damage and summary.damage.all) },
        };
    elseif (viewKey == "taken") then
        return {
            { L("Taken"), Short(summary.taken.total) }, { L("Per second"), PerSecond(summary.taken.total / d) },
            { L("Avoided"), AvoidRate(summary.taken) }, { L("Critical"), CritRate(summary.taken) },
        };
    elseif (viewKey == "enemies") then
        local count = 0;
        for _ in pairs(fight.data.enemies) do count = count + 1; end
        local total = fight.totals.enemies;
        return {
            { L("Damage"), Short(total) }, { L("DPS"), PerSecond(total / d) },
            { L("Enemies"), tostring(count) }, { L("Killing blows"), tostring(summary.counters.kills) },
        };
    elseif (viewKey == "heal") then
        local total = summary.healDone and summary.healDone.total or 0;
        return {
            { L("Healing done"), Short(total) }, { L("HPS"), PerSecond(total / d) },
            { L("Received"), Short(summary.healReceived) }, { L("Critical"), CritRate(summary.healDone and summary.healDone.all) },
        };
    elseif (viewKey == "power") then
        return {
            { L("Received"), Short(summary.powerReceived) }, { L("Per second"), PerSecond(summary.powerReceived / d) },
            { L("Fight length"), Clock(d) },
        };
    end
    -- Summary view: the main numbers, the lines below give the rest
    local total = summary.damage and summary.damage.total or 0;
    return {
        { L("Damage"), Short(total) }, { L("DPS"), PerSecond(total / d) },
        { L("Taken"), Short(summary.taken.total) }, { L("Fight length"), Clock(d) },
    };
end

-- Bars of a view and grouping: { name, total, perSecond, percent, stats, open = { mode, actor, tab, key }, enemy }
local function BarEntries(fight, viewKey, groupKey, now)
    if (fight == nil) then return {}; end
    local you = Log.PlayerName();
    local entries;
    local function Mine(field)
        local actor = Meter.ActorFor(fight, viewKey, you);
        if (actor == nil) then return {}; end
        local list = Combats.Entries(fight, actor[field], actor.total, now);
        for _, entry in ipairs(list) do
            entry.open = { viewKey, you, field, entry.name };
            if (field == "skills") then entry.label = Meter.SkillName(entry.name); end
        end
        return list;
    end
    local function People(enemy)
        local list = Combats.Ranking(fight, viewKey, now);
        for _, entry in ipairs(list) do
            entry.open = { viewKey, entry.name, "skills", nil };
            entry.enemy = enemy;
        end
        return list;
    end

    if (groupKey == "pets") then
        -- The pets alone, each skill opening the detail of its pet
        local pets = Combats.MergedActor(fight, viewKey, you, false);
        if (pets == nil) then return {}; end
        entries = Combats.Entries(fight, pets.skills, pets.total, now);
        for _, entry in ipairs(entries) do
            local pet, skill = string.match(entry.name, "^(.-)" .. "%" .. Combats.PET_SEPARATOR .. "(.*)$");
            entry.label = Meter.SkillName(entry.name);
            entry.open = { viewKey, pet, "skills", skill };
        end
    elseif (viewKey == "enemies") then
        entries = People(true);
    elseif (viewKey == "taken" and groupKey == "skills") then
        entries = Combats.Entries(fight, Combats.MergedSkills(fight, "taken"), fight.totals.taken, now);
        for _, entry in ipairs(entries) do
            entry.label = Meter.SkillName(entry.name);
            entry.enemy = true;
            entry.open = { "taken", entry.stats.top, "skills", entry.name };
        end
    elseif (groupKey == "attackers") then
        entries = People(true);
    elseif (groupKey == "healers" or groupKey == "sources") then
        entries = People(false);
    else
        entries = Mine(groupKey);
        if (viewKey == "damage" and groupKey == "targets") then
            for _, entry in ipairs(entries) do entry.enemy = true; end
        end
    end
    return entries;
end

-- Summary lines the player chose
local function SummaryEntries(summary)
    local entries = {};
    if (summary == nil) then return entries; end
    for _, line in ipairs(Meter.SUMMARY) do
        if (settingsRoot.summary[line.key] ~= false) then
            local ok, value = pcall(line.value, summary);
            table.insert(entries, { line = true; label = L(line.name); value = ok and value or "-"; view = line.view; });
        end
    end
    return entries;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Window

function Meter.OutlinedLabel(parent, align)
    local label = Turbine.UI.Label();
    label:SetParent(parent);
    label:SetTextAlignment(align);
    label:SetMouseVisible(false);
    label:SetMultiline(false);
    label:SetFontStyle(Turbine.UI.FontStyle.Outline);
    label:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    return label;
end
local OutlinedLabel = Meter.OutlinedLabel;

local function Refresh() if (window) then window.Refresh(); end end

local function ShowMenu(owner, items, current, onPick)
    local screenX, screenY = UI.ScreenPosition(owner);
    UI.OpenMenu(owner, screenX, screenY + owner:GetHeight() + 2, 270, items, current, onPick);
end

-- The views and their groupings in one list: "Damage done - by skill"...
local function ViewItems()
    local items = {};
    for _, view in ipairs(Meter.VIEWS) do
        if (#view.groups == 0) then
            table.insert(items, { value = view.key; text = L(view.name); });
        else
            for _, group in ipairs(view.groups) do
                table.insert(items, { value = view.key .. ":" .. group.key; text = L(view.name) .. " - " .. L(group.name); });
            end
        end
    end
    return items;
end

local function CurrentViewItem(settings)
    local current = settings.mode;
    if (#View(current).groups > 0) then current = current .. ":" .. GroupOf(current, settings).key; end
    return current;
end

local function SetViewItem(settings, value)
    local viewKey, groupKey = string.match(value, "^([^:]+):?(.*)$");
    settings.mode = viewKey;
    if (groupKey ~= "") then settings.groups[viewKey] = groupKey; end
end

local function ViewMenu(owner)
    ShowMenu(owner, ViewItems(), CurrentViewItem(settingsRoot), function(value)
        SetViewItem(settingsRoot, value);
        offset = 0;
        Grommey.Profiles.RequestSave();
        Refresh();
    end);
end

local function FightMenu(owner)
    local items = {
        { value = "current"; text = L("Current fight"); },
        { value = "overall"; text = L("Overall"); },
    };
    for index, fight in ipairs(Combats.History()) do
        local name = Combats.Name(fight);
        table.insert(items, { value = index; text = "#" .. index .. "  " .. (name ~= "" and name or L("Fight")) .. "  " .. Clock(Combats.Duration(fight)); });
    end
    ShowMenu(owner, items, settingsRoot.fight, function(value)
        settingsRoot.fight = value;
        offset = 0;
        Grommey.Profiles.RequestSave();
        Refresh();
        if (Meter.Detail) then Meter.Detail.Refresh(); end
    end);
end

-- Colour of a bar: the player's class colour for the player's bars, red tones for enemies, theme colour otherwise
local function ClassMix()
    local UF = Grommey.UnitFrames;
    local color = UF and UF.ClassColorOf and UF.ClassColorOf(player);
    if (color == nil) then return nil; end
    -- Mixed into the panel colour like the other bars, so the text stays readable
    local ok, mixed = pcall(function()
        local panel = Theme.Color("panel");
        local amount = 0.75;
        return Turbine.UI.Color(1,
            panel.R + (color.R - panel.R) * amount,
            panel.G + (color.G - panel.G) * amount,
            panel.B + (color.B - panel.B) * amount);
    end);
    return ok and mixed or nil;
end

function Meter.BarColor(enemy, mine)
    if (enemy) then return Theme.Mix("panel", "danger", 0.55); end
    if (mine and settingsRoot and settingsRoot.classColor) then
        local mixed = ClassMix();
        if (mixed) then return mixed; end
    end
    return Theme.Mix("panel", "accent", 0.55);
end

local function WindowSize()
    local rows = settingsRoot.rows;
    local body = rows * settingsRoot.rowHeight + (rows - 1) * settingsRoot.rowSpacing;
    local strip = settingsRoot.showStrip and STRIP or 0;
    return settingsRoot.width, 1 + HEADER + strip + 2 + body + 2 + FOOTER + 1;
end

local function CreateWindow()
    local w = Turbine.UI.Window();
    w:SetVisible(false);
    local width, height = WindowSize();
    w:SetSize(width, height);
    local inner = width - 2;

    w.frame = UI.Frame(w, 0, 0, width, height, "background", "border");
    w.frame:SetMouseVisible(false);
    w.frame.inner:SetMouseVisible(false);

    -- Title bar: view on the left, fight on the right, close button
    w.header = Turbine.UI.Control();
    w.header:SetParent(w);
    w.header:SetPosition(1, 1);
    w.header:SetSize(inner, HEADER);
    w.accent = Turbine.UI.Control();
    w.accent:SetParent(w.header);
    w.accent:SetPosition(0, 0);
    w.accent:SetSize(inner, 2);
    w.accent:SetMouseVisible(false);

    local modeWidth = math.floor((inner - 30) * 0.45);
    w.modeLabel = UI.Label(w.header, 6, 2, modeWidth, HEADER - 2, "", { bold = true; role = "accent"; mouse = true; size = 13; });
    w.fightLabel = UI.Label(w.header, 6 + modeWidth, 2, inner - 50 - modeWidth - 6, HEADER - 2, "", { role = "dim"; mouse = true; size = 12; align = Align.MiddleRight; });
    w.closeLabel = UI.Label(w.header, inner - 22, 2, 20, HEADER - 2, "×", { size = 16; role = "dim"; mouse = true; align = Align.MiddleCenter; });
    w.closeLabel.MouseEnter = function() w.closeLabel:SetForeColor(Theme.Color("danger")); end
    w.closeLabel.MouseLeave = function() w.closeLabel:SetForeColor(Theme.Color("dim")); end
    w.closeLabel.MouseClick = function()
        settingsRoot.shown = false;
        Grommey.Profiles.RequestSave();
        w.UpdateVisibility();
        Grommey.Print(L("Combat meter hidden. Type /gui meter to show it again."));
    end
    -- Reset icon left of the close button, in two clicks: the second one within a few seconds
    w.resetIcon = Turbine.UI.Control();
    w.resetIcon:SetParent(w.header);
    w.resetIcon:SetSize(16, 16);
    w.resetIcon:SetPosition(inner - 42, math.floor((HEADER - 16) / 2) + 1);
    w.resetIcon:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend);
    local function ResetImage(hover) w.resetIcon:SetBackground(hover and RESET_HOVER or RESET_IMAGE); end
    ResetImage(false);
    local function Disarm()
        w.resetArmed = false;
        ResetImage(false);
        w.hoverText = nil;
        w.Refresh();
    end
    w.resetIcon.MouseEnter = function() ResetImage(true); end
    w.resetIcon.MouseLeave = function() if (not w.resetArmed) then ResetImage(false); end end
    w.resetIcon.MouseClick = function()
        if (w.resetArmed) then
            Combats.Reset();
            settingsRoot.fight = "current";
            Grommey.Profiles.RequestSave();
            Disarm();
            if (Meter.Detail) then Meter.Detail.Refresh(); end
            return;
        end
        w.resetArmed = true;
        w.hoverText = L("Click again to erase every fight");
        w.footer:SetText(w.hoverText);
        Grommey.Delay("MeterReset", 3, function()
            if (window == w and w.resetArmed) then Disarm(); end
        end);
    end

    -- The window itself does not move: it is placed with the move mode, like the other frames
    w.modeLabel.MouseClick = function() ViewMenu(w.modeLabel); end
    w.fightLabel.MouseClick = function() FightMenu(w.fightLabel); end

    -- Key figures: up to four tiles, a small name over a big value
    local top = 1 + HEADER;
    w.tiles = {};
    if (settingsRoot.showStrip) then
        w.strip = Turbine.UI.Control();
        w.strip:SetParent(w);
        w.strip:SetPosition(1, top);
        w.strip:SetSize(inner, STRIP);
        w.strip:SetMouseVisible(false);
        local tileWidth = math.floor(inner / 4);
        for index = 1, 4 do
            local x = (index - 1) * tileWidth;
            local tile = {};
            tile.name = UI.Label(w.strip, x + 2, 3, tileWidth - 4, 14, "", { size = 10; role = "dim"; align = Align.MiddleCenter; });
            tile.value = UI.Label(w.strip, x + 2, 17, tileWidth - 4, 19, "", { size = 15; align = Align.MiddleCenter; });
            w.tiles[index] = tile;
        end
        top = top + STRIP;
    end

    -- Bars
    w.body = Turbine.UI.Control();
    w.body:SetParent(w);
    w.body:SetPosition(1, top + 2);
    w.body:SetSize(inner, height - top - FOOTER - 5);
    local function Scroll(sender, args)
        offset = math.max(0, offset - (args.Direction or 0));
        w.Refresh();
    end
    w.body.MouseWheel = Scroll;

    w.footer = UI.Label(w, 6, height - FOOTER - 1, width - 12, FOOTER, "", { size = 11; role = "dim"; });
    w.hoverText = nil;

    w.rows = {};
    local rowHeight = settingsRoot.rowHeight;
    local step = rowHeight + settingsRoot.rowSpacing;
    local font = Theme.Font(settingsRoot.fontSize, false);
    local rightWidth = math.floor(inner * 0.5);
    for index = 1, settingsRoot.rows do
        local row = Turbine.UI.Control();
        row:SetParent(w.body);
        row:SetPosition(0, (index - 1) * step);
        row:SetSize(inner, rowHeight);
        row.fill = Turbine.UI.Control();
        row.fill:SetParent(row);
        row.fill:SetMouseVisible(false);
        row.fill:SetHeight(rowHeight);
        row.left = OutlinedLabel(row, Align.MiddleLeft);
        row.left:SetPosition(4, 0);
        row.left:SetSize(inner - rightWidth - 8, rowHeight);
        row.left:SetFont(font);
        row.right = OutlinedLabel(row, Align.MiddleRight);
        row.right:SetPosition(inner - rightWidth - 4, 0);
        row.right:SetSize(rightWidth, rowHeight);
        row.right:SetFont(font);
        row.MouseWheel = Scroll;
        row.MouseClick = function()
            local entry = row.entry;
            if (entry == nil) then return; end
            if (entry.line) then
                -- A summary line opens its view
                if (entry.view == nil) then return; end
                settingsRoot.mode = entry.view;
                offset = 0;
                Grommey.Profiles.RequestSave();
                w.Refresh();
            elseif (entry.open ~= nil and Meter.Detail) then
                Meter.Detail.Open(entry.open[1], entry.open[2], entry.open[3], entry.open[4]);
            end
        end
        row.MouseEnter = function()
            if (row.entry == nil or row.entry.stats == nil) then return; end
            w.hoverText = StatsLine(row.entry.stats);
            w.footer:SetText(w.hoverText);
        end
        row.MouseLeave = function()
            w.hoverText = nil;
            w.Refresh();
        end
        w.rows[index] = row;
    end

    function w.Refresh()
        local now = Now();
        local which = settingsRoot.fight;
        local fight = Meter.DisplayedFight();
        local viewKey = settingsRoot.mode;
        local group = GroupOf(viewKey);
        w.modeLabel:SetText(Meter.ViewName(viewKey));
        w.fightLabel:SetText(Meter.FightText(fight, which));
        local summary = Combats.Summary(fight, Log.PlayerName(), now, PetsWithMe());

        -- Key figures
        local figures = KeyFigures(fight, viewKey, summary);
        for index, tile in ipairs(w.tiles) do
            local figure = figures[index];
            tile.name:SetText(figure and figure[1] or "");
            tile.value:SetText(figure and figure[2] or "");
        end

        -- Bars or summary lines
        local summaryView = (viewKey == "summary");
        local entries = summaryView and SummaryEntries(summary) or BarEntries(fight, viewKey, group and group.key, now);
        offset = math.max(0, math.min(offset, #entries - #w.rows));
        local best = (not summaryView and entries[1] and entries[1].total) or 0;
        local mine = (group ~= nil and (group.key == "skills" or group.key == "targets") and viewKey ~= "taken");
        for index, row in ipairs(w.rows) do
            local entry = entries[index + offset];
            row.entry = entry;
            if (entry == nil) then
                row:SetVisible(false);
            elseif (summaryView) then
                row:SetVisible(true);
                row.fill:SetWidth(0);
                row.left:SetForeColor(Theme.Color("dim"));
                row.left:SetText(entry.label);
                row.right:SetText(entry.value);
            else
                row:SetVisible(true);
                local ratio = (best > 0) and (entry.total / best) or 0;
                row.fill:SetWidth(math.floor(inner * ratio + 0.5));
                row.fill:SetBackColor(Meter.BarColor(entry.enemy, mine or entry.name == Log.PlayerName()));
                row.left:SetForeColor(Theme.Color("text"));
                row.left:SetText((settingsRoot.rank and ((index + offset) .. ". ") or "") .. (entry.label or entry.name));
                local parts = {};
                if (settingsRoot.showHits and entry.stats) then table.insert(parts, entry.stats.hits .. "x"); end
                if (settingsRoot.showPerSecond) then table.insert(parts, PerSecond(entry.perSecond)); end
                if (settingsRoot.showPercent) then table.insert(parts, math.floor(entry.percent + 0.5) .. "%"); end
                local text = Short(entry.total);
                if (#parts > 0) then text = text .. " (" .. table.concat(parts, ", ") .. ")"; end
                row.right:SetText(text);
            end
        end

        if (w.hoverText == nil) then
            if (fight == nil) then
                w.footer:SetText(L("Waiting for the first fight"));
            elseif (summaryView) then
                w.footer:SetText(L("Click a line for more"));
            else
                local text = group and (L(group.name) .. "  ·  ") or "";
                w.footer:SetText(text .. L("hover: counters, click: detail"));
            end
        end
        w.drawnVersion = Combats.version;
        w.drawnAt = now;
    end

    function w.UpdateVisibility()
        local shown = settingsRoot.shown and not Grommey.HudHidden;
        if (shown and settingsRoot.show == "combat") then
            shown = InCombat() or Combats.Current() ~= nil or (Now() - lastCombat < AFTER_COMBAT);
        end
        if (Grommey.Movers.IsActive()) then shown = true; end
        if (shown ~= w:IsVisible()) then
            w:SetVisible(shown);
            if (shown) then w.Refresh(); end
        end
    end

    Theme.Track(function()
        -- A window built again leaves this one behind, it no longer needs painting
        if (window ~= nil and window ~= w) then return; end
        w.header:SetBackColor(Theme.Color("panel"));
        w.accent:SetBackColor(Theme.Color("accent"));
        if (w.strip) then w.strip:SetBackColor(Theme.Color("panel")); end
        for _, row in ipairs(w.rows or {}) do
            row:SetBackColor(Theme.Color("field"));
            row.right:SetForeColor(Theme.Color("text"));
        end
        if (w.drawnVersion ~= nil) then w.Refresh(); end
    end);

    -- Redrawn when something changed, every second while a fight goes on
    local nextTick = 0;
    w:SetWantsUpdates(true);
    w.Update = function()
        local now = Now();
        if (now < nextTick) then return; end
        nextTick = now + 0.25;
        local inCombat = InCombat();
        if (inCombat) then lastCombat = now; end
        Combats.Tick(now, inCombat);
        w.UpdateVisibility();
        if (Meter.Detail) then Meter.Detail.Tick(now); end
        if (not w:IsVisible() or w.hoverText ~= nil) then return; end
        if (w.drawnVersion ~= Combats.version or (Combats.Current() ~= nil and now - (w.drawnAt or 0) >= 1)) then
            w.Refresh();
        end
    end

    w.Refresh();
    return w;
end

local function DefaultX()
    return Turbine.UI.Display.GetWidth() - settingsRoot.width - 20;
end

local function DefaultY()
    local _, height = WindowSize();
    return Turbine.UI.Display.GetHeight() - height - 240;
end

local function Build()
    if (window ~= nil) then
        Grommey.Movers.Unregister("meter");
        window:SetWantsUpdates(false);
        window:SetVisible(false);
        window = nil;
    end
    window = CreateWindow();
    -- A global keeps the window alive
    Meter.Window = window;
    Grommey.Movers.Register("meter", window, L("Combat meter"), DefaultX, DefaultY);
    window.UpdateVisibility();
end

function Meter.Command(arguments)
    if (settingsRoot == nil) then
        Grommey.Print(L("The combat meter module is off. Turn it on in the options, Modules page."));
        return;
    end
    local option = string.lower(string.match(arguments or "", "^%s*%S+%s+(%S+)") or "");
    if (option == "reset") then
        Combats.Reset();
        Refresh();
        return;
    end
    settingsRoot.shown = not settingsRoot.shown;
    Grommey.Profiles.RequestSave();
    if (window) then window.UpdateVisibility(); end
end

local function SaveFights()
    Grommey.Storage.Save(Turbine.DataScope.Character, FIGHTS_FILE, Combats.Export());
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Preview: a made up fight to set the windows up without fighting (button in the options, and in move mode)

local preview = false;
local previewBeforeMove = false;
local previewFight = nil;

local function SampleFight()
    local you = Log.PlayerName() or player:GetName();
    local fight = Combats.NewFight(0);
    fight.last = 84;
    fight.preview = true;
    -- Always the same numbers: a small random generator with a fixed start
    local seed = 7;
    local function Random(count)
        -- Park-Miller: stays inside the exact range of Lua numbers
        seed = (seed * 16807) % 2147483647;
        return seed % count;
    end
    local function Event(base, avoidChance, damageType)
        local roll = Random(100);
        if (roll < avoidChance) then
            local avoids = { "parry", "evade", "block", "miss" };
            return { amount = 0; avoid = avoids[Random(4) + 1]; };
        end
        local event = { amount = 0; damageType = damageType; };
        local factor = 0.8 + Random(40) / 100;
        if (roll >= 97) then event.crit = "devastating"; factor = factor * 2;
        elseif (roll >= 82) then event.crit = "critical"; factor = factor * 1.5; end
        if (roll >= avoidChance and roll < avoidChance + 5) then event.partial = "parry"; factor = factor * 0.5; end
        event.amount = math.floor(base * factor);
        return event;
    end

    local orc, warg = L("Orc warrior"), L("Warg");
    local mySkills = {
        { Meter.Parser.AUTO_ATTACK, 110, 40, "common" }, { L("Heavy Strike"), 460, 9, "common" },
        { L("Quick Strike"), 250, 14, "common" }, { L("Bleeding Wound"), 85, 20, "common" }, { L("Fire Blast"), 380, 6, "fire" },
    };
    for _, skill in ipairs(mySkills) do
        for index = 1, skill[3] do
            local target = (index % 3 == 0) and warg or orc;
            local event = Event(skill[2], 7, skill[4]);
            Combats.RecordInto(fight, "damage", you, skill[1], target, event);
            Combats.RecordInto(fight, "enemies", target, skill[1], you, event);
        end
    end
    -- A pet, so its lines can be seen without having one
    local pet = L("Raven");
    fight.pets[pet] = true;
    for _, skill in ipairs({ { Meter.Parser.AUTO_ATTACK, 55, 30 }, { L("Peck"), 140, 8 } }) do
        for index = 1, skill[3] do
            local target = (index % 2 == 0) and warg or orc;
            local event = Event(skill[2], 10, "common");
            Combats.RecordInto(fight, "damage", pet, skill[1], target, event);
            Combats.RecordInto(fight, "enemies", target, skill[1], pet, event);
        end
    end
    for index = 1, 6 do Combats.RecordInto(fight, "taken", warg, Meter.Parser.AUTO_ATTACK, pet, Event(40, 15, "common")); end

    local theirSkills = {
        { orc, Meter.Parser.AUTO_ATTACK, 60, 25 }, { orc, L("Cleave"), 150, 5 },
        { warg, Meter.Parser.AUTO_ATTACK, 40, 15 }, { warg, L("Bite"), 70, 6 },
    };
    for _, skill in ipairs(theirSkills) do
        for index = 1, skill[4] do
            Combats.RecordInto(fight, "taken", skill[1], skill[2], you, Event(skill[3], 15, "common"));
        end
    end
    for index = 1, 3 do Combats.RecordInto(fight, "heal", you, L("Second Wind"), you, Event(400, 0)); end
    for index = 1, 4 do Combats.RecordInto(fight, "heal", "Elendil", L("Healing Words"), you, Event(300, 0)); end
    for index = 1, 10 do Combats.RecordInto(fight, "power", you, L("Power Surge"), you, Event(12, 0)); end
    fight.counters.kills = 2;
    fight.counters.interruptsDone = 1;
    fight.counters.bubble = 350;
    fight.counters.bubbleHits = 2;
    return fight;
end

local function SetPreview(enabled)
    preview = enabled;
    previewFight = enabled and SampleFight() or nil;
    Refresh();
    if (Meter.Detail) then Meter.Detail.Refresh(); end
end

-- The fight both windows show: the preview, or the one chosen in the fight menu
function Meter.DisplayedFight()
    if (preview and previewFight) then return previewFight; end
    if (settingsRoot == nil) then return Combats.Get("current"); end
    local fight = Combats.Get(settingsRoot.fight);
    if (fight == nil and type(settingsRoot.fight) == "number") then
        -- That fight is no longer kept
        settingsRoot.fight = "current";
        fight = Combats.Get("current");
    end
    return fight;
end

-- Fight shown in the main window, for the detail window
function Meter.SelectedFight()
    return settingsRoot and settingsRoot.fight or "current";
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Options

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

local SHOW_ITEMS = {
    { value = "always"; text = "Always"; },
    { value = "combat"; text = "In combat (and a few seconds after)"; },
};

local PET_ITEMS = {
    { value = "with"; text = "Added to my damage"; },
    { value = "apart"; text = "Apart (view Damage done - pets)"; },
};

local optionsTab = "window";

local function BuildOptions(page, width, settings)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    local function Reopen() Grommey.Options.ShowPage("module:Meter"); end
    local function Changed() Grommey.Profiles.RequestSave(); Combats.SetHistorySize(settings.history); Build(); end

    UI.Header(page, 0, 16, width, L("Combat meter"));
    -- A made up fight to set everything up without fighting
    UI.Button(page, width - 200, 12, 200, preview and L("Preview: on") or L("Preview: off"), function()
        SetPreview(not preview);
        Reopen();
    end, preview and "accent" or nil);
    local x = 0;
    for _, tab in ipairs({ { key = "window"; text = L("Window"); }, { key = "summary"; text = L("My summary"); } }) do
        UI.Button(page, x, 52, 150, tab.text, function() optionsTab = tab.key; Reopen(); end, (optionsTab == tab.key) and "accent" or nil);
        x = x + 158;
    end

    local y = 100;
    if (optionsTab == "summary") then
        UI.Label(page, 0, y, width, 20, L("Lines of the summary view:"), { role = "dim"; size = 12; });
        y = y + 28;
        for index, line in ipairs(Meter.SUMMARY) do
            local column = (index - 1) % 2;
            UI.Toggle(page, column == 0 and 0 or right, y, half, L(line.name), settings.summary[line.key] ~= false, function(value)
                settings.summary[line.key] = value;
                Grommey.Profiles.RequestSave();
                Refresh();
            end);
            if (column == 1) then y = y + 30; end
        end
        return;
    end

    UI.Label(page, 0, y, half, 18, L("Show the window"));
    UI.Dropdown(page, 0, y + 20, half, Translated(SHOW_ITEMS), settings.show, function(value) settings.show = value; Changed(); end);
    UI.Label(page, right, y, half, 18, L("Pets"));
    UI.Dropdown(page, right, y + 20, half, Translated(PET_ITEMS), settings.pets, function(value) settings.pets = value; Changed(); end);
    y = y + 60;

    UI.Toggle(page, 0, y, half, L("Key figures at the top"), settings.showStrip, function(value) settings.showStrip = value; Changed(); end);
    UI.Toggle(page, right, y, half, L("Number of hits"), settings.showHits, function(value) settings.showHits = value; Changed(); end);
    y = y + 28;
    UI.Toggle(page, 0, y, half, L("Per second"), settings.showPerSecond, function(value) settings.showPerSecond = value; Changed(); end);
    UI.Toggle(page, right, y, half, L("Percentage"), settings.showPercent, function(value) settings.showPercent = value; Changed(); end);
    y = y + 28;
    UI.Toggle(page, 0, y, half, L("Rank numbers"), settings.rank, function(value) settings.rank = value; Changed(); end);
    UI.Toggle(page, right, y, half, L("Class colour for my bars"), settings.classColor, function(value) settings.classColor = value; Changed(); end);
    y = y + 38;

    UI.Slider(page, 0, y, half, L("Width"), 180, 500, 10, settings.width, function(value) settings.width = value; Changed(); end, " px");
    UI.Slider(page, right, y, half, L("Number of bars"), 3, 20, 1, settings.rows, function(value) settings.rows = value; Changed(); end);
    y = y + 48;
    UI.Slider(page, 0, y, half, L("Bar height"), 12, 32, 1, settings.rowHeight, function(value) settings.rowHeight = value; Changed(); end, " px");
    UI.Slider(page, right, y, half, L("Space between bars"), 0, 6, 1, settings.rowSpacing, function(value) settings.rowSpacing = value; Changed(); end, " px");
    y = y + 48;
    UI.Slider(page, 0, y, half, L("Text size"), 10, 18, 1, settings.fontSize, function(value) settings.fontSize = value; Changed(); end, " px");
    UI.Slider(page, right, y, half, L("Fights kept"), 3, 30, 1, settings.history, function(value) settings.history = value; Changed(); end);
    y = y + 52;

    UI.Button(page, 0, y, half, settings.shown and L("Hide the window") or L("Show the window"), function()
        settings.shown = not settings.shown;
        Changed();
        Reopen();
    end);
    UI.Button(page, right, y, half, L("Reset the data"), function() Combats.Reset(); Refresh(); end, "danger");
    y = y + 34;
    UI.Note(page, 0, y, width,
        L("Click the title of the window to change the view, the fight name to pick a fight, a bar for its full detail. The game only writes in the combat log what concerns you: the meter cannot show the damage of the other players."));
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Module

local summaryDefaults = {};
for _, line in ipairs(Meter.SUMMARY) do summaryDefaults[line.key] = true; end

Grommey.Modules.Register({
    id = "Meter";
    name = "Combat meter";
    description = "Damage, healing and damage taken by fight, in the style of Details.";
    enabledByDefault = true;
    defaults = {
        shown = true;
        show = "always";
        mode = "damage";
        groups = {};
        pets = "with";
        fight = "current";
        width = 300;
        rows = 8;
        rowHeight = 18;
        rowSpacing = 1;
        fontSize = 12;
        history = 10;
        showStrip = true;
        showHits = false;
        showPerSecond = true;
        showPercent = true;
        rank = false;
        classColor = true;
        summary = summaryDefaults;
    };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();
        Combats.SetHistorySize(settings.history);
        -- The fights of the character come back after a reload
        Combats.Import(Grommey.Storage.Load(Turbine.DataScope.Character, FIGHTS_FILE));
        Combats.SaveRequested = function() Grommey.Delay("MeterSave", 3, SaveFights); end
        Log.Use("meter", true);
        eventListener = Grommey.On("CombatEvent", function(event) Combats.Add(event, event.time); end);
        combatCallback = Grommey.AddCallback(player, "InCombatChanged", function()
            if (player:IsInCombat()) then Combats.StartFight(Now()); end
        end);
        Build();
        if (Meter.Detail) then Meter.Detail.Create(); end

        Grommey.On("MoveModeChanged", function(active)
            if (settingsRoot == nil) then return; end
            -- The made up fight in move mode, so the window has its real size and content
            if (active) then
                previewBeforeMove = preview;
                SetPreview(true);
            else
                SetPreview(previewBeforeMove == true);
            end
            if (window) then window.UpdateVisibility(); end
        end);
        Grommey.On("HudToggled", function() if (window) then window.UpdateVisibility(); end end);
        Grommey.On("ProfileChanged", function() if (settingsRoot) then Build(); end end);
    end;

    Disable = function()
        -- A fight going on is kept as it is
        Combats.SaveRequested = nil;
        Combats.EndFight();
        SaveFights();
        if (eventListener) then Grommey.Off("CombatEvent", eventListener); eventListener = nil; end
        if (combatCallback) then Grommey.RemoveCallback(player, "InCombatChanged", combatCallback); combatCallback = nil; end
        Log.Use("meter", false);
        if (window) then
            Grommey.Movers.Unregister("meter");
            window:SetWantsUpdates(false);
            window:SetVisible(false);
            window = nil;
            Meter.Window = nil;
        end
        if (Meter.Detail) then Meter.Detail.Destroy(); end
        settingsRoot = nil;
    end;

    BuildOptions = BuildOptions;

    SetupOptions = function(page, width, settings)
        UI.Label(page, 0, 0, width, 18, L("Show the window"));
        UI.Dropdown(page, 0, 20, math.min(width, 300), Translated(SHOW_ITEMS), settings.show, function(value) settings.show = value; end);
        UI.Label(page, 0, 62, width, 18, L("View shown"));
        UI.Dropdown(page, 0, 82, math.min(width, 300), ViewItems(), CurrentViewItem(settings), function(value) SetViewItem(settings, value); end);
        UI.Toggle(page, 0, 124, width, L("Key figures at the top"), settings.showStrip, function(value) settings.showStrip = value; end);
        UI.Toggle(page, 0, 158, width, L("Class colour for my bars"), settings.classColor, function(value) settings.classColor = value; end);
        UI.Note(page, 0, 196, width, L("A window with your damage, healing and damage taken for each fight, and a summary of your character. Place it with the move mode."));
    end;
});

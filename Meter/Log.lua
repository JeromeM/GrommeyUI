-- Combat log engine: listens to the combat chat, reads each line with the parser and sends the
-- events with Grommey.Fire("CombatEvent", event). It only listens while something uses it:
-- Grommey.Meter.Log.Use(key, true) / Use(key, false).
--
-- On top of the parser fields, every event gets:
--   time      Turbine.Engine.GetGameTime() when the line arrived
--   channel   "player", "enemy" or "death" (the combat chat it came from)
--   byYou     the player did it, onYou   it was done to the player
--
-- /gui combatlog shows every line read in the chat and keeps them in a file (to check the patterns),
-- /gui combatlog stats tells how many lines were read.

local Parser = Grommey.Meter.Parser;

local Log = {};
Grommey.Meter.Log = Log;

local CAPTURE_FILE = "GrommeyUI_CombatCapture";
local CAPTURE_MAX = 2000;

local users = {};
local handler = nil;
local playerName = nil;
local debugOn = false;
local capture = nil;

Log.stats = { lines = 0; read = 0; unknown = 0; };

local function Channels()
    local channels = {};
    local types = Turbine.ChatType or {};
    if (types.PlayerCombat ~= nil) then channels[types.PlayerCombat] = "player"; end
    if (types.EnemyCombat ~= nil) then channels[types.EnemyCombat] = "enemy"; end
    if (types.Death ~= nil) then channels[types.Death] = "death"; end
    return channels;
end

local channels = Channels();

local KIND_SHORT = {
    damage = "dmg"; heal = "heal"; power = "pow"; benefit = "buff"; tempMorale = "bubble";
    interrupt = "int"; dispel = "disp"; death = "dead"; revive = "rez";
};

-- One line of text for an event, for the debug output and the capture
function Log.Describe(event)
    local parts = { KIND_SHORT[event.kind] or event.kind, tostring(event.source or "-") .. " > " .. tostring(event.target or "-") };
    if (event.amount ~= nil and event.amount > 0) then table.insert(parts, tostring(event.amount)); end
    if (event.damageType ~= nil or event.damageTypeName ~= nil) then table.insert(parts, tostring(event.damageType or ("?" .. event.damageTypeName))); end
    if (event.pool == "power" and event.kind == "damage") then table.insert(parts, "power"); end
    if (event.skill ~= nil) then table.insert(parts, "[" .. event.skill .. "]"); end
    if (event.crit ~= nil) then table.insert(parts, event.crit); end
    if (event.avoid ~= nil) then table.insert(parts, "avoid:" .. event.avoid); end
    if (event.partial ~= nil) then table.insert(parts, "partial:" .. event.partial); end
    if (event.noDamage) then table.insert(parts, "no damage"); end
    if (event.reflect) then table.insert(parts, "reflect"); end
    if (event.fromEffect) then table.insert(parts, "effect"); end
    return table.concat(parts, " ");
end

local function SaveCapture()
    if (capture == nil) then return; end
    Grommey.Storage.Save(Turbine.DataScope.Account, CAPTURE_FILE, capture);
end

local function Capture(channel, line, event)
    if (capture == nil or #capture.lines >= CAPTURE_MAX) then return; end
    table.insert(capture.lines, channel .. " | " .. line .. " | " .. (event and Log.Describe(event) or "?"));
    -- Saved a few seconds after the last line, not on every one
    Grommey.Delay("MeterCapture", 5, SaveCapture);
end

local function OnChat(sender, args)
    local channel = channels[args.ChatType];
    if (channel == nil) then return; end

    local line = Parser.Clean(args.Message);
    if (line == "") then return; end
    Log.stats.lines = Log.stats.lines + 1;

    local event = Parser.Parse(line, Grommey.GameLanguage, playerName);
    if (debugOn) then
        Capture(channel, line, event);
        if (event ~= nil) then
            Grommey.Print("<rgb=#A0A0A0>" .. Log.Describe(event) .. "</rgb>");
        else
            Grommey.Print("<rgb=#FFA040>? " .. line .. "</rgb>");
        end
    end
    if (event == nil) then
        Log.stats.unknown = Log.stats.unknown + 1;
        return;
    end
    Log.stats.read = Log.stats.read + 1;

    event.time = Turbine.Engine.GetGameTime();
    event.channel = channel;
    event.byYou = (event.source == playerName);
    event.onYou = (event.target == playerName);
    Grommey.Fire("CombatEvent", event);
end

local function Listening()
    return next(users) ~= nil;
end

local function Refresh()
    if (Listening() and handler == nil) then
        playerName = Turbine.Gameplay.LocalPlayer.GetInstance():GetName();
        handler = Grommey.AddCallback(Turbine.Chat, "Received", OnChat);
    elseif (not Listening() and handler ~= nil) then
        Grommey.RemoveCallback(Turbine.Chat, "Received", handler);
        handler = nil;
    end
end

-- key: who needs the log ("debug", the meter...), on: true or false
function Log.Use(key, on)
    users[key] = on and true or nil;
    Refresh();
end

function Log.PlayerName()
    return playerName;
end

local function PrintStats()
    local stats = Log.stats;
    Grommey.Print(string.format(L("Combat log: %d lines, %d read, %d not recognised."), stats.lines, stats.read, stats.unknown));
end

function Log.Command(arguments)
    local option = string.lower(string.match(arguments or "", "^%s*%S+%s+(%S+)") or "");
    if (option == "stats") then
        PrintStats();
        return;
    end
    debugOn = not debugOn;
    if (debugOn) then
        capture = { language = Grommey.GameLanguage; lines = {}; };
        Log.Use("debug", true);
        Grommey.Print(string.format(L("Combat log: test on. Every combat line is shown here and saved in %s."), CAPTURE_FILE .. ".plugindata"));
    else
        SaveCapture();
        capture = nil;
        Log.Use("debug", false);
        Grommey.Print(L("Combat log: test off."));
        PrintStats();
    end
end

-- Called when the plugin unloads
function Log.Shutdown()
    SaveCapture();
    users = {};
    Refresh();
end

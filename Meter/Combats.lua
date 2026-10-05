-- Fights: cuts the combat log into fights and adds everything up, like Details in World of Warcraft.
-- A fight starts with the first hit given or taken (or when the player enters combat), and ends when
-- the player leaves combat, or after a few quiet seconds outside combat. The last fights are kept,
-- with a total of the whole session.
--
-- What is counted, by view ("mode"), each person with the detail by skill, by other person
-- ("targets") and by damage type:
--   damage    damage dealt, by who dealt it (you, your pet); targets = enemies hit
--   taken     damage taken, by attacker; targets = who was hit (you, your pet)
--   enemies   damage dealt, by enemy hit; targets = who hit it
--   heal      healing, by healer (you, and whoever heals you); targets = who was healed
--   power     power restored, by who restored it; targets = who got it
-- Damage to power is left out, as in Combat Analysis.
-- On top of that each fight counts interrupts, corruptions removed, deaths, kills and temporary morale.

Grommey.Meter = Grommey.Meter or {};

local Combats = {};
Grommey.Meter.Combats = Combats;

Combats.MODES = { "damage", "taken", "enemies", "heal", "power" };
Combats.NO_SKILL = "*none";

-- Called when the fights should be saved (a fight ended, the data was reset)
Combats.SaveRequested = nil;

local function RequestSave()
    if (Combats.SaveRequested) then Combats.SaveRequested(); end
end

-- Seconds without any line, outside combat, before a fight is over
local QUIET = 4;

local history = {};         -- finished fights, newest first
local current = nil;        -- fight going on
local overall = nil;        -- every fight of the session added up
local maxHistory = 10;

-- Goes up on every change, the windows redraw when it moves
Combats.version = 0;

local COUNTERS = { "interruptsDone", "interruptsTaken", "dispels", "deaths", "kills", "bubble", "bubbleHits" };

local function NewFight(now)
    local fight = { start = now; last = now; data = {}; totals = {}; counters = {}; };
    for _, mode in ipairs(Combats.MODES) do
        fight.data[mode] = {};
        fight.totals[mode] = 0;
    end
    for _, counter in ipairs(COUNTERS) do fight.counters[counter] = 0; end
    return fight;
end

local function NewOverall()
    local fight = NewFight(0);
    fight.overall = true;
    fight.time = 0;
    return fight;
end

overall = NewOverall();

-- Length of a fight in seconds, at least one
function Combats.Duration(fight, now)
    if (fight == nil) then return 1; end
    if (fight.overall) then
        local time = fight.time;
        if (current ~= nil) then time = time + Combats.Duration(current, now); end
        return math.max(time, 1);
    end
    local finish = (fight == current and now ~= nil) and math.max(now, fight.last) or fight.last;
    return math.max(finish - fight.start, 1);
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Counters of a skill, a target or a whole person

local function Bucket()
    return { count = 0; total = 0; max = 0; min = nil; };
end

local function NewStats(name)
    return {
        name = name; total = 0;
        count = 0;          -- every try, avoided or not
        hits = 0;           -- tries that landed (with or without damage)
        normal = Bucket(); crit = Bucket(); devastating = Bucket();
        avoided = 0; avoid = {};        -- avoid type = count
        partialCount = 0; partial = {}; -- partial type = count
        noDamage = 0;                   -- landed without damage (effect only, absorbed)
        types = {};                     -- damage type = amount
    };
end
Combats.NewStats = NewStats;

local function AddStats(stats, event, amount)
    stats.total = stats.total + amount;
    stats.count = stats.count + 1;
    if (event.avoid ~= nil) then
        stats.avoided = stats.avoided + 1;
        stats.avoid[event.avoid] = (stats.avoid[event.avoid] or 0) + 1;
        return;
    end
    stats.hits = stats.hits + 1;
    if (event.noDamage) then
        stats.noDamage = stats.noDamage + 1;
        return;
    end
    local bucket = (event.crit == "critical" and stats.crit) or (event.crit == "devastating" and stats.devastating) or stats.normal;
    bucket.count = bucket.count + 1;
    bucket.total = bucket.total + amount;
    if (amount > bucket.max) then bucket.max = amount; end
    if (bucket.min == nil or amount < bucket.min) then bucket.min = amount; end
    if (event.partial ~= nil) then
        stats.partialCount = stats.partialCount + 1;
        stats.partial[event.partial] = (stats.partial[event.partial] or 0) + 1;
    end
    local damageType = event.damageType or event.damageTypeName;
    if (damageType ~= nil) then stats.types[damageType] = (stats.types[damageType] or 0) + amount; end
end

-- Biggest and smallest landed amounts of a stats, all hit kinds together
function Combats.Extremes(stats)
    local max, min = 0, nil;
    for _, key in ipairs({ "normal", "crit", "devastating" }) do
        local bucket = stats[key];
        if (bucket.max > max) then max = bucket.max; end
        if (bucket.min ~= nil and (min == nil or bucket.min < min)) then min = bucket.min; end
    end
    return max, min or 0;
end

-- Adds the counters of "from" into "into"
local function MergeStats(into, from)
    into.total = into.total + from.total;
    into.count = into.count + from.count;
    into.hits = into.hits + from.hits;
    into.avoided = into.avoided + from.avoided;
    into.partialCount = into.partialCount + from.partialCount;
    into.noDamage = into.noDamage + from.noDamage;
    for _, key in ipairs({ "normal", "crit", "devastating" }) do
        local a, b = into[key], from[key];
        a.count = a.count + b.count;
        a.total = a.total + b.total;
        if (b.max > a.max) then a.max = b.max; end
        if (b.min ~= nil and (a.min == nil or b.min < a.min)) then a.min = b.min; end
    end
    for key, count in pairs(from.avoid) do into.avoid[key] = (into.avoid[key] or 0) + count; end
    for key, count in pairs(from.partial) do into.partial[key] = (into.partial[key] or 0) + count; end
    for key, amount in pairs(from.types) do into.types[key] = (into.types[key] or 0) + amount; end
end

-- Skills of every actor of a view added up by skill name ("Bite" of all the wolves together).
-- Each merged skill remembers the actor who did the most of it (top).
function Combats.MergedSkills(fight, mode)
    local merged = {};
    if (fight == nil) then return merged; end
    for actorName, actor in pairs(fight.data[mode]) do
        for skillName, skill in pairs(actor.skills) do
            local into = merged[skillName];
            if (into == nil) then
                into = NewStats(skillName);
                into.topTotal = -1;
                merged[skillName] = into;
            end
            MergeStats(into, skill);
            if (skill.total > into.topTotal) then into.top, into.topTotal = actorName, skill.total; end
        end
    end
    return merged;
end

local function Record(fight, mode, actorName, skillName, targetName, event)
    local amount = event.amount or 0;
    local actors = fight.data[mode];
    local actor = actors[actorName];
    if (actor == nil) then
        actor = { name = actorName; total = 0; all = NewStats(actorName); skills = {}; targets = {}; };
        actors[actorName] = actor;
    end
    actor.total = actor.total + amount;
    AddStats(actor.all, event, amount);

    -- An empty name cannot be a key of a saved file
    if (skillName == nil or skillName == "") then skillName = Combats.NO_SKILL; end
    local skill = actor.skills[skillName];
    if (skill == nil) then
        skill = NewStats(skillName);
        actor.skills[skillName] = skill;
    end
    AddStats(skill, event, amount);

    targetName = targetName or "?";
    local target = actor.targets[targetName];
    if (target == nil) then
        target = NewStats(targetName);
        actor.targets[targetName] = target;
    end
    AddStats(target, event, amount);

    fight.totals[mode] = fight.totals[mode] + amount;
end

local function RecordBoth(mode, actorName, skillName, targetName, event)
    Record(current, mode, actorName, skillName, targetName, event);
    Record(overall, mode, actorName, skillName, targetName, event);
end

local function Count(counter, amount)
    current.counters[counter] = current.counters[counter] + (amount or 1);
    overall.counters[counter] = overall.counters[counter] + (amount or 1);
end

local function IsEmpty(fight)
    for _, mode in ipairs(Combats.MODES) do
        if (next(fight.data[mode]) ~= nil) then return false; end
    end
    return true;
end

local function Changed()
    Combats.version = Combats.version + 1;
end

function Combats.StartFight(now)
    if (current ~= nil) then return; end
    current = NewFight(now);
    Changed();
end

function Combats.EndFight()
    if (current == nil) then return; end
    local fight = current;
    current = nil;
    if (not IsEmpty(fight)) then
        overall.time = overall.time + Combats.Duration(fight);
        table.insert(history, 1, fight);
        while (#history > maxHistory) do table.remove(history); end
        RequestSave();
    end
    Changed();
end

-- Outgoing: what the player (or the pet) did. The chat channel tells it; without it, the name does.
local function IsOutgoing(event)
    if (event.channel ~= nil) then return event.channel == "player"; end
    return event.byYou == true;
end

function Combats.Add(event, now)
    local kind = event.kind;
    if (kind == "damage") then
        if (event.pool == "power") then return; end
        if (current == nil) then Combats.StartFight(now); end
        local source, target = event.source or "?", event.target or "?";
        if (IsOutgoing(event)) then
            RecordBoth("damage", source, event.skill, target, event);
            RecordBoth("enemies", target, event.skill, source, event);
        else
            RecordBoth("taken", source, event.skill, target, event);
        end
    else
        -- Nothing else starts a fight (regeneration, heals while travelling...)
        if (current == nil) then return; end
        if (kind == "heal" or kind == "power") then
            RecordBoth(kind, event.source or "?", event.skill, event.target or "?", event);
        elseif (kind == "interrupt") then
            if (event.byYou) then Count("interruptsDone"); elseif (event.onYou) then Count("interruptsTaken"); else return; end
        elseif (kind == "dispel") then
            Count("dispels");
        elseif (kind == "death") then
            if (event.onYou) then Count("deaths"); elseif (event.byYou) then Count("kills"); else return; end
        elseif (kind == "tempMorale") then
            Count("bubble", event.amount or 0);
            Count("bubbleHits");
        else
            return;
        end
    end
    current.last = now;
    Changed();
end

-- Called about once a second: ends a fight that went quiet outside combat
function Combats.Tick(now, inCombat)
    if (current ~= nil and not inCombat and now - current.last >= QUIET) then
        Combats.EndFight();
    end
end

function Combats.Reset()
    history = {};
    current = nil;
    overall = NewOverall();
    Changed();
    RequestSave();
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Saving: the finished fights and the session total. Whole numbers only (French and German
-- clients write decimals with a comma), so a fight keeps its length in seconds, not its game times.

local SAVE_VERSION = 1;

local function ExportFight(fight, isOverall)
    local copy = { data = fight.data; totals = fight.totals; counters = fight.counters; };
    if (isOverall) then
        copy.time = math.floor(fight.time + 0.5);
    else
        copy.length = math.floor(Combats.Duration(fight) + 0.5);
    end
    return copy;
end

function Combats.Export()
    local saved = { version = SAVE_VERSION; history = {}; overall = ExportFight(overall, true); };
    for index, fight in ipairs(history) do saved.history[index] = ExportFight(fight, false); end
    return saved;
end

local function ImportFight(saved, isOverall)
    if (type(saved) ~= "table" or type(saved.data) ~= "table") then return nil; end
    local fight = isOverall and NewOverall() or NewFight(0);
    for _, mode in ipairs(Combats.MODES) do
        if (type(saved.data[mode]) == "table") then fight.data[mode] = saved.data[mode]; end
        if (type(saved.totals) == "table" and tonumber(saved.totals[mode])) then fight.totals[mode] = tonumber(saved.totals[mode]); end
    end
    for _, counter in ipairs(COUNTERS) do
        if (type(saved.counters) == "table" and tonumber(saved.counters[counter])) then fight.counters[counter] = tonumber(saved.counters[counter]); end
    end
    if (isOverall) then
        fight.time = tonumber(saved.time) or 0;
    else
        fight.start = 0;
        fight.last = tonumber(saved.length) or 1;
    end
    return fight;
end

function Combats.Import(saved)
    if (type(saved) ~= "table" or saved.version ~= SAVE_VERSION) then return; end
    history = {};
    for index = 1, maxHistory do
        local fight = ImportFight(type(saved.history) == "table" and saved.history[index], false);
        if (fight == nil) then break; end
        table.insert(history, fight);
    end
    overall = ImportFight(saved.overall, true) or NewOverall();
    current = nil;
    Changed();
end

function Combats.SetHistorySize(size)
    maxHistory = size;
    while (#history > maxHistory) do table.remove(history); end
    Changed();
end

-- which: "current" (the fight going on, or the last one), "overall", or a number (1 = last finished)
function Combats.Get(which)
    if (which == "overall") then return overall; end
    if (which == "current") then return current or history[1]; end
    return history[which];
end

function Combats.Current()
    return current;
end

function Combats.History()
    return history;
end

-- Name of a fight: the enemy hit the hardest, or the one that hit the hardest
function Combats.Name(fight)
    if (fight == nil) then return ""; end
    for _, mode in ipairs({ "enemies", "taken" }) do
        local best = nil;
        for _, actor in pairs(fight.data[mode]) do
            if (best == nil or actor.total > best.total) then best = actor; end
        end
        if (best ~= nil) then return best.name; end
    end
    return "";
end

local function Sorted(list)
    table.sort(list, function(a, b)
        if (a.total ~= b.total) then return a.total > b.total; end
        return tostring(a.name) < tostring(b.name);
    end);
    return list;
end

-- Actors of a view, highest first: { name, total, perSecond, percent, actor }
function Combats.Ranking(fight, mode, now)
    local list = {};
    if (fight == nil) then return list; end
    local duration = Combats.Duration(fight, now);
    local total = fight.totals[mode];
    for _, actor in pairs(fight.data[mode]) do
        table.insert(list, {
            name = actor.name; total = actor.total; actor = actor; stats = actor.all;
            perSecond = actor.total / duration;
            percent = (total > 0) and (actor.total * 100 / total) or 0;
        });
    end
    return Sorted(list);
end

-- Entries of a table of stats (skills or targets of an actor), highest first
function Combats.Entries(fight, statsTable, parentTotal, now)
    local list = {};
    local duration = Combats.Duration(fight, now);
    for _, stats in pairs(statsTable or {}) do
        table.insert(list, {
            name = stats.name; total = stats.total; stats = stats;
            perSecond = stats.total / duration;
            percent = (parentTotal > 0) and (stats.total * 100 / parentTotal) or 0;
        });
    end
    return Sorted(list);
end

-- Damage types of a stats, highest first
function Combats.Types(stats)
    local list = {};
    for name, total in pairs(stats.types) do
        table.insert(list, { name = name; total = total; percent = (stats.total > 0) and (total * 100 / stats.total) or 0; });
    end
    return Sorted(list);
end

-- What concerns the player in a fight: keys for the summary of the window
function Combats.Summary(fight, you, now)
    if (fight == nil) then return nil; end
    local function Of(mode, name) return fight.data[mode][name]; end
    local summary = { duration = Combats.Duration(fight, now); counters = fight.counters; };
    summary.damage = Of("damage", you);
    summary.taken = NewStats("");
    for _, actor in pairs(fight.data.taken) do
        local victim = actor.targets[you];
        -- Added up over every attacker
        if (victim ~= nil) then MergeStats(summary.taken, victim); end
    end
    -- Healing done by you, healing you got from anyone
    summary.healDone = Of("heal", you);
    summary.healReceived = 0;
    for _, actor in pairs(fight.data.heal) do
        local target = actor.targets[you];
        if (target ~= nil) then summary.healReceived = summary.healReceived + target.total; end
    end
    summary.powerReceived = 0;
    for _, actor in pairs(fight.data.power) do
        local target = actor.targets[you];
        if (target ~= nil) then summary.powerReceived = summary.powerReceived + target.total; end
    end
    -- Your best hit, with its skill
    summary.bestHit, summary.bestSkill = 0, nil;
    if (summary.damage ~= nil) then
        for name, skill in pairs(summary.damage.skills) do
            local max = Combats.Extremes(skill);
            if (max > summary.bestHit) then summary.bestHit, summary.bestSkill = max, name; end
        end
    end
    return summary;
end

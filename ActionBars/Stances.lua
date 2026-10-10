-- Stances of the stances bar: the ones of Grommey.StanceSkills the character knows.
-- The game lists the skills a character knows by name only (no id), so a stance is known when its
-- name in the client language is in that list, with the same icon when two stances share a name.

Grommey.Stances = {};

local player = nil;
local known = {};
local trainedCount = -1;

local function Call(object, method, ...)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object, ...);
    if (ok) then return value; end
    return nil;
end

local function NameOf(entry)
    return entry[Grommey.GameLanguage] or entry.en;
end

-- Looks again only when the number of trained skills changed
local function UpdateKnown()
    local list = Call(player, "GetTrainedSkills");
    local count = Call(list, "GetCount") or 0;
    if (count == trainedCount) then return; end
    trainedCount = count;

    local trained = {};
    for index = 1, count do
        local info = Call(Call(list, "GetItem", index), "GetSkillInfo");
        local name = Call(info, "GetName");
        if (name ~= nil) then
            trained[name] = trained[name] or {};
            trained[name][Call(info, "GetIconImageID") or 0] = true;
        end
    end

    local sameName = {};
    for _, entry in ipairs(Grommey.StanceSkills or {}) do
        local name = NameOf(entry);
        sameName[name] = (sameName[name] or 0) + 1;
    end

    known = {};
    for _, entry in ipairs(Grommey.StanceSkills or {}) do
        local icons = trained[NameOf(entry)];
        if (icons ~= nil and (sameName[NameOf(entry)] == 1 or icons[entry.icon])) then
            table.insert(known, entry);
        end
    end
end

function Grommey.Stances.Start(localPlayer)
    player = localPlayer;
    trainedCount = -1;
end

-- Known stances, in the order of the base (grouped by class)
function Grommey.Stances.Known()
    if (player == nil) then return {}; end
    UpdateKnown();
    return known;
end

-- Travel skills of the travel bar: which ones the character knows, which ones the player chose and
-- in what order, and the window to choose them.
-- The game lists the skills a character knows by name only (no id), so a skill of Grommey.TravelSkills
-- is known when its name in the client language is in that list. A few names exist twice: the icon,
-- then the race of the character, tell them apart.
-- The choice is kept for each character (classes have travel skills of their own).

local UI = Grommey.UI;
local Theme = Grommey.Theme;

Grommey.Travel = {};
local Travel = Grommey.Travel;

local CHOICE_FILE = "GrommeyUI_Travel";

-- Families in display order, with their names
Travel.FAMILIES = {
    { key = "home"; name = "Return home and milestones"; },
    { key = "house"; name = "Houses"; },
    { key = "regions"; name = "Regions and reputation"; },
    { key = "hunter"; name = "Hunter guides"; },
    { key = "warden"; name = "Warden musters"; },
    { key = "mariner"; name = "Mariner voyages"; },
    { key = "mount"; name = "Mounts"; },
    { key = "other"; name = "Other"; },
};

Travel.SORTS = {
    { value = "family"; text = "By family"; },
    { value = "name"; text = "By name"; },
    { value = "custom"; text = "My order"; },
};

local byId = {};
local familyRank = {};
for index, entry in ipairs(Grommey.TravelSkills or {}) do
    entry.rank = index;
    byId[entry.id] = entry;
end
for rank, familyInfo in ipairs(Travel.FAMILIES) do familyRank[familyInfo.key] = rank; end

local player = nil;
local choice = nil;         -- { chosen = { id = true }, order = { id, ... }, initialized = true }
local known = {};           -- known entries, in the order of the base
local trainedCount = -1;
local listeners = {};

local function Call(object, method, ...)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object, ...);
    if (ok) then return value; end
    return nil;
end

local function NameOf(entry)
    return entry[Grommey.GameLanguage] or entry.en;
end
Travel.NameOf = NameOf;

function Travel.IsSkill(id)
    return byId[id] ~= nil;
end

local function Save()
    Grommey.Delay("SaveTravel", 1, function()
        Grommey.Storage.Save(Turbine.DataScope.Character, CHOICE_FILE, choice);
    end);
end

local function Changed()
    Save();
    for _, listener in ipairs(listeners) do pcall(listener); end
end

function Travel.OnChange(listener)
    table.insert(listeners, listener);
end

local function RaceName()
    local race = Call(player, "GetRace");
    for name, value in pairs((Turbine.Gameplay and Turbine.Gameplay.Race) or {}) do
        if (value == race and type(name) == "string") then return name; end
    end
    return nil;
end

-- Finds the known travel skills again when the list of trained skills changed
local function UpdateKnown()
    local list = Call(player, "GetTrainedSkills");
    local count = Call(list, "GetCount") or 0;
    if (count == trainedCount) then return false; end
    trainedCount = count;

    -- Trained skills by name, with their icons
    local trained = {};
    for index = 1, count do
        local info = Call(Call(list, "GetItem", index), "GetSkillInfo");
        local name = Call(info, "GetName");
        if (name ~= nil) then
            trained[name] = trained[name] or {};
            trained[name][Call(info, "GetIconImageID") or 0] = true;
        end
    end

    -- Entries of the base sharing a name
    local sameName = {};
    for _, entry in ipairs(Grommey.TravelSkills or {}) do
        local name = NameOf(entry);
        sameName[name] = sameName[name] or {};
        table.insert(sameName[name], entry);
    end

    local race = RaceName();
    local tallRaces = { Man = true; Elf = true; HighElf = true; Beorning = true; };
    local tall = race == nil or tallRaces[race] == true;
    local seen = {};
    known = {};
    for _, entry in ipairs(Grommey.TravelSkills or {}) do
        local name = NameOf(entry);
        local icons = trained[name];
        local isKnown = false;
        if (icons ~= nil) then
            local same = sameName[name];
            if (#same == 1) then
                isKnown = true;
            elseif (icons[entry.icon]) then
                -- Same name: the icon tells them apart, then the race
                local withIcon = {};
                for _, other in ipairs(same) do
                    if (icons[other.icon]) then table.insert(withIcon, other); end
                end
                -- A mount and its peer: the horse or the pony, from the size of the race
                if (#withIcon > 1 and entry.tall ~= nil) then
                    local sized = {};
                    for _, other in ipairs(withIcon) do
                        if (other.tall == nil or other.tall == tall) then table.insert(sized, other); end
                    end
                    if (#sized > 0) then withIcon = sized; end
                end
                local kept = false;
                for _, other in ipairs(withIcon) do
                    if (other == entry) then kept = true; end
                end
                if (not kept) then
                    isKnown = false;
                elseif (#withIcon == 1) then
                    isKnown = true;
                else
                    local raceMatch = false;
                    for _, other in ipairs(withIcon) do
                        if (other.race ~= nil and other.race == race) then raceMatch = true; end
                    end
                    if (raceMatch) then isKnown = (entry.race == race); else isKnown = (entry.race == nil); end
                end
            end
        end
        -- Still twice the same name and icon: the first one only
        local key = name .. "|" .. tostring(entry.icon);
        if (isKnown and not seen[key]) then
            seen[key] = true;
            table.insert(known, entry);
        end
    end

    -- The first time, the return home skills and the houses are chosen
    if (not choice.initialized and #known > 0) then
        choice.initialized = true;
        for _, entry in ipairs(known) do
            if (entry.family == "home" or entry.family == "house") then
                choice.chosen[entry.id] = true;
                table.insert(choice.order, entry.id);
            end
        end
        Save();
    end
    return true;
end

function Travel.Start(localPlayer)
    player = localPlayer;
    choice = Grommey.Storage.Load(Turbine.DataScope.Character, CHOICE_FILE) or {};
    choice.chosen = choice.chosen or {};
    choice.order = choice.order or {};
    trainedCount = -1;
    UpdateKnown();
end

-- Known skills, in the order of the base
function Travel.Known()
    if (choice == nil) then return {}; end
    UpdateKnown();
    return known;
end

function Travel.IsChosen(id)
    return choice ~= nil and choice.chosen[id] == true;
end

function Travel.SetChosen(id, chosen)
    if (choice == nil) then return; end
    choice.chosen[id] = chosen or nil;
    for index = #choice.order, 1, -1 do
        if (choice.order[index] == id) then table.remove(choice.order, index); end
    end
    if (chosen) then table.insert(choice.order, id); end
    Changed();
end

-- Moves a chosen skill up (-1) or down (+1) in the player's order
function Travel.Move(id, delta)
    if (choice == nil) then return; end
    for index, other in ipairs(choice.order) do
        if (other == id) then
            local target = index + delta;
            if (target >= 1 and target <= #choice.order) then
                choice.order[index], choice.order[target] = choice.order[target], choice.order[index];
                Changed();
            end
            return;
        end
    end
end

-- "Return Home 2" before "Return Home 10"
local function Natural(text)
    return (string.gsub(string.lower(text or ""), "%d+", function(number) return string.rep("0", 6 - #number) .. number; end));
end

-- Chosen skills the character knows, sorted: "family", "name" or "custom"
function Travel.Chosen(sort)
    local list = {};
    for _, entry in ipairs(Travel.Known()) do
        if (choice.chosen[entry.id]) then table.insert(list, entry); end
    end
    if (sort == "name") then
        table.sort(list, function(a, b) return Natural(NameOf(a)) < Natural(NameOf(b)); end);
    elseif (sort == "custom") then
        local position = {};
        for index, id in ipairs(choice.order) do position[id] = index; end
        table.sort(list, function(a, b) return (position[a.id] or 9999) < (position[b.id] or 9999); end);
    end
    return list;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Window to choose the skills of the bar

local WIDTH, HEIGHT = 480, 560;
local IMAGES = "GrommeyUI/ActionBars/Resources/";
local PAD = 16;
local ROW = 28;
local picker = nil;
local pickerSort = "family";

local function FillPicker()
    local list = picker.list;
    list:ClearItems();
    local width = list:GetWidth();
    local function Line(height)
        local line = Turbine.UI.Control();
        line:SetSize(width, height);
        list:AddItem(line);
        return line;
    end

    local entries = Travel.Known();
    if (#entries == 0) then
        UI.Label(Line(60), 0, 4, width, 52, L("Your character does not know any travel skill yet."), { role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
        return;
    end

    local custom = (pickerSort == "custom");
    local function SkillLine(entry)
        local line = Line(ROW);
        local arrows = custom and Travel.IsChosen(entry.id);
        UI.Toggle(line, 0, 3, width - (arrows and 60 or 0), NameOf(entry), Travel.IsChosen(entry.id), function(value)
            Travel.SetChosen(entry.id, value);
            if (custom) then FillPicker(); end
        end);
        if (arrows) then
            -- Images: the game fonts have no arrow characters
            for index, arrow in ipairs({ { image = "up"; delta = -1; }, { image = "down"; delta = 1; } }) do
                local button = Turbine.UI.Control();
                button:SetParent(line);
                button:SetSize(16, 16);
                button:SetPosition(width - 54 + (index - 1) * 26, math.floor((ROW - 16) / 2));
                button:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend);
                local function Image(hover) button:SetBackground(IMAGES .. arrow.image .. (hover and "_hover" or "") .. ".tga"); end
                Image(false);
                button.MouseEnter = function() Image(true); end
                button.MouseLeave = function() Image(false); end
                button.MouseClick = function() Travel.Move(entry.id, arrow.delta); FillPicker(); end
            end
        end
    end

    if (custom) then
        -- The chosen ones first in the player's order, then the others
        UI.Label(Line(26), 0, 4, width, 20, L("Shown, in this order"), { bold = true; role = "accent"; });
        local chosen = Travel.Chosen("custom");
        for _, entry in ipairs(chosen) do SkillLine(entry); end
        UI.Label(Line(34), 0, 12, width, 20, L("Not shown"), { bold = true; role = "accent"; });
        for _, entry in ipairs(entries) do
            if (not Travel.IsChosen(entry.id)) then SkillLine(entry); end
        end
        return;
    end

    -- By family, as the bar sorts them by default
    local current = nil;
    for _, entry in ipairs(entries) do
        if (entry.family ~= current) then
            current = entry.family;
            local name = entry.family;
            for _, familyInfo in ipairs(Travel.FAMILIES) do
                if (familyInfo.key == current) then name = L(familyInfo.name); end
            end
            UI.Label(Line(30), 0, 8, width, 20, name, { bold = true; role = "accent"; });
        end
        SkillLine(entry);
    end
end

local function CreatePicker()
    -- Moved freely by its title bar while it is open, like the detail window of the meter
    picker = Grommey.Window("travelPicker", L("Travel skills"), WIDTH, HEIGHT);
    local saved = Grommey.Profile.positions["travelPicker"];
    local screenWidth, screenHeight = Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
    local x = saved and saved.x or math.floor((screenWidth - WIDTH) / 2);
    local y = saved and saved.y or math.floor((screenHeight - HEIGHT) / 2);
    picker:SetPosition(Grommey.Clamp(x, 0, math.max(0, screenWidth - WIDTH)), Grommey.Clamp(y, 0, math.max(0, screenHeight - HEIGHT)));
    local contentWidth, contentHeight = picker.content:GetSize();

    UI.Label(picker.content, PAD, 10, contentWidth - 2 * PAD, 36, L("The travel skills your character knows. Tick the ones to show on the travel bar."),
        { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });

    picker.list = Turbine.UI.ListBox();
    picker.list:SetParent(picker.content);
    picker.list:SetPosition(PAD, 52);
    picker.list:SetSize(contentWidth - 2 * PAD - 14, contentHeight - 52 - 56);
    picker.scrollBar = Turbine.UI.Lotro.ScrollBar();
    picker.scrollBar:SetOrientation(Turbine.UI.Orientation.Vertical);
    picker.scrollBar:SetParent(picker.content);
    picker.scrollBar:SetPosition(contentWidth - PAD - 10, 52);
    picker.scrollBar:SetSize(10, contentHeight - 52 - 56);
    picker.list:SetVerticalScrollBar(picker.scrollBar);

    UI.Separator(picker.content, 0, contentHeight - 50, contentWidth);
    UI.Button(picker.content, contentWidth - PAD - 140, contentHeight - 38, 140, L("Close"), function() picker:SetVisible(false); end, "accent");
    Grommey.On("HudToggled", function(hidden) if (hidden and picker) then picker:SetVisible(false); end end);
    -- A global keeps the window alive
    Grommey.TravelPicker = picker;
end

-- sort: the sort of the bar, "custom" shows the arrows to order the skills
function Travel.OpenPicker(sort)
    if (choice == nil) then return; end
    if (picker == nil) then CreatePicker(); end
    pickerSort = sort or "family";
    FillPicker();
    picker:SetVisible(true);
    picker:Activate();
end

function Travel.Stop()
    if (picker) then picker:SetVisible(false); end
    listeners = {};
end

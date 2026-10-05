-- Auras: the player's buffs and debuffs in two areas of their own, by default at the top right
-- of the screen next to the minimap, as in World of Warcraft. Each area is placed with the move mode.

local UF = Grommey.UnitFrames;
local UI = Grommey.UI;

local TIMES_DELAY = 0.5;
-- Room left on the right of the screen for the minimap
local MINIMAP_ROOM = 230;
local TOP_MARGIN = 34;
local AREA_GAP = 12;

local areas = {};         -- "buffs" / "debuffs" = window
local settingsRoot = nil;
local player = nil;
local preview = false;
local previewBeforeMove = false;

local AREA_KEYS = { "buffs", "debuffs" };

-- Settings of the effects grid, from the settings of an area
local function GridSettings(key)
    local settings = settingsRoot[key];
    return {
        show = true;
        filter = key;
        position = (settings.lines == "up") and "top" or "bottom";
        growth = settings.growth;
        perLine = settings.perLine;
        max = settings.max;
        spacing = settings.spacing;
        timeBelow = (settings.time == "below");
        colorByType = settings.colorByType;
        debuffsFirst = false;
        hidden = settingsRoot.hidden;
        important = settingsRoot.important;
        hidePermanent = settings.hidePermanent;
    };
end

local function AreaSize(key)
    local probe = UF.EffectsBar(nil, GridSettings(key));
    return probe:GetAreaSize();
end

-- Buffs right of the screen, left of the minimap, debuffs under them
local function DefaultX(key)
    local width = AreaSize(key);
    return function() return Turbine.UI.Display.GetWidth() - MINIMAP_ROOM - width; end
end

local function DefaultY(key)
    if (key == "buffs") then return TOP_MARGIN; end
    local _, buffsHeight = AreaSize("buffs");
    return TOP_MARGIN + buffsHeight + AREA_GAP;
end

local function UnitForEffects()
    if (preview) then return UF.DummyEffectsUnit(); end
    return player;
end

local function DestroyArea(key)
    local area = areas[key];
    if (area == nil) then return; end
    area:SetWantsUpdates(false);
    area.grid:Destroy();
    Grommey.Movers.Unregister("auras:" .. key);
    area:SetVisible(false);
    areas[key] = nil;
end

local function CreateArea(key)
    local area = Turbine.UI.Window();
    area:SetMouseVisible(false);
    area.grid = UF.EffectsBar(area, GridSettings(key));

    area.nextTimes = 0;
    area:SetWantsUpdates(true);
    area.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (now >= area.nextTimes) then
            area.nextTimes = now + TIMES_DELAY;
            area.grid:UpdateTimes();
        end
    end

    area.grid:SetUnit(UnitForEffects());
    area:SetSize(area.grid:GetAreaSize());
    area:SetVisible(not Grommey.HudHidden);
    areas[key] = area;

    local name = (key == "buffs") and L("Buffs") or L("Debuffs");
    Grommey.Movers.Register("auras:" .. key, area, name, DefaultX(key), DefaultY(key));
end

-- Builds the areas again from the settings
local function Build()
    for _, key in ipairs(AREA_KEYS) do
        DestroyArea(key);
        if (settingsRoot[key].enabled) then CreateArea(key); end
    end
end

local function SetPreview(enabled)
    if (preview == enabled) then return; end
    preview = enabled;
    for _, area in pairs(areas) do area.grid:SetUnit(UnitForEffects()); end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Options

local selectedArea = "buffs";

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

-- Hidden and important effects, by name, for both areas
local function BuildFilterOptions(page, width, settings, Reopen)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    settings.hidden = settings.hidden or {};
    settings.important = settings.important or {};
    local function Changed() Grommey.Profiles.RequestSave(); Build(); Reopen(); end
    local function Toggle(list, name)
        list[name] = (not list[name]) or nil;
        -- An effect is either hidden or important
        if (list[name]) then
            if (list == settings.hidden) then settings.important[name] = nil; else settings.hidden[name] = nil; end
        end
        Changed();
    end

    -- Effects on the character right now, each can be marked
    UI.Label(page, 0, 0, half, 20, L("Your effects right now"), { bold = true; role = "accent"; });
    local names, isDebuff = {}, {};
    local effects = player and player:GetEffects();
    for index = 1, (effects and effects:GetCount()) or 0 do
        local effect = effects:Get(index);
        local name = effect and effect:GetName();
        if (name and not isDebuff[name] and not names[name]) then
            names[name] = true;
            isDebuff[name] = effect:IsDebuff() == true;
        end
    end
    local sorted = {};
    for name in pairs(names) do table.insert(sorted, name); end
    table.sort(sorted);
    local y = 28;
    if (#sorted == 0) then
        UI.Label(page, 0, y, half, 36, L("No effect on you at the moment."), { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end
    local buttonWidth = 76;
    for _, name in ipairs(sorted) do
        local label = UI.Label(page, 0, y, half - 2 * (buttonWidth + 6), 26, name, { size = 12; role = isDebuff[name] and "danger" or "text"; });
        UI.Button(page, half - 2 * buttonWidth - 6, y, buttonWidth, L("Important"), function() Toggle(settings.important, name); end,
            settings.important[name] and "accent" or nil);
        UI.Button(page, half - buttonWidth, y, buttonWidth, L("Hide"), function() Toggle(settings.hidden, name); end,
            settings.hidden[name] and "accent" or nil);
        y = y + 30;
        if (y > page:GetHeight() - 30) then break; end
    end

    -- The two lists, the cross takes a name off
    local function List(top, title, list)
        UI.Label(page, right, top, half, 20, title, { bold = true; role = "accent"; });
        local entries = {};
        for name in pairs(list) do table.insert(entries, name); end
        table.sort(entries);
        local rowY = top + 26;
        if (#entries == 0) then UI.Label(page, right, rowY, half, 20, L("None"), { size = 12; role = "dim"; }); rowY = rowY + 22; end
        for _, name in ipairs(entries) do
            UI.Label(page, right, rowY, half - 26, 22, name, { size = 12; });
            local remove = UI.Label(page, width - 22, rowY, 22, 22, "x", { role = "danger"; mouse = true; align = Turbine.UI.ContentAlignment.MiddleCenter; });
            remove.MouseClick = function() list[name] = nil; Changed(); end
            rowY = rowY + 22;
        end
        return rowY;
    end
    local listY = List(0, L("Important (shown first)"), settings.important);
    listY = List(listY + 12, L("Hidden effects"), settings.hidden);

    -- A name typed by hand, for an effect you do not have right now
    listY = listY + 14;
    local nameBox = UI.TextInput(page, right, listY, half, "");
    local addWidth = math.floor((half - 8) / 2);
    local function Add(list)
        local name = string.match(nameBox:GetText() or "", "^%s*(.-)%s*$");
        if (name ~= "" and not list[name]) then Toggle(list, name); end
    end
    UI.Button(page, right, listY + 32, addWidth, L("Important"), function() Add(settings.important); end);
    UI.Button(page, right + addWidth + 8, listY + 32, addWidth, L("Hide"), function() Add(settings.hidden); end);
end

local function BuildOptions(page, width, settings)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    local function Reopen() Grommey.Options.ShowPage("module:Auras"); end
    local function Changed() Grommey.Profiles.RequestSave(); Build(); end
    local function LabeledDropdown(x, y, text, items, value, onChange)
        UI.Label(page, x, y, half, 18, text);
        UI.Dropdown(page, x, y + 20, half, Translated(items), value, onChange);
    end

    UI.Header(page, 0, 16, width, L("Auras"));
    -- Fake effects to set everything up without buffs
    UI.Button(page, width - 200, 12, 200, preview and L("Preview: on") or L("Preview: off"), function()
        SetPreview(not preview);
        Reopen();
    end, preview and "accent" or nil);

    local x = 0;
    local sections = { { key = "buffs"; text = L("Buffs"); }, { key = "debuffs"; text = L("Debuffs"); }, { key = "filters"; text = L("Filters"); } };
    for _, section in ipairs(sections) do
        UI.Button(page, x, 52, 150, section.text, function() selectedArea = section.key; Reopen(); end,
            (selectedArea == section.key) and "accent" or nil);
        x = x + 158;
    end

    if (selectedArea == "filters") then
        local holder = Turbine.UI.Control();
        holder:SetParent(page);
        holder:SetPosition(0, 100);
        holder:SetSize(width, page:GetHeight() - 100);
        BuildFilterOptions(holder, width, settings, Reopen);
        return;
    end

    local area = settings[selectedArea];
    local y = 100;
    UI.Toggle(page, 0, y, half, L("Show this area"), area.enabled, function(value) area.enabled = value; Changed(); end);
    if (selectedArea == "debuffs") then
        UI.Toggle(page, right, y, half, L("Border colour by type"), area.colorByType, function(value) area.colorByType = value; Changed(); end);
    end
    UI.Toggle(page, 0, y + 32, width, L("Hide permanent effects (no duration or an hour and more)"), area.hidePermanent == true, function(value)
        area.hidePermanent = value;
        Changed();
    end);
    y = y + 74;

    LabeledDropdown(0, y, L("Direction"), {
        { value = "left"; text = "Toward the left"; }, { value = "right"; text = "Toward the right"; },
    }, area.growth, function(value) area.growth = value; Changed(); end);
    LabeledDropdown(right, y, L("New lines"), {
        { value = "down"; text = "Downward"; }, { value = "up"; text = "Upward"; },
    }, area.lines, function(value) area.lines = value; Changed(); end);
    y = y + 60;

    UI.Slider(page, 0, y, half, L("Icons per line"), 2, 20, 1, area.perLine, function(value) area.perLine = value; Changed(); end);
    UI.Slider(page, right, y, half, L("Maximum icons"), 1, 40, 1, area.max, function(value) area.max = value; Changed(); end);
    y = y + 54;
    UI.Slider(page, 0, y, half, L("Space between icons"), 0, 12, 1, area.spacing, function(value) area.spacing = value; Changed(); end, " px");
    LabeledDropdown(right, y, L("Remaining time"), {
        { value = "below"; text = "Under the icon"; }, { value = "inside"; text = "On the icon"; },
    }, area.time, function(value) area.time = value; Changed(); end);
    y = y + 70;

    -- The same effects can also stay under the player frame
    local unitFrames = Grommey.Modules.Settings("UnitFrames");
    if (unitFrames ~= nil and unitFrames.player ~= nil) then
        UI.Separator(page, 0, y, width);
        y = y + 16;
        UI.Toggle(page, 0, y, width, L("Also show the effects under the player frame"), unitFrames.player.effects.show, function(value)
            unitFrames.player.effects.show = value;
            Grommey.Profiles.RequestSave();
            Grommey.Fire("UnitFramesSettingsChanged");
        end);
        y = y + 30;
    end
    UI.Label(page, 0, y, width, 36, L("Place the areas with the move mode. The game does not let plugins cancel a buff."), { size = 12; role = "dim"; });
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Module

Grommey.Modules.Register({
    id = "Auras";
    name = "Auras";
    description = "Your buffs and debuffs in two areas of their own, next to the minimap.";
    enabledByDefault = true;
    defaults = {
        buffs = { enabled = true; growth = "left"; lines = "down"; perLine = 10; max = 20; spacing = 4; time = "below"; colorByType = false; hidePermanent = false; };
        debuffs = { enabled = true; growth = "left"; lines = "down"; perLine = 8; max = 8; spacing = 4; time = "below"; colorByType = true; hidePermanent = false; };
        -- Effect name = true, for both areas
        hidden = {};
        important = {};
    };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();

        -- The first time, the auras take over from the effects under the player frame
        if (not settings.tookOverPlayerEffects) then
            settings.tookOverPlayerEffects = true;
            local unitFrames = Grommey.Modules.Settings("UnitFrames");
            if (unitFrames ~= nil and unitFrames.player ~= nil and unitFrames.player.effects ~= nil) then
                unitFrames.player.effects.show = false;
                Grommey.Fire("UnitFramesSettingsChanged");
            end
            Grommey.Profiles.RequestSave();
        end

        Build();

        -- Fake effects in move mode so each area has something to show
        Grommey.On("MoveModeChanged", function(active)
            if (settingsRoot == nil) then return; end
            if (active) then
                previewBeforeMove = preview;
                SetPreview(true);
            else
                SetPreview(previewBeforeMove == true);
            end
        end);
        Grommey.On("HudToggled", function() for _, area in pairs(areas) do area:SetVisible(not Grommey.HudHidden); end end);
        Grommey.On("ThemeChanged", function() if (settingsRoot) then Build(); end end);
    end;

    Disable = function()
        for _, key in ipairs(AREA_KEYS) do DestroyArea(key); end
        settingsRoot = nil;
    end;

    BuildOptions = BuildOptions;

    SetupOptions = function(page, width, settings)
        UI.Toggle(page, 0, 0, width, L("Buffs"), settings.buffs.enabled, function(value) settings.buffs.enabled = value; end);
        UI.Toggle(page, 0, 34, width, L("Debuffs"), settings.debuffs.enabled, function(value) settings.debuffs.enabled = value; end);
        UI.Toggle(page, 0, 68, width, L("Border colour by type"), settings.debuffs.colorByType, function(value) settings.debuffs.colorByType = value; end);
        UI.Toggle(page, 0, 102, width, L("Remaining time under the icon"), settings.buffs.time == "below", function(value)
            settings.buffs.time = value and "below" or "inside";
            settings.debuffs.time = settings.buffs.time;
        end);
        local unitFrames = Grommey.Modules.Settings("UnitFrames");
        if (unitFrames ~= nil and unitFrames.player ~= nil) then
            UI.Toggle(page, 0, 136, width, L("Also show the effects under the player frame"), unitFrames.player.effects.show, function(value)
                unitFrames.player.effects.show = value;
            end);
        end
        UI.Label(page, 0, 180, width, 36, L("Two areas at the top right, next to the minimap. Place them with the move mode."), { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end;
});

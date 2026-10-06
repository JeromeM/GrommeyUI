-- Timer bars: the player's buffs and debuffs as bars that empty as they run out, with the name
-- and the time left. Two areas of their own (buffs, debuffs), each placed with the move mode,
-- with their own filters. Works next to the icons of the auras.

local UF = Grommey.UnitFrames;
local UI = Grommey.UI;

local UPDATE_DELAY = 0.05;  -- the bars move smoothly
local AREA_GAP = 40;

local areas = {};           -- "buffs" / "debuffs" = window
local settingsRoot = nil;
local player = nil;
local preview = false;
local previewBeforeMove = false;

local AREA_KEYS = { "buffs", "debuffs" };

local function GridSettings(key)
    local settings = settingsRoot[key];
    -- The fake effects of the preview are never among the chosen ones
    local onlyMode = (settingsRoot.filterMode == "only") and not preview;
    return {
        show = true;
        filter = key;
        lines = settings.lines;
        max = settings.max;
        spacing = settings.spacing;
        barWidth = settings.barWidth;
        barHeight = settings.barHeight;
        barIcon = settings.barIcon;
        colorByType = settings.colorByType;
        hidePermanent = settings.hidePermanent;
        hidden = (not onlyMode) and settingsRoot.hidden or nil;
        only = onlyMode and settingsRoot.shown or nil;
        important = settingsRoot.important;
    };
end

local function AreaSize(key)
    return Grommey.TimerBars.Bars(nil, GridSettings(key)):GetAreaSize();
end

-- Under the middle of the screen: buffs on the left, debuffs on the right
local function DefaultX(key)
    return function()
        local width = AreaSize(key);
        local middle = math.floor(Turbine.UI.Display.GetWidth() / 2);
        if (key == "buffs") then return middle - AREA_GAP / 2 - width; end
        return middle + AREA_GAP / 2;
    end
end

local function DefaultY()
    return math.floor(Turbine.UI.Display.GetHeight() * 0.58);
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
    Grommey.Movers.Unregister("timerbars:" .. key);
    area:SetVisible(false);
    areas[key] = nil;
end

local function CreateArea(key)
    local area = Turbine.UI.Window();
    area:SetMouseVisible(false);
    area.grid = Grommey.TimerBars.Bars(area, GridSettings(key));

    area.nextTimes = 0;
    area:SetWantsUpdates(true);
    area.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (now >= area.nextTimes) then
            area.nextTimes = now + UPDATE_DELAY;
            area.grid:UpdateTimes();
        end
    end

    area.grid:SetUnit(UnitForEffects());
    area:SetSize(area.grid:GetAreaSize());
    area:SetVisible(not Grommey.HudHidden);
    areas[key] = area;

    local name = (key == "buffs") and L("Buff bars") or L("Debuff bars");
    Grommey.Movers.Register("timerbars:" .. key, area, name, DefaultX(key), DefaultY);
end

local function Build()
    for _, key in ipairs(AREA_KEYS) do
        -- A new size keeps in place the side the area grows from
        local area = areas[key];
        local old = nil;
        if (area) then
            local width, height = area:GetSize();
            old = { left = area:GetLeft(); top = area:GetTop(); width = width; height = height; };
        end
        DestroyArea(key);
        if (settingsRoot[key].enabled) then
            CreateArea(key);
            Grommey.Movers.KeepEdges("timerbars:" .. key, areas[key], old, false, settingsRoot[key].lines == "up");
        end
    end
end

local function SetPreview(enabled)
    if (preview == enabled) then return; end
    preview = enabled;
    Build();
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Options

local selectedArea = "debuffs";

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

local function BuildOptions(page, width, settings)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    local function Reopen() Grommey.Options.ShowPage("module:TimerBars"); end
    local function Changed() Grommey.Profiles.RequestSave(); Build(); end

    UI.Header(page, 0, 16, width, L("Timer bars"));
    -- Fake effects to set everything up without buffs
    UI.Button(page, width - 200, 12, 200, preview and L("Preview: on") or L("Preview: off"), function()
        SetPreview(not preview);
        Reopen();
    end, preview and "accent" or nil);

    local x = 0;
    local sections = { { key = "debuffs"; text = L("Debuffs"); }, { key = "buffs"; text = L("Buffs"); }, { key = "filters"; text = L("Filters"); } };
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
        Grommey.Auras.BuildFilterOptions(holder, width, settings, function() Changed(); Reopen(); end, true);
        return;
    end

    local area = settings[selectedArea];
    local y = 100;
    UI.Toggle(page, 0, y, half, L("Show these bars"), area.enabled, function(value) area.enabled = value; Changed(); end);
    if (selectedArea == "debuffs") then
        UI.Toggle(page, right, y, half, L("Bar colour by type"), area.colorByType, function(value) area.colorByType = value; Changed(); end);
    end
    UI.Toggle(page, 0, y + 32, width, L("Hide permanent effects (no duration or an hour and more)"), area.hidePermanent == true, function(value)
        area.hidePermanent = value;
        Changed();
    end);
    y = y + 74;

    UI.Slider(page, 0, y, half, L("Bar width"), 100, 400, 10, area.barWidth, function(value) area.barWidth = value; Changed(); end, " px");
    UI.Slider(page, right, y, half, L("Bar height"), 14, 40, 1, area.barHeight, function(value) area.barHeight = value; Changed(); end, " px");
    y = y + 54;
    UI.Slider(page, 0, y, half, L("Maximum bars"), 1, 40, 1, area.max, function(value) area.max = value; Changed(); end);
    UI.Slider(page, right, y, half, L("Space between bars"), 0, 12, 1, area.spacing, function(value) area.spacing = value; Changed(); end, " px");
    y = y + 54;
    UI.Label(page, 0, y, half, 18, L("New bars"));
    UI.Dropdown(page, 0, y + 20, half, Translated({
        { value = "down"; text = "Downward"; }, { value = "up"; text = "Upward"; },
    }), area.lines, function(value) area.lines = value; Changed(); end);
    UI.Toggle(page, right, y + 20, half, L("Icon on the left of the bar"), area.barIcon ~= false, function(value) area.barIcon = value; Changed(); end);
    y = y + 70;

    UI.Note(page, 0, y, width, L("The bar empties as the effect runs out: the soonest to end comes first, the important ones before all. Place the bars with the move mode. The filters let you keep only the effects you want."));
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Module

Grommey.Modules.Register({
    id = "TimerBars";
    category = "effects";
    name = "Timer bars";
    description = "Your buffs and debuffs as bars that empty as they run out.";
    enabledByDefault = true;
    defaults = {
        buffs = { enabled = true; lines = "down"; max = 8; spacing = 2; barWidth = 220; barHeight = 22; barIcon = true; colorByType = false; hidePermanent = true; };
        debuffs = { enabled = true; lines = "down"; max = 8; spacing = 2; barWidth = 220; barHeight = 22; barIcon = true; colorByType = true; hidePermanent = true; };
        -- Effect name = true, for both areas
        filterMode = "all";
        hidden = {};
        important = {};
        shown = {};
    };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();
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
});

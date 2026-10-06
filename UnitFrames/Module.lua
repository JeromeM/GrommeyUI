-- Unit frames module: player, target and party frames replacing the game ones.

local UF = Grommey.UnitFrames;
local LotroUI = Turbine.UI.Lotro.LotroUI;
local Element = Turbine.UI.Lotro.LotroUIElement;

local frames = {};      -- key = frame object
local settingsRoot = nil;
local player = nil;
local targetCallback = nil;
local previewBeforeMove = false;

-- Every frame of the module, in the order they are built
local FRAME_KEYS = { "player", "target", "targettarget", "party" };

-- Game window replaced by each frame
local NativeElement = { player = "Vitals"; target = "Target"; party = "Party"; };

local function SetNative(key, enabled)
    local element = Element[NativeElement[key]];
    if (element ~= nil) then pcall(LotroUI.SetEnabled, element, enabled); end
end

local function ScreenWidth() return Turbine.UI.Display.GetWidth(); end
local function ScreenHeight() return Turbine.UI.Display.GetHeight(); end

local function CreateFrame(key)
    local settings = settingsRoot[key];
    if (key == "player") then
        frames.player = UF.UnitFrame("player", L("Player"), settings,
            function() return player; end,
            function() return math.floor(ScreenWidth() / 2) - settings.width - 140; end,
            function() return math.floor(ScreenHeight() * 0.68); end);
    elseif (key == "target") then
        frames.target = UF.UnitFrame("target", L("Target"), settings,
            function() return player:GetTarget(); end,
            function() return math.floor(ScreenWidth() / 2) + 140; end,
            function() return math.floor(ScreenHeight() * 0.68); end);
    elseif (key == "targettarget") then
        -- The target of the target, when the game tells it (the frame stays hidden otherwise)
        frames.targettarget = UF.UnitFrame("targettarget", L("Target of target"), settings,
            function()
                local target = player:GetTarget();
                if (target == nil or target.GetTarget == nil) then return nil; end
                local ok, unit = pcall(target.GetTarget, target);
                return ok and unit or nil;
            end,
            function() return math.floor(ScreenWidth() / 2) + 140 + settingsRoot.target.width + 12; end,
            function() return math.floor(ScreenHeight() * 0.68); end);
    elseif (key == "party") then
        frames.party = UF.PartyFrames(settings,
            function() return 40; end,
            function() return math.floor(ScreenHeight() * 0.30); end);
    end
    SetNative(key, false);
end

local function DestroyFrame(key)
    if (frames[key]) then frames[key]:Destroy(); frames[key] = nil; end
    SetNative(key, true);
end

-- Applies the settings of one frame: creates, removes or lays it out again
-- Unit of a frame, for its free bars
local function UnitGetter(key)
    if (key == "target") then return function() return player:GetTarget(); end; end
    return function() return player; end;
end

local function Apply(key)
    local settings = settingsRoot[key];
    if (key == "player" or key == "target") then UF.FreeResource.Apply(key, settings, UnitGetter(key)); end
    if (not settings.enabled) then DestroyFrame(key); return; end
    if (frames[key] == nil) then CreateFrame(key); return; end
    if (key == "party") then frames.party:Relayout(); else frames[key]:UpdateUnit(); end
end

-- Copy of the player settings for the target, left and right swapped
local function MirrorPlayerToTarget()
    local copy = Grommey.DeepCopy(settingsRoot.player);
    copy.mirrored = not settingsRoot.player.mirrored;
    copy.showResource = false;
    local swap = { left = "right"; right = "left"; };
    copy.effects.position = swap[copy.effects.position] or copy.effects.position;
    copy.effects.growth = swap[copy.effects.growth] or copy.effects.growth;
    copy.enabled = settingsRoot.target.enabled;
    -- Keep the same table so the frame sees the new values
    for name in pairs(settingsRoot.target) do settingsRoot.target[name] = nil; end
    for name, value in pairs(copy) do settingsRoot.target[name] = value; end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Options

local FrameChoices = {
    { value = "player"; text = "Player"; };
    { value = "target"; text = "Target"; };
    { value = "targettarget"; text = "Target of target"; };
    { value = "party"; text = "Party"; };
};

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

local selectedFrame = "player";
local selectedSection = "general";

-- Builds the controls of one section of one frame
local function BuildFrameOptions(page, width, key, section)
    local UI = Grommey.UI;
    local settings = settingsRoot[key];
    local half = math.floor((width - 30) / 2);
    local right = half + 30;

    local function Changed()
        Grommey.Profiles.RequestSave();
        Apply(key);
    end
    local function LabeledDropdown(x, y, text, items, value, onChange)
        UI.Label(page, x, y, half, 18, text);
        UI.Dropdown(page, x, y + 20, half, Translated(items), value, onChange);
        return 52;
    end

    -- Player and target: general, morale, power and resource each in a section of their own
    if (section == "general") then
        UI.Toggle(page, 0, 0, half, L("Show this frame"), settings.enabled, function(value) settings.enabled = value; Changed(); end);
        if (key == "target") then
            UI.Button(page, right, -2, half, L("Copy the player, mirrored"), function()
                MirrorPlayerToTarget();
                if (frames.target) then frames.target:Destroy(); frames.target = nil; end
                Changed();
                Grommey.Options.ShowPage("module:UnitFrames");
            end, "accent");
        end
        UI.Toggle(page, 0, 30, half, L("Mirrored (right to left)"), settings.mirrored, function(value) settings.mirrored = value; Changed(); end);
        UI.Toggle(page, right, 30, half, L("Name and level"), settings.showName, function(value) settings.showName = value; Changed(); end);
        UI.Slider(page, 0, 72, half, L("Width"), 100, 400, 10, settings.width, function(value) settings.width = value; Changed(); end, " px");
        UI.Slider(page, right, 72, half, L("Space between bars"), 0, 20, 1, settings.barGap or 2, function(value) settings.barGap = value; Changed(); end, " px");
        -- Morale and power glide to their new value instead of jumping
        UI.Toggle(page, 0, 130, width, L("Smooth bars (morale and power glide to their new value)"), settings.smoothBars == true, function(value) settings.smoothBars = value; Changed(); end);
        return;
    elseif (section == "morale") then
        UI.Slider(page, 0, 0, half, L("Morale height"), 6, 40, 1, settings.moraleHeight, function(value) settings.moraleHeight = value; Changed(); end, " px");
        LabeledDropdown(right, 0, L("Morale text"), UF.TextModes, settings.moraleText, function(value) settings.moraleText = value; Changed(); end);
        return;
    elseif (section == "power" or section == "resource") then
        local power = (section == "power");
        local function Reopen() Grommey.Options.ShowPage("module:UnitFrames"); end
        if (power) then
            UI.Toggle(page, 0, 0, half, L("Power bar"), settings.showPower, function(value) settings.showPower = value; Changed(); Reopen(); end);
            UI.Slider(page, right, 0, half, L("Power height"), 2, 30, 1, settings.powerHeight, function(value) settings.powerHeight = value; Changed(); end, " px");
            LabeledDropdown(0, 50, L("Power text"), UF.TextModes, settings.powerText, function(value) settings.powerText = value; Changed(); end);
        else
            UI.Toggle(page, 0, 0, half, L("Class resource"), settings.showResource, function(value) settings.showResource = value; Changed(); Reopen(); end);
            UI.Slider(page, right, 0, half, L("Resource height"), 4, 30, 1, settings.resourceHeight or 8, function(value) settings.resourceHeight = value; Changed(); end, " px");
        end
        local shown = power and settings.showPower or (not power and settings.showResource);
        if (not shown) then return; end

        -- Free bar: out of the frame, in a window of its own placed with the move mode
        local y = 118;
        UI.Separator(page, 0, y, width);
        y = y + 16;
        local freeKey, widthKey, heightKey, combatKey = "powerFree", "powerFreeWidth", "powerFreeHeight", "powerFreeCombat";
        if (not power) then freeKey, widthKey, heightKey, combatKey = "resourceFree", "freeWidth", "freeHeight", "freeCombatOnly"; end
        UI.Toggle(page, 0, y, width, L("Free bar (placed on its own)"), settings[freeKey] == true, function(value)
            settings[freeKey] = value;
            Changed();
            Reopen();
        end);
        y = y + 36;
        if (settings[freeKey]) then
            UI.Slider(page, 0, y, half, L("Width"), 40, 400, 10, settings[widthKey] or 200, function(value) settings[widthKey] = value; Changed(); end, " px");
            UI.Slider(page, right, y, half, L("Height"), 4, 40, 1, settings[heightKey] or 10, function(value) settings[heightKey] = value; Changed(); end, " px");
            y = y + 54;
            UI.Button(page, 0, y, half, L("Same width as the morale"), function()
                settings[widthKey] = settings.width;
                Changed();
                Reopen();
            end, "accent");
            UI.Toggle(page, right, y + 2, half, L("In combat only"), settings[combatKey] == true, function(value) settings[combatKey] = value; Changed(); end);
            y = y + 44;
            UI.Note(page, 0, y, width, L("Place the free bar with the move mode. It leaves the frame, which gets smaller."));
        end
        return;
    end

    if (section == "bars") then
        local y = 0;
        UI.Toggle(page, 0, y, half, L("Show this frame"), settings.enabled, function(value) settings.enabled = value; Changed(); end);
        if (key == "target") then
            UI.Button(page, right, y - 2, half, L("Copy the player, mirrored"), function()
                MirrorPlayerToTarget();
                -- The effects settings are a new table, build the frame again around them
                if (frames.target) then frames.target:Destroy(); frames.target = nil; end
                Changed();
                Grommey.Options.ShowPage("module:UnitFrames");
            end, "accent");
        end
        UI.Toggle(page, 0, y + 30, half, L("Mirrored (right to left)"), settings.mirrored, function(value) settings.mirrored = value; Changed(); end);
        -- Both columns start under the note of the target of target, when there is one
        local top = 76;
        if (key == "targettarget") then
            local note = UI.Note(page, 0, 64, width, L("Shown when the game tells who your target is targeting. If it never shows up, the game does not give it."));
            top = 64 + note:GetHeight() + 14;
        end

        -- Left column: size and name
        y = top;
        UI.Slider(page, 0, y, half, L("Width"), 100, 400, 10, settings.width, function(value) settings.width = value; Changed(); end, " px");
        UI.Toggle(page, 0, y + 54, half, L("Name and level"), settings.showName, function(value) settings.showName = value; Changed(); end);
        UI.Slider(page, 0, y + 84, half, L("Space between bars"), 0, 20, 1, settings.barGap or 2, function(value) settings.barGap = value; Changed(); end, " px");
        if (key == "player") then
            UI.Toggle(page, 0, y + 138, half, L("Class resource"), settings.showResource, function(value) settings.showResource = value; Changed(); end);
        end

        -- Right column: the two bars
        y = top;
        UI.Slider(page, right, y, half, L("Morale height"), 6, 40, 1, settings.moraleHeight, function(value) settings.moraleHeight = value; Changed(); end, " px"); y = y + 46;
        y = y + LabeledDropdown(right, y, L("Morale text"), UF.TextModes, settings.moraleText, function(value) settings.moraleText = value; Changed(); end);
        UI.Toggle(page, right, y, half, L("Power bar"), settings.showPower, function(value) settings.showPower = value; Changed(); end); y = y + 30;
        UI.Slider(page, right, y, half, L("Power height"), 2, 30, 1, settings.powerHeight, function(value) settings.powerHeight = value; Changed(); end, " px"); y = y + 46;
        LabeledDropdown(right, y, L("Power text"), UF.TextModes, settings.powerText, function(value) settings.powerText = value; Changed(); end);

    elseif (section == "effects" and key == "party") then
        local y = 0;
        y = y + LabeledDropdown(0, y, L("Arrangement"), {
            { value = "vertical"; text = "One under the other"; };
            { value = "horizontal"; text = "Side by side"; };
        }, settings.layout, function(value) settings.layout = value; Changed(); end);
        UI.Slider(page, 0, y, half, L("Spacing"), 0, 30, 1, settings.spacing, function(value) settings.spacing = value; Changed(); end, " px");
        UI.Toggle(page, 0, y + 54, half, L("Include me"), settings.showPlayer, function(value) settings.showPlayer = value; Changed(); end);

    elseif (section == "effects") then
        local effects = settings.effects;
        local y = 0;
        UI.Toggle(page, 0, y, half, L("Show buffs and debuffs"), effects.show, function(value) effects.show = value; Changed(); end);
        UI.Toggle(page, 0, y + 30, half, L("Debuffs first"), effects.debuffsFirst, function(value) effects.debuffsFirst = value; Changed(); end);
        y = 76;
        y = y + LabeledDropdown(0, y, L("Position"), UF.EffectPositions, effects.position, function(value) effects.position = value; Changed(); end);
        LabeledDropdown(0, y, L("Direction"), UF.EffectGrowths, effects.growth, function(value) effects.growth = value; Changed(); end);
        y = 76;
        UI.Slider(page, right, y, half, L("Icons per line"), 2, 20, 1, effects.perLine, function(value) effects.perLine = value; Changed(); end); y = y + 50;
        UI.Slider(page, right, y, half, L("Maximum icons"), 1, 40, 1, effects.max, function(value) effects.max = value; Changed(); end); y = y + 50;
        UI.Slider(page, right, y, half, L("Space between icons"), 0, 12, 1, effects.spacing or 2, function(value) effects.spacing = value; Changed(); end, " px");

    elseif (section == "text") then
        -- A row of colour squares with the colour name under each
        local function ColorRow(y, text, settingName)
            UI.Label(page, 0, y, width, 20, text);
            local x = 0;
            for _, color in ipairs(UF.TextColors) do
                local preview = color.key == "accent" and Grommey.Profile.theme.accent or color;
                UI.Swatch(page, x + 8, y + 24, 30, preview, function()
                    settings[settingName] = color.key;
                    Changed();
                    Grommey.Options.ShowPage("module:UnitFrames");
                end, function() return (settings[settingName] or "white") == color.key; end);
                UI.Label(page, x - 6, y + 56, 58, 16, L(color.name), { size = 12; role = "dim"; align = Turbine.UI.ContentAlignment.MiddleCenter; });
                x = x + 64;
            end
            return 84;
        end

        local y = 0;
        -- Morale bar: a mode, and the fixed colour when that mode is used
        y = y + LabeledDropdown(0, y, L("Morale bar colour"), UF.MoraleColorModes, settings.moraleColorMode or "fixed", function(value)
            settings.moraleColorMode = value;
            Changed();
            Grommey.Options.ShowPage("module:UnitFrames");
        end);
        local mode = settings.moraleColorMode or "fixed";
        -- The fixed colour is also used by "class" and "level" when they have nothing to go on
        if (mode == "fixed" or mode == "class" or mode == "level") then
            local x = 0;
            for _, color in ipairs(UF.BarColors) do
                UI.Swatch(page, x + 8, y, 26, color, function()
                    settings.moraleColor = color.key;
                    Changed();
                    Grommey.Options.ShowPage("module:UnitFrames");
                end, function() return (settings.moraleColor or "green") == color.key; end);
                x = x + 40;
            end
            y = y + 36;
        end
        y = y + 6;
        y = y + ColorRow(y, L("Name and level colour"), "nameColor");
        y = y + ColorRow(y, L("Bar text colour"), "textColor");
        LabeledDropdown(0, y + 6, L("Text style"), UF.TextStyles(), settings.textStyle or "outline", function(value) settings.textStyle = value; Changed(); end);
    end
end

local function BuildOptions(page, width, settings)
    local UI = Grommey.UI;
    UI.Header(page, 0, 16, width, L("Unit frames"));
    -- Fake target, party and effects to set everything up while solo
    UI.Button(page, width - 200, 12, 200, UF.Preview and L("Preview: on") or L("Preview: off"), function()
        UF.SetPreview(not UF.Preview);
        Grommey.Options.ShowPage("module:UnitFrames");
    end, UF.Preview and "accent" or nil);

    -- Which frame, then which section of its settings
    UI.Dropdown(page, 0, 52, 170, Translated(FrameChoices), selectedFrame, function(value)
        selectedFrame = value;
        Grommey.Options.ShowPage("module:UnitFrames");
    end);

    -- Player and target: a section for each bar; the others keep their bars together
    local sections;
    if (selectedFrame == "player" or selectedFrame == "target") then
        sections = { { key = "general"; text = L("General"); }, { key = "morale"; text = L("Morale"); }, { key = "power"; text = L("Power"); } };
        if (selectedFrame == "player") then table.insert(sections, { key = "resource"; text = L("Resource"); }); end
    else
        sections = { { key = "bars"; text = L("Bars"); } };
    end
    table.insert(sections, { key = "effects"; text = (selectedFrame == "party") and L("Party") or L("Effects"); });
    table.insert(sections, { key = "text"; text = L("Colours"); });
    local known = false;
    for _, section in ipairs(sections) do if (section.key == selectedSection) then known = true; end end
    if (not known) then selectedSection = sections[1].key; end

    -- The sections on their own line, under the frame choice
    local x = 0;
    local buttonWidth = math.floor((width - 8 * (#sections - 1)) / #sections);
    for _, section in ipairs(sections) do
        UI.Button(page, x, 90, buttonWidth, section.text, function()
            selectedSection = section.key;
            Grommey.Options.ShowPage("module:UnitFrames");
        end, (selectedSection == section.key) and "accent" or nil);
        x = x + buttonWidth + 8;
    end

    local holder = Turbine.UI.Control();
    holder:SetParent(page);
    holder:SetPosition(0, 136);
    holder:SetSize(width, page:GetHeight() - 136);
    BuildFrameOptions(holder, width, selectedFrame, selectedSection);
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Module

local function EffectDefaults(position, growth)
    return { show = true; position = position; growth = growth; size = 26; perLine = 8; max = 16; debuffsFirst = true; };
end

Grommey.Modules.Register({
    id = "UnitFrames";
    name = "Unit frames";
    description = "Player, target and party frames, with buffs and debuffs.";
    enabledByDefault = true;
    defaults = {
        player = {
            enabled = true; mirrored = false; width = 240; showName = true;
            moraleHeight = 22; moraleText = "both"; showPower = true; powerHeight = 10; powerText = "number";
            showResource = true; resourceHeight = 8; barGap = 2;
            resourceFree = false; freeWidth = 200; freeHeight = 12; freeCombatOnly = false;
            powerFree = false; powerFreeWidth = 200; powerFreeHeight = 8; powerFreeCombat = false;
            nameColor = "white"; textColor = "white"; textStyle = "outline";
            effects = EffectDefaults("bottom", "right");
        };
        target = {
            enabled = true; mirrored = true; width = 240; showName = true;
            moraleHeight = 22; moraleText = "both"; showPower = true; powerHeight = 10; powerText = "number";
            showResource = false; resourceHeight = 8; barGap = 2;
            powerFree = false; powerFreeWidth = 200; powerFreeHeight = 8; powerFreeCombat = false;
            nameColor = "white"; textColor = "white"; textStyle = "outline";
            effects = EffectDefaults("bottom", "left");
        };
        targettarget = {
            enabled = true; mirrored = false; width = 160; showName = true;
            moraleHeight = 14; moraleText = "percent"; showPower = false; powerHeight = 6; powerText = "none";
            showResource = false; resourceHeight = 8; barGap = 2;
            nameColor = "white"; textColor = "white"; textStyle = "outline";
            effects = { show = false; position = "bottom"; growth = "right"; size = 26; perLine = 6; max = 6; debuffsFirst = true; };
        };
        party = {
            enabled = true; mirrored = false; width = 180; showName = true;
            moraleHeight = 18; moraleText = "percent"; showPower = true; powerHeight = 6; powerText = "none";
            showResource = false; layout = "vertical"; spacing = 6; showPlayer = false; barGap = 2;
            nameColor = "white"; textColor = "white"; textStyle = "outline";
        };
    };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();
        for _, key in ipairs(FRAME_KEYS) do
            if (settings[key].enabled) then CreateFrame(key); end
        end
        UF.FreeResource.Apply("player", settings.player, UnitGetter("player"));
        UF.FreeResource.Apply("target", settings.target, UnitGetter("target"));

        targetCallback = Grommey.AddCallback(player, "TargetChanged", function()
            if (frames.target) then frames.target:UpdateUnit(); end
            if (frames.targettarget) then frames.targettarget:UpdateUnit(); end
        end);

        -- Preview on or off: every frame takes its units again
        Grommey.On("UnitFramesPreviewChanged", function()
            for _, key in ipairs(FRAME_KEYS) do
                if (frames[key]) then
                    if (key == "party") then frames.party:CheckMembers(true); else frames[key]:UpdateUnit(); end
                end
            end
        end);

        -- The move mode shows the previews so every frame has its real size
        Grommey.On("MoveModeChanged", function(active)
            if (active) then
                previewBeforeMove = UF.Preview;
                UF.SetPreview(true);
            else
                UF.SetPreview(previewBeforeMove == true);
            end
        end);

        -- Another module changed these settings (the auras hide the player effects)
        Grommey.On("UnitFramesSettingsChanged", function()
            for _, key in ipairs(FRAME_KEYS) do Apply(key); end
        end);

        -- A new accent colour reaches the texts that use it
        Grommey.On("ThemeChanged", function()
            for _, key in ipairs(FRAME_KEYS) do if (frames[key]) then Apply(key); end end
        end);

        -- Hiding the interface (F12) hides the frames too
        Grommey.On("HudToggled", function()
            if (frames.player) then frames.player:UpdateUnit(); end
            if (frames.target) then frames.target:UpdateUnit(); end
            if (frames.targettarget) then frames.targettarget:UpdateUnit(); end
            if (frames.party) then frames.party:CheckMembers(true); end
        end);
    end;

    Disable = function()
        if (targetCallback) then Grommey.RemoveCallback(player, "TargetChanged", targetCallback); targetCallback = nil; end
        for _, key in ipairs(FRAME_KEYS) do DestroyFrame(key); end
        UF.FreeResource.Destroy();
    end;

    BuildOptions = BuildOptions;

    SetupOptions = function(page, width, settings)
        local UI = Grommey.UI;
        UI.Toggle(page, 0, 0, width, L("Player frame"), settings.player.enabled, function(value) settings.player.enabled = value; end);
        UI.Toggle(page, 0, 34, width, L("Target frame"), settings.target.enabled, function(value) settings.target.enabled = value; end);
        UI.Toggle(page, 0, 68, width, L("Target of target"), settings.targettarget.enabled, function(value) settings.targettarget.enabled = value; end);
        UI.Toggle(page, 0, 102, width, L("Party frames"), settings.party.enabled, function(value) settings.party.enabled = value; end);
        UI.Label(page, 0, 146, 300, 18, L("Morale bar colour"));
        UI.Dropdown(page, 0, 166, 300, Translated(UF.MoraleColorModes), settings.player.moraleColorMode or "fixed", function(value)
            for _, key in ipairs(FRAME_KEYS) do settings[key].moraleColorMode = value; end
        end);
        UI.Note(page, 0, 214, width, L("Each frame replaces the game one. Bars, effects and colours are set in the options."));
    end;
});

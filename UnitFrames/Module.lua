-- Unit frames module: player, target and party frames replacing the game ones.

local UF = Grommey.UnitFrames;
local LotroUI = Turbine.UI.Lotro.LotroUI;
local Element = Turbine.UI.Lotro.LotroUIElement;

local frames = {};      -- key = frame object
local settingsRoot = nil;
local player = nil;
local targetCallback = nil;
local previewBeforeMove = false;

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
local function Apply(key)
    local settings = settingsRoot[key];
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
    { value = "party"; text = "Party"; };
};

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

local selectedFrame = "player";
local selectedSection = "bars";

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

        -- Left column: size and name
        y = 76;
        UI.Slider(page, 0, y, half, L("Width"), 100, 400, 10, settings.width, function(value) settings.width = value; Changed(); end, " px");
        UI.Toggle(page, 0, y + 54, half, L("Name and level"), settings.showName, function(value) settings.showName = value; Changed(); end);
        UI.Slider(page, 0, y + 84, half, L("Space between bars"), 0, 20, 1, settings.barGap or 2, function(value) settings.barGap = value; Changed(); end, " px");
        if (key == "player") then
            UI.Toggle(page, 0, y + 138, half, L("Class resource"), settings.showResource, function(value) settings.showResource = value; Changed(); end);
        end

        -- Right column: the two bars
        y = 76;
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

    local sections = {
        { key = "bars"; text = L("Bars"); };
        { key = "effects"; text = (selectedFrame == "party") and L("Party") or L("Effects"); };
        { key = "text"; text = L("Colours"); };
    };
    local x = 190;
    local buttonWidth = math.floor((width - x - 16) / 3);
    for _, section in ipairs(sections) do
        UI.Button(page, x, 52, buttonWidth, section.text, function()
            selectedSection = section.key;
            Grommey.Options.ShowPage("module:UnitFrames");
        end, (selectedSection == section.key) and "accent" or nil);
        x = x + buttonWidth + 8;
    end

    local holder = Turbine.UI.Control();
    holder:SetParent(page);
    holder:SetPosition(0, 100);
    holder:SetSize(width, page:GetHeight() - 100);
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
            nameColor = "white"; textColor = "white"; textStyle = "outline";
            effects = EffectDefaults("bottom", "right");
        };
        target = {
            enabled = true; mirrored = true; width = 240; showName = true;
            moraleHeight = 22; moraleText = "both"; showPower = true; powerHeight = 10; powerText = "number";
            showResource = false; resourceHeight = 8; barGap = 2;
            nameColor = "white"; textColor = "white"; textStyle = "outline";
            effects = EffectDefaults("bottom", "left");
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
        for _, key in ipairs({ "player", "target", "party" }) do
            if (settings[key].enabled) then CreateFrame(key); end
        end

        targetCallback = Grommey.AddCallback(player, "TargetChanged", function()
            if (frames.target) then frames.target:UpdateUnit(); end
        end);

        -- Preview on or off: every frame takes its units again
        Grommey.On("UnitFramesPreviewChanged", function()
            for _, key in ipairs({ "player", "target", "party" }) do
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
            for _, key in ipairs({ "player", "target", "party" }) do Apply(key); end
        end);

        -- A new accent colour reaches the texts that use it
        Grommey.On("ThemeChanged", function()
            for _, key in ipairs({ "player", "target", "party" }) do if (frames[key]) then Apply(key); end end
        end);

        -- Hiding the interface (F12) hides the frames too
        Grommey.On("HudToggled", function()
            if (frames.player) then frames.player:UpdateUnit(); end
            if (frames.target) then frames.target:UpdateUnit(); end
            if (frames.party) then frames.party:CheckMembers(true); end
        end);
    end;

    Disable = function()
        if (targetCallback) then Grommey.RemoveCallback(player, "TargetChanged", targetCallback); targetCallback = nil; end
        for _, key in ipairs({ "player", "target", "party" }) do DestroyFrame(key); end
    end;

    BuildOptions = BuildOptions;
});

Grommey.AddTranslations({
    ["Unit frames"] = "Cadres d'unités",
    ["Player, target and party frames, with buffs and debuffs."] = "Cadres du joueur, de la cible et du groupe, avec buffs et débuffs.",
    ["Player"] = "Joueur",
    ["Target"] = "Cible",
    ["Frame"] = "Cadre",
    ["Place the frames with the move mode."] = "Place les cadres avec le mode déplacement.",
    ["Show this frame"] = "Afficher ce cadre",
    ["Copy the player, mirrored"] = "Copier le joueur en miroir",
    ["Mirrored (right to left)"] = "Miroir (de droite à gauche)",
    ["Bars"] = "Barres",
    ["Width"] = "Largeur",
    ["Name and level"] = "Nom et niveau",
    ["Morale height"] = "Hauteur du moral",
    ["Morale text"] = "Texte du moral",
    ["Power bar"] = "Barre de puissance",
    ["Power height"] = "Hauteur de la puissance",
    ["Power text"] = "Texte de la puissance",
    ["Class resource"] = "Ressource de classe",
    ["Arrangement"] = "Disposition",
    ["One under the other"] = "Les uns sous les autres",
    ["Side by side"] = "Côte à côte",
    ["Spacing"] = "Espacement",
    ["Include me"] = "M'inclure",
    ["Effects"] = "Effets",
    ["Show buffs and debuffs"] = "Afficher buffs et débuffs",
    ["Position"] = "Position",
    ["Direction"] = "Direction",
    ["Icon size"] = "Taille des icônes",
    ["Icons per line"] = "Icônes par ligne",
    ["Maximum icons"] = "Nombre maximum d'icônes",
    ["Debuffs first"] = "Débuffs en premier",
    ["Space between icons"] = "Espace entre les icônes",
    ["Texts"] = "Textes",
    ["Preview: on"] = "Aperçu : activé",
    ["Preview: off"] = "Aperçu : désactivé",
    ["Space between bars"] = "Espace entre les barres",
    ["Shown with fake units and effects. Also on in move mode."] = "Affiche des unités et des effets fictifs. Aussi actif en mode déplacement.",
    ["Name and level colour"] = "Couleur du nom et du niveau",
    ["Bar text colour"] = "Couleur du texte des barres",
    ["Text style"] = "Style du texte",
});

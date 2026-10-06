-- Shared pieces of the unit frames: number formatting and the flat status bar.

Grommey.UnitFrames = Grommey.UnitFrames or {};
local UF = Grommey.UnitFrames;
local Theme = Grommey.Theme;

UF.Colors = {
    morale = Turbine.UI.Color(0.30, 0.78, 0.38);
    power = Turbine.UI.Color(0.27, 0.56, 0.96);
    dead = Turbine.UI.Color(0.45, 0.45, 0.45);
};

-- 152340 -> "152 340" in French, "152,340" in English
function UF.FormatNumber(value)
    value = math.floor((value or 0) + 0.5);
    local separator = Grommey.IsFrench and " " or ",";
    local digits = tostring(math.abs(value));
    local result = string.reverse(string.gsub(string.reverse(digits), "(%d%d%d)", "%1" .. separator));
    if (string.sub(result, 1, 1) == separator) then result = string.sub(result, 2); end
    return (value < 0 and "-" or "") .. result;
end

-- Text of a bar: "none", "number", "percent" or "both"
function UF.BarText(mode, current, maximum)
    if (mode == "none" or maximum == nil or maximum <= 0) then return ""; end
    local percent = math.floor(current / maximum * 100 + 0.5) .. " %";
    if (mode == "percent") then return percent; end
    local numbers = UF.FormatNumber(current) .. " / " .. UF.FormatNumber(maximum);
    if (mode == "number") then return numbers; end
    return numbers .. "   " .. percent;
end

-- Text colours offered in the options, "accent" follows the theme
UF.TextColors = {
    { key = "white"; name = "White"; r = 255; g = 255; b = 255; };
    { key = "grey";  name = "Light grey"; r = 200; g = 202; b = 206; };
    { key = "gold";  name = "Gold"; r = 240; g = 205; b = 110; };
    { key = "accent"; name = "Accent"; };
    { key = "green"; name = "Green"; r = 140; g = 230; b = 140; };
    { key = "blue";  name = "Blue"; r = 140; g = 190; b = 255; };
};

function UF.ResolveColor(key)
    if (key == "accent") then return Theme.Color("accent"); end
    for _, color in ipairs(UF.TextColors) do
        if (color.key == key) then return Turbine.UI.Color(color.r / 255, color.g / 255, color.b / 255); end
    end
    return Turbine.UI.Color(1, 1, 1);
end

-- Fixed colours offered for the morale bar
UF.BarColors = {
    { key = "green";  name = "Green";  r = 77;  g = 199; b = 97;  };
    { key = "red";    name = "Red";    r = 214; g = 69;  b = 65;  };
    { key = "blue";   name = "Blue";   r = 69;  g = 143; b = 245; };
    { key = "gold";   name = "Gold";   r = 226; g = 184; b = 92;  };
    { key = "violet"; name = "Violet"; r = 160; g = 110; b = 230; };
    { key = "grey";   name = "Light grey"; r = 170; g = 172; b = 178; };
};

-- Class colours, by class name as the game spells it (lower case, letters only)
UF.ClassColors = {
    beorning = { 0.66, 0.46, 0.27 };
    brawler = { 0.88, 0.47, 0.25 };
    burglar = { 0.62, 0.46, 0.84 };
    captain = { 0.27, 0.58, 0.92 };
    champion = { 0.86, 0.30, 0.26 };
    guardian = { 0.58, 0.68, 0.80 };
    hunter = { 0.42, 0.78, 0.36 };
    loremaster = { 0.30, 0.82, 0.82 };
    minstrel = { 0.92, 0.66, 0.82 };
    runekeeper = { 0.96, 0.86, 0.36 };
    warden = { 0.64, 0.72, 0.30 };
    mariner = { 0.22, 0.54, 0.74 };
};

-- Colour of a unit's class, nil for monsters, NPCs and unknown classes
function UF.ClassColorOf(unit)
    if (unit == nil or Turbine.Gameplay.Class == nil) then return nil; end
    -- Targeting yourself gives an object without class: use your own character
    local player = Turbine.Gameplay.LocalPlayer.GetInstance();
    if (unit.GetName ~= nil and unit ~= player) then
        local okName, name = pcall(unit.GetName, unit);
        if (okName and name == player:GetName()) then unit = player; end
    end
    if (unit.GetClass == nil) then return nil; end
    local ok, class = pcall(unit.GetClass, unit);
    if (not ok or class == nil) then return nil; end
    for name, value in pairs(Turbine.Gameplay.Class) do
        if (value == class and type(name) == "string") then
            local color = UF.ClassColors[string.lower(string.gsub(name, "[^%a]", ""))];
            if (color) then return Turbine.UI.Color(color[1], color[2], color[3]); end
        end
    end
    return nil;
end

local function FixedBarColor(key)
    for _, color in ipairs(UF.BarColors) do
        if (color.key == key) then return Turbine.UI.Color(color.r / 255, color.g / 255, color.b / 255); end
    end
    return UF.Colors.morale;
end

-- Level difference colours, close to the game scale: grey far below, then green, blue,
-- white at the same level, yellow, orange, red and purple far above
local function LevelColor(difference)
    if (difference <= -10) then return Turbine.UI.Color(0.55, 0.55, 0.55); end
    if (difference <= -5) then return Turbine.UI.Color(0.35, 0.78, 0.35); end
    if (difference <= -2) then return Turbine.UI.Color(0.35, 0.60, 0.95); end
    if (difference <= 1) then return Turbine.UI.Color(0.92, 0.92, 0.92); end
    if (difference <= 3) then return Turbine.UI.Color(0.95, 0.85, 0.30); end
    if (difference <= 5) then return Turbine.UI.Color(0.95, 0.55, 0.20); end
    if (difference <= 8) then return Turbine.UI.Color(0.88, 0.25, 0.22); end
    return Turbine.UI.Color(0.68, 0.35, 0.90);
end

-- Morale bar colour from the frame settings: "fixed", "class", "health", "level" or "accent"
function UF.MoraleColor(settings, ratio, classColor, unit)
    local mode = settings.moraleColorMode or "fixed";
    if (mode == "class" and classColor) then return classColor; end
    if (mode == "level" and unit ~= nil and unit.GetLevel ~= nil) then
        local okUnit, unitLevel = pcall(unit.GetLevel, unit);
        local okMine, myLevel = pcall(function() return Turbine.Gameplay.LocalPlayer.GetInstance():GetLevel(); end);
        if (okUnit and okMine and unitLevel and myLevel) then return LevelColor(unitLevel - myLevel); end
    end
    if (mode == "accent") then return Theme.Color("accent"); end
    if (mode == "health") then
        -- Green above half, then yellow, red when it gets low
        local red, green;
        if (ratio > 0.5) then red, green = (1 - ratio) * 2 * 0.9, 0.78;
        else red, green = 0.9, ratio * 2 * 0.78; end
        return Turbine.UI.Color(red, green, 0.2);
    end
    return FixedBarColor(settings.moraleColor or "green");
end

UF.MoraleColorModes = {
    { value = "fixed"; text = "Fixed colour"; };
    { value = "class"; text = "Class colour"; };
    { value = "health"; text = "Following morale (green to red)"; };
    { value = "level"; text = "Level difference"; };
    { value = "accent"; text = "Theme accent"; };
};

-- Text styles the game offers: outline always, shadow only if the game has it
function UF.TextStyles()
    local styles = { { value = "outline"; text = "Black outline"; } };
    if (Turbine.UI.FontStyle.Shadow ~= nil) then table.insert(styles, { value = "shadow"; text = "Shadow"; }); end
    table.insert(styles, { value = "none"; text = "None"; });
    return styles;
end

-- Applies a style to a label
function UF.ApplyTextStyle(label, style)
    local FontStyle = Turbine.UI.FontStyle;
    if (style == "shadow" and FontStyle.Shadow ~= nil) then
        label:SetFontStyle(FontStyle.Shadow);
    elseif (style == "none") then
        label:SetFontStyle(FontStyle.None or 0);
    else
        label:SetFontStyle(FontStyle.Outline);
    end
    label:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
end

UF.TextModes = {
    { value = "both"; text = "Number and percent"; };
    { value = "number"; text = "Number"; };
    { value = "percent"; text = "Percent"; };
    { value = "none"; text = "Nothing"; };
};

-- Flat bar with a 1 pixel border, a dark background, a coloured fill and centred text
function UF.CreateBar(parent)
    local bar = Turbine.UI.Control();
    bar:SetParent(parent);
    bar:SetMouseVisible(false);

    bar.back = Turbine.UI.Control();
    bar.back:SetParent(bar);
    bar.back:SetPosition(1, 1);
    bar.back:SetMouseVisible(false);

    bar.fill = Turbine.UI.Control();
    bar.fill:SetParent(bar.back);
    bar.fill:SetMouseVisible(false);

    bar.text = Turbine.UI.Label();
    bar.text:SetParent(bar);
    bar.text:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    bar.text:SetFontStyle(Turbine.UI.FontStyle.Outline);
    bar.text:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    bar.text:SetForeColor(Turbine.UI.Color(1, 1, 1));
    bar.text:SetMouseVisible(false);

    bar.ratio = 0;
    bar.color = UF.Colors.morale;

    bar.Paint = function()
        bar:SetBackColor(Theme.Color("border"));
        bar.back:SetBackColor(Theme.Mix("field", "background", 0.5));
        bar.fill:SetBackColor(bar.color);
    end
    Theme.Track(bar.Paint);

    bar.Resize = function(width, height)
        bar:SetSize(width, height);
        bar.back:SetSize(width - 2, height - 2);
        bar.text:SetSize(width, height);
        -- Text size follows the bar height, no text on very thin bars
        bar.text:SetVisible(height >= 10);
        bar.text:SetFont(Theme.Font(height >= 20 and 14 or 12, false));
        bar.SetRatio(bar.ratio, true);
    end

    local function Draw(ratio)
        bar.shown = ratio;
        local width, height = bar.back:GetSize();
        local fillWidth = math.floor(width * ratio + 0.5);
        bar.fill:SetSize(fillWidth, height);
        -- A mirrored bar fills from the right
        bar.fill:SetPosition(bar.mirrored and (width - fillWidth) or 0, 0);
    end

    -- Smooth bars glide to a new value instead of jumping: a little closer on every frame,
    -- fast at first and slower at the end (about a third of a second)
    local SMOOTH_SPEED = 12;
    bar.Update = function()
        local now = Turbine.Engine.GetGameTime();
        local elapsed = math.min(0.1, now - (bar.lastFrame or now));
        bar.lastFrame = now;
        local shown = bar.shown or bar.ratio;
        local step = (bar.ratio - shown) * math.min(1, elapsed * SMOOTH_SPEED);
        if (math.abs(bar.ratio - shown) < 0.002) then
            Draw(bar.ratio);
            bar:SetWantsUpdates(false);
            return;
        end
        Draw(shown + step);
    end

    bar.SetRatio = function(ratio, force)
        ratio = Grommey.Clamp(ratio or 0, 0, 1);
        if (ratio == bar.ratio and not force) then return; end
        bar.ratio = ratio;
        if (bar.smooth and not force and bar.shown ~= nil) then
            bar.lastFrame = Turbine.Engine.GetGameTime();
            bar:SetWantsUpdates(true);
            return;
        end
        bar:SetWantsUpdates(false);
        Draw(ratio);
    end

    bar.SetSmooth = function(smooth)
        bar.smooth = (smooth == true);
    end

    bar.SetMirrored = function(mirrored)
        bar.mirrored = mirrored;
        bar.SetRatio(bar.ratio, true);
    end

    bar.SetColor = function(color)
        bar.color = color;
        bar.fill:SetBackColor(color);
    end

    bar.SetTextStyle = function(color, style)
        bar.text:SetForeColor(color);
        UF.ApplyTextStyle(bar.text, style);
    end

    bar.SetText = function(text)
        if (text ~= bar.lastText) then bar.lastText = text; bar.text:SetText(text); end
    end

    return bar;
end

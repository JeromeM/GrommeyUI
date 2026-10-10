-- Tooltip of the unit frames: name, level and class, morale and power, and who the unit targets.
-- Plugins cannot open the game tooltip of a character, so this one is drawn by GrommeyUI.
-- It follows the unit while the mouse stays over the frame.

local UF = Grommey.UnitFrames;
local Theme = Grommey.Theme;

local WIDTH = 250;
local LINE = 18;
local REFRESH_DELAY = 0.25;

-- Translated class names, by class name as the game spells it (lower case, letters only)
local CLASS_NAMES = {
    beorning = L("Beorning"); brawler = L("Brawler"); burglar = L("Burglar"); captain = L("Captain"); champion = L("Champion");
    guardian = L("Guardian"); hunter = L("Hunter"); loremaster = L("Lore-master"); minstrel = L("Minstrel");
    runekeeper = L("Rune-keeper"); warden = L("Warden"); mariner = L("Mariner");
};

local tooltip = nil;
local shownUnit = nil;

local function Read(object, method)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object);
    if (ok) then return value; end
    return nil;
end

-- Targeting yourself gives an object without class: the character itself stands in for it
local function RealUnit(unit)
    local player = Turbine.Gameplay.LocalPlayer.GetInstance();
    if (unit ~= player and Read(unit, "GetName") == player:GetName()) then return player; end
    return unit;
end

local function ClassName(unit)
    local class = Read(unit, "GetClass");
    if (class == nil) then return nil; end
    for name, value in pairs(Turbine.Gameplay.Class or {}) do
        if (value == class and type(name) == "string") then
            return CLASS_NAMES[string.lower(string.gsub(name, "[^%a]", ""))];
        end
    end
    return nil;
end

-- "Morale: 52 300 / 60 000 (87 %)"
local function VitalLine(text, current, maximum)
    if (current == nil or maximum == nil or maximum <= 0) then return nil; end
    return string.format(L("%s: %s / %s  (%d %%)"), text, UF.FormatNumber(current), UF.FormatNumber(maximum), math.floor(current / maximum * 100 + 0.5));
end

local function Create()
    tooltip = Turbine.UI.Window();
    tooltip:SetZOrder(3000);
    tooltip:SetMouseVisible(false);
    tooltip.frame = Grommey.UI.Frame(tooltip, 0, 0, 10, 10, "raised", "accent");
    tooltip.frame:SetMouseVisible(false);
    tooltip.title = Grommey.UI.Label(tooltip, 10, 6, WIDTH - 20, 20, "", { bold = true; });
    tooltip.lines = {};
    for index = 1, 4 do
        tooltip.lines[index] = Grommey.UI.Label(tooltip, 10, 28 + (index - 1) * LINE, WIDTH - 20, LINE, "", { size = 12; });
    end
    -- The values change while the mouse is over the frame
    tooltip.nextRefresh = 0;
    tooltip.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (now < tooltip.nextRefresh) then return; end
        tooltip.nextRefresh = now + REFRESH_DELAY;
        UF.FillUnitTooltip();
    end
    -- A global keeps the window alive
    Grommey.UnitTooltip = tooltip;
end

function UF.FillUnitTooltip()
    local unit = shownUnit and RealUnit(shownUnit);
    if (unit == nil) then return; end

    tooltip.title:SetText(Read(unit, "GetName") or "");
    tooltip.title:SetForeColor(UF.ClassColorOf(unit) or Theme.Color("accent"));

    -- Level and class, then morale, power and the target of the unit
    local texts = {};
    local level = Read(unit, "GetLevel");
    local class = ClassName(unit);
    local first = level and string.format(L("Level %d"), level) or nil;
    if (class) then first = first and (first .. "  ·  " .. class) or class; end
    if (first) then table.insert(texts, { text = first; role = "dim"; }); end
    local morale = VitalLine(L("Morale"), Read(unit, "GetMorale"), Read(unit, "GetMaxMorale"));
    if (morale) then table.insert(texts, { text = morale; role = "text"; }); end
    local power = VitalLine(L("Power"), Read(unit, "GetPower"), Read(unit, "GetMaxPower"));
    if (power) then table.insert(texts, { text = power; role = "text"; }); end
    local target = Read(unit, "GetTarget");
    local targetName = target and Read(target, "GetName");
    if (targetName) then table.insert(texts, { text = string.format(L("Target: %s"), targetName); role = "accent"; }); end

    for index, label in ipairs(tooltip.lines) do
        local line = texts[index];
        label:SetVisible(line ~= nil);
        if (line) then
            label:SetText(line.text);
            label:SetForeColor(Theme.Color(line.role));
        end
    end
    local height = 34 + #texts * LINE;
    tooltip:SetSize(WIDTH, height);
    tooltip.frame.Resize(WIDTH, height);
end

-- Next to the mouse, above it (the frames sit low on the screen), kept inside the screen
local function Place()
    local ok, mouseX, mouseY = pcall(Turbine.UI.Display.GetMousePosition);
    if (not ok or mouseX == nil) then return; end
    local width, height = tooltip:GetSize();
    local screenWidth, screenHeight = Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
    local x = mouseX + 16;
    if (x + width > screenWidth) then x = mouseX - width - 8; end
    local y = mouseY - height - 8;
    if (y < 0) then y = mouseY + 24; end
    if (y + height > screenHeight) then y = screenHeight - height; end
    tooltip:SetPosition(math.max(0, x), math.max(0, y));
end

function UF.ShowUnitTooltip(unit)
    if (unit == nil) then return; end
    if (tooltip == nil) then Create(); end
    shownUnit = unit;
    UF.FillUnitTooltip();
    Place();
    tooltip.nextRefresh = Turbine.Engine.GetGameTime() + REFRESH_DELAY;
    tooltip:SetWantsUpdates(true);
    tooltip:SetVisible(true);
end

function UF.HideUnitTooltip()
    shownUnit = nil;
    if (tooltip) then
        tooltip:SetWantsUpdates(false);
        tooltip:SetVisible(false);
    end
end

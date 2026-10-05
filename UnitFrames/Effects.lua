-- Effects of a unit (buffs and debuffs) as a grid of icons with their remaining time.
-- settings: show, position ("top", "bottom", "left", "right"), growth ("right", "left", "down", "up"),
--           size (pixels), perLine (icons per line), max (icons shown), debuffsFirst,
--           filter (nil, "buffs" or "debuffs"), timeBelow (time under the icon instead of on it),
--           colorByType (debuff border coloured by disease, fear, poison or wound),
--           hidden / important (effect name = true: never shown / shown first with a theme border),
--           hidePermanent (no effects without a duration or lasting an hour or more)

local UF = Grommey.UnitFrames;
local Theme = Grommey.Theme;

-- Space between two icons when the settings have none
local DEFAULT_SPACING = 2;
-- The game does not scale effect icons (stretching crops them or leaves them at 32 pixels),
-- so they are always shown at their native size with a 1 pixel border
local ICON_BOX = 34;
-- Height of the time line when it is shown under the icon
local TIME_HEIGHT = 14;
-- Effects lasting this long (or without a duration) count as permanent: traits, class auras...
local PERMANENT_DURATION = 3600;

UF.EffectPositions = {
    { value = "bottom"; text = "Below"; };
    { value = "top"; text = "Above"; };
    { value = "left"; text = "Left"; };
    { value = "right"; text = "Right"; };
};

UF.EffectGrowths = {
    { value = "right"; text = "Toward the right"; };
    { value = "left"; text = "Toward the left"; };
    { value = "down"; text = "Downward"; };
    { value = "up"; text = "Upward"; };
};

-- 75 -> "1m", 3700 -> "1h", 12 -> "12"
local function FormatRemaining(seconds)
    if (seconds == nil or seconds <= 0) then return ""; end
    if (seconds >= 3600) then return math.floor(seconds / 3600) .. "h"; end
    if (seconds >= 60) then return math.floor(seconds / 60) .. "m"; end
    return tostring(math.floor(seconds));
end

local function Read(effect, method)
    if (effect == nil or effect[method] == nil) then return nil; end
    local ok, value = pcall(effect[method], effect);
    if (ok) then return value; end
    return nil;
end

-- Debuff border by type, the four kinds the game lets you cure
local TYPE_COLORS = {
    Disease = { r = 196; g = 160; b = 60; };
    Fear = { r = 150; g = 90; b = 220; };
    Poison = { r = 80; g = 190; b = 70; };
    Wound = { r = 232; g = 84; b = 84; };
};

local function BorderColor(entry, settings)
    if (entry.important) then return Theme.Color("accent"); end
    if (not entry.debuff) then return Theme.Color("border"); end
    local categories = Turbine.Gameplay.EffectCategory;
    local category = Read(entry.effect, "GetCategory");
    if (settings.colorByType and categories ~= nil and category ~= nil) then
        for name, color in pairs(TYPE_COLORS) do
            if (categories[name] ~= nil and categories[name] == category) then
                return Turbine.UI.Color(color.r / 255, color.g / 255, color.b / 255);
            end
        end
    end
    return Theme.Color("danger");
end

-- Shared tooltip: name, kind and remaining time, then the description of the effect
local TOOLTIP_WIDTH = 300;
local TYPE_NAMES = { Disease = "Disease"; Fear = "Fear"; Poison = "Poison"; Wound = "Wound"; Corruption = "Corruption"; };
local tooltip = nil;

-- 252 -> "4 min 12 s"
local function FormatLong(seconds)
    seconds = math.floor(seconds);
    if (seconds >= 3600) then return string.format(L("%d h %d min"), math.floor(seconds / 3600), math.floor(seconds / 60) % 60); end
    if (seconds >= 60) then return string.format(L("%d min %d s"), math.floor(seconds / 60), seconds % 60); end
    return string.format(L("%d s"), seconds);
end

local function TypeName(effect)
    local categories = Turbine.Gameplay.EffectCategory;
    local category = Read(effect, "GetCategory");
    if (categories == nil or category == nil) then return nil; end
    for name, text in pairs(TYPE_NAMES) do
        if (categories[name] ~= nil and categories[name] == category) then return L(text); end
    end
    return nil;
end

local function ShowTooltip(icon)
    local effect = icon.effect;
    if (effect == nil) then return; end
    if (tooltip == nil) then
        tooltip = Turbine.UI.Window();
        tooltip:SetZOrder(3000);
        tooltip:SetMouseVisible(false);
        tooltip.frame = Grommey.UI.Frame(tooltip, 0, 0, 10, 10, "raised", "accent");
        tooltip.frame:SetMouseVisible(false);
        tooltip.title = Grommey.UI.Label(tooltip, 10, 6, 10, 20, "", { bold = true; });
        tooltip.info = Grommey.UI.Label(tooltip, 10, 26, 10, 18, "", { size = 12; role = "dim"; });
        tooltip.description = Grommey.UI.Label(tooltip, 10, 48, 10, 10, "", { size = 12; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end

    local name = Read(effect, "GetName") or "";
    local description = Read(effect, "GetDescription") or "";
    description = string.gsub(description, "^%s+", "");
    description = string.gsub(description, "%s+$", "");

    -- Second line: buff or debuff with its type, and the time left
    local info = icon.debuff and L("Debuff") or L("Buff");
    local typeName = icon.debuff and TypeName(effect);
    if (typeName) then info = info .. " - " .. typeName; end
    local duration = Read(effect, "GetDuration") or 0;
    local start = Read(effect, "GetStartTime");
    if (duration > 0 and duration < 86400 and start ~= nil) then
        local left = start + duration - Turbine.Engine.GetGameTime();
        if (left > 0) then info = info .. "  |  " .. FormatLong(left); end
    end

    -- Width from the longest of the short lines, the description wraps
    local width = math.max(string.len(name) * 8, string.len(info) * 7) + 24;
    local height = 50;
    if (description ~= "") then
        width = math.max(width, TOOLTIP_WIDTH);
        local perLine = math.floor((width - 20) / 6.6);
        local lines = 0;
        for paragraph in string.gmatch(description .. "\n", "([^\n]*)\n") do
            lines = lines + math.max(1, math.ceil(string.len(paragraph) / perLine));
        end
        height = 56 + lines * 15;
    end

    tooltip:SetSize(width, height);
    tooltip.frame.Resize(width, height);
    tooltip.title:SetSize(width - 20, 20);
    tooltip.title:SetText(name);
    tooltip.title:SetForeColor(icon.debuff and Theme.Color("danger") or Theme.Color("accent"));
    tooltip.info:SetSize(width - 20, 18);
    tooltip.info:SetText(info);
    tooltip.description:SetSize(width - 20, math.max(1, height - 54));
    tooltip.description:SetText(description);
    tooltip.description:SetVisible(description ~= "");

    -- Next to the mouse, kept inside the screen (the auras sit at the top right)
    local ok, mouseX, mouseY = pcall(Turbine.UI.Display.GetMousePosition);
    if (ok and mouseX) then
        local screenWidth, screenHeight = Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
        local x = mouseX + 16;
        if (x + width > screenWidth) then x = mouseX - width - 8; end
        local y = mouseY - height - 8;
        if (y < 0) then y = mouseY + 24; end
        if (y + height > screenHeight) then y = screenHeight - height; end
        tooltip:SetPosition(math.max(0, x), math.max(0, y));
    end
    tooltip:SetVisible(true);
end

local function HideTooltip()
    if (tooltip) then tooltip:SetVisible(false); end
end

UF.EffectsBar = class(Turbine.UI.Control);

function UF.EffectsBar:Constructor(parent, settings)
    Turbine.UI.Control.Constructor(self);
    self:SetParent(parent);
    self:SetMouseVisible(false);
    self.settings = settings;
    self.icons = {};
    self.callbacks = {};
end

-- Width and height of one icon with its time
function UF.EffectsBar:GetCellSize()
    return ICON_BOX, ICON_BOX + (self.settings.timeBelow and TIME_HEIGHT or 0);
end

-- Size of the area reserved for all the icons, so the frame never jumps when effects come and go
function UF.EffectsBar:GetAreaSize()
    local settings = self.settings;
    local spacing = settings.spacing or DEFAULT_SPACING;
    local cellWidth, cellHeight = self:GetCellSize();
    local lines = math.ceil(settings.max / settings.perLine);
    if (settings.position == "left" or settings.position == "right") then
        return lines * (cellWidth + spacing) - spacing, settings.perLine * (cellHeight + spacing) - spacing;
    end
    return settings.perLine * (cellWidth + spacing) - spacing, lines * (cellHeight + spacing) - spacing;
end

function UF.EffectsBar:SetUnit(unit)
    -- Stop listening to the previous unit
    for _, entry in ipairs(self.callbacks) do Grommey.RemoveCallback(entry.object, entry.eventName, entry.callback); end
    self.callbacks = {};
    self.effects = nil;

    if (unit ~= nil and unit.GetEffects ~= nil) then
        local ok, effects = pcall(unit.GetEffects, unit);
        if (ok and effects ~= nil) then
            self.effects = effects;
            local function Changed() Grommey.Delay(self, 0.05, function() self:Rebuild(); end); end
            for _, eventName in ipairs({ "EffectAdded", "EffectRemoved", "EffectsCleared" }) do
                table.insert(self.callbacks, { object = effects; eventName = eventName; callback = Grommey.AddCallback(effects, eventName, Changed); });
            end
        end
    end
    self:Rebuild();
end

-- Game icons are 32 pixels. The game only scales an image right when a control is set up once,
-- so a new control is made whenever the image or the size changes.
local function SetIconImage(icon, image, size)
    local key = tostring(image) .. ":" .. size;
    if (icon.imageKey == key) then return; end
    icon.imageKey = key;
    if (icon.image) then icon.image:SetParent(nil); icon.image = nil; end
    if (image == nil) then return; end

    local control = Turbine.UI.Control();
    control:SetParent(icon);
    control:SetPosition(1, 1);
    control:SetMouseVisible(false);
    control:SetSize(32, 32);
    control:SetBackground(image);
    icon.image = control;
    -- Keep the time on top of the new image
    icon.timeLabel:SetZOrder(2);
end

local function CreateIcon(bar)
    local icon = Turbine.UI.Control();
    icon:SetParent(bar);

    -- Border behind the image, the time can sit under it
    icon.box = Turbine.UI.Control();
    icon.box:SetParent(icon);
    icon.box:SetSize(ICON_BOX, ICON_BOX);
    icon.box:SetMouseVisible(false);

    -- The game icon control is created in SetIconImage, a fresh one for each image and size

    -- Plain colour square used by the preview instead of an icon
    icon.swatch = Turbine.UI.Control();
    icon.swatch:SetParent(icon);
    icon.swatch:SetPosition(1, 1);
    icon.swatch:SetMouseVisible(false);
    icon.swatch:SetVisible(false);

    icon.timeLabel = Turbine.UI.Label();
    icon.timeLabel:SetParent(icon);
    icon.timeLabel:SetTextAlignment(Turbine.UI.ContentAlignment.BottomCenter);
    icon.timeLabel:SetFontStyle(Turbine.UI.FontStyle.Outline);
    icon.timeLabel:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    icon.timeLabel:SetForeColor(Turbine.UI.Color(1, 1, 1));
    icon.timeLabel:SetMouseVisible(false);

    icon.MouseEnter = function() ShowTooltip(icon); end
    icon.MouseLeave = HideTooltip;
    return icon;
end

-- Reads the effect list and places the icons
function UF.EffectsBar:Rebuild()
    local settings = self.settings;
    local areaWidth, areaHeight = self:GetAreaSize();
    self:SetSize(areaWidth, areaHeight);

    local entries = {};
    if (settings.show and self.effects ~= nil) then
        local count = Read(self.effects, "GetCount") or 0;
        for index = 1, count do
            local ok, effect = pcall(self.effects.Get, self.effects, index);
            if (ok and effect ~= nil) then
                local debuff = Read(effect, "IsDebuff") == true;
                local name = Read(effect, "GetName") or "";
                local duration = Read(effect, "GetDuration") or 0;
                local permanent = (duration <= 0 or duration >= PERMANENT_DURATION);
                local wanted = (settings.filter == nil or (settings.filter == "debuffs") == debuff)
                    and not (settings.hidden and settings.hidden[name])
                    and not (settings.hidePermanent and permanent);
                if (wanted) then
                    local important = (settings.important ~= nil and settings.important[name] == true);
                    table.insert(entries, { effect = effect; debuff = debuff; important = important; order = index; });
                end
            end
        end
        -- Important effects first, then debuffs when asked, then the game order
        table.sort(entries, function(a, b)
            if (a.important ~= b.important) then return a.important; end
            if (settings.debuffsFirst and a.debuff ~= b.debuff) then return a.debuff; end
            return a.order < b.order;
        end);
    end

    local size = ICON_BOX;
    local spacing = settings.spacing or DEFAULT_SPACING;
    local cellWidth, cellHeight = self:GetCellSize();
    local stepX, stepY = cellWidth + spacing, cellHeight + spacing;
    local shown = math.min(#entries, settings.max);
    local vertical = (settings.position == "left" or settings.position == "right");

    for index = 1, math.max(shown, #self.icons) do
        local icon = self.icons[index];
        if (index > shown) then
            if (icon) then icon:SetVisible(false); icon.effect = nil; end
        else
            if (icon == nil) then icon = CreateIcon(self); self.icons[index] = icon; end
            local entry = entries[index];
            icon.effect = entry.effect;
            icon.debuff = entry.debuff;

            icon:SetSize(cellWidth, cellHeight);
            icon.box:SetBackColor(BorderColor(entry, settings));
            local image = Read(entry.effect, "GetIcon");
            local previewColor = Read(entry.effect, "GetPreviewColor");
            SetIconImage(icon, image, size - 2);
            icon.swatch:SetSize(size - 2, size - 2);
            icon.swatch:SetBackColor(previewColor or Theme.Color("raised"));
            icon.swatch:SetVisible(image == nil);
            if (settings.timeBelow) then
                icon.timeLabel:SetPosition(0, size);
                icon.timeLabel:SetSize(cellWidth, TIME_HEIGHT);
                icon.timeLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
            else
                icon.timeLabel:SetPosition(0, 0);
                icon.timeLabel:SetSize(size, size - 1);
                icon.timeLabel:SetTextAlignment(Turbine.UI.ContentAlignment.BottomCenter);
            end
            icon.timeLabel:SetFont(Theme.Font(12, false));

            -- Position along the line and line number, then flip for the chosen growth
            local slot = (index - 1) % settings.perLine;
            local line = math.floor((index - 1) / settings.perLine);
            local x, y;
            if (vertical) then
                y = (settings.growth == "up") and (areaHeight - cellHeight - slot * stepY) or (slot * stepY);
                x = (settings.position == "left") and (areaWidth - cellWidth - line * stepX) or (line * stepX);
            else
                x = (settings.growth == "left") and (areaWidth - cellWidth - slot * stepX) or (slot * stepX);
                y = (settings.position == "top") and (areaHeight - cellHeight - line * stepY) or (line * stepY);
            end
            icon:SetPosition(x, y);
            icon:SetVisible(true);
        end
    end
    self:UpdateTimes();
end

-- Remaining times, called twice a second by the frame
function UF.EffectsBar:UpdateTimes()
    local now = Turbine.Engine.GetGameTime();
    for _, icon in ipairs(self.icons) do
        if (icon.effect ~= nil) then
            local duration = Read(icon.effect, "GetDuration") or 0;
            local start = Read(icon.effect, "GetStartTime") or now;
            -- Very long effects (passives, auras) show no time
            local text = "";
            if (duration > 0 and duration < 86400) then text = FormatRemaining(start + duration - now); end
            if (text ~= icon.lastTime) then icon.lastTime = text; icon.timeLabel:SetText(text); end
        end
    end
end

function UF.EffectsBar:Destroy()
    self:SetUnit(nil);
    HideTooltip();
end

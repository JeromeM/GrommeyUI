-- Effects of a unit (buffs and debuffs) as a grid of icons with their remaining time.
-- settings: show, position ("top", "bottom", "left", "right"), growth ("right", "left", "down", "up"),
--           size (pixels), perLine (icons per line), max (icons shown), debuffsFirst

local UF = Grommey.UnitFrames;
local Theme = Grommey.Theme;

-- Space between two icons when the settings have none
local DEFAULT_SPACING = 2;
-- The game does not scale effect icons (stretching crops them or leaves them at 32 pixels),
-- so they are always shown at their native size with a 1 pixel border
local ICON_BOX = 34;

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

-- Shared tooltip with the effect name
local tooltip = nil;
local function ShowTooltip(text)
    if (tooltip == nil) then
        tooltip = Turbine.UI.Window();
        tooltip:SetZOrder(3000);
        tooltip:SetMouseVisible(false);
        tooltip.frame = Grommey.UI.Frame(tooltip, 0, 0, 10, 10, "raised", "accent");
        tooltip.frame:SetMouseVisible(false);
        tooltip.label = Grommey.UI.Label(tooltip, 8, 0, 10, 24, "");
    end
    local width = 16 + string.len(text) * 7;
    tooltip:SetSize(width, 24);
    tooltip.frame.Resize(width, 24);
    tooltip.label:SetSize(width - 16, 24);
    tooltip.label:SetText(text);
    local ok, mouseX, mouseY = pcall(Turbine.UI.Display.GetMousePosition);
    if (ok and mouseX) then tooltip:SetPosition(mouseX + 16, mouseY - 30); end
    tooltip:SetVisible(true);
end

local function HideTooltip()
    if (tooltip) then tooltip:SetVisible(false); end
end

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

UF.EffectsBar = class(Turbine.UI.Control);

function UF.EffectsBar:Constructor(parent, settings)
    Turbine.UI.Control.Constructor(self);
    self:SetParent(parent);
    self:SetMouseVisible(false);
    self.settings = settings;
    self.icons = {};
    self.callbacks = {};
end

-- Size of the area reserved for all the icons, so the frame never jumps when effects come and go
function UF.EffectsBar:GetAreaSize()
    local settings = self.settings;
    local spacing = settings.spacing or DEFAULT_SPACING;
    local step = ICON_BOX + spacing;
    local lines = math.ceil(settings.max / settings.perLine);
    local along = settings.perLine * step - spacing;
    local across = lines * step - spacing;
    if (settings.position == "left" or settings.position == "right") then return across, along; end
    return along, across;
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

    icon.MouseEnter = function() if (icon.effectName) then ShowTooltip(icon.effectName); end end
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
                table.insert(entries, { effect = effect; debuff = Read(effect, "IsDebuff") == true; order = index; });
            end
        end
        if (settings.debuffsFirst) then
            table.sort(entries, function(a, b)
                if (a.debuff ~= b.debuff) then return a.debuff; end
                return a.order < b.order;
            end);
        end
    end

    local size = ICON_BOX;
    local step = size + (settings.spacing or DEFAULT_SPACING);
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
            icon.effectName = Read(entry.effect, "GetName");

            icon:SetSize(size, size);
            icon:SetBackColor(entry.debuff and Theme.Color("danger") or Theme.Color("border"));
            local image = Read(entry.effect, "GetIcon");
            local previewColor = Read(entry.effect, "GetPreviewColor");
            SetIconImage(icon, image, size - 2);
            icon.swatch:SetSize(size - 2, size - 2);
            icon.swatch:SetBackColor(previewColor or Theme.Color("raised"));
            icon.swatch:SetVisible(image == nil);
            icon.timeLabel:SetSize(size, size - 1);
            icon.timeLabel:SetFont(Theme.Font(size >= 28 and 12 or 10, false));

            -- Position along the line and line number, then flip for the chosen growth
            local slot = (index - 1) % settings.perLine;
            local line = math.floor((index - 1) / settings.perLine);
            local x, y;
            if (vertical) then
                y = (settings.growth == "up") and (areaHeight - size - slot * step) or (slot * step);
                x = (settings.position == "left") and (areaWidth - size - line * step) or (line * step);
            else
                x = (settings.growth == "left") and (areaWidth - size - slot * step) or (slot * step);
                y = (settings.position == "top") and (areaHeight - size - line * step) or (line * step);
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

Grommey.AddTranslations({
    ["Below"] = "En dessous",
    ["Above"] = "Au-dessus",
    ["Left"] = "À gauche",
    ["Right"] = "À droite",
    ["Toward the right"] = "Vers la droite",
    ["Toward the left"] = "Vers la gauche",
    ["Downward"] = "Vers le bas",
    ["Upward"] = "Vers le haut",
});

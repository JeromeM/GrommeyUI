-- Effects of a unit as timer bars: the name in the bar, the time left on the right and the bar
-- emptying as the effect runs out. Same filters as UF.EffectsBar, plus these settings:
-- barWidth, barHeight, barIcon (the 32 pixel game icon on the left), lines ("down" or "up"),
-- spacing, max, colorByType.
-- Used by the TimerBars module.

local UF = Grommey.UnitFrames;
local Theme = Grommey.Theme;

Grommey.TimerBars = Grommey.TimerBars or {};

-- The game does not scale effect icons: they stay at 32 pixels with a 1 pixel border
local ICON_BOX = 34;
local ICON_GAP = 4;
local TEXT_PAD = 6;
local LONG_EFFECT = 86400;

local function Read(object, method)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object);
    if (ok) then return value; end
    return nil;
end

-- 4.2 under ten seconds, 45, 2:05, 1h
local function FormatTime(seconds)
    if (seconds <= 0) then return "0"; end
    if (seconds >= 3600) then return math.floor(seconds / 3600) .. "h"; end
    if (seconds >= 60) then return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds) % 60); end
    if (seconds < 10) then return string.format("%.1f", seconds); end
    return tostring(math.floor(seconds));
end

local function Outline(label)
    label:SetFontStyle(Turbine.UI.FontStyle.Outline);
    label:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    label:SetForeColor(Turbine.UI.Color(1, 1, 1));
    label:SetMouseVisible(false);
end

Grommey.TimerBars.Bars = class(UF.EffectsBar);

function Grommey.TimerBars.Bars:Constructor(parent, settings)
    UF.EffectsBar.Constructor(self, parent, settings);
    self.rows = {};
end

-- Height of one bar with its icon
function Grommey.TimerBars.Bars:RowHeight()
    local height = self.settings.barHeight;
    if (self.settings.barIcon) then height = math.max(height, ICON_BOX); end
    return height;
end

function Grommey.TimerBars.Bars:GetAreaSize()
    local settings = self.settings;
    local width = settings.barWidth + (settings.barIcon and (ICON_BOX + ICON_GAP) or 0);
    local spacing = settings.spacing or 2;
    return width, settings.max * (self:RowHeight() + spacing) - spacing;
end

-- The game scales an image only when a control is set up once: a new control for each new icon
local function SetIcon(row, image)
    if (row.imageKey == image) then return; end
    row.imageKey = image;
    if (row.image) then row.image:SetParent(nil); row.image = nil; end
    if (image == nil) then return; end
    local control = Turbine.UI.Control();
    control:SetParent(row.iconBox);
    control:SetPosition(1, 1);
    control:SetSize(32, 32);
    control:SetMouseVisible(false);
    control:SetBackground(image);
    row.image = control;
end

local function CreateRow(bars)
    local row = Turbine.UI.Control();
    row:SetParent(bars);

    row.iconBox = Turbine.UI.Control();
    row.iconBox:SetParent(row);
    row.iconBox:SetSize(ICON_BOX, ICON_BOX);
    row.iconBox:SetMouseVisible(false);
    -- Plain colour square used by the preview instead of an icon
    row.swatch = Turbine.UI.Control();
    row.swatch:SetParent(row.iconBox);
    row.swatch:SetPosition(1, 1);
    row.swatch:SetSize(32, 32);
    row.swatch:SetMouseVisible(false);

    -- Bar: border, dark background, the fill on it, then the texts
    row.bar = Turbine.UI.Control();
    row.bar:SetParent(row);
    row.bar:SetMouseVisible(false);
    row.back = Turbine.UI.Control();
    row.back:SetParent(row.bar);
    row.back:SetPosition(1, 1);
    row.back:SetMouseVisible(false);
    row.fill = Turbine.UI.Control();
    row.fill:SetParent(row.bar);
    row.fill:SetPosition(1, 1);
    row.fill:SetMouseVisible(false);
    row.name = Turbine.UI.Label();
    row.name:SetParent(row.bar);
    row.name:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    Outline(row.name);
    row.time = Turbine.UI.Label();
    row.time:SetParent(row.bar);
    row.time:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleRight);
    Outline(row.time);

    row.MouseEnter = function() UF.ShowEffectTooltip(row); end
    row.MouseLeave = UF.HideEffectTooltip;
    return row;
end

local function Remaining(effect, now)
    local duration = Read(effect, "GetDuration") or 0;
    local start = Read(effect, "GetStartTime");
    if (duration <= 0 or duration >= LONG_EFFECT or start == nil) then return nil, nil; end
    return math.max(0, start + duration - now), duration;
end

function Grommey.TimerBars.Bars:Rebuild()
    local settings = self.settings;
    local areaWidth, areaHeight = self:GetAreaSize();
    self:SetSize(areaWidth, areaHeight);

    -- Important ones first, then the one ending soonest, the effects without an end last
    local now = Turbine.Engine.GetGameTime();
    local entries = UF.CollectEffects(self.effects, settings);
    for _, entry in ipairs(entries) do entry.left = Remaining(entry.effect, now) or math.huge; end
    table.sort(entries, function(a, b)
        if (a.important ~= b.important) then return a.important; end
        if (a.left ~= b.left) then return a.left < b.left; end
        return a.order < b.order;
    end);

    local rowHeight = self:RowHeight();
    local barHeight = settings.barHeight;
    local barX = settings.barIcon and (ICON_BOX + ICON_GAP) or 0;
    local spacing = settings.spacing or 2;
    local shown = math.min(#entries, settings.max);
    local fontSize = (barHeight >= 26) and 14 or ((barHeight >= 20) and 13 or 12);

    for index = 1, math.max(shown, #self.rows) do
        local row = self.rows[index];
        if (index > shown) then
            if (row) then row:SetVisible(false); row.effect = nil; end
        else
            if (row == nil) then row = CreateRow(self); self.rows[index] = row; end
            local entry = entries[index];
            row.effect = entry.effect;
            row.debuff = entry.debuff;
            row:SetSize(areaWidth, rowHeight);

            -- Icon on the left, centred on the bar
            row.iconBox:SetVisible(settings.barIcon == true);
            if (settings.barIcon) then
                row.iconBox:SetPosition(0, math.floor((rowHeight - ICON_BOX) / 2));
                row.iconBox:SetBackColor(entry.important and Theme.Color("accent") or Theme.Color("border"));
                local image = Read(entry.effect, "GetIcon");
                SetIcon(row, image);
                row.swatch:SetBackColor(Read(entry.effect, "GetPreviewColor") or Theme.Color("raised"));
                row.swatch:SetVisible(image == nil);
            end

            local color = entry.debuff and UF.DebuffColor(entry.effect, settings.colorByType) or Theme.Color("accent");
            row.bar:SetPosition(barX, math.floor((rowHeight - barHeight) / 2));
            row.bar:SetSize(settings.barWidth, barHeight);
            row.bar:SetBackColor(entry.important and Theme.Color("accent") or Theme.Color("border"));
            row.back:SetSize(settings.barWidth - 2, barHeight - 2);
            row.back:SetBackColor(Theme.Color("field"));
            row.fill:SetBackColor(color);
            row.innerWidth = settings.barWidth - 2;
            row.innerHeight = barHeight - 2;
            row.lastWidth = nil;
            row.lastTime = nil;

            local font = Theme.Font(fontSize, false);
            row.name:SetFont(font);
            row.time:SetFont(font);
            row.name:SetPosition(TEXT_PAD, 0);
            row.name:SetSize(settings.barWidth - 2 * TEXT_PAD - 44, barHeight);
            row.name:SetText(Read(entry.effect, "GetName") or "");
            row.time:SetPosition(settings.barWidth - TEXT_PAD - 44, 0);
            row.time:SetSize(44, barHeight);
            row.time:SetZOrder(2);
            row.name:SetZOrder(2);

            local step = (index - 1) * (rowHeight + spacing);
            row:SetPosition(0, (settings.lines == "up") and (areaHeight - rowHeight - step) or step);
            row:SetVisible(true);
        end
    end
    self:UpdateTimes();
end

-- Bars and times, called often by the area so the bars move smoothly
function Grommey.TimerBars.Bars:UpdateTimes()
    local now = Turbine.Engine.GetGameTime();
    for _, row in ipairs(self.rows) do
        if (row.effect ~= nil) then
            local left, duration = Remaining(row.effect, now);
            local fraction = 1;
            local text = "";
            if (left ~= nil) then
                fraction = math.max(0, math.min(1, left / duration));
                text = FormatTime(left);
            end
            local width = math.floor(row.innerWidth * fraction + 0.5);
            if (width ~= row.lastWidth) then
                row.lastWidth = width;
                row.fill:SetSize(width, row.innerHeight);
                row.fill:SetVisible(width > 0);
            end
            if (text ~= row.lastTime) then row.lastTime = text; row.time:SetText(text); end
        end
    end
end

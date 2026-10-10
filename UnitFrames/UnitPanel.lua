-- Unit panel: name and level, then the morale, power and class resource bars of one unit.
-- Used by the player and target frames and by every party member.
-- Values are read on a timer by the owner (Refresh), which keeps the bars right even when
-- the game forgets to send an event.

local UF = Grommey.UnitFrames;
local Theme = Grommey.Theme;

local NAME_HEIGHT = 18;
local BAR_GAP = 2;

-- Returns a function giving the value of the local player resource and its definition
-- (UF.ClassResources, UnitFrames/ClassResource.lua), or nil
function UF.FindClassResource(unit)
    if (unit == nil or unit.GetClassAttributes == nil) then return nil; end
    local ok, attributes = pcall(unit.GetClassAttributes, unit);
    if (not ok or attributes == nil) then return nil; end
    for _, resource in ipairs(UF.ClassResources) do
        if (attributes[resource.detect] ~= nil) then
            -- The preview gives a sample instead of the real attributes
            if (attributes.isSample) then return resource.Sample, resource; end
            return function()
                local readOk, state = pcall(resource.Read, attributes);
                if (not readOk) then return nil; end
                return state;
            end, resource;
        end
    end
    return nil;
end

local function Read(unit, method)
    if (unit == nil or unit[method] == nil) then return nil; end
    local ok, value = pcall(unit[method], unit);
    if (ok) then return value; end
    return nil;
end

UF.UnitPanel = class(Turbine.UI.Control);

-- settings: width, showName, moraleHeight, showPower, powerHeight, moraleText, powerText, showResource, resourceHeight
function UF.UnitPanel:Constructor(parent, settings)
    Turbine.UI.Control.Constructor(self);
    self:SetParent(parent);
    self:SetMouseVisible(false);
    self.settings = settings;

    -- Regular font: the game draws no outline or shadow around its only bold font
    self.nameLabel = Grommey.UI.Label(self, 0, 0, 10, NAME_HEIGHT, "", { size = 14; });
    self.nameLabel:SetFontStyle(Turbine.UI.FontStyle.Outline);
    self.nameLabel:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    self.levelLabel = Grommey.UI.Label(self, 0, 0, 40, NAME_HEIGHT, "", { size = 12; align = Turbine.UI.ContentAlignment.MiddleRight; role = "dim"; });
    self.levelLabel:SetFontStyle(Turbine.UI.FontStyle.Outline);
    self.levelLabel:SetOutlineColor(Turbine.UI.Color(0, 0, 0));

    -- Thin accent line under the name, for units without morale (most NPCs)
    self.plainLine = Turbine.UI.Control();
    self.plainLine:SetParent(self);
    self.plainLine:SetMouseVisible(false);
    self.plainLine:SetVisible(false);
    Theme.Track(function() self.plainLine:SetBackColor(Theme.Color("accent")); end);

    self.moraleBar = UF.CreateBar(self);
    self.powerBar = UF.CreateBar(self);
    self.powerBar.SetColor(UF.Colors.power);
    self.resourceBar = UF.CreateResource(self);

    -- Clicking the panel selects the unit, like the game frames do
    if (Turbine.UI.Lotro.EntityControl ~= nil) then
        local ok, entityControl = pcall(Turbine.UI.Lotro.EntityControl);
        if (ok and entityControl) then
            self.entityControl = entityControl;
            self.entityControl:SetParent(self);
            self.entityControl:SetZOrder(10);
        end
    end

    -- Tooltip of the unit while the mouse is over the frame
    local hover = self.entityControl or self;
    hover.MouseEnter = function()
        if (self.settings.tooltip ~= false and self.unit ~= nil) then UF.ShowUnitTooltip(self.unit); end
    end
    hover.MouseLeave = function() UF.HideUnitTooltip(); end
end

-- Lays out the panel from its settings and returns its size
function UF.UnitPanel:Layout()
    local settings = self.settings;
    local width = settings.width;
    local y = 0;

    local mirrored = settings.mirrored == true;
    local gap = settings.barGap or BAR_GAP;

    -- NPCs without morale only show their name, the game does the same
    local maxMorale = Read(self.unit, "GetMaxMorale");
    local hasVitals = (self.unit == nil) or (maxMorale ~= nil and maxMorale > 0);
    self.hasVitals = hasVitals;
    local showName = settings.showName or not hasVitals;

    self.nameLabel:SetVisible(showName);
    self.levelLabel:SetVisible(showName);
    if (showName) then
        -- Mirrored: name on the right, level on the left
        local Align = Turbine.UI.ContentAlignment;
        self.nameLabel:SetSize(width - 44, NAME_HEIGHT);
        self.nameLabel:SetPosition(mirrored and 42 or 2, 0);
        self.nameLabel:SetTextAlignment(mirrored and Align.MiddleRight or Align.MiddleLeft);
        self.levelLabel:SetPosition(mirrored and 2 or (width - 42), 0);
        self.levelLabel:SetTextAlignment(mirrored and Align.MiddleLeft or Align.MiddleRight);
        y = NAME_HEIGHT;
    end
    self.moraleBar.SetMirrored(mirrored);
    self.powerBar.SetMirrored(mirrored);
    self.moraleBar.SetSmooth(settings.smoothBars);
    self.powerBar.SetSmooth(settings.smoothBars);

    -- Text colours and style
    local textColor = UF.ResolveColor(settings.textColor or "white");
    local textStyle = settings.textStyle or "outline";
    for _, bar in ipairs({ self.moraleBar, self.powerBar }) do bar.SetTextStyle(textColor, textStyle); end
    UF.ApplyTextStyle(self.nameLabel, textStyle);
    UF.ApplyTextStyle(self.levelLabel, textStyle);
    self.nameColor = UF.ResolveColor(settings.nameColor or "white");
    self.nameLabel:SetForeColor(self.highlighted and Theme.Color("accent") or self.nameColor);
    self.levelLabel:SetForeColor(self.nameColor);

    self.plainLine:SetVisible(not hasVitals);
    self.moraleBar:SetVisible(hasVitals);
    if (not hasVitals) then
        self.powerBar:SetVisible(false);
        self.resourceBar:SetVisible(false);
        self.resourceGetter = nil;
        self.plainLine:SetPosition(0, y);
        self.plainLine:SetSize(width, 2);
        y = y + 2;
        self:SetSize(width, y);
        if (self.entityControl) then self.entityControl:SetSize(width, y); end
        self.width, self.height = width, y;
        self:Refresh(true);
        return width, y;
    end

    self.moraleBar:SetPosition(0, y);
    self.moraleBar.Resize(width, settings.moraleHeight);
    y = y + settings.moraleHeight;

    -- A free power bar lives in a window of its own (UnitFrames/FreeResource.lua)
    local powerHere = settings.showPower and not settings.powerFree;
    self.powerBar:SetVisible(powerHere);
    if (powerHere) then
        y = y + gap;
        self.powerBar:SetPosition(0, y);
        self.powerBar.Resize(width, settings.powerHeight);
        y = y + settings.powerHeight;
    end

    local getter, definition = nil, nil;
    -- A free resource lives in a window of its own (UnitFrames/FreeResource.lua)
    if (settings.showResource and not settings.resourceFree) then getter, definition = UF.FindClassResource(self.unit); end
    self.resourceGetter = getter;
    self.resourceBar:SetVisible(getter ~= nil);
    if (getter ~= nil) then
        y = y + gap;
        self.resourceBar:SetPosition(0, y);
        self.resourceBar.Resize(width, settings.resourceHeight or 8, definition);
        y = y + (settings.resourceHeight or 8);
    end

    self:SetSize(width, y);
    if (self.entityControl) then self.entityControl:SetSize(width, y); end
    self.width, self.height = width, y;
    self:Refresh(true);
    return width, y;
end

function UF.UnitPanel:SetUnit(unit)
    self.unit = unit;
    self.classColor = UF.ClassColorOf(unit);
    if (self.entityControl) then pcall(self.entityControl.SetEntity, self.entityControl, unit); end
    self.lastName = nil;
    self:Layout();
end

-- Reads the unit and updates the bars, only what changed
function UF.UnitPanel:Refresh(force)
    local unit = self.unit;
    local settings = self.settings;
    if (unit == nil) then return; end

    if (self.nameLabel:IsVisible()) then
        local name = Read(unit, "GetName") or "";
        if (force or name ~= self.lastName) then self.lastName = name; self.nameLabel:SetText(name); end
        local level = Read(unit, "GetLevel");
        local levelText = level and tostring(level) or "";
        if (force or levelText ~= self.lastLevel) then self.lastLevel = levelText; self.levelLabel:SetText(levelText); end
    end

    local morale = Read(unit, "GetMorale");
    local maxMorale = Read(unit, "GetMaxMorale");

    -- The game can send the morale of a new target a moment after it is selected:
    -- lay the panel out again when it shows up (or goes away)
    local hasVitals = (maxMorale ~= nil and maxMorale > 0);
    if (not force and hasVitals ~= self.hasVitals) then
        self:Layout();
        if (self.OnLayoutChanged) then self.OnLayoutChanged(); end
        return;
    end
    if (morale ~= nil and maxMorale ~= nil and maxMorale > 0) then
        self.moraleBar.SetRatio(morale / maxMorale, force);
        local ratio = morale / maxMorale;
        self.moraleBar.SetColor(morale <= 0 and UF.Colors.dead or UF.MoraleColor(settings, ratio, self.classColor, unit));
        self.moraleBar.SetText(UF.BarText(settings.moraleText, morale, maxMorale));
    else
        -- Objects and some NPCs have no morale
        self.moraleBar.SetRatio(0, force);
        self.moraleBar.SetText("");
    end

    if (settings.showPower and not settings.powerFree) then
        local power = Read(unit, "GetPower");
        local maxPower = Read(unit, "GetMaxPower");
        if (power ~= nil and maxPower ~= nil and maxPower > 0) then
            self.powerBar.SetRatio(power / maxPower, force);
            self.powerBar.SetText(UF.BarText(settings.powerText, power, maxPower));
        else
            self.powerBar.SetRatio(0, force);
            self.powerBar.SetText("");
        end
    end

    if (self.resourceGetter ~= nil) then
        local state = self.resourceGetter();
        if (state ~= nil) then self.resourceBar.Set(state, force); end
    end
end

-- Name in the accent colour, used for the party leader
function UF.UnitPanel:SetHighlighted(highlighted)
    self.highlighted = highlighted;
    self.nameLabel:SetForeColor(highlighted and Theme.Color("accent") or (self.nameColor or Theme.Color("text")));
end

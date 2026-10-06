-- Player and target frames: a unit panel and its effects, in a window placed with the move mode.
-- The window has no background, only the bars and icons are drawn.

local UF = Grommey.UnitFrames;

local REFRESH_DELAY = 0.1;  -- bars
local TIMES_DELAY = 0.5;    -- effect durations
local EFFECTS_GAP = 4;      -- space between the bars and the effects
local UNIT_CHECK_DELAY = 0.25;  -- target of target

-- Name and level of a unit, to see when another one takes its place
local function UnitSignature(unit)
    if (unit == nil) then return ""; end
    local okName, name = pcall(unit.GetName, unit);
    local okLevel, level = pcall(unit.GetLevel, unit);
    return tostring(okName and name) .. "#" .. tostring(okLevel and level);
end

UF.UnitFrame = class(Turbine.UI.Window);

-- key: "player" or "target", name: shown in move mode, getUnit: returns the unit to show
function UF.UnitFrame:Constructor(key, name, settings, getUnit, defaultX, defaultY)
    Turbine.UI.Window.Constructor(self);
    self.key = key;
    self.settings = settings;
    self.getUnit = getUnit;
    self:SetMouseVisible(false);

    self.panel = UF.UnitPanel(self, settings);
    -- The panel changed size by itself (morale arrived late), place everything again
    self.panel.OnLayoutChanged = function() self:Layout(); end
    self.effects = UF.EffectsBar(self, settings.effects);
    -- Effects of other units can change many times a second in a group: read them 4 times a second at most
    if (key ~= "player") then self.effects.rebuildDelay = 0.25; end

    self.nextRefresh = 0;
    self.nextTimes = 0;
    self:SetWantsUpdates(true);
    self.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (now >= self.nextRefresh) then
            self.nextRefresh = now + REFRESH_DELAY;
            self.panel:Refresh(false);
        end
        if (now >= self.nextTimes) then
            self.nextTimes = now + TIMES_DELAY;
            self.effects:UpdateTimes();
        end
        -- The game sends no event when the target changes its own target: look a few times a second
        if (key == "targettarget" and now >= (self.nextCheck or 0)) then
            self.nextCheck = now + UNIT_CHECK_DELAY;
            if (UnitSignature(self.getUnit()) ~= self.shownSignature) then self:UpdateUnit(); end
        end
    end

    self:Layout();
    self:UpdateUnit();

    Grommey.Movers.Register("unitframe:" .. key, self, name, defaultX, defaultY);
end

-- Places the panel and the effects around it, from the settings
function UF.UnitFrame:Layout()
    local settings = self.settings;
    local effectSettings = settings.effects;
    local panelWidth, panelHeight = self.panel:Layout();

    if (not effectSettings.show) then
        self.effects:SetVisible(false);
        self.panel:SetPosition(0, 0);
        self:SetSize(panelWidth, panelHeight);
        return;
    end

    self.effects:SetVisible(true);
    self.effects:Rebuild();
    local areaWidth, areaHeight = self.effects:GetAreaSize();
    local position = effectSettings.position;

    -- Icons growing toward the left (or upward) start from the right (or bottom) edge of the bars
    local growth = effectSettings.growth;
    local alignX = (growth == "left") and math.max(0, panelWidth - areaWidth) or 0;
    local alignY = (growth == "up") and math.max(0, panelHeight - areaHeight) or 0;

    if (position == "top") then
        self.effects:SetPosition(alignX, 0);
        self.panel:SetPosition(0, areaHeight + EFFECTS_GAP);
        self:SetSize(math.max(panelWidth, areaWidth), panelHeight + EFFECTS_GAP + areaHeight);
    elseif (position == "left") then
        self.effects:SetPosition(0, alignY);
        self.panel:SetPosition(areaWidth + EFFECTS_GAP, 0);
        self:SetSize(panelWidth + EFFECTS_GAP + areaWidth, math.max(panelHeight, areaHeight));
    elseif (position == "right") then
        self.panel:SetPosition(0, 0);
        self.effects:SetPosition(panelWidth + EFFECTS_GAP, alignY);
        self:SetSize(panelWidth + EFFECTS_GAP + areaWidth, math.max(panelHeight, areaHeight));
    else
        self.panel:SetPosition(0, 0);
        self.effects:SetPosition(alignX, panelHeight + EFFECTS_GAP);
        self:SetSize(math.max(panelWidth, areaWidth), panelHeight + EFFECTS_GAP + areaHeight);
    end
end

-- Takes the unit again (target changed) and shows the frame only when there is one
function UF.UnitFrame:UpdateUnit()
    local unit = self.getUnit();
    self.shownSignature = UnitSignature(unit);
    local effectsUnit = unit;
    if (UF.Preview) then
        -- Fake target when nothing is selected, fake effects to set up the icons
        if (unit == nil and self.key == "target") then unit = UF.DummyTarget; end
        if (unit == nil and self.key == "targettarget") then unit = UF.DummyParty[3]; end
        effectsUnit = UF.DummyEffectsUnit();
    end
    self.panel:SetUnit(unit);
    self.effects:SetUnit(self.settings.effects.show and effectsUnit or nil);
    self:Layout();
    self:SetVisible(unit ~= nil and not Grommey.HudHidden);
end

function UF.UnitFrame:Destroy()
    self:SetWantsUpdates(false);
    self.effects:Destroy();
    Grommey.Movers.Unregister("unitframe:" .. self.key);
    self:SetVisible(false);
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Party: one window holding a panel per member, stacked or side by side

local PARTY_CHECK_DELAY = 0.5;

UF.PartyFrames = class(Turbine.UI.Window);

function UF.PartyFrames:Constructor(settings, defaultX, defaultY)
    Turbine.UI.Window.Constructor(self);
    self.settings = settings;
    self.player = Turbine.Gameplay.LocalPlayer.GetInstance();
    self.panels = {};
    self.signature = nil;
    self:SetMouseVisible(false);

    -- Room for a full party so the move mode box has a useful size
    self:LayoutPanels(6);

    self.nextRefresh = 0;
    self.nextCheck = 0;
    self:SetWantsUpdates(true);
    self.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (now >= self.nextCheck) then
            self.nextCheck = now + PARTY_CHECK_DELAY;
            self:CheckMembers();
        end
        if (now >= self.nextRefresh) then
            self.nextRefresh = now + REFRESH_DELAY;
            for _, panel in ipairs(self.panels) do
                if (panel:IsVisible()) then panel:Refresh(false); end
            end
        end
    end

    Grommey.Movers.Register("unitframe:party", self, L("Party"), defaultX, defaultY);
    self:CheckMembers(true);
end

-- Party members in order, without the local player unless asked
function UF.PartyFrames:GetMembers()
    local members = {};
    local ok, party = pcall(self.player.GetParty, self.player);
    if (not ok or party == nil) then
        -- Solo: fake members in preview so the party frames can be set up
        if (UF.Preview) then
            for _, dummy in ipairs(UF.DummyParty) do table.insert(members, dummy); end
            return members, UF.DummyParty[1]:GetName();
        end
        return members, nil;
    end
    local myName = self.player:GetName();
    local leaderName = nil;
    local leaderOk, leader = pcall(party.GetLeader, party);
    if (leaderOk and leader ~= nil) then leaderName = leader:GetName(); end

    for index = 1, party:GetMemberCount() do
        local member = party:GetMember(index);
        if (member ~= nil and (self.settings.showPlayer or member:GetName() ~= myName)) then
            table.insert(members, member);
        end
    end
    return members, leaderName;
end

-- Rebuilds the panels when someone joins, leaves or the leader changes
function UF.PartyFrames:CheckMembers(force)
    local members, leaderName = self:GetMembers();
    local names = {};
    for _, member in ipairs(members) do table.insert(names, member:GetName()); end
    local signature = table.concat(names, "|") .. "#" .. tostring(leaderName);
    if (signature == self.signature and not force) then return; end
    self.signature = signature;

    for index, member in ipairs(members) do
        local panel = self.panels[index];
        if (panel == nil) then panel = UF.UnitPanel(self, self.settings); self.panels[index] = panel; end
        panel:SetUnit(member);
        panel:SetHighlighted(member:GetName() == leaderName);
        panel:SetVisible(true);
    end
    for index = #members + 1, #self.panels do
        self.panels[index]:SetUnit(nil);
        self.panels[index]:SetVisible(false);
    end

    self:LayoutPanels(math.max(#members, 1));
    self:SetVisible(#members > 0 and not Grommey.HudHidden);
end

function UF.PartyFrames:LayoutPanels(count)
    local settings = self.settings;
    local width, height = 0, 0;
    local panelWidth, panelHeight = settings.width, 0;

    -- Size of one panel, from a panel if there is one
    if (self.panels[1]) then panelWidth, panelHeight = self.panels[1]:Layout(); end
    if (panelHeight == 0) then
        panelHeight = (settings.showName and 18 or 0) + settings.moraleHeight + (settings.showPower and ((settings.barGap or 2) + settings.powerHeight) or 0);
    end

    for index = 1, count do
        local panel = self.panels[index];
        local x, y = 0, 0;
        if (settings.layout == "horizontal") then
            x = (index - 1) * (panelWidth + settings.spacing);
        else
            y = (index - 1) * (panelHeight + settings.spacing);
        end
        if (panel) then panel:SetPosition(x, y); end
        width = math.max(width, x + panelWidth);
        height = math.max(height, y + panelHeight);
    end
    self:SetSize(width, height);
end

-- Settings changed: lay out every panel again
function UF.PartyFrames:Relayout()
    for _, panel in ipairs(self.panels) do panel:Layout(); end
    self:CheckMembers(true);
end

function UF.PartyFrames:Destroy()
    self:SetWantsUpdates(false);
    Grommey.Movers.Unregister("unitframe:party");
    self:SetVisible(false);
end

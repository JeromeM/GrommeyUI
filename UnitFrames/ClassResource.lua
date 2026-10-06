-- Class resource under the player frame, drawn as fits each class:
--   "pips"    one box per point or per state, lit or not (fervour, focus, critical tiers, gambits...)
--   "bar"     a gauge with its value (beorning wrath, red in bear form)
--   "center"  a gauge going from the middle, left for healing and right for damage (rune-keeper attunement)
-- The class attributes come from the documented API (Turbine.Gameplay.Attributes.*Attributes).
-- Every part is opaque: a see-through child would show what is behind the window.

local UF = Grommey.UnitFrames;
local Theme = Grommey.Theme;

local PIP_GAP = 3;
local GROUP_GAP = 9;

local function Call(object, method, ...)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object, ...);
    if (ok) then return value; end
    return nil;
end

-- Lit boxes for a list of "Is...Available" states
local function Flags(attributes, methods)
    local lit = {};
    for index, method in ipairs(methods) do lit[index] = Call(attributes, method) == true; end
    return lit;
end

local function Count(value, total)
    local lit = {};
    for index = 1, total do lit[index] = index <= (value or 0); end
    return lit;
end

-- The warden gambit builder: one box per element, its colour from the kind of element
local GAMBIT_COLORS = {
    Turbine.UI.Color(0.86, 0.32, 0.28),
    Turbine.UI.Color(0.32, 0.56, 0.92),
    Turbine.UI.Color(0.92, 0.76, 0.30),
};

-- detect: the method telling the class; Read(attributes) gives the state shown, Sample() the preview
UF.ClassResources = {
    { detect = "GetFervor"; style = "pips"; count = 5;                                    -- Champion
      Read = function(a) return { lit = Count(Call(a, "GetFervor"), 5); }; end;
      Sample = function() return { lit = Count(3, 5); }; end; };
    { detect = "GetFocus"; style = "pips"; count = 9;                                     -- Hunter
      Read = function(a) return { lit = Count(Call(a, "GetFocus"), 9); }; end;
      Sample = function() return { lit = Count(5, 9); }; end; };
    { detect = "IsCriticalTier1Available"; style = "pips"; count = 2;                     -- Burglar
      Read = function(a) return { lit = Flags(a, { "IsCriticalTier1Available", "IsCriticalTier2Available" }); }; end;
      Sample = function() return { lit = { true, false }; }; end; };
    { detect = "IsReadiedTier1Available"; style = "pips"; count = 2;                      -- Captain
      Read = function(a) return { lit = Flags(a, { "IsReadiedTier1Available", "IsReadiedTier2Available" }); }; end;
      Sample = function() return { lit = { true, false }; }; end; };
    { detect = "IsSerenadeTier1Available"; style = "pips"; count = 3;                     -- Minstrel
      Read = function(a) return { lit = Flags(a, { "IsSerenadeTier1Available", "IsSerenadeTier2Available", "IsSerenadeTier3Available" }); }; end;
      Sample = function() return { lit = { true, true, false }; }; end; };
    { detect = "IsBlockTier1Available"; style = "pips"; count = 6; groups = 3; secondColor = true; -- Guardian
      Read = function(a) return { lit = Flags(a, { "IsBlockTier1Available", "IsBlockTier2Available", "IsBlockTier3Available",
          "IsParryTier1Available", "IsParryTier2Available", "IsParryTier3Available" }); }; end;
      Sample = function() return { lit = { true, true, false, true, false, false }; }; end; };
    { detect = "GetGambitCount"; style = "pips";                                          -- Warden
      Count = function(a) return Call(a, "GetMaxGambitCount") or 5; end;
      Read = function(a)
          local total = Call(a, "GetMaxGambitCount") or 5;
          local count = Call(a, "GetGambitCount") or 0;
          local lit, colors = {}, {};
          for index = 1, total do
              lit[index] = index <= count;
              local kind = (index <= count) and Call(a, "GetGambit", index) or nil;
              colors[index] = GAMBIT_COLORS[tonumber(kind) or 0];
          end
          return { lit = lit; colors = colors; };
      end;
      Sample = function() return { lit = { true, true, false, false, false }; colors = { GAMBIT_COLORS[1], GAMBIT_COLORS[2] }; }; end; };
    { detect = "GetWrath"; style = "bar"; minimum = 0; maximum = 100;                     -- Beorning
      Read = function(a) return { value = Call(a, "GetWrath") or 0; alternate = Call(a, "IsInBearForm") == true; }; end;
      Sample = function() return { value = 60; }; end; };
    { detect = "GetAttunement"; style = "center"; minimum = -10; maximum = 10;            -- Rune-keeper
      Read = function(a) return { value = Call(a, "GetAttunement") or 0; alternate = Call(a, "IsCharged") == true; }; end;
      Sample = function() return { value = -4; }; end; };
};

local function Box(parent)
    local control = Turbine.UI.Control();
    control:SetParent(parent);
    control:SetMouseVisible(false);
    return control;
end

function UF.CreateResource(parent)
    local resource = Box(parent);
    resource.pips = {};
    resource.definition = nil;
    resource.pipCount = 0;

    -- Gauges: dark field, fill, and for the centre style a mark in the middle
    resource.field = Box(resource);
    resource.fill = Box(resource.field);
    resource.middle = Box(resource.field);
    resource.text = Turbine.UI.Label();
    resource.text:SetParent(resource);
    resource.text:SetMouseVisible(false);
    resource.text:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    resource.text:SetFontStyle(Turbine.UI.FontStyle.Outline);
    resource.text:SetOutlineColor(Turbine.UI.Color(0, 0, 0));

    -- Boxes in a row, with a wider gap between groups (guardian block and parry)
    local function LayoutPips(count)
        resource.pipCount = count;
        local width, height = resource.width, resource.height;
        local groupSize = resource.definition.groups;
        local groupGaps = groupSize and math.floor((count - 1) / groupSize) or 0;
        local pipWidth = (width - PIP_GAP * (count - 1 - groupGaps) - GROUP_GAP * groupGaps) / count;
        for _, pip in ipairs(resource.pips) do pip:SetVisible(false); end
        local left = 0;
        for index = 1, count do
            local pip = resource.pips[index];
            if (pip == nil) then
                -- A 1 pixel border and the inside, lit or not
                pip = Box(resource);
                pip.inside = Box(pip);
                resource.pips[index] = pip;
            end
            local x = math.floor(left + 0.5);
            local right = math.floor(left + pipWidth + 0.5);
            pip:SetPosition(x, 0);
            pip:SetSize(right - x, height);
            pip.inside:SetPosition(1, 1);
            pip.inside:SetSize(right - x - 2, height - 2);
            pip:SetBackColor(Theme.Color("border"));
            pip:SetVisible(true);
            local gap = (groupSize and index % groupSize == 0) and GROUP_GAP or PIP_GAP;
            left = left + pipWidth + gap;
        end
    end

    local function Paint()
        resource.field:SetBackColor(Theme.Color("field"));
        resource.middle:SetBackColor(Theme.Color("text"));
        resource.text:SetForeColor(Theme.Color("text"));
        resource.text:SetFont(Theme.Font(11, false));
        for _, pip in ipairs(resource.pips) do pip:SetBackColor(Theme.Color("border")); end
        if (resource.state ~= nil) then resource.Set(resource.state, true); end
    end

    -- definition: an entry of UF.ClassResources, count: number of boxes when it changes (warden)
    function resource.Resize(width, height, definition)
        resource.definition = definition;
        resource.width, resource.height = width, height;
        resource:SetSize(width, height);
        local pips = (definition.style == "pips");
        for _, pip in ipairs(resource.pips) do pip:SetVisible(false); end
        resource.pipCount = 0;
        resource.field:SetVisible(not pips);
        resource.text:SetVisible(not pips and height >= 10);
        if (pips) then
            LayoutPips(definition.count or 5);
        else
            resource.field:SetPosition(0, 0);
            resource.field:SetSize(width, height);
            resource.middle:SetVisible(definition.style == "center");
            resource.middle:SetPosition(math.floor(width / 2), 0);
            resource.middle:SetSize(1, height);
            resource.text:SetPosition(0, 0);
            resource.text:SetSize(width, height);
        end
        Paint();
    end

    -- state: what Read or Sample gave
    function resource.Set(state, force)
        resource.state = state;
        local definition = resource.definition;
        if (definition == nil or state == nil) then return; end
        local accent = Theme.Color("accent");

        if (definition.style == "pips") then
            local lit = state.lit or {};
            if (#lit ~= resource.pipCount and #lit > 0) then LayoutPips(#lit); end
            local groupSize = definition.groups;
            for index = 1, resource.pipCount do
                local color = (state.colors and state.colors[index]) or accent;
                -- The second group of the guardian (parry) in the power colour
                if (definition.secondColor and groupSize and index > groupSize and not (state.colors and state.colors[index])) then color = UF.Colors.power; end
                resource.pips[index].inside:SetBackColor(lit[index] and color or Theme.Color("field"));
            end
            return;
        end

        local value = state.value or 0;
        local width, height = resource.width, resource.height;
        if (definition.style == "center") then
            -- From the middle: left in the healing colour, right in the damage colour; charged: accent mark
            local half = width / 2;
            local ratio = math.max(-1, math.min(1, value / math.max(definition.maximum, -definition.minimum)));
            local size = math.floor(math.abs(ratio) * half + 0.5);
            if (ratio < 0) then
                resource.fill:SetPosition(math.floor(half) - size, 0);
                resource.fill:SetBackColor(UF.Colors.power);
            else
                resource.fill:SetPosition(math.floor(half), 0);
                resource.fill:SetBackColor(Theme.Color("danger"));
            end
            resource.fill:SetSize(size, height);
            resource.middle:SetBackColor(state.alternate and accent or Theme.Color("text"));
        else
            local ratio = (value - definition.minimum) / (definition.maximum - definition.minimum);
            resource.fill:SetPosition(0, 0);
            resource.fill:SetSize(math.floor(math.max(0, math.min(1, ratio)) * width + 0.5), height);
            -- Beorning: red in bear form
            resource.fill:SetBackColor(state.alternate and Theme.Color("danger") or accent);
        end
        resource.text:SetText(tostring(value));
    end

    Theme.Track(Paint);
    return resource;
end

-- What the class attributes of the player give (/gui resources): every method and, for the
-- Get and Is ones, their value now. Printed in the chat, to find the resources of other classes.
function UF.ResourcesReport()
    local player = Turbine.Gameplay.LocalPlayer.GetInstance();
    local ok, attributes = pcall(player.GetClassAttributes, player);
    if (not ok or attributes == nil) then Grommey.Print("GetClassAttributes: nothing"); return; end
    local names, seen = {}, {};
    local function Scan(source)
        for name, value in pairs(source) do
            if (type(name) == "string" and type(value) == "function" and not seen[name]) then
                seen[name] = true;
                table.insert(names, name);
            end
        end
    end
    -- Methods live in the class tables behind the object
    local current = attributes;
    for _ = 1, 6 do
        if (type(current) == "table") then Scan(current); end
        local meta = getmetatable(current);
        if (meta == nil or type(meta.__index) ~= "table") then break; end
        current = meta.__index;
    end
    table.sort(names);
    local parts = {};
    for _, name in ipairs(names) do
        if (string.match(name, "^Get") or string.match(name, "^Is") or string.match(name, "^Has")) then
            local readOk, value = pcall(attributes[name], attributes);
            table.insert(parts, name .. "=" .. tostring(readOk and value or "?"));
        end
    end
    Grommey.Print("Class resources: " .. (#parts > 0 and table.concat(parts, ", ") or "none"));
end

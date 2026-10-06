-- Free bars: the power bar (player, target) and the class resource (player) taken out of their
-- frame, each in a window of its own placed with the move mode, with its own width and height,
-- shown always or in combat only. Settings of the frame: powerFree, powerFreeWidth, powerFreeHeight,
-- powerFreeCombat, and resourceFree, freeWidth, freeHeight, freeCombatOnly.

local UF = Grommey.UnitFrames;

UF.FreeResource = {};
local Free = UF.FreeResource;

local UPDATE_DELAY = 0.1;
local windows = {};         -- "player:power", "player:resource", "target:power" = window

local function Read(unit, method)
    if (unit == nil or unit[method] == nil) then return nil; end
    local ok, value = pcall(unit[method], unit);
    if (ok) then return value; end
    return nil;
end

local function Destroy(id)
    local window = windows[id];
    if (window == nil) then return; end
    window:SetWantsUpdates(false);
    Grommey.Movers.Unregister("unitframe:" .. id);
    window:SetVisible(false);
    windows[id] = nil;
end

-- Width, height and combat option of a free bar in the frame settings
local function Sizes(settings, kind)
    if (kind == "resource") then return settings.freeWidth or 200, settings.freeHeight or 12, settings.freeCombatOnly; end
    return settings.powerFreeWidth or 200, settings.powerFreeHeight or 8, settings.powerFreeCombat;
end

-- getUnit: the unit of the frame (player, target); in preview the target falls back to the fake one
local function Create(key, kind, settings, getUnit)
    local id = key .. ":" .. kind;
    local width, height, combatOnly = Sizes(settings, kind);
    local window = Turbine.UI.Window();
    window:SetMouseVisible(false);
    window:SetSize(width, height);
    if (kind == "resource") then
        window.resource = UF.CreateResource(window);
    else
        window.bar = UF.CreateBar(window);
        window.bar.Resize(width, height);
        window.bar.SetColor(UF.Colors.power);
        window.bar.SetSmooth(settings.smoothBars);
        window.bar.SetTextStyle(UF.ResolveColor(settings.textColor or "white"), settings.textStyle or "outline");
    end
    windows[id] = window;

    local nextUpdate = 0;
    local layoutKey = nil;
    window.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (now < nextUpdate) then return; end
        nextUpdate = now + UPDATE_DELAY;

        local unit = getUnit();
        if (UF.Preview and unit == nil and key == "target") then unit = UF.DummyTarget; end
        local player = Turbine.Gameplay.LocalPlayer.GetInstance();
        local shown, getter, definition = false, nil, nil;
        if (kind == "resource") then
            -- In preview, a sample of the class resource
            if (UF.Preview and UF.DummyClassAttributes) then unit = { GetClassAttributes = UF.DummyClassAttributes; }; end
            getter, definition = UF.FindClassResource(unit);
            shown = getter ~= nil;
        else
            local maxPower = Read(unit, "GetMaxPower");
            shown = maxPower ~= nil and maxPower > 0;
        end
        if (Grommey.HudHidden) then shown = false; end
        if (shown and combatOnly and not UF.Preview) then shown = player:IsInCombat(); end
        if (Grommey.Movers.IsActive()) then shown = true; end
        window:SetVisible(shown);
        if (not shown) then return; end

        if (kind == "resource") then
            if (getter == nil) then return; end
            -- Laid out again when the class or the preview changes
            local layout = tostring(definition) .. tostring(UF.Preview);
            if (layout ~= layoutKey) then
                layoutKey = layout;
                window.resource.Resize(width, height, definition);
            end
            local state = getter();
            if (state ~= nil) then window.resource.Set(state); end
        else
            local power, maxPower = Read(unit, "GetPower"), Read(unit, "GetMaxPower");
            if (power ~= nil and maxPower ~= nil and maxPower > 0) then
                window.bar.SetRatio(power / maxPower);
                window.bar.SetText(UF.BarText(settings.powerText, power, maxPower));
            else
                window.bar.SetRatio(0);
                window.bar.SetText("");
            end
        end
    end
    window:SetWantsUpdates(true);
    -- A global keeps the windows alive
    UF.FreeBarWindows = windows;

    local name = (kind == "resource") and L("Class resource") or ((key == "target") and L("Target power") or L("Player power"));
    Grommey.Movers.Register("unitframe:" .. id, window, name,
        function() return math.floor(Turbine.UI.Display.GetWidth() / 2) - math.floor(width / 2) + ((key == "target") and 200 or -200); end,
        function() return math.floor(Turbine.UI.Display.GetHeight() * 0.62) + ((kind == "resource") and -20 or 0); end);
end

-- Builds again or removes the free bars of a frame (settings nil: removed)
function Free.Apply(key, settings, getUnit)
    for _, kind in ipairs({ "power", "resource" }) do
        Destroy(key .. ":" .. kind);
        if (settings ~= nil and settings.enabled) then
            if (kind == "power" and settings.showPower and settings.powerFree) then Create(key, kind, settings, getUnit); end
            if (kind == "resource" and key == "player" and settings.showResource and settings.resourceFree) then Create(key, kind, settings, getUnit); end
        end
    end
end

function Free.Destroy()
    for id in pairs(windows) do Destroy(id); end
end

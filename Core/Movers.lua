-- Places the frames of the interface. Each frame registers once with an id, a name and a
-- default position. In move mode a coloured box covers every frame and can be dragged,
-- snapping to the grid and to the centre of the screen.

Grommey.Movers = {};

local registered = {};      -- id = { frame, name, defaultX, defaultY }
local order = {};           -- ids in registration order
local overlays = {};        -- id = overlay window, only in move mode
local grid = nil;
local toolbar = nil;
local active = false;

local CENTER_SNAP = 10;

local function ScreenSize()
    return Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
end

-- Keeps a frame of the given size inside the screen
local function ClampToScreen(x, y, width, height)
    local screenWidth, screenHeight = ScreenSize();
    x = Grommey.Clamp(x, 0, math.max(0, screenWidth - width));
    y = Grommey.Clamp(y, 0, math.max(0, screenHeight - height));
    return math.floor(x), math.floor(y);
end

local function DefaultPosition(entry)
    local x = entry.defaultX;
    local y = entry.defaultY;
    if (type(x) == "function") then x = x(); end
    if (type(y) == "function") then y = y(); end
    return x, y;
end

local function ApplyPosition(id)
    local entry = registered[id];
    if (entry == nil) then return; end
    local saved = Grommey.Profile.positions[id];
    local x, y;
    if (saved ~= nil and saved.x ~= nil and saved.y ~= nil) then
        x, y = saved.x, saved.y;
    else
        x, y = DefaultPosition(entry);
    end
    local width, height = entry.frame:GetSize();
    entry.frame:SetPosition(ClampToScreen(x, y, width, height));
end

-- defaultX and defaultY can be numbers or functions returning a number
function Grommey.Movers.Register(id, frame, name, defaultX, defaultY)
    if (registered[id] == nil) then table.insert(order, id); end
    registered[id] = { frame = frame; name = name; defaultX = defaultX; defaultY = defaultY; };
    ApplyPosition(id);
end

function Grommey.Movers.Unregister(id)
    registered[id] = nil;
    for index = #order, 1, -1 do
        if (order[index] == id) then table.remove(order, index); end
    end
end

function Grommey.Movers.SavePosition(id, x, y)
    Grommey.Profile.positions[id] = { x = math.floor(x); y = math.floor(y); };
    Grommey.Profiles.RequestSave();
end

function Grommey.Movers.Reset(id)
    Grommey.Profile.positions[id] = nil;
    ApplyPosition(id);
    Grommey.Profiles.RequestSave();
    if (overlays[id]) then overlays[id].Follow(); end
end

function Grommey.Movers.ResetAll()
    for _, id in ipairs(order) do Grommey.Movers.Reset(id); end
end

function Grommey.Movers.IsActive()
    return active;
end

-- Snaps a position to the grid and to the centre lines of the screen
local function Snap(x, y, width, height)
    local settings = Grommey.Profile.movers;
    if (settings.snap) then
        local size = Grommey.Clamp(settings.grid, 2, 64);
        x = math.floor(x / size + 0.5) * size;
        y = math.floor(y / size + 0.5) * size;
    end

    local screenWidth, screenHeight = ScreenSize();
    local centerX = screenWidth / 2;
    local centerY = screenHeight / 2;
    if (math.abs(x + width / 2 - centerX) < CENTER_SNAP) then x = centerX - width / 2; end
    if (math.abs(y + height / 2 - centerY) < CENTER_SNAP) then y = centerY - height / 2; end

    return ClampToScreen(x, y, width, height);
end

-- Move box: see-through accent over the frame, a thick accent outline and the name in the middle.
-- The whole box can be dragged, right click puts the frame back in place.
local function CreateOverlay(id)
    local entry = registered[id];
    local Theme = Grommey.Theme;

    local overlay = Turbine.UI.Window();
    overlay:SetZOrder(1500);
    overlay:SetMouseVisible(true);

    local borders = {};
    for index = 1, 4 do
        local border = Turbine.UI.Control();
        border:SetParent(overlay);
        border:SetMouseVisible(false);
        borders[index] = border;
    end

    local nameLabel = Grommey.UI.Label(overlay, 0, 0, 10, 10, entry.name, { align = Turbine.UI.ContentAlignment.MiddleCenter; bold = true; mouse = true; });
    nameLabel:SetFontStyle(Turbine.UI.FontStyle.Outline);
    nameLabel:SetOutlineColor(Turbine.UI.Color(0, 0, 0));

    local hovered = false;
    local function Paint()
        overlay:SetBackColor(Theme.Color("accent", hovered and 0.5 or 0.35));
        for _, border in ipairs(borders) do border:SetBackColor(Theme.Color("accent")); end
    end
    Theme.Track(Paint);

    -- Follows the frame size and position
    overlay.Follow = function()
        local width, height = entry.frame:GetSize();
        width = math.max(width, 60);
        height = math.max(height, 24);
        overlay:SetSize(width, height);
        borders[1]:SetPosition(0, 0);          borders[1]:SetSize(width, 2);
        borders[2]:SetPosition(0, height - 2); borders[2]:SetSize(width, 2);
        borders[3]:SetPosition(0, 0);          borders[3]:SetSize(2, height);
        borders[4]:SetPosition(width - 2, 0);  borders[4]:SetSize(2, height);
        nameLabel:SetSize(width, height);
        overlay:SetPosition(entry.frame:GetLeft(), entry.frame:GetTop());
    end
    overlay.Follow();

    local function MouseDown(sender, args)
        -- Right click resets instead of dragging
        if (Turbine.UI.MouseButton ~= nil and args.Button == Turbine.UI.MouseButton.Right) then return; end
        overlay.dragging = true;
        overlay.dragX = args.X;
        overlay.dragY = args.Y;
    end
    local function MouseMove(sender, args)
        if (not overlay.dragging) then return; end
        local width, height = entry.frame:GetSize();
        local x, y = Snap(overlay:GetLeft() + args.X - overlay.dragX, overlay:GetTop() + args.Y - overlay.dragY, width, height);
        entry.frame:SetPosition(x, y);
        overlay:SetPosition(x, y);
    end
    local function MouseUp()
        if (not overlay.dragging) then return; end
        overlay.dragging = false;
        Grommey.Movers.SavePosition(id, entry.frame:GetLeft(), entry.frame:GetTop());
    end
    local function MouseClick(sender, args)
        if (Turbine.UI.MouseButton ~= nil and args.Button == Turbine.UI.MouseButton.Right) then Grommey.Movers.Reset(id); end
    end

    -- The name label covers the whole box at its top left corner, its mouse coordinates match the box ones
    for _, control in ipairs({ overlay, nameLabel }) do
        control.MouseDown = MouseDown;
        control.MouseMove = MouseMove;
        control.MouseUp = MouseUp;
        control.MouseClick = MouseClick;
        control.MouseEnter = function() hovered = true; Paint(); end
        control.MouseLeave = function() hovered = false; Paint(); end
    end

    overlay:SetVisible(true);
    return overlay;
end

local function CreateGrid()
    local Theme = Grommey.Theme;
    local screenWidth, screenHeight = ScreenSize();
    local window = Turbine.UI.Window();
    window:SetSize(screenWidth, screenHeight);
    window:SetPosition(0, 0);
    window:SetMouseVisible(false);
    window:SetZOrder(1000);
    window.lines = {};

    window.Rebuild = function()
        for _, line in ipairs(window.lines) do line:SetParent(nil); end
        window.lines = {};
        if (not Grommey.Profile.movers.showGrid) then return; end

        -- Visible lines are spaced wider than the snapping grid so the screen stays readable
        local spacing = math.max(Grommey.Profile.movers.grid * 4, 32);
        local centerX = math.floor(screenWidth / 2);
        local centerY = math.floor(screenHeight / 2);

        local function AddLine(x, y, width, height, isCenter)
            local line = Turbine.UI.Control();
            line:SetParent(window);
            line:SetPosition(x, y);
            line:SetSize(width, height);
            line:SetMouseVisible(false);
            if (isCenter) then line:SetBackColor(Theme.Color("accent", 0.7));
            else line:SetBackColor(Theme.Color("text", 0.08)); end
            table.insert(window.lines, line);
        end

        local x = centerX % spacing;
        while (x < screenWidth) do AddLine(x, 0, 1, screenHeight, false); x = x + spacing; end
        local y = centerY % spacing;
        while (y < screenHeight) do AddLine(0, y, screenWidth, 1, false); y = y + spacing; end
        AddLine(centerX, 0, 1, screenHeight, true);
        AddLine(0, centerY, screenWidth, 1, true);
    end

    window:SetVisible(true);
    return window;
end

local function CreateToolbar()
    local width, height = 520, 96;
    local screenWidth = ScreenSize();
    local window = Turbine.UI.Window();
    window:SetSize(width, height);
    window:SetPosition(math.floor((screenWidth - width) / 2), 80);
    window:SetZOrder(1600);

    local frame = Grommey.UI.Frame(window, 0, 0, width, height, "background", "accent");
    Grommey.UI.Label(frame.inner, 12, 6, width - 24, 22, L("Move mode"), { bold = true; role = "accent"; });
    Grommey.UI.Label(frame.inner, 12, 28, width - 24, 30, L("Drag the coloured frames to place them. Right click a frame to put it back in place."), { size = 12; role = "dim"; multiline = true; });

    Grommey.UI.Toggle(frame.inner, 12, 64, 200, L("Snap to grid"), Grommey.Profile.movers.snap, function(value)
        Grommey.Profile.movers.snap = value;
        Grommey.Profiles.RequestSave();
    end);
    Grommey.UI.Toggle(frame.inner, 218, 64, 170, L("Show the grid"), Grommey.Profile.movers.showGrid, function(value)
        Grommey.Profile.movers.showGrid = value;
        Grommey.Profiles.RequestSave();
        if (grid) then grid.Rebuild(); end
    end);
    Grommey.UI.Button(frame.inner, width - 112, 62, 98, L("Done"), function() Grommey.Movers.Exit(); end, "accent");

    -- The toolbar itself can be dragged out of the way
    frame.inner.MouseDown = function(sender, args) window.dragging = true; window.dragX = args.X; window.dragY = args.Y; end
    frame.inner.MouseMove = function(sender, args)
        if (window.dragging) then window:SetPosition(window:GetLeft() + args.X - window.dragX, window:GetTop() + args.Y - window.dragY); end
    end
    frame.inner.MouseUp = function() window.dragging = false; end

    window:SetWantsKeyEvents(true);
    window.KeyDown = function(sender, args)
        if (args.Action == Turbine.UI.Lotro.Action.Escape) then Grommey.Movers.Exit(); end
    end

    window:SetVisible(true);
    window:Activate();
    return window;
end

function Grommey.Movers.Enter()
    if (active) then return; end
    active = true;
    Grommey.UI.ClosePopup();
    -- Frames may change for the move mode (previews), let them do it before drawing the boxes
    Grommey.Fire("MoveModeChanged", true);
    grid = CreateGrid();
    grid.Rebuild();
    for _, id in ipairs(order) do overlays[id] = CreateOverlay(id); end
    toolbar = CreateToolbar();
end

function Grommey.Movers.Exit()
    if (not active) then return; end
    active = false;
    for id, overlay in pairs(overlays) do overlay:SetVisible(false); end
    overlays = {};
    if (grid) then grid:SetVisible(false); grid = nil; end
    if (toolbar) then toolbar:SetVisible(false); toolbar = nil; end
    Grommey.Profiles.Save();
    Grommey.Fire("MoveModeChanged", false);
end

function Grommey.Movers.Toggle()
    if (active) then Grommey.Movers.Exit(); else Grommey.Movers.Enter(); end
end

-- The game shortcut hiding the interface (F12 by default) hides GrommeyUI too.
-- The one moving the interface (Ctrl + \) is left alone: both move modes on top of each other are unreadable
local ACTION_TOGGLE_HUD = 0x100000B3;
Grommey.HudHidden = false;

-- Kept in a global: a window only held by a local variable is garbage collected by the game
-- once this file has run, and then never receives the keys
Grommey.KeyListener = Turbine.UI.Window();
local keyListener = Grommey.KeyListener;
keyListener:SetSize(1, 1);
keyListener:SetPosition(0, 0);
keyListener:SetMouseVisible(false);
keyListener:SetVisible(true);
keyListener:SetWantsKeyEvents(true);
keyListener.KeyDown = function(sender, args)
    if (args.Action == ACTION_TOGGLE_HUD) then
        Grommey.HudHidden = not Grommey.HudHidden;
        Grommey.Fire("HudToggled", Grommey.HudHidden);
    end
end

-- A new profile brings its own positions
Grommey.On("ProfileChanged", function()
    for _, id in ipairs(order) do ApplyPosition(id); end
    for id, overlay in pairs(overlays) do overlay.Follow(); end
end);

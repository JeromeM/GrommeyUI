-- Options window: a menu on the left, the selected page on the right.
-- Pages are rebuilt each time they are shown so they always reflect the active profile.

Grommey.Options = {};

local WIDTH = 800;
local HEIGHT = 560;
local MENU_WIDTH = 190;
local PAD = 24;

local window = nil;
local pageHolder = nil;
local currentPage = nil;
local currentKey = nil;
local menuItems = {};

local UI = Grommey.UI;

------------------------------------------------------------------------------------------------------------------------------------------
-- Pages

local function BuildGeneral(page, width)
    local y = 16;
    UI.Header(page, 0, y, width, L("General"));
    UI.Label(page, 0, y + 36, width, 40, L("Welcome to GrommeyUI. Pick a theme, then add modules as they come."), { multiline = true; role = "dim"; });

    y = y + 90;
    UI.Toggle(page, 0, y, width, L("Show the GrommeyUI button"), Grommey.Profile.launcher.shown, function(value)
        Grommey.Profile.launcher.shown = value;
        Grommey.Launcher.Refresh();
        Grommey.Profiles.RequestSave();
    end);
    UI.Label(page, 42, y + 24, width - 42, 20, L("Left click: options. Right click: move frames."), { size = 12; role = "dim"; });

    y = y + 70;
    UI.Header(page, 0, y, width, L("Chat commands"));
    local commands = {
        L("/gui - open or close the options"),
        L("/gui move - move the frames"),
        L("/gui reload - reload the interface"),
        L("/gui reset - put every frame back in place"),
    };
    for index, text in ipairs(commands) do
        UI.Label(page, 0, y + 14 + index * 24, width, 22, text);
    end

    UI.Button(page, 0, y + 150, 220, L("Reload UI"), function() Grommey.Reload(); end);
end

local function BuildTheme(page, width)
    local theme = Grommey.Profile.theme;
    local Theme = Grommey.Theme;
    local y = 16;

    UI.Header(page, 0, y, width, L("Accent colour"));
    local sliders = {};

    -- Presets, each with its name under it
    local swatchX = 10;
    for _, preset in ipairs(Theme.AccentPresets) do
        local isSelected = function()
            return theme.accent.r == preset.r and theme.accent.g == preset.g and theme.accent.b == preset.b;
        end
        UI.Swatch(page, swatchX, y + 40, 40, preset, function()
            theme.accent = { r = preset.r; g = preset.g; b = preset.b; };
            sliders.r:SetValue(preset.r);
            sliders.g:SetValue(preset.g);
            sliders.b:SetValue(preset.b);
            Theme.Changed();
        end, isSelected);
        UI.Label(page, swatchX - 11, y + 82, 62, 18, L(preset.name), { size = 12; role = "dim"; align = Turbine.UI.ContentAlignment.MiddleCenter; });
        swatchX = swatchX + 66;
    end

    -- Fine tuning with red, green and blue
    local sliderWidth = 260;
    y = y + 114;
    local function ColourSlider(key, text, top)
        sliders[key] = UI.Slider(page, 0, top, sliderWidth, text, 0, 255, 1, theme.accent[key], function(value)
            theme.accent[key] = value;
            Theme.Changed();
        end);
    end
    ColourSlider("r", L("Red"), y);
    ColourSlider("g", L("Green"), y + 46);
    ColourSlider("b", L("Blue"), y + 92);

    -- Live preview on the right
    local previewX = sliderWidth + 40;
    local previewWidth = width - previewX;
    local preview = UI.Frame(page, previewX, y - 4, previewWidth, 142, "panel", "border");
    UI.Label(preview.inner, 12, 6, previewWidth - 24, 20, L("Preview"), { bold = true; role = "accent"; });
    UI.Button(preview.inner, 12, 34, 110, L("Button"), nil);
    UI.Button(preview.inner, 130, 34, 110, L("Button"), nil, "accent");
    UI.Toggle(preview.inner, 12, 70, previewWidth - 24, L("Option"), true, nil);
    UI.Slider(preview.inner, 12, 96, previewWidth - 30, L("Value"), 0, 100, 1, 60, nil, " %");

    -- Background tint and opacity
    y = y + 150;
    UI.Header(page, 0, y, width, L("Background"));
    local backgroundItems = {};
    for _, background in ipairs(Theme.Backgrounds) do
        table.insert(backgroundItems, { value = background.name; text = L(background.name); });
    end
    UI.Dropdown(page, 0, y + 46, 200, backgroundItems, theme.background, function(value)
        theme.background = value;
        Theme.Changed();
    end);
    UI.Slider(page, previewX, y + 38, previewWidth, L("Background opacity"), 40, 100, 1, theme.opacity, function(value)
        theme.opacity = value;
        Theme.Changed();
    end, " %");

    -- Font family
    y = y + 92;
    UI.Header(page, 0, y, width, L("Font"));
    local fontItems = {};
    for _, font in ipairs(Theme.Fonts) do
        table.insert(fontItems, { value = font.name; text = L(font.label); });
    end
    UI.Dropdown(page, 0, y + 40, 260, fontItems, theme.font, function(value)
        theme.font = value;
        Theme.Changed();
    end);
end

local function BuildProfiles(page, width)
    local y = 16;
    local status = nil;

    local function ProfileItems(excludeCurrent)
        local items = {};
        for _, name in ipairs(Grommey.Profiles.List()) do
            if (not excludeCurrent or name ~= Grommey.ProfileName) then
                table.insert(items, { value = name; text = name; });
            end
        end
        return items;
    end

    local function Done(message, isError)
        -- The page is rebuilt by ProfileChanged, the message is shown on the new page
        Grommey.Options.pendingStatus = { text = message; isError = isError; };
        Grommey.Options.ShowPage("Profiles");
    end

    UI.Header(page, 0, y, width, L("Current profile"));
    UI.Label(page, 0, y + 32, width, 20, L("Each character chooses its profile. Profiles are shared by all your characters."), { size = 12; role = "dim"; });
    UI.Dropdown(page, 0, y + 58, 260, ProfileItems(false), Grommey.ProfileName, function(value)
        Grommey.Profiles.Use(value);
        Done(L("Some modules need a reload to follow the new profile."), false);
    end);

    y = y + 110;
    UI.Header(page, 0, y, width, L("New profile"));
    local nameBox = UI.TextInput(page, 0, y + 38, 260, "");
    UI.Button(page, 272, y + 38, 240, L("Create (copy of the current one)"), function()
        local name = string.match(nameBox:GetText() or "", "^%s*(.-)%s*$");
        if (name == "" or Grommey.Profiles.Exists(name)) then
            status:SetForeColor(Grommey.Theme.Color("danger"));
            status:SetText(L("The name is empty or already used."));
            return;
        end
        Grommey.Profiles.Create(name);
        Done(L("Profile created."), false);
    end, "accent");

    y = y + 84;
    UI.Header(page, 0, y, width, L("Copy settings from"));
    local others = ProfileItems(true);
    local source = others[1] and others[1].value or nil;
    UI.Dropdown(page, 0, y + 38, 260, others, source, function(value) source = value; end);
    UI.Button(page, 272, y + 38, 120, L("Copy"), function()
        if (source and Grommey.Profiles.CopyFrom(source)) then Done(L("Settings copied."), false); end
    end);

    y = y + 90;
    UI.Separator(page, 0, y, width);
    UI.Button(page, 0, y + 16, 240, L("Reset this profile"), function()
        Grommey.Profiles.Reset();
        Done(L("Profile reset."), false);
    end, "danger");
    UI.Button(page, 252, y + 16, 240, L("Delete this profile"), function()
        if (Grommey.Profiles.IsDefault(Grommey.ProfileName)) then
            status:SetForeColor(Grommey.Theme.Color("danger"));
            status:SetText(L("The Default profile cannot be deleted."));
            return;
        end
        Grommey.Profiles.DeleteCurrent();
        Done(L("Profile deleted."), false);
    end, "danger");

    status = UI.Label(page, 0, y + 56, width, 22, "", { role = "accent"; });
    if (Grommey.Options.pendingStatus) then
        status:SetText(Grommey.Options.pendingStatus.text);
        if (Grommey.Options.pendingStatus.isError) then status:SetForeColor(Grommey.Theme.Color("danger")); end
        Grommey.Options.pendingStatus = nil;
    end
end

local function BuildLayout(page, width)
    local movers = Grommey.Profile.movers;
    local y = 16;

    UI.Header(page, 0, y, width, L("Move frames"));
    UI.Label(page, 0, y + 32, width, 36, L("Drag the coloured frames to place them. Right click a frame to put it back in place."), { multiline = true; role = "dim"; });
    UI.Button(page, 0, y + 76, 240, L("Move mode"), function() Grommey.Movers.Enter(); end, "accent");

    y = y + 130;
    UI.Toggle(page, 0, y, width, L("Snap to grid"), movers.snap, function(value)
        movers.snap = value;
        Grommey.Profiles.RequestSave();
    end);
    UI.Toggle(page, 0, y + 30, width, L("Show the grid"), movers.showGrid, function(value)
        movers.showGrid = value;
        Grommey.Profiles.RequestSave();
    end);
    UI.Slider(page, 0, y + 66, 300, L("Grid size"), 2, 32, 2, movers.grid, function(value)
        movers.grid = value;
        Grommey.Profiles.RequestSave();
    end, " px");

    y = y + 130;
    UI.Separator(page, 0, y, width);
    UI.Button(page, 0, y + 16, 260, L("Reset all positions"), function() Grommey.Movers.ResetAll(); end, "danger");
end

local function BuildModules(page, width)
    local y = 16;
    UI.Header(page, 0, y, width, L("Modules"));
    local list = Grommey.Modules.List();

    if (#list == 0) then
        UI.Label(page, 0, y + 40, width, 44, L("No module yet. They will show up here: unit frames, bags, buffs..."), { multiline = true; role = "dim"; });
        return;
    end

    UI.Label(page, 0, y + 32, width, 20, L("Changes to modules are applied after a reload."), { size = 12; role = "dim"; });
    y = y + 64;
    for _, module in ipairs(list) do
        UI.Toggle(page, 0, y, width, L(module.name), Grommey.Modules.IsEnabled(module.id), function(value)
            Grommey.Modules.SetEnabled(module.id, value);
        end);
        UI.Label(page, 42, y + 22, width - 42, 20, L(module.description or ""), { size = 12; role = "dim"; });
        y = y + 54;
    end
    UI.Button(page, 0, y + 8, 220, L("Reload UI"), function() Grommey.Reload(); end, "accent");
end

local Pages = {
    { key = "General";  build = BuildGeneral; };
    { key = "Theme";    build = BuildTheme; };
    { key = "Profiles"; build = BuildProfiles; };
    { key = "Layout";   build = BuildLayout; };
    { key = "Modules";  build = BuildModules; };
};

------------------------------------------------------------------------------------------------------------------------------------------
-- Window

local function CreateMenuItem(parent, index, page)
    local Theme = Grommey.Theme;
    local item = Turbine.UI.Control();
    item:SetParent(parent);
    item:SetPosition(0, 12 + (index - 1) * 38);
    item:SetSize(MENU_WIDTH, 36);

    local marker = Turbine.UI.Control();
    marker:SetParent(item);
    marker:SetPosition(0, 6);
    marker:SetSize(3, 24);
    marker:SetMouseVisible(false);

    local label = UI.Label(item, 20, 0, MENU_WIDTH - 24, 36, L(page.key), { size = 15; });

    local hovered = false;
    item.Paint = function()
        local selected = (currentKey == page.key);
        marker:SetBackColor(Theme.Color("accent", selected and 1 or 0));
        item:SetBackColor(Theme.Color((selected or hovered) and "raised" or "panel"));
        label:SetForeColor(Theme.Color(selected and "accent" or (hovered and "text" or "dim")));
    end
    Theme.Track(item.Paint);

    item.MouseEnter = function() hovered = true; item.Paint(); end
    item.MouseLeave = function() hovered = false; item.Paint(); end
    item.MouseClick = function() Grommey.Options.ShowPage(page.key); end
    return item;
end

function Grommey.Options.Create()
    local Theme = Grommey.Theme;
    window = Grommey.Window("options", "GrommeyUI  ·  " .. L("Options"), WIDTH, HEIGHT);

    local contentWidth, contentHeight = window.content:GetSize();

    local menu = Turbine.UI.Control();
    menu:SetParent(window.content);
    menu:SetPosition(0, 0);
    menu:SetSize(MENU_WIDTH, contentHeight);
    Theme.Track(function() menu:SetBackColor(Theme.Color("panel")); end);

    local divider = Turbine.UI.Control();
    divider:SetParent(window.content);
    divider:SetPosition(MENU_WIDTH, 0);
    divider:SetSize(1, contentHeight);
    Theme.Track(function() divider:SetBackColor(Theme.Color("border")); end);

    for index, page in ipairs(Pages) do
        menuItems[page.key] = CreateMenuItem(menu, index, page);
    end

    UI.Label(menu, 20, contentHeight - 30, MENU_WIDTH - 24, 20, "v" .. plugin:GetVersion(), { size = 12; role = "dim"; });

    pageHolder = Turbine.UI.Control();
    pageHolder:SetParent(window.content);
    pageHolder:SetPosition(MENU_WIDTH + 1 + PAD, 0);
    pageHolder:SetSize(contentWidth - MENU_WIDTH - 1 - 2 * PAD, contentHeight - 8);

    window.VisibleChanged = function()
        if (not window:IsVisible()) then
            Grommey.UI.ClosePopup();
            Grommey.Profiles.Save();
        end
    end

    Grommey.Movers.Register("options", window, L("Options window"),
        function() return math.floor((Turbine.UI.Display.GetWidth() - WIDTH) / 2); end,
        function() return math.floor((Turbine.UI.Display.GetHeight() - HEIGHT) / 2); end);

    -- Hiding the interface (F12) closes the options
    Grommey.On("HudToggled", function(hidden) if (hidden) then window:SetVisible(false); end end);

    -- Another profile: rebuild the page so it shows the new values
    Grommey.On("ProfileChanged", function()
        if (window:IsVisible() and currentKey) then Grommey.Options.ShowPage(currentKey); end
    end);

    Grommey.Options.ShowPage("General");
end

function Grommey.Options.ShowPage(key)
    Grommey.UI.ClosePopup();
    currentKey = key;
    if (currentPage) then currentPage:SetParent(nil); end

    local width, height = pageHolder:GetSize();
    currentPage = Turbine.UI.Control();
    currentPage:SetParent(pageHolder);
    currentPage:SetSize(width, height);

    for _, page in ipairs(Pages) do
        if (page.key == key) then page.build(currentPage, width); end
    end
    for _, item in pairs(menuItems) do item.Paint(); end
end

function Grommey.Options.Toggle()
    if (window == nil) then return; end
    window:Toggle();
end

function Grommey.Options.Show()
    if (window == nil) then return; end
    window:SetVisible(true);
    window:Activate();
end

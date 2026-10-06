-- First run assistant: a window in steps to choose the profile, the theme, the modules and the
-- main settings of each module. It opens once after the install (remembered for the account) and
-- can be started again from the General page. Finishing reloads the interface so every choice applies.
--
-- A module can offer its own step with SetupOptions = function(page, width, settings) in its
-- registration: a few plain settings, saved when the assistant finishes.

Grommey.Setup = {};

local WIDTH = 700;
local HEIGHT = 540;
local PAD = 28;
local FOOTER = 56;

local UI = Grommey.UI;
local window = nil;
local pageHolder = nil;
local currentPage = nil;
local stepIndex = 1;
local finishing = false;
local footer = {};

------------------------------------------------------------------------------------------------------------------------------------------
-- Steps

local function StepProfile(page, width)
    -- Changing the language reloads at once, the assistant comes back on this step in the new language
    UI.Label(page, width - 220, 0, 220, 18, L("Language"));
    UI.Dropdown(page, width - 220, 20, 220, Grommey.LanguageItems(), Grommey.LanguageChoice, function(value)
        if (value == Grommey.LanguageChoice) then return; end
        Grommey.SetLanguage(value);
        Grommey.Reload();
    end);
    UI.Label(page, 0, 0, width - 240, 60, L("Welcome to GrommeyUI! This assistant sets up the interface in a few steps. Everything can be changed later in the options (/gui)."),
        { multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });

    local y = 64;
    UI.Header(page, 0, y, width, L("Profile"));
    local note = UI.Note(page, 0, y + 32, width, L("A profile holds every setting. Several characters can share one, or each can have its own."));
    -- The rest goes down when the note takes more lines
    y = y + math.max(0, note:GetHeight() - 36);

    local items = {};
    for _, name in ipairs(Grommey.Profiles.List()) do table.insert(items, { value = name; text = name; }); end
    UI.Label(page, 0, y + 74, 260, 18, L("Use the profile"));
    UI.Dropdown(page, 0, y + 94, 260, items, Grommey.ProfileName, function(value)
        Grommey.Profiles.Use(value);
        Grommey.Setup.ShowStep(stepIndex);
    end);

    UI.Label(page, 300, y + 74, 260, 18, L("Or create a new one"));
    local nameBox = UI.TextInput(page, 300, y + 94, 200, "");
    local status = UI.Label(page, 300, y + 128, width - 300, 20, "", { size = 12; role = "danger"; });
    UI.Button(page, 510, y + 94, width - 510, L("Create"), function()
        local name = string.match(nameBox:GetText() or "", "^%s*(.-)%s*$");
        if (name == "" or Grommey.Profiles.Exists(name)) then
            status:SetText(L("The name is empty or already used."));
            return;
        end
        Grommey.Profiles.Create(name);
        Grommey.Setup.ShowStep(stepIndex);
    end, "accent");

    UI.Label(page, 0, y + 170, width, 20, string.format(L("This character uses: %s"), Grommey.ProfileName), { role = "accent"; });
end

local function StepTheme(page, width)
    local Theme = Grommey.Theme;
    local theme = Grommey.Profile.theme;

    UI.Header(page, 0, 0, width, L("Accent colour"));
    local x = 4;
    for _, preset in ipairs(Theme.AccentPresets) do
        UI.Swatch(page, x, 36, 44, preset, function()
            theme.accent = { r = preset.r; g = preset.g; b = preset.b; };
            Theme.Changed();
        end, function() return theme.accent.r == preset.r and theme.accent.g == preset.g and theme.accent.b == preset.b; end);
        UI.Label(page, x - 12, 84, 68, 18, L(preset.name), { size = 12; role = "dim"; align = Turbine.UI.ContentAlignment.MiddleCenter; });
        x = x + 76;
    end

    local y = 124;
    UI.Header(page, 0, y, width, L("Background"));
    local backgrounds = {};
    for _, background in ipairs(Theme.Backgrounds) do table.insert(backgrounds, { value = background.name; text = L(background.name); }); end
    UI.Dropdown(page, 0, y + 40, 260, backgrounds, theme.background, function(value) theme.background = value; Theme.Changed(); end);

    y = y + 90;
    UI.Header(page, 0, y, width, L("Font"));
    local fonts = {};
    for _, font in ipairs(Theme.Fonts) do table.insert(fonts, { value = font.name; text = L(font.label); }); end
    UI.Dropdown(page, 0, y + 40, 260, fonts, theme.font, function(value) theme.font = value; Theme.Changed(); end);
    UI.Slider(page, 0, y + 80, 260, L("Text size"), -2, 4, 1, theme.fontOffset or 0, function(value)
        theme.fontOffset = value;
        Theme.Changed();
    end, " px");

    -- Small sample, painted with the theme as it is chosen
    local sample = UI.Frame(page, 300, y + 34, width - 300, 70, "panel", "border");
    UI.Label(sample.inner, 12, 4, width - 330, 20, L("Preview"), { bold = true; role = "accent"; });
    UI.Button(sample.inner, 12, 32, 110, L("Button"), nil);
    UI.Button(sample.inner, 130, 32, 110, L("Button"), nil, "accent");
end

local function StepModules(page, width)
    local note = UI.Note(page, 0, 0, width, L("Choose the parts of the interface you want. A module that is off leaves the game window it replaces."));
    local y = note:GetHeight() + 10;
    for _, module in ipairs(Grommey.Modules.List()) do
        UI.Toggle(page, 0, y, width, L(module.name), Grommey.Modules.IsEnabled(module.id), function(value)
            Grommey.Modules.SetEnabled(module.id, value);
            -- The module steps follow the choice
            Grommey.Setup.ShowStep(stepIndex);
        end);
        UI.Label(page, 42, y + 22, width - 42, 20, L(module.description or ""), { size = 12; role = "dim"; });
        y = y + 54;
    end
end

local function StepFinish(page, width)
    UI.Header(page, 0, 0, width, L("All set!"));
    UI.Label(page, 0, 36, width, 60, L("Finishing reloads the interface so every choice applies. Then place your frames with the move mode: drag the coloured boxes, right click one to put it back."),
        { multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    local lines = {
        L("/gui - open or close the options"),
        L("/gui move - move the frames"),
        L("/gui reload - reload the interface"),
    };
    for index, text in ipairs(lines) do UI.Label(page, 0, 110 + index * 26, width, 22, text, { role = "dim"; }); end
    UI.Note(page, 0, 230, width, L("This assistant can be started again from the General page of the options."));
end

-- Profile, theme, modules, one step per enabled module that has one, and the end
local function Steps()
    local steps = {
        { title = L("Profile"); build = StepProfile; };
        { title = L("Theme"); build = StepTheme; };
        { title = L("Modules"); build = StepModules; };
    };
    for _, module in ipairs(Grommey.Modules.List()) do
        if (module.SetupOptions and Grommey.Modules.IsEnabled(module.id)) then
            table.insert(steps, {
                title = L(module.name);
                build = function(page, width) module.SetupOptions(page, width, Grommey.Modules.Settings(module.id)); end;
            });
        end
    end
    table.insert(steps, { title = L("Finish"); build = StepFinish; });
    return steps;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Window

local function Finish()
    finishing = true;
    Grommey.Profiles.SetSetupDone(true);
    window:SetVisible(false);
    Grommey.Reload();
end

local function Create()
    window = Grommey.Window(nil, "GrommeyUI  ·  " .. L("Setup"), WIDTH, HEIGHT);
    window:SetPosition(math.floor((Turbine.UI.Display.GetWidth() - WIDTH) / 2), math.floor((Turbine.UI.Display.GetHeight() - HEIGHT) / 2));
    local contentWidth, contentHeight = window.content:GetSize();

    -- Step title and the row of steps
    footer.title = UI.Label(window.content, PAD, 14, contentWidth - 2 * PAD, 26, "", { size = 18; bold = true; role = "accent"; });
    footer.counter = UI.Label(window.content, PAD, 14, contentWidth - 2 * PAD, 26, "", { size = 12; role = "dim"; align = Turbine.UI.ContentAlignment.MiddleRight; });
    footer.dots = Turbine.UI.Control();
    footer.dots:SetParent(window.content);
    footer.dots:SetPosition(PAD, 46);
    footer.dots:SetSize(contentWidth - 2 * PAD, 4);

    pageHolder = Turbine.UI.Control();
    pageHolder:SetParent(window.content);
    pageHolder:SetPosition(PAD, 70);
    pageHolder:SetSize(contentWidth - 2 * PAD, contentHeight - 70 - FOOTER);

    UI.Separator(window.content, 0, contentHeight - FOOTER, contentWidth);
    footer.back = UI.Button(window.content, PAD, contentHeight - FOOTER + 14, 150, L("Back"), function() Grommey.Setup.ShowStep(stepIndex - 1); end);
    footer.skip = UI.Label(window.content, PAD + 166, contentHeight - FOOTER + 14, 220, 26, L("Skip the assistant"), { size = 12; role = "dim"; mouse = true; });
    footer.skip.MouseClick = function() window:SetVisible(false); end
    footer.next = UI.Button(window.content, contentWidth - PAD - 170, contentHeight - FOOTER + 14, 170, L("Next"), function()
        if (stepIndex >= #Steps()) then Finish(); else Grommey.Setup.ShowStep(stepIndex + 1); end
    end, "accent");

    -- Closing it (cross, Escape, skip) counts as done, it does not come back at every login
    window.VisibleChanged = function()
        if (window:IsVisible()) then return; end
        Grommey.UI.ClosePopup();
        if (not finishing) then
            Grommey.Profiles.SetSetupDone(true);
            Grommey.Profiles.Save();
        end
    end
    Grommey.On("HudToggled", function(hidden) if (hidden and window) then window:SetVisible(false); end end);
end

function Grommey.Setup.ShowStep(index)
    local steps = Steps();
    stepIndex = Grommey.Clamp(index, 1, #steps);
    local step = steps[stepIndex];
    Grommey.UI.ClosePopup();

    footer.title:SetText(step.title);
    footer.counter:SetText(string.format(L("Step %d of %d"), stepIndex, #steps));
    footer.back:SetVisible(stepIndex > 1);
    footer.next:SetText(stepIndex == #steps and L("Finish and reload") or L("Next"));

    -- One segment per step, the done ones and the current one in the theme colour
    footer.dots:SetParent(nil);
    footer.dots = Turbine.UI.Control();
    footer.dots:SetParent(window.content);
    local dotsWidth = WIDTH - 2 - 2 * PAD;
    footer.dots:SetPosition(PAD, 46);
    footer.dots:SetSize(dotsWidth, 4);
    local segment = math.floor((dotsWidth - (#steps - 1) * 6) / #steps);
    for number = 1, #steps do
        local bar = Turbine.UI.Control();
        bar:SetParent(footer.dots);
        bar:SetPosition((number - 1) * (segment + 6), 0);
        bar:SetSize(segment, 4);
        bar:SetBackColor(Grommey.Theme.Color(number <= stepIndex and "accent" or "raised"));
        bar:SetMouseVisible(false);
    end

    if (currentPage) then currentPage:SetParent(nil); end
    local width, height = pageHolder:GetSize();
    currentPage = Turbine.UI.Control();
    currentPage:SetParent(pageHolder);
    currentPage:SetSize(width, height);
    step.build(currentPage, width);
end

-- Opens the assistant at its first step
function Grommey.Setup.Start()
    if (window == nil) then Create(); end
    finishing = false;
    Grommey.Setup.ShowStep(1);
    window:SetVisible(true);
    window:Activate();
end

-- The step being shown is drawn again when the theme changes, so the step bar follows
Grommey.On("ThemeChanged", function()
    if (window and window:IsVisible()) then Grommey.Setup.ShowStep(stepIndex); end
end);

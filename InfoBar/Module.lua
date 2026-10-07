-- Info bars: up to two bars (top and bottom of the screen), each with a left, centre and right zone.
-- Every element (money, currencies, bags, durability, FPS, time, session time and money, memory,
-- character) chooses its bar, zone, order, label, colour, text size, outline and value format.

local Theme = Grommey.Theme;
local UI = Grommey.UI;

local PAD = 12;
local SEPARATOR_GAP = 10;
local UPDATE_DELAY = 1;
-- A session goes on after a reload of the interface, a break longer than this starts a new one
local SESSION_BREAK = 600;
local SESSION_FILE = "GrommeyUI_Session";

local bars = {};          -- "top" / "bottom" = window
local settingsRoot = nil;
local player = nil;
local frames, frameStart, fps = 0, 0, 0;
local session = nil;        -- { start = local time, money = copper at the start, seen = last check }

local function Call(object, method, ...)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, a, b, c = pcall(object[method], object, ...);
    if (ok) then return a, b, c; end
    return nil;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Values: each returns the label and the value text (markup allowed)

local TotalCopper = Grommey.Money.Total;
local MoneyText = Grommey.Money.Text;

local function Money(element)
    local total = TotalCopper();
    if (total == nil) then return nil; end
    return L("Money"), MoneyText(total, element.format == "gold");
end

local function Now()
    local ok, time = pcall(Turbine.Engine.GetLocalTime);
    if (ok and time) then return time; end
    return Turbine.Engine.GetGameTime();
end

-- Starts or goes on with the session of this character, kept in a small file of the character
local function LoadSession()
    local ok, saved = pcall(Turbine.PluginData.Load, Turbine.DataScope.Character, SESSION_FILE);
    local now = Now();
    if (ok and type(saved) == "table" and tonumber(saved.seen) and now - tonumber(saved.seen) < SESSION_BREAK) then
        session = { start = tonumber(saved.start) or now; money = tonumber(saved.money); seen = now; };
    else
        session = { start = now; money = TotalCopper(); seen = now; };
    end
end

local function SaveSession()
    if (session == nil) then return; end
    session.seen = Now();
    -- Whole numbers only, as text: French and German clients write decimals with a comma
    pcall(Turbine.PluginData.Save, Turbine.DataScope.Character, SESSION_FILE, {
        start = tostring(math.floor(session.start)); money = session.money and tostring(session.money); seen = tostring(math.floor(session.seen));
    });
end

-- 5040 -> "1 h 24", 300 -> "5 min"
local function DurationText(seconds)
    seconds = math.max(0, math.floor(seconds));
    local hours = math.floor(seconds / 3600);
    local minutes = math.floor(seconds / 60) % 60;
    if (hours > 0) then return string.format(L("%d h %02d"), hours, minutes); end
    return string.format(L("%d min"), minutes);
end

local function SessionTime()
    if (session == nil) then return nil; end
    return L("Session"), DurationText(Now() - session.start);
end

local function SessionMoney(element)
    local total = TotalCopper();
    if (session == nil or total == nil) then return nil; end
    if (session.money == nil) then session.money = total; end
    local gained = total - session.money;
    if (element.format == "hour") then
        local hours = math.max((Now() - session.start) / 3600, 1 / 60);
        gained = math.floor(gained / hours);
    end
    local sign = (gained < 0) and "-" or "+";
    local color = (gained < 0) and "#FF6060" or "#7CD67C";
    local text = "<rgb=" .. color .. ">" .. sign .. "</rgb> " .. MoneyText(math.abs(gained), false);
    if (element.format == "hour") then text = text .. " " .. L("/ h"); end
    return L("Gained"), text;
end

-- Memory used by the Lua of GrommeyUI, "3,2 MB" with the decimal mark of the language
local function Memory()
    local tenths = math.floor(collectgarbage("count") / 1024 * 10 + 0.5);
    local mark = (Grommey.Language == "en") and "." or ",";
    return L("Memory"), math.floor(tenths / 10) .. mark .. (tenths % 10) .. L(" MB");
end

local function Character(element)
    local name = Call(player, "GetName") or "";
    if (element.format == "name") then return L("Character"), name; end
    -- "Duntguiff - 6", the level in the theme colour
    local level = Call(player, "GetLevel");
    if (level == nil) then return L("Character"), name; end
    return L("Character"), name .. " - <rgb=" .. Theme.Hex("accent") .. ">" .. level .. "</rgb>";
end

local function Durability(element)
    local equipment = Call(player, "GetEquipment");
    local WearState = Turbine.Gameplay.ItemWearState;
    if (equipment == nil or WearState == nil) then return nil; end
    local values = { [WearState.Pristine] = 100; [WearState.Worn] = 50; [WearState.Damaged] = 20; [WearState.Broken] = 0; };
    local total, count, worst = 0, 0, 100;
    for index = 1, equipment:GetSize() do
        local item = equipment:GetItem(index);
        local value = item and values[Call(item, "GetWearState")];
        if (value ~= nil) then total = total + value; count = count + 1; worst = math.min(worst, value); end
    end
    if (count == 0) then return L("Durability"), "-"; end
    local percent = (element.format == "worst") and worst or math.floor(total / count + 0.5);
    local color = (percent < 20 and "#FF5050") or (percent < 50 and "#FF9933") or nil;
    local text = percent .. " %";
    if (color) then text = "<rgb=" .. color .. ">" .. text .. "</rgb>"; end
    return L("Durability"), text;
end

local function Bags(element)
    local backpack = Call(player, "GetBackpack");
    if (backpack == nil) then return nil; end
    local size = backpack:GetSize();
    local free = 0;
    for index = 1, size do
        if (backpack:GetItem(index) == nil) then free = free + 1; end
    end
    local color = (free == 0 and "#FF5050") or (free < 5 and "#FF9933") or nil;
    local text = (element.format == "used") and ((size - free) .. " / " .. size) or tostring(free);
    if (color) then text = "<rgb=" .. color .. ">" .. text .. "</rgb>"; end
    return L("Bags"), text;
end

local function Clock(element)
    local ok, date = pcall(Turbine.Engine.GetDate);
    if (not ok or date == nil or date.Hour == nil) then return nil; end
    local hour, minute = date.Hour, date.Minute or 0;
    if (element.format == "12h") then
        local suffix = (hour < 12) and " AM" or " PM";
        hour = hour % 12;
        if (hour == 0) then hour = 12; end
        return L("Time"), string.format("%d:%02d", hour, minute) .. suffix;
    end
    return L("Time"), string.format("%02d:%02d", hour, minute);
end

local function Fps()
    return "FPS", tostring(fps);
end

-- Elements, their value function and the formats they offer
local Elements = {
    { key = "money"; name = "Money"; value = Money; formats = { { value = "full"; text = "Gold, silver and copper"; }, { value = "gold"; text = "Gold only"; } }; };
    { key = "currencies"; name = "Currencies"; currencies = true; };
    { key = "bags"; name = "Free bag slots"; value = Bags; formats = { { value = "free"; text = "Free slots"; }, { value = "used"; text = "Used / total"; } }; };
    { key = "durability"; name = "Durability"; value = Durability; formats = { { value = "average"; text = "Average"; }, { value = "worst"; text = "Most worn piece"; } }; };
    { key = "fps"; name = "Frames per second"; value = Fps; };
    { key = "clock"; name = "Time"; value = Clock; formats = { { value = "24h"; text = "24 hours"; }, { value = "12h"; text = "12 hours"; } }; };
    { key = "sessionTime"; name = "Session time"; value = SessionTime; };
    { key = "sessionMoney"; name = "Money of the session"; value = SessionMoney; formats = { { value = "total"; text = "Since the login"; }, { value = "hour"; text = "Per hour"; } }; };
    { key = "memory"; name = "GrommeyUI memory"; value = Memory; };
    { key = "character"; name = "Character"; value = Character; formats = { { value = "nameLevel"; text = "Name and level"; }, { value = "name"; text = "Name only"; } }; };
};

local function Clicked(key)
    if (key == "bags" and Grommey.Bags.Instance) then Grommey.Bags.Instance:Toggle(); end
    if (key == "character") then Grommey.Options.Toggle(); end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Drawing

local function TextWidth(text, size)
    local visible = string.gsub(text, "<[^>]*>", "");
    return math.floor(string.len(visible) * size * 0.58) + 6;
end

-- Plain labels: bars are rebuilt every second, theme listeners would pile up
local function AddLabel(bar, text, element, height)
    local label = Turbine.UI.Label();
    label:SetParent(bar);
    label:SetFont(Theme.Font(element.size or 13, false));
    label:SetForeColor(Grommey.UnitFrames.ResolveColor(element.color or "white"));
    Grommey.UnitFrames.ApplyTextStyle(label, element.style or "outline");
    label:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft);
    label:SetMarkupEnabled(true);
    label:SetMouseVisible(false);
    label:SetText(text);
    local width = TextWidth(text, element.size or 13);
    label:SetSize(width, height);
    table.insert(bar.parts, label);
    return label, width;
end

-- Builds one element as a list of { control, width, icon }
local function BuildElement(bar, definition, element, height)
    local parts = {};
    if (definition.currencies) then
        local wallet = Call(player, "GetWallet");
        if (wallet == nil) then return parts; end
        for index = 1, wallet:GetSize() do
            local item = wallet:GetItem(index);
            if (settingsRoot.currencies[item:GetName()]) then
                if (element.icons ~= false) then
                    local icon = Turbine.UI.Control();
                    icon:SetParent(bar);
                    icon:SetSize(16, 16);
                    icon:SetBlendMode(Turbine.UI.BlendMode.Overlay);
                    icon:SetBackground(item:GetSmallImage());
                    icon:SetMouseVisible(false);
                    table.insert(bar.parts, icon);
                    table.insert(parts, { control = icon; width = 18; icon = true; });
                end
                local text = tostring(item:GetQuantity());
                if (element.label) then text = item:GetName() .. " " .. text; end
                local label, width = AddLabel(bar, text, element, height);
                table.insert(parts, { control = label; width = width + 6; });
            end
        end
        return parts;
    end

    local labelText, valueText = definition.value(element);
    if (valueText == nil) then return parts; end
    local text = element.label and ("<rgb=" .. Theme.Hex("dim") .. ">" .. labelText .. "</rgb> " .. valueText) or valueText;
    local label, width = AddLabel(bar, text, element, height);
    if (definition.key == "bags" or definition.key == "character") then
        label:SetMouseVisible(true);
        label.MouseClick = function() Clicked(definition.key); end
    end
    table.insert(parts, { control = label; width = width; });
    return parts;
end

local function RefreshBar(position)
    local bar = bars[position];
    if (bar == nil) then return; end
    for _, part in ipairs(bar.parts) do part:SetParent(nil); end
    bar.parts = {};

    local height = settingsRoot.bars[position].height;
    local screenWidth = Turbine.UI.Display.GetWidth();
    local zones = { left = {}; center = {}; right = {}; };

    for index, definition in ipairs(Elements) do
        local element = settingsRoot.elements[definition.key];
        if (element.bar == position and zones[element.zone]) then
            local parts = BuildElement(bar, definition, element, height);
            if (#parts > 0) then
                table.insert(zones[element.zone], { parts = parts; order = element.order or 1; index = index; });
            end
        end
    end

    local function Place(group, startX)
        table.sort(group, function(a, b)
            if (a.order ~= b.order) then return a.order < b.order; end
            return a.index < b.index;
        end);
        local x = startX;
        for position, entry in ipairs(group) do
            for _, part in ipairs(entry.parts) do
                part.control:SetPosition(x, part.icon and math.floor((height - 16) / 2) or 0);
                x = x + part.width;
            end
            if (position < #group) then
                -- Thin vertical line between two elements
                local separator = Turbine.UI.Control();
                separator:SetParent(bar);
                separator:SetSize(1, height - 10);
                separator:SetBackColor(Theme.Color("border"));
                separator:SetMouseVisible(false);
                separator:SetPosition(x + SEPARATOR_GAP, 5);
                table.insert(bar.parts, separator);
                x = x + 2 * SEPARATOR_GAP;
            end
        end
        return x - startX;
    end

    local function GroupWidth(group)
        local width = 0;
        for _, entry in ipairs(group) do for _, part in ipairs(entry.parts) do width = width + part.width; end end
        return width + math.max(0, #group - 1) * 2 * SEPARATOR_GAP;
    end

    Place(zones.left, PAD);
    Place(zones.center, math.floor((screenWidth - GroupWidth(zones.center)) / 2));
    Place(zones.right, screenWidth - PAD - GroupWidth(zones.right));
end

local function RefreshAll()
    for position in pairs(bars) do RefreshBar(position); end
end

local function DestroyBars()
    for position, bar in pairs(bars) do
        bar:SetWantsUpdates(false);
        for _, part in ipairs(bar.parts) do part:SetParent(nil); end
        bar:SetVisible(false);
    end
    bars = {};
end

-- Creates the enabled bars again from the settings
local function Build()
    DestroyBars();
    local screenWidth = Turbine.UI.Display.GetWidth();
    for _, position in ipairs({ "top", "bottom" }) do
        local barSettings = settingsRoot.bars[position];
        if (barSettings.enabled) then
            local bar = Turbine.UI.Window();
            bar.parts = {};
            bar:SetZOrder(5);
            local height = barSettings.height;
            bar:SetSize(screenWidth, height);
            bar:SetPosition(0, position == "top" and 0 or (Turbine.UI.Display.GetHeight() - height));
            bar:SetBackColor(Theme.Color("background"));
            -- Thin theme coloured line on the side facing the screen
            local line = Turbine.UI.Control();
            line:SetParent(bar);
            line:SetSize(screenWidth, 1);
            line:SetPosition(0, position == "top" and (height - 1) or 0);
            line:SetBackColor(Theme.Color("accent"));
            line:SetMouseVisible(false);
            bar:SetVisible(not Grommey.HudHidden);
            bars[position] = bar;
        end
    end

    -- One bar does the timing for all of them
    local first = bars.top or bars.bottom;
    if (first) then
        local nextUpdate = 0;
        first:SetWantsUpdates(true);
        first.Update = function()
            local now = Turbine.Engine.GetGameTime();
            frames = frames + 1;
            if (now - frameStart >= 1) then
                fps = math.floor(frames / (now - frameStart) + 0.5);
                frames, frameStart = 0, now;
            end
            if (now >= nextUpdate) then
                nextUpdate = now + UPDATE_DELAY;
                RefreshAll();
                -- The session is written once a minute, a reload keeps it
                if (session and Now() - session.seen >= 60) then SaveSession(); end
            end
        end
    end
    RefreshAll();
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Options

local selectedSection = "elements";
local selectedElement = "money";

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

local function BuildOptions(page, width, settings)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    local function Changed() Grommey.Profiles.RequestSave(); Build(); end
    local function Reopen() Grommey.Options.ShowPage("module:InfoBar"); end
    local function LabeledDropdown(x, y, text, items, value, onChange)
        UI.Label(page, x, y, half, 18, text);
        UI.Dropdown(page, x, y + 20, half, Translated(items), value, onChange);
    end

    UI.Header(page, 0, 16, width, L("Info bar"));
    local x = 0;
    for _, section in ipairs({ { key = "elements"; text = L("Elements"); }, { key = "bars"; text = L("Bars"); } }) do
        UI.Button(page, x, 52, 150, section.text, function() selectedSection = section.key; Reopen(); end, (selectedSection == section.key) and "accent" or nil);
        x = x + 158;
    end

    if (selectedSection == "bars") then
        local y = 100;
        for _, position in ipairs({ "top", "bottom" }) do
            local barSettings = settings.bars[position];
            local title = (position == "top") and L("Top bar") or L("Bottom bar");
            UI.Toggle(page, 0, y, half, title, barSettings.enabled, function(value) barSettings.enabled = value; Changed(); end);
            UI.Slider(page, right, y - 6, half, L("Height"), 20, 40, 1, barSettings.height, function(value) barSettings.height = value; Changed(); end, " px");
            y = y + 60;
        end
        return;
    end

    -- Element choice, then its settings in two columns
    local definition = nil;
    local elementItems = {};
    for _, item in ipairs(Elements) do
        table.insert(elementItems, { value = item.key; text = item.name; });
        if (item.key == selectedElement) then definition = item; end
    end
    UI.Dropdown(page, 330, 52, width - 330, Translated(elementItems), selectedElement, function(value) selectedElement = value; Reopen(); end);
    local element = settings.elements[selectedElement];

    local y = 100;
    LabeledDropdown(0, y, L("Bar"), {
        { value = "top"; text = "Top bar"; }, { value = "bottom"; text = "Bottom bar"; }, { value = "hidden"; text = "Hidden"; },
    }, element.bar, function(value) element.bar = value; Changed(); end);
    LabeledDropdown(right, y, L("Zone"), {
        { value = "left"; text = "Left"; }, { value = "center"; text = "Centre"; }, { value = "right"; text = "Right"; },
    }, element.zone, function(value) element.zone = value; Changed(); end);
    y = y + 56;
    UI.Slider(page, 0, y, half, L("Order in the zone"), 1, 10, 1, element.order or 1, function(value) element.order = value; Changed(); end);
    UI.Slider(page, right, y, half, L("Text size"), 10, 20, 1, element.size or 13, function(value) element.size = value; Changed(); end, " px");
    y = y + 50;
    UI.Toggle(page, 0, y, half, L("Show the label"), element.label == true, function(value) element.label = value; Changed(); end);
    if (definition.currencies) then
        UI.Toggle(page, right, y, half, L("Show the icons"), element.icons ~= false, function(value) element.icons = value; Changed(); end);
    end
    y = y + 34;
    LabeledDropdown(0, y, L("Text style"), Grommey.UnitFrames.TextStyles(), element.style or "outline", function(value) element.style = value; Changed(); end);
    if (definition.formats) then
        LabeledDropdown(right, y, L("Format"), definition.formats, element.format, function(value) element.format = value; Changed(); end);
    end
    y = y + 58;

    -- Text colour squares
    UI.Label(page, 0, y, width, 18, L("Text colour"));
    local swatchX = 0;
    for _, color in ipairs(Grommey.UnitFrames.TextColors) do
        local preview = (color.key == "accent") and Grommey.Profile.theme.accent or color;
        UI.Swatch(page, swatchX + 8, y + 22, 26, preview, function() element.color = color.key; Changed(); Reopen(); end,
            function() return (element.color or "white") == color.key; end);
        swatchX = swatchX + 40;
    end
    y = y + 60;

    -- Which currencies the currencies element shows
    if (definition.currencies) then
        local wallet = Call(player, "GetWallet");
        local names = {};
        if (wallet) then for index = 1, wallet:GetSize() do table.insert(names, wallet:GetItem(index):GetName()); end end
        table.sort(names);
        -- A long wallet scrolls
        local area = UI.ScrollArea(page, 0, y, width, page:GetHeight() - y);
        local columnWidth = math.floor((area.contentWidth - 30) / 2);
        for index, name in ipairs(names) do
            local column = (index - 1) % 2;
            local row = math.floor((index - 1) / 2);
            UI.Toggle(area.content, column * (columnWidth + 30), row * 26, columnWidth, name, settings.currencies[name] == true, function(value)
                settings.currencies[name] = value or nil;
                Changed();
            end);
        end
        area.Fit(math.ceil(#names / 2) * 26);
    end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Module

local function ElementDefaults(bar, zone, order, label, format)
    return { bar = bar; zone = zone; order = order; label = label; format = format; color = "white"; size = 13; style = "outline"; icons = true; };
end

Grommey.Modules.Register({
    id = "InfoBar";
    name = "Info bar";
    description = "Money, currencies, bags, durability, FPS and time along the edge of the screen.";
    enabledByDefault = true;
    defaults = {
        bars = {
            top = { enabled = true; height = 26; };
            bottom = { enabled = false; height = 26; };
        };
        elements = {
            money = ElementDefaults("top", "left", 1, false, "full");
            currencies = ElementDefaults("top", "left", 2, false, nil);
            bags = ElementDefaults("top", "right", 1, true, "free");
            durability = ElementDefaults("top", "right", 2, true, "average");
            fps = ElementDefaults("top", "right", 3, true, nil);
            clock = ElementDefaults("top", "right", 4, false, "24h");
            character = ElementDefaults("top", "center", 1, false, "nameLevel");
            sessionTime = ElementDefaults("top", "center", 2, true, nil);
            sessionMoney = ElementDefaults("top", "center", 3, true, "total");
            memory = ElementDefaults("top", "right", 5, true, nil);
        };
        currencies = {};
    };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();
        frameStart = Turbine.Engine.GetGameTime();
        LoadSession();
        SaveSession();
        Build();
        Grommey.On("HudToggled", function() for _, bar in pairs(bars) do bar:SetVisible(not Grommey.HudHidden); end end);
        Grommey.On("ThemeChanged", function() if (settingsRoot) then Build(); end end);
    end;

    Disable = function()
        SaveSession();
        DestroyBars();
        settingsRoot = nil;
    end;

    BuildOptions = BuildOptions;

    SetupOptions = function(page, width, settings)
        local half = math.floor((width - 30) / 2);
        UI.Toggle(page, 0, 0, half, L("Top bar"), settings.bars.top.enabled, function(value) settings.bars.top.enabled = value; end);
        UI.Toggle(page, half + 30, 0, half, L("Bottom bar"), settings.bars.bottom.enabled, function(value) settings.bars.bottom.enabled = value; end);
        UI.Label(page, 0, 44, width, 18, L("Shown elements"), { role = "dim"; });
        for index, definition in ipairs(Elements) do
            local element = settings.elements[definition.key];
            local column = (index - 1) % 2;
            local row = math.floor((index - 1) / 2);
            UI.Toggle(page, column * (half + 30), 70 + row * 32, half, L(definition.name), element.bar ~= "hidden", function(value)
                -- Back on the top bar unless the bottom one is the only one on
                local onBar = (settings.bars.top.enabled or not settings.bars.bottom.enabled) and "top" or "bottom";
                element.bar = value and onBar or "hidden";
            end);
        end
    end;
});

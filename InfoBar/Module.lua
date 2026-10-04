-- Info bars: up to two bars (top and bottom of the screen), each with a left, centre and right zone.
-- Every element (money, currencies, bags, durability, FPS, time) chooses its bar, zone, order,
-- label, colour, text size, outline and value format.

local Theme = Grommey.Theme;
local UI = Grommey.UI;

local PAD = 12;
local SEPARATOR_GAP = 10;
local UPDATE_DELAY = 1;

local bars = {};          -- "top" / "bottom" = window
local settingsRoot = nil;
local player = nil;
local frames, frameStart, fps = 0, 0, 0;

local function Call(object, method, ...)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, a, b, c = pcall(object[method], object, ...);
    if (ok) then return a, b, c; end
    return nil;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Values: each returns the label and the value text (markup allowed)

local function Money(element)
    local attributes = Call(player, "GetAttributes");
    local copper = Call(attributes, "GetMoney");
    local gold, silver;
    if (copper ~= nil) then
        gold = math.floor(copper / 100000);
        silver = math.floor(copper / 100) % 1000;
        copper = copper % 100;
    else
        copper, silver, gold = Call(attributes, "GetMoneyComponents");
        if (gold == nil) then return nil; end
    end
    if (element.format == "gold") then return L("Money"), "<rgb=#E8C45C>" .. gold .. L(" g") .. "</rgb>"; end
    local text = "";
    if (gold > 0) then text = "<rgb=#E8C45C>" .. gold .. L(" g") .. "</rgb> "; end
    if (gold > 0 or silver > 0) then text = text .. "<rgb=#C8CCD2>" .. silver .. L(" s") .. "</rgb> "; end
    return L("Money"), text .. "<rgb=#C88A52>" .. copper .. L(" c") .. "</rgb>";
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
};

local function Clicked(key)
    if (key == "bags" and Grommey.Bags.Instance) then Grommey.Bags.Instance:Toggle(); end
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
    if (definition.key == "bags") then
        label:SetMouseVisible(true);
        label.MouseClick = function() Clicked("bags"); end
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
            if (now >= nextUpdate) then nextUpdate = now + UPDATE_DELAY; RefreshAll(); end
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
        for index, name in ipairs(names) do
            local column = (index - 1) % 2;
            local row = math.floor((index - 1) / 2);
            UI.Toggle(page, column * right, y + row * 26, half, name, settings.currencies[name] == true, function(value)
                settings.currencies[name] = value or nil;
                Changed();
            end);
        end
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
        };
        currencies = {};
    };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();
        frameStart = Turbine.Engine.GetGameTime();
        Build();
        Grommey.On("HudToggled", function() for _, bar in pairs(bars) do bar:SetVisible(not Grommey.HudHidden); end end);
        Grommey.On("ThemeChanged", function() if (settingsRoot) then Build(); end end);
    end;

    Disable = function()
        DestroyBars();
        settingsRoot = nil;
    end;

    BuildOptions = BuildOptions;
});

Grommey.AddTranslations({
    ["Info bar"] = "Barre d'infos",
    ["Money, currencies, bags, durability, FPS and time along the edge of the screen."] = "Argent, monnaies, sacs, durabilité, FPS et heure sur le bord de l'écran.",
    ["Money"] = "Argent",
    ["Currencies"] = "Monnaies",
    ["Durability"] = "Durabilité",
    ["Free bag slots"] = "Emplacements des sacs",
    ["Frames per second"] = "Images par seconde (FPS)",
    ["Time"] = "Heure",
    [" g"] = " o",
    [" s"] = " a",
    [" c"] = " c",
    ["Gold, silver and copper"] = "Or, argent et cuivre",
    ["Gold only"] = "Or seulement",
    ["Used / total"] = "Occupés / total",
    ["Average"] = "Moyenne",
    ["Most worn piece"] = "Pièce la plus usée",
    ["24 hours"] = "24 heures",
    ["12 hours"] = "12 heures",
    ["Elements"] = "Éléments",
    ["Top bar"] = "Barre du haut",
    ["Bottom bar"] = "Barre du bas",
    ["Height"] = "Hauteur",
    ["Bar"] = "Barre",
    ["Hidden"] = "Masqué",
    ["Zone"] = "Zone",
    ["Centre"] = "Centre",
    ["Order in the zone"] = "Ordre dans la zone",
    ["Text size"] = "Taille du texte",
    ["Show the label"] = "Afficher le libellé",
    ["Show the icons"] = "Afficher les icônes",
    ["Format"] = "Format",
    ["Text colour"] = "Couleur du texte",
});

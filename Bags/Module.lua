-- Bags module: replaces the game bags with a single window sorted by category.

local window = nil;
local LotroUI = Turbine.UI.Lotro.LotroUI;
local Element = Turbine.UI.Lotro.LotroUIElement;
local NATIVE_BAGS = { "Backpack1", "Backpack2", "Backpack3", "Backpack4", "Backpack5", "Backpack6" };

local function SetNativeBags(enabled)
    for _, name in ipairs(NATIVE_BAGS) do
        if (Element[name] ~= nil) then pcall(LotroUI.SetEnabled, Element[name], enabled); end
    end
end

-- Two bag plugins at once fight over the bag keys, say so
local function WarnAboutOtherBagPlugins()
    local ok, plugins = pcall(Turbine.PluginManager.GetLoadedPlugins);
    if (not ok or plugins == nil) then return; end
    for _, loaded in ipairs(plugins) do
        local name = loaded.Name or "";
        if (name == "Prime Bags" or name == "HugeBag") then
            Grommey.Print(string.format(L("%s is also loaded, unload it to avoid two bag windows: /plugins unload %s"), name, name));
        end
    end
end

local function Refresh()
    if (window) then window:RequestLayout(); end
end

local selectedSection = "display";
local selectedCategory = nil;

local function Reopen() Grommey.Options.ShowPage("module:Bags"); end

-- Look of the bag
local function BuildDisplayOptions(page, width, settings, Changed)
    local UI = Grommey.UI;
    local half = math.floor((width - 30) / 2);
    local y = 0;
    UI.Toggle(page, 0, y, half, L("Sort items by category"), settings.groupByCategory, function(value) settings.groupByCategory = value; Changed(); end);
    UI.Slider(page, half + 30, y - 6, half, L("Columns without categories"), 6, 20, 1, settings.flatColumns, function(value) settings.flatColumns = value; Changed(); end);

    y = y + 50;
    UI.Slider(page, 0, y, half, L("Categories side by side"), 1, 6, 1, settings.categoryColumns, function(value) settings.categoryColumns = value; Changed(); end);
    UI.Slider(page, half + 30, y + 50, half, L("Items per row"), 3, 12, 1, settings.itemsPerRow, function(value) settings.itemsPerRow = value; Changed(); end);
    UI.Slider(page, half + 30, y, half, L("Slot size"), 36, 48, 2, settings.slotSize, function(value) settings.slotSize = value; Changed(); end, " px");
    UI.Slider(page, 0, y + 50, half, L("Maximum height"), 30, 100, 5, settings.maxHeight, function(value) settings.maxHeight = value; Changed(); end, " %");

    y = y + 110;
    UI.Toggle(page, 0, y, width, L("Show new items in their own section"), settings.showNew, function(value) settings.showNew = value; Changed(); end);

    -- Currencies shown at the bottom of the bag, from the wallet
    y = y + 44;
    UI.Header(page, 0, y, width, L("Currencies shown at the bottom"));
    local wallet = Turbine.Gameplay.LocalPlayer.GetInstance():GetWallet();
    local names = {};
    for index = 1, wallet:GetSize() do table.insert(names, wallet:GetItem(index):GetName()); end
    table.sort(names);
    if (#names == 0) then
        UI.Label(page, 0, y + 36, width, 20, L("Your wallet is empty for now."), { role = "dim"; });
    end
    for position, name in ipairs(names) do
        local column = (position - 1) % 2;
        local row = math.floor((position - 1) / 2);
        UI.Toggle(page, column * (half + 30), y + 36 + row * 28, half, name, settings.currencies[name] == true, function(value)
            settings.currencies[name] = value or nil;
            Changed();
        end);
    end
end

-- Categories made by the player, and the items put in them
local function BuildCategoryOptions(page, width, settings, Changed)
    local UI = Grommey.UI;
    local Theme = Grommey.Theme;
    settings.customCategories = settings.customCategories or {};
    settings.itemCategory = settings.itemCategory or {};
    local categories = settings.customCategories;
    local listWidth = 250;
    local right = listWidth + 24;
    local rightWidth = width - right;

    -- New category
    local nameBox = UI.TextInput(page, 0, 0, listWidth - 90, "");
    UI.Button(page, listWidth - 82, 0, 82, L("Create"), function()
        local name = string.match(nameBox:GetText() or "", "^%s*(.-)%s*$");
        if (name == "") then return; end
        local number = settings.nextCategory or 1;
        settings.nextCategory = number + 1;
        table.insert(categories, { id = "c" .. number; name = name; });
        selectedCategory = "c" .. number;
        Changed();
        Reopen();
    end, "accent");

    if (Grommey.Bags.FindCustom(settings, selectedCategory or "") == nil) then selectedCategory = categories[1] and categories[1].id; end

    -- Item count of each category
    local counts = {};
    for _, id in pairs(settings.itemCategory) do counts[id] = (counts[id] or 0) + 1; end

    -- List of the categories, click one to see its items
    local y = 40;
    if (#categories == 0) then
        UI.Label(page, 0, y, listWidth, 60, L("No category yet. Give it a name and create it."), { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end
    for _, category in ipairs(categories) do
        local selected = (category.id == selectedCategory);
        local row = UI.Frame(page, 0, y, listWidth, 30, selected and "raised" or "panel", selected and "accent" or "border");
        UI.Label(row.inner, 10, 0, listWidth - 60, 28, category.name, { mouse = false; });
        UI.Label(row.inner, listWidth - 52, 0, 40, 28, tostring(counts[category.id] or 0), { size = 12; role = "dim"; align = Turbine.UI.ContentAlignment.MiddleRight; });
        row.inner.MouseClick = function() selectedCategory = category.id; Reopen(); end
        y = y + 34;
        if (y > page:GetHeight() - 40) then break; end
    end

    local category, position = Grommey.Bags.FindCustom(settings, selectedCategory or "");
    if (category == nil) then return; end

    -- Name, order and removal of the selected category
    local renameBox = UI.TextInput(page, right, 0, rightWidth - 120, category.name);
    UI.Button(page, width - 112, 0, 112, L("Rename"), function()
        local name = string.match(renameBox:GetText() or "", "^%s*(.-)%s*$");
        if (name ~= "") then category.name = name; Changed(); Reopen(); end
    end);
    local buttonWidth = math.floor((rightWidth - 16) / 3);
    UI.Button(page, right, 36, buttonWidth, L("Move up"), function()
        if (position > 1) then categories[position], categories[position - 1] = categories[position - 1], categories[position]; Changed(); Reopen(); end
    end);
    UI.Button(page, right + buttonWidth + 8, 36, buttonWidth, L("Move down"), function()
        if (position < #categories) then categories[position], categories[position + 1] = categories[position + 1], categories[position]; Changed(); Reopen(); end
    end);
    UI.Button(page, right + 2 * (buttonWidth + 8), 36, buttonWidth, L("Delete"), function()
        table.remove(categories, position);
        -- Its items go back to their game category
        for name, id in pairs(settings.itemCategory) do if (id == category.id) then settings.itemCategory[name] = nil; end end
        selectedCategory = nil;
        Changed();
        Reopen();
    end, "danger");

    -- Drop zone: an item dragged from the bag goes into this category. Nothing may sit behind
    -- a quickslot, its border is four thin lines around it.
    local zoneY = 80;
    for _, line in ipairs({ { 0, 0, 38, 1 }, { 0, 37, 38, 1 }, { 0, 1, 1, 36 }, { 37, 1, 1, 36 } }) do
        local edge = Turbine.UI.Control();
        edge:SetParent(page);
        edge:SetPosition(right + line[1], zoneY + line[2]);
        edge:SetSize(line[3], line[4]);
        edge:SetBackColor(Theme.Color("accent"));
        edge:SetMouseVisible(false);
    end
    local drop = Turbine.UI.Lotro.Quickslot();
    drop:SetParent(page);
    drop:SetPosition(right + 1, zoneY + 1);
    drop:SetSize(36, 36);
    drop:SetAllowDrop(true);
    drop.ShortcutChanged = function()
        local shortcut = drop:GetShortcut();
        local item = shortcut and shortcut.GetItem and shortcut:GetItem();
        if (item ~= nil and item:GetName()) then
            settings.itemCategory[item:GetName()] = category.id;
            Changed();
        end
        -- Leave the slot empty for the next item (a quickslot keeping a shortcut can crash the client
        -- on unload), then draw the page again
        drop.ShortcutChanged = nil;
        pcall(drop.SetShortcut, drop, Turbine.UI.Lotro.Shortcut(Turbine.UI.Lotro.ShortcutType.Undefined, ""));
        Grommey.Delay("BagsCategoryDrop", 0.1, Reopen);
    end
    UI.Label(page, right + 48, zoneY, rightWidth - 48, 38, L("Drag an item here to put it in this category. You can also drop it on a category title in the bag."),
        { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.MiddleLeft; });

    -- Items of the category, the cross sends one back to its game category
    local names = {};
    for name, id in pairs(settings.itemCategory) do if (id == category.id) then table.insert(names, name); end end
    table.sort(names);
    y = zoneY + 52;
    if (#names == 0) then
        UI.Label(page, right, y, rightWidth, 20, L("No item in this category yet."), { size = 12; role = "dim"; });
    end
    for _, name in ipairs(names) do
        UI.Label(page, right, y, rightWidth - 30, 22, name);
        local remove = UI.Label(page, width - 22, y, 22, 22, "x", { role = "danger"; mouse = true; align = Turbine.UI.ContentAlignment.MiddleCenter; });
        remove.MouseClick = function() settings.itemCategory[name] = nil; Changed(); Reopen(); end
        y = y + 24;
        if (y > page:GetHeight() - 24) then break; end
    end
end

local function BuildOptions(page, width, settings)
    local UI = Grommey.UI;
    local function Changed()
        Grommey.Profiles.RequestSave();
        Refresh();
    end

    UI.Header(page, 0, 16, width, L("Bags"));
    UI.Button(page, width - 180, 14, 180, L("Open the bags"), function() if (window) then window:SetVisible(true); end end, "accent");

    local x = 0;
    for _, section in ipairs({ { key = "display"; text = L("Display"); }, { key = "categories"; text = L("My categories"); } }) do
        UI.Button(page, x, 52, 170, section.text, function() selectedSection = section.key; Reopen(); end, (selectedSection == section.key) and "accent" or nil);
        x = x + 178;
    end

    local holder = Turbine.UI.Control();
    holder:SetParent(page);
    holder:SetPosition(0, 100);
    holder:SetSize(width, page:GetHeight() - 100);
    if (selectedSection == "categories") then
        BuildCategoryOptions(holder, width, settings, Changed);
    else
        BuildDisplayOptions(holder, width, settings, Changed);
    end
end

Grommey.Modules.Register({
    id = "Bags";
    name = "Bags";
    description = "All your bags in one window, sorted by category.";
    enabledByDefault = true;
    defaults = {
        groupByCategory = true;
        flatColumns = 12;
        categoryColumns = 3;
        itemsPerRow = 6;
        slotSize = 38;
        maxHeight = 70;
        showNew = true;
        collapsed = {};
        currencies = {};
        -- Categories of the player and the items in them
        customCategories = {};
        itemCategory = {};
    };

    Enable = function(settings)
        SetNativeBags(false);
        window = Grommey.Bags.Window(settings);
        -- Other modules (info bar) can open the bag
        Grommey.Bags.Instance = window;
        Grommey.On("ThemeChanged", Refresh);
        Grommey.On("HudToggled", function(hidden) if (hidden and window) then window:SetVisible(false); end end);
        WarnAboutOtherBagPlugins();
    end;

    Disable = function()
        if (window) then window:Destroy(); window = nil; end
        Grommey.Bags.Instance = nil;
        Grommey.Off("ThemeChanged", Refresh);
        SetNativeBags(true);
    end;

    BuildOptions = BuildOptions;

    SetupOptions = function(page, width, settings)
        local UI = Grommey.UI;
        UI.Toggle(page, 0, 0, width, L("Sort items by category"), settings.groupByCategory, function(value) settings.groupByCategory = value; end);
        UI.Toggle(page, 0, 34, width, L("Show new items in their own section"), settings.showNew, function(value) settings.showNew = value; end);
        UI.Slider(page, 0, 76, 300, L("Items per row"), 3, 12, 1, settings.itemsPerRow, function(value) settings.itemsPerRow = value; end);
        UI.Slider(page, 0, 126, 300, L("Slot size"), 36, 48, 2, settings.slotSize, function(value) settings.slotSize = value; end, " px");
        UI.Label(page, 0, 186, width, 36, L("The bag replaces the game bags. Open it with the usual bag key."), { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end;
});

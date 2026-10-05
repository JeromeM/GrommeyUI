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

local function BuildOptions(page, width, settings)
    local UI = Grommey.UI;
    local function Changed()
        Grommey.Profiles.RequestSave();
        Refresh();
    end

    local y = 16;
    UI.Header(page, 0, y, width, L("Bags"));
    UI.Label(page, 0, y + 32, width, 20, L("Items are always sorted by category. Click a category title to fold it."), { size = 12; role = "dim"; });
    UI.Button(page, width - 180, y - 2, 180, L("Open the bags"), function() if (window) then window:SetVisible(true); end end, "accent");

    y = y + 66;
    local half = math.floor((width - 30) / 2);
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

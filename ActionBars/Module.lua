-- Action bars: extra bars of game shortcuts (skills, items, chat commands) drawn in the GrommeyUI style.
-- The layout of the bars lives in the profile, the shortcuts in a file of the character, since
-- skills differ from one class to another. Plugins cannot bind keys: these bars are used with the mouse.
--
-- Unlocked bars show their empty slots and a small cross on each shortcut to take it off.
-- A consumables bar fills itself with the food, potions and scrolls found in the backpack;
-- its cross hides an item from the bar.

local Theme = Grommey.Theme;
local UI = Grommey.UI;
local ShortcutType = Turbine.UI.Lotro.ShortcutType;

local SLOT = 36;            -- game quickslot
local CELL = SLOT + 2;      -- with its 1 pixel border
local MAX_BARS = 10;
local UPDATE_DELAY = 0.1;
local FADED_OPACITY = 0.25;
local SHORTCUTS_FILE = "GrommeyUI_ActionBars";
local SCAN_DELAY = 1;       -- consumables bars look at the backpack every second
-- Game item categories of the consumables, same list as the bag
local CONSUMABLES = (Grommey.Bags and Grommey.Bags.CategoryByKey and Grommey.Bags.CategoryByKey.Consumables
    and Grommey.Bags.CategoryByKey.Consumables.ids) or { 28, 55, 57, 189, 190, 292, 25 };

local bars = {};            -- bar id = window
local settingsRoot = nil;
local shortcuts = nil;      -- bar id = { slot index = { type, data } }, saved per character
local player = nil;
local callbacks = {};
local moving = false;

local function SaveShortcuts()
    Grommey.Delay("SaveActionBars", 1, function()
        Grommey.Storage.Save(Turbine.DataScope.Character, SHORTCUTS_FILE, shortcuts);
    end);
end

local function BarSettings(id)
    for _, bar in ipairs(settingsRoot.bars) do
        if (bar.id == id) then return bar; end
    end
    return nil;
end

local function IsEmpty(shortcut)
    if (shortcut == nil) then return true; end
    local ok, shortcutType = pcall(shortcut.GetType, shortcut);
    return (not ok) or shortcutType == nil or shortcutType == ShortcutType.Undefined;
end

local function EmptyShortcut()
    return Turbine.UI.Lotro.Shortcut(ShortcutType.Undefined, "");
end

------------------------------------------------------------------------------------------------------------------------------------------
-- One slot: border, dark field, the game quickslot and the cross to take the shortcut off

local function Fill(parent, x, y, width, height, role)
    local control = Turbine.UI.Control();
    control:SetParent(parent);
    control:SetPosition(x, y);
    control:SetSize(width, height);
    control:SetBackColor(Theme.Color(role));
    control:SetMouseVisible(false);
    return control;
end

-- "0x0347000139044C34,0x70000D5D" -> "0x0000000000000000,0x70000D5D"
local function GenericItemData(data)
    local item = string.match(data or "", ",(0x%x+)$");
    if (item == nil) then return data; end
    return "0x0000000000000000," .. item;
end

local function CreateSlot(window, id, index, auto)
    local slot = Turbine.UI.Control();
    slot:SetParent(window);
    slot:SetSize(CELL, CELL);
    slot:SetMouseVisible(false);

    -- Nothing may sit behind the quickslot, the game then leaves its icon out:
    -- the border is four thin lines and the dark field is only shown on empty slots
    slot.field = Fill(slot, 1, 1, SLOT, SLOT, "field");
    Fill(slot, 0, 0, CELL, 1, "border");
    Fill(slot, 0, CELL - 1, CELL, 1, "border");
    Fill(slot, 0, 1, 1, CELL - 2, "border");
    Fill(slot, CELL - 1, 1, 1, CELL - 2, "border");

    slot.quickslot = Turbine.UI.Lotro.Quickslot();
    slot.quickslot:SetParent(slot);
    slot.quickslot:SetPosition(1, 1);
    slot.quickslot:SetSize(SLOT, SLOT);
    slot.quickslot:SetAllowDrop(not auto);
    slot.quickslot:SetUseOnRightClick(false);

    slot.QuickslotFilled = function() return not IsEmpty(slot.quickslot:GetShortcut()); end
    slot.IsFilled = function() return slot.QuickslotFilled() or slot.itemShown == true; end

    -- Bag item shown in place of the quickslot, made on first use. Its icon is drawn 3 pixels
    -- from its corner, so it sits at 0,0 to centre the icon in the slot.
    slot.ShowItem = function(item)
        if (item ~= nil and slot.itemControl == nil) then
            slot.itemControl = Turbine.UI.Lotro.ItemControl();
            slot.itemControl:SetParent(slot);
            slot.itemControl:SetPosition(0, 0);
            slot.itemControl:SetZOrder(2);
        end
        if (slot.itemControl) then
            slot.itemControl:SetItem(item);
            slot.itemControl:SetVisible(item ~= nil);
        end
        slot.itemShown = (item ~= nil);
        slot.quickslot:SetVisible(item == nil);
    end

    slot.clear = UI.Label(slot, CELL - 16, 2, 14, 14, "x", { size = 11; mouse = true; align = Turbine.UI.ContentAlignment.MiddleCenter; });
    slot.clear:SetBackColor(Theme.Color("danger"));
    slot.clear:SetZOrder(5);

    if (auto) then
        -- Total quantity of the item in the backpack, every stack together
        slot.count = Turbine.UI.Label();
        slot.count:SetParent(slot);
        slot.count:SetPosition(1, 1);
        slot.count:SetSize(SLOT - 2, SLOT - 1);
        slot.count:SetFont(Theme.Font(12, false));
        slot.count:SetFontStyle(Turbine.UI.FontStyle.Outline);
        slot.count:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
        slot.count:SetForeColor(Turbine.UI.Color(1, 1, 1));
        slot.count:SetTextAlignment(Turbine.UI.ContentAlignment.BottomRight);
        slot.count:SetMouseVisible(false);
        slot.count:SetZOrder(4);
        -- The cross hides this item from the bar
        slot.clear.MouseClick = function() if (slot.entry) then window.Hide(slot.entry.name); end end
        return slot;
    end

    -- Shortcut saved for this character, the game refuses the ones that no longer exist
    local saved = shortcuts[id] and shortcuts[id][index];
    if (saved ~= nil and saved.type ~= nil) then
        local data = saved.data or "";
        -- Item shortcuts saved before 0.5 still name a stack
        if (saved.type == ShortcutType.Item) then data = GenericItemData(data); end
        local ok, shortcut = pcall(Turbine.UI.Lotro.Shortcut, saved.type, data);
        if (ok and shortcut) then pcall(slot.quickslot.SetShortcut, slot.quickslot, shortcut); end
    end

    -- A shortcut dropped on the slot (or replaced) is saved at once
    slot.quickslot.ShortcutChanged = function()
        local shortcut = slot.quickslot:GetShortcut();
        -- An item shortcut names one stack ("stack id,item id"): keep only the item, so any stack
        -- of the same potion or food is used and the shortcut survives an empty stack
        if (not IsEmpty(shortcut) and shortcut:GetType() == ShortcutType.Item) then
            local generic = GenericItemData(shortcut:GetData());
            if (generic ~= shortcut:GetData()) then
                local ok, replacement = pcall(Turbine.UI.Lotro.Shortcut, ShortcutType.Item, generic);
                -- Changing the shortcut calls this function again with the generic one
                if (ok and replacement) then slot.quickslot:SetShortcut(replacement); return; end
            end
        end
        shortcuts[id] = shortcuts[id] or {};
        if (IsEmpty(shortcut)) then
            shortcuts[id][index] = nil;
        else
            shortcuts[id][index] = { type = shortcut:GetType(); data = shortcut:GetData(); };
        end
        SaveShortcuts();
        window.Refresh();
    end

    slot.clear.MouseClick = function()
        slot.quickslot:SetShortcut(EmptyShortcut());
        if (shortcuts[id]) then shortcuts[id][index] = nil; end
        SaveShortcuts();
        window.Refresh();
    end
    return slot;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Consumables found in the backpack, one entry per kind of item with the total quantity

local categoryRank = {};
for rank, category in ipairs(CONSUMABLES) do categoryRank[category] = rank; end

local function Call(object, method, ...)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object, ...);
    if (ok) then return value; end
    return nil;
end

local reportedFailure = false;

local function ScanConsumables(hidden)
    local entries, byKey = {}, {};
    local backpack = Call(player, "GetBackpack");
    if (backpack == nil) then return entries; end
    for index = 1, backpack:GetSize() do
        local item = backpack:GetItem(index);
        local category = item and Call(Call(item, "GetItemInfo"), "GetCategory");
        local name = item and Call(item, "GetName");
        if (category ~= nil and categoryRank[category] and name and not hidden[name]) then
            local entry = byKey[name];
            if (entry == nil) then
                -- Shortcut to this kind of item, whatever the stack
                local ok, shortcut = pcall(Turbine.UI.Lotro.Shortcut, item);
                if (not ok and not reportedFailure) then
                    -- Said once, so a client that refuses it shows why the bar stays empty
                    reportedFailure = true;
                    Grommey.Print("<rgb=#FF6060>" .. L("Consumables bar: the game refuses item shortcuts.") .. " " .. tostring(shortcut) .. "</rgb>");
                end
                -- The game gives this shortcut without the item id, so it is kept as it is (it names
                -- this stack, the next scan picks another stack once it is empty)
                local data = (ok and shortcut and Call(shortcut, "GetData")) or "";
                if (ok and string.match(data, ",0x%x+$")) then
                    local genericOk, generic = pcall(Turbine.UI.Lotro.Shortcut, ShortcutType.Item, GenericItemData(data));
                    if (genericOk and generic) then shortcut = generic; end
                end
                entry = { name = name; category = category; count = 0; item = item; shortcut = ok and shortcut or nil; };
                byKey[name] = entry;
                table.insert(entries, entry);
            end
            if (entry) then entry.count = entry.count + (Call(item, "GetQuantity") or 1); end
        end
    end
    table.sort(entries, function(a, b)
        if (a.category ~= b.category) then return categoryRank[a.category] < categoryRank[b.category]; end
        return a.name < b.name;
    end);
    return entries;
end

-- What the consumables bars see in the backpack (/gui consumables), written to a file of the
-- account (PluginData/<account>/AllServers/GrommeyUI_Diagnostic.plugindata) to be read outside the game
function Grommey.ActionBarsConsumablesReport()
    local lines = {};
    local function Add(text) table.insert(lines, text); end
    if (settingsRoot == nil) then Add("ActionBars: module off"); end
    for _, bar in ipairs((settingsRoot and settingsRoot.bars) or {}) do
        Add(bar.id .. " " .. tostring(bar.name) .. " kind " .. tostring(bar.kind) .. " enabled " .. tostring(bar.enabled) .. " built " .. tostring(bars[bar.id] ~= nil));
    end
    local backpack = Call(player, "GetBackpack");
    if (backpack == nil) then Add("no backpack"); end
    for index = 1, (backpack and backpack:GetSize()) or 0 do
        local item = backpack:GetItem(index);
        if (item ~= nil) then
            local category = Call(Call(item, "GetItemInfo"), "GetCategory");
            local ok, shortcut = pcall(Turbine.UI.Lotro.Shortcut, item);
            local data = (ok and shortcut and Call(shortcut, "GetData")) or tostring(shortcut);
            Add(index .. " " .. tostring(Call(item, "GetName")) .. " | cat " .. tostring(category)
                .. (categoryRank[category or -1] and " [conso]" or "") .. " | shortcut " .. tostring(ok) .. " " .. tostring(data));
        end
    end
    local saved = pcall(Turbine.PluginData.Save, Turbine.DataScope.Account, "GrommeyUI_Diagnostic", lines);
    Grommey.Print(saved and L("Report written to the plugin data folder.") or "Report: save failed");
end

------------------------------------------------------------------------------------------------------------------------------------------
-- One bar: a window holding its slots in lines

local function Unlocked() return settingsRoot ~= nil and (not settingsRoot.locked or moving); end

local function CreateBar(barSettings, position)
    local id = barSettings.id;
    local window = Turbine.UI.Window();
    window:SetMouseVisible(false);
    window.slots = {};

    local columns = math.max(1, math.min(barSettings.perLine, barSettings.slots));
    local lines = math.ceil(barSettings.slots / columns);
    local step = CELL + barSettings.spacing;
    window:SetSize(columns * step - barSettings.spacing, lines * step - barSettings.spacing);

    local auto = (barSettings.kind == "consumables");
    for index = 1, barSettings.slots do
        local slot = CreateSlot(window, id, index, auto);
        slot:SetPosition(((index - 1) % columns) * step, math.floor((index - 1) / columns) * step);
        window.slots[index] = slot;
    end

    -- Shows or hides the bar from its conditions, and the empty slots and crosses from the lock
    window.Refresh = function()
        local unlocked = Unlocked();
        for _, slot in ipairs(window.slots) do
            local filled = slot.IsFilled();
            slot:SetVisible(filled or unlocked or barSettings.showEmpty);
            -- The bag item control can have the field behind it, the quickslot cannot
            slot.field:SetVisible(not slot.QuickslotFilled());
            slot.clear:SetVisible(filled and unlocked);
        end

        local shown = not Grommey.HudHidden;
        if (shown and not unlocked) then
            local mode = barSettings.visibility;
            if (mode == "combat") then shown = player:IsInCombat();
            elseif (mode == "peace") then shown = not player:IsInCombat();
            elseif (mode == "target") then shown = player:GetTarget() ~= nil;
            end
        end
        window:SetVisible(shown);
    end

    -- Consumables bar: puts the backpack content in the slots when it changes
    window.signature = nil;
    window.Scan = function()
        barSettings.hidden = barSettings.hidden or {};
        local entries = ScanConsumables(barSettings.hidden);
        local parts = {};
        for index = 1, math.min(#entries, #window.slots) do
            table.insert(parts, entries[index].name .. "=" .. entries[index].count);
        end
        local signature = table.concat(parts, "|");
        if (signature == window.signature) then return; end
        window.signature = signature;
        for index, slot in ipairs(window.slots) do
            local entry = entries[index];
            if (entry ~= nil) then
                if (entry.shortcut) then pcall(slot.quickslot.SetShortcut, slot.quickslot, entry.shortcut); end
                -- No usable shortcut: the bag item itself is shown, used with a right click like in the bag
                slot.ShowItem((not slot.QuickslotFilled()) and entry.item or nil);
                slot.count:SetText(entry.count > 1 and tostring(entry.count) or "");
            else
                slot.quickslot:SetShortcut(EmptyShortcut());
                slot.ShowItem(nil);
                slot.count:SetText("");
            end
            slot.entry = entry;
        end
        window.Refresh();
    end
    window.Hide = function(name)
        barSettings.hidden = barSettings.hidden or {};
        barSettings.hidden[name] = true;
        Grommey.Profiles.RequestSave();
        window.Scan();
    end

    -- Faded bars come back when the mouse is over them
    window.nextUpdate = 0;
    window.nextScan = 0;
    window:SetWantsUpdates(barSettings.fade == true or auto);
    window.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (auto and now >= window.nextScan) then window.nextScan = now + SCAN_DELAY; window.Scan(); end
        if (not barSettings.fade or now < window.nextUpdate) then return; end
        window.nextUpdate = now + UPDATE_DELAY;
        local over = false;
        local ok, mouseX, mouseY = pcall(Turbine.UI.Display.GetMousePosition);
        if (ok and mouseX) then
            local left, top = window:GetPosition();
            local width, height = window:GetSize();
            over = mouseX >= left and mouseX < left + width and mouseY >= top and mouseY < top + height;
        end
        window:SetOpacity((over or Unlocked()) and 1 or FADED_OPACITY);
    end
    if (not barSettings.fade) then window:SetOpacity(1); end

    window.Destroy = function()
        window:SetWantsUpdates(false);
        -- Other plugins report a client crash when quickslots still hold shortcuts on unload.
        -- The slot stops listening first, so emptying it does not erase the saved shortcut.
        for _, slot in ipairs(window.slots) do
            slot.quickslot.ShortcutChanged = nil;
            pcall(slot.quickslot.SetShortcut, slot.quickslot, nil);
        end
        Grommey.Movers.Unregister("actionbar:" .. id);
        window:SetVisible(false);
    end

    if (auto) then window.Scan(); end
    window.Refresh();
    -- New bars stack upward above the game toolbar, centred
    Grommey.Movers.Register("actionbar:" .. id, window, barSettings.name,
        function() return math.floor((Turbine.UI.Display.GetWidth() - window:GetWidth()) / 2); end,
        function() return Turbine.UI.Display.GetHeight() - 190 - (position - 1) * (CELL + 8) - window:GetHeight(); end);
    return window;
end

local function DestroyBars()
    for id, window in pairs(bars) do window.Destroy(); end
    bars = {};
end

local function Build()
    DestroyBars();
    for position, barSettings in ipairs(settingsRoot.bars) do
        if (barSettings.enabled) then bars[barSettings.id] = CreateBar(barSettings, position); end
    end
end

local function RefreshAll()
    for _, window in pairs(bars) do window.Refresh(); end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Options

local selectedBar = nil;

local function NewBar(kind)
    local number = settingsRoot.nextNumber or (#settingsRoot.bars + 1);
    settingsRoot.nextNumber = number + 1;
    local bar = {
        id = "bar" .. number; name = string.format(L("Bar %d"), number); enabled = true;
        slots = 12; perLine = 12; spacing = 2; visibility = "always"; fade = false; showEmpty = false;
    };
    if (kind == "consumables") then
        bar.kind = kind;
        bar.name = L("Consumables");
        bar.hidden = {};
    end
    table.insert(settingsRoot.bars, bar);
    return bar;
end

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

local function BuildOptions(page, width, settings)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    local function Reopen() Grommey.Options.ShowPage("module:ActionBars"); end
    local function Changed() Grommey.Profiles.RequestSave(); Build(); end

    UI.Header(page, 0, 16, width, L("Action bars"));
    UI.Toggle(page, width - 200, 18, 200, L("Locked"), settings.locked, function(value)
        settings.locked = value;
        Grommey.Profiles.RequestSave();
        RefreshAll();
    end);

    if (BarSettings(selectedBar or "") == nil) then selectedBar = settings.bars[1] and settings.bars[1].id; end
    local items = {};
    for _, bar in ipairs(settings.bars) do table.insert(items, { value = bar.id; text = bar.name; }); end

    local y = 52;
    if (#items > 0) then
        UI.Dropdown(page, 0, y, half, items, selectedBar, function(value) selectedBar = value; Reopen(); end);
    end
    -- Buttons on their own line, wide enough for their text
    y = 90;
    local buttonWidth = 170;
    if (#settings.bars < MAX_BARS) then
        UI.Button(page, 0, y, buttonWidth, L("New bar"), function()
            selectedBar = NewBar().id;
            Changed();
            Reopen();
        end, "accent");
        UI.Button(page, buttonWidth + 10, y, buttonWidth, L("Consumables"), function()
            selectedBar = NewBar("consumables").id;
            Changed();
            Reopen();
        end, "accent");
    end
    if (selectedBar) then
        UI.Button(page, width - buttonWidth, y, buttonWidth, L("Delete"), function()
            for index, bar in ipairs(settings.bars) do
                if (bar.id == selectedBar) then table.remove(settings.bars, index); break; end
            end
            shortcuts[selectedBar] = nil;
            SaveShortcuts();
            selectedBar = nil;
            Changed();
            Reopen();
        end, "danger");
    end

    local bar = BarSettings(selectedBar or "");
    if (bar == nil) then
        UI.Label(page, 0, 140, width, 20, L("No bar yet."), { role = "dim"; });
        return;
    end

    y = 140;
    UI.Toggle(page, 0, y, half, L("Show this bar"), bar.enabled, function(value) bar.enabled = value; Changed(); end);
    local auto = (bar.kind == "consumables");
    if (not auto) then
        UI.Toggle(page, right, y, half, L("Show the empty slots"), bar.showEmpty, function(value) bar.showEmpty = value; Changed(); end);
    end
    y = y + 40;
    UI.Slider(page, 0, y, half, auto and L("Maximum items") or L("Number of slots"), 1, 36, 1, bar.slots, function(value) bar.slots = value; Changed(); end);
    UI.Slider(page, right, y, half, L("Slots per line"), 1, 36, 1, bar.perLine, function(value) bar.perLine = value; Changed(); end);
    y = y + 54;
    UI.Slider(page, 0, y, half, L("Spacing"), 0, 12, 1, bar.spacing, function(value) bar.spacing = value; Changed(); end, " px");
    UI.Label(page, right, y, half, 18, L("Shown"));
    UI.Dropdown(page, right, y + 20, half, Translated({
        { value = "always"; text = "Always"; },
        { value = "combat"; text = "In combat only"; },
        { value = "peace"; text = "Out of combat only"; },
        { value = "target"; text = "With a target"; },
    }), bar.visibility, function(value) bar.visibility = value; Changed(); end);
    y = y + 60;
    UI.Toggle(page, 0, y, width, L("Faded until the mouse is over it"), bar.fade, function(value) bar.fade = value; Changed(); end);
    y = y + 40;

    if (auto) then
        local hiddenCount = 0;
        for _ in pairs(bar.hidden or {}) do hiddenCount = hiddenCount + 1; end
        if (hiddenCount > 0) then
            UI.Button(page, 0, y, half, string.format(L("Show the hidden items again (%d)"), hiddenCount), function()
                bar.hidden = {};
                Changed();
                Reopen();
            end);
            y = y + 40;
        end
        UI.Label(page, 0, y, width, 60, L("This bar fills itself with the food, potions and scrolls of your backpack, with their total quantity. Unlock the bars and use the cross to hide an item you do not want here."),
            { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
        return;
    end
    UI.Label(page, 0, y, width, 60, L("Drag skills, items or chat commands onto the slots. Unlock the bars to see the empty slots and take shortcuts off with the cross. Place the bars with the move mode. The game does not let plugins use keys: these bars are clicked."),
        { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Module

Grommey.Modules.Register({
    id = "ActionBars";
    name = "Action bars";
    description = "Extra bars for your skills, items and commands, used with the mouse.";
    enabledByDefault = true;
    defaults = { locked = false; };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();
        shortcuts = Grommey.Storage.Load(Turbine.DataScope.Character, SHORTCUTS_FILE) or {};
        -- The bar list is not in the defaults, a deleted first bar would come back
        if (settings.bars == nil) then
            settings.bars = {};
            NewBar();
            Grommey.Profiles.RequestSave();
        end
        -- A consumables bar comes once on its own, it can be deleted after that
        if (not settings.consumablesAdded) then
            settings.consumablesAdded = true;
            if (#settings.bars < MAX_BARS) then NewBar("consumables"); end
            Grommey.Profiles.RequestSave();
        end
        Build();

        callbacks = {
            { object = player; eventName = "InCombatChanged"; callback = Grommey.AddCallback(player, "InCombatChanged", RefreshAll); },
            { object = player; eventName = "TargetChanged"; callback = Grommey.AddCallback(player, "TargetChanged", RefreshAll); },
        };
        -- Move mode shows every bar with its empty slots, so they all have their real size
        Grommey.On("MoveModeChanged", function(active) moving = active; if (settingsRoot) then RefreshAll(); end end);
        Grommey.On("HudToggled", function() if (settingsRoot) then RefreshAll(); end end);
        Grommey.On("ThemeChanged", function() if (settingsRoot) then Build(); end end);
    end;

    Disable = function()
        for _, entry in ipairs(callbacks) do Grommey.RemoveCallback(entry.object, entry.eventName, entry.callback); end
        callbacks = {};
        DestroyBars();
        settingsRoot = nil;
    end;

    BuildOptions = BuildOptions;
});

Grommey.AddTranslations({
    ["Action bars"] = "Barres d'action",
    ["Extra bars for your skills, items and commands, used with the mouse."] = "Barres supplémentaires pour tes compétences, objets et commandes, à la souris.",
    ["Bar %d"] = "Barre %d",
    ["Locked"] = "Verrouillées",
    ["New bar"] = "Nouvelle barre",
    ["Delete"] = "Supprimer",
    ["Maximum items"] = "Nombre maximum d'objets",
    ["Report written to the plugin data folder."] = "Rapport écrit dans le dossier PluginData.",
    ["Consumables bar: the game refuses item shortcuts."] = "Barre Consommables : le jeu refuse les raccourcis d'objets.",
    ["Show the hidden items again (%d)"] = "Réafficher les objets masqués (%d)",
    ["This bar fills itself with the food, potions and scrolls of your backpack, with their total quantity. Unlock the bars and use the cross to hide an item you do not want here."] = "Cette barre se remplit toute seule avec la nourriture, les potions et les parchemins de ton sac, avec leur quantité totale. Déverrouille les barres et utilise la croix pour masquer un objet que tu ne veux pas ici.",
    ["No bar yet."] = "Aucune barre pour l'instant.",
    ["Show this bar"] = "Afficher cette barre",
    ["Show the empty slots"] = "Afficher les emplacements vides",
    ["Number of slots"] = "Nombre d'emplacements",
    ["Slots per line"] = "Emplacements par ligne",
    ["Shown"] = "Affichée",
    ["Always"] = "Toujours",
    ["In combat only"] = "En combat seulement",
    ["Out of combat only"] = "Hors combat seulement",
    ["With a target"] = "Avec une cible",
    ["Faded until the mouse is over it"] = "Estompée tant que la souris n'est pas dessus",
    ["Drag skills, items or chat commands onto the slots. Unlock the bars to see the empty slots and take shortcuts off with the cross. Place the bars with the move mode. The game does not let plugins use keys: these bars are clicked."] = "Glisse des compétences, objets ou commandes sur les emplacements. Déverrouille les barres pour voir les emplacements vides et retirer un raccourci avec la croix. Place les barres avec le mode déplacement. Le jeu ne permet pas aux plugins d'utiliser les touches : ces barres s'utilisent au clic.",
});

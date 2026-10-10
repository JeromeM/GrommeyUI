-- Action bars: extra bars of game shortcuts (skills, items, chat commands) drawn in the GrommeyUI style.
-- The layout of the bars lives in the profile, the shortcuts in a file of the character, since
-- skills differ from one class to another. Plugins cannot bind keys: these bars are used with the mouse.
--
-- Unlocked bars show their empty slots and a small cross on each shortcut to take it off.
-- Automatic bars fill themselves from the backpack: the consumables bar with the food, potions and
-- scrolls, the travel bar with the travel skills chosen by the player (ActionBars/Travel.lua) and the
-- travel items, the stances bar with the stances the character knows (ActionBars/Stances.lua).
-- Their cross hides an item from the bar.
-- Any bar can show its name above it.

local Theme = Grommey.Theme;
local UI = Grommey.UI;
local ShortcutType = Turbine.UI.Lotro.ShortcutType;

local SLOT = 36;            -- game quickslot
local CELL = SLOT + 2;      -- with its 1 pixel border
local MAX_BARS = 10;
local UPDATE_DELAY = 0.1;
local FADED_OPACITY = 0.25;
local SHORTCUTS_FILE = "GrommeyUI_ActionBars";
local SCAN_DELAY = 1;       -- automatic bars look at the backpack every second
local TITLE = 16;           -- height of the name shown above a bar

-- Game item categories of a category of the bag, or the given list when the bag is not there
local function BagCategory(key, fallback)
    local category = Grommey.Bags and Grommey.Bags.CategoryByKey and Grommey.Bags.CategoryByKey[key];
    return (category and category.ids) or fallback;
end

-- Kinds of automatic bars: their name and the item categories they take from the backpack
local AUTO = {
    consumables = { name = "Consumables"; categories = BagCategory("Consumables", { 28, 55, 57, 189, 190, 292, 25 });
        description = "This bar fills itself with the food, potions and scrolls of your backpack, with their total quantity. Unlock the bars and use the cross to hide an item you do not want here."; };
    travel = { name = "Travel"; categories = BagCategory("Travel", { 191, 175, 186 });
        description = "This bar shows the travel skills you chose among the ones your character knows, then the travel items of your backpack. Unlock the bars and use the cross to take a skill or an item off the bar."; };
    stances = { name = "Stances"; categories = {};
        description = "This bar shows the stances your character knows (hunter, minstrel, guardian, warden, brawler), and fills itself when a new one is learned. Unlock the bars and use the cross to hide a stance."; };
};
local AUTO_ORDER = { "consumables", "travel", "stances" };
local CONSUMABLES = AUTO.consumables.categories;

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

-- Rank of each category in each kind of automatic bar, for the order of the items
local categoryRanks = {};
for kind, info in pairs(AUTO) do
    categoryRanks[kind] = {};
    for rank, category in ipairs(info.categories) do categoryRanks[kind][category] = rank; end
end
local categoryRank = categoryRanks.consumables;

local function Call(object, method, ...)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object, ...);
    if (ok) then return value; end
    return nil;
end

local reportedFailure = false;

local function ScanItems(kind, hidden, barSettings)
    local categoryRank = categoryRanks[kind] or categoryRanks.consumables;
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
    -- The order chosen for the bar: by category (above), by name or the player's own
    if (barSettings) then Grommey.ItemOrder.Sort(entries, barSettings); end
    -- Travel bar: the chosen travel skills first, made from their id, then the items if wanted
    if (kind == "travel") then
        if (barSettings and barSettings.travelItems == false) then entries = {}; end
        local skills = {};
        for _, skill in ipairs(Grommey.Travel.Chosen(barSettings and barSettings.travelSort)) do
            local ok, shortcut = pcall(Turbine.UI.Lotro.Shortcut, ShortcutType.Skill, skill.id);
            if (ok and shortcut) then table.insert(skills, { name = skill.id; count = 0; shortcut = shortcut; }); end
        end
        for index = #skills, 1, -1 do table.insert(entries, 1, skills[index]); end
    end
    -- Stances bar: the known stances, made from their id
    if (kind == "stances") then
        entries = {};
        for _, stance in ipairs(Grommey.Stances.Known()) do
            if (not hidden[stance.id]) then
                local ok, shortcut = pcall(Turbine.UI.Lotro.Shortcut, ShortcutType.Skill, stance.id);
                if (ok and shortcut) then table.insert(entries, { name = stance.id; count = 0; shortcut = shortcut; }); end
            end
        end
    end
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

-- The skills of the character (/gui skills), to find out whether travel skills can be put on a bar:
-- name, type, and the shortcut the game gives for it. Written to GrommeyUI_Diagnostic like the report above.
function Grommey.ActionBarsSkillsReport()
    local lines = {};
    local function Add(text) table.insert(lines, text); end
    local types = {};
    for name, value in pairs((Turbine.Gameplay and Turbine.Gameplay.SkillType) or {}) do
        if (type(value) == "number") then table.insert(types, name .. "=" .. value); end
    end
    table.sort(types);
    Add("SkillType: " .. table.concat(types, ", "));
    local methods = {};
    for _, method in ipairs({ "GetTrainedSkills", "GetUntrainedSkills" }) do
        table.insert(methods, method .. " " .. tostring(player and player[method] ~= nil));
    end
    Add(table.concat(methods, " | "));
    local list = Call(player, "GetTrainedSkills");
    local count = Call(list, "GetCount") or 0;
    Add("trained skills: " .. count);
    for index = 1, count do
        local skill = Call(list, "GetItem", index);
        local info = Call(skill, "GetSkillInfo");
        local ok, shortcut = pcall(Turbine.UI.Lotro.Shortcut, skill);
        local data = (ok and shortcut and Call(shortcut, "GetData")) or tostring(shortcut);
        local shortcutType = ok and shortcut and Call(shortcut, "GetType");
        Add(index .. " " .. tostring(Call(info, "GetName")) .. " | type " .. tostring(Call(info, "GetType"))
            .. " | icon " .. tostring(Call(info, "GetIconImageID")) .. " | shortcut " .. tostring(ok) .. " " .. tostring(shortcutType) .. " " .. tostring(data));
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
    local top = barSettings.showTitle and TITLE or 0;
    local width = columns * step - barSettings.spacing;
    window:SetSize(width, top + lines * step - barSettings.spacing);

    -- Name of the bar above it, outlined to stay readable over the game
    if (barSettings.showTitle) then
        window.title = Turbine.UI.Label();
        window.title:SetParent(window);
        window.title:SetPosition(1, 0);
        window.title:SetSize(width - 2, TITLE - 2);
        window.title:SetFont(Theme.Font(11, false));
        window.title:SetFontStyle(Turbine.UI.FontStyle.Outline);
        window.title:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
        window.title:SetForeColor(Theme.Color("text"));
        window.title:SetTextAlignment(Turbine.UI.ContentAlignment.BottomLeft);
        window.title:SetMouseVisible(false);
        window.title:SetText(barSettings.name);
    end

    local auto = (AUTO[barSettings.kind] ~= nil);
    for index = 1, barSettings.slots do
        local slot = CreateSlot(window, id, index, auto);
        slot:SetPosition(((index - 1) % columns) * step, top + math.floor((index - 1) / columns) * step);
        window.slots[index] = slot;
    end

    -- Shows or hides the bar from its conditions, and the empty slots and crosses from the lock
    window.Refresh = function()
        local unlocked = Unlocked();
        local anyShown = false;
        local anyFilled = false;
        for _, slot in ipairs(window.slots) do
            local filled = slot.IsFilled();
            anyFilled = anyFilled or filled;
            slot:SetVisible(filled or unlocked or barSettings.showEmpty);
            anyShown = anyShown or filled or unlocked or barSettings.showEmpty;
            -- The bag item control can have the field behind it, the quickslot cannot
            slot.field:SetVisible(not slot.QuickslotFilled());
            slot.clear:SetVisible(filled and unlocked);
        end
        -- No name over an empty bar
        if (window.title) then window.title:SetVisible(anyShown); end

        local shown = not Grommey.HudHidden;
        -- A character without stances has no stances bar, except to place it
        if (barSettings.kind == "stances" and not anyFilled and not moving) then shown = false; end
        if (shown and not unlocked) then
            local mode = barSettings.visibility;
            if (mode == "combat") then shown = player:IsInCombat();
            elseif (mode == "peace") then shown = not player:IsInCombat();
            elseif (mode == "target") then shown = player:GetTarget() ~= nil;
            end
        end
        window:SetVisible(shown);
    end

    -- Automatic bar: puts the backpack content in the slots when it changes
    window.signature = nil;
    window.Scan = function()
        barSettings.hidden = barSettings.hidden or {};
        local entries = ScanItems(barSettings.kind, barSettings.hidden, barSettings);
        -- The stances bar has one slot per stance, no more: a new count builds the bar again
        if (barSettings.kind == "stances") then
            local wanted = math.max(1, #entries);
            if (wanted ~= barSettings.slots) then
                barSettings.slots = wanted;
                Grommey.Profiles.RequestSave();
                Grommey.Delay("ActionBarsStances" .. id, 0.1, function()
                    if (bars[id] == window) then window.Destroy(); bars[id] = CreateBar(barSettings, position); end
                end);
                return;
            end
        end
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
        -- A travel skill is taken off the choice, it comes back from the choice window
        if (Grommey.Travel.IsSkill(name)) then Grommey.Travel.SetChosen(name, false); return; end
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

-- root: the module settings, also usable before the module runs (setup assistant)
local function NewBar(kind, root)
    root = root or settingsRoot;
    local number = root.nextNumber or (#root.bars + 1);
    root.nextNumber = number + 1;
    local bar = {
        id = "bar" .. number; name = string.format(L("Bar %d"), number); enabled = true;
        slots = 12; perLine = 12; spacing = 2; visibility = "always"; fade = false; showEmpty = true;
    };
    if (AUTO[kind] ~= nil) then
        bar.kind = kind;
        bar.name = L(AUTO[kind].name);
        bar.hidden = {};
        bar.showTitle = true;
    end
    table.insert(root.bars, bar);
    return bar;
end

-- First bar and the consumables bar, made once
local function EnsureBars(root)
    -- The bar list is not in the defaults, a deleted first bar would come back
    if (root.bars == nil) then
        root.bars = {};
        NewBar(nil, root);
    end
    -- The consumables bar comes once on its own, it can be deleted after that
    if (not root.consumablesAdded) then
        root.consumablesAdded = true;
        if (#root.bars < MAX_BARS) then NewBar("consumables", root); end
    end
    if (not root.travelAdded) then
        root.travelAdded = true;
        if (#root.bars < MAX_BARS) then NewBar("travel", root); end
    end
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

    -- Creating a bar: one list for every kind, so each one says what it is
    local labelWidth = 130;
    local listWidth = math.min(260, width - labelWidth - 160);
    local y = 52;
    if (#settings.bars < MAX_BARS) then
        local kinds = { { value = "empty"; text = L("Empty bar (you fill it)"); } };
        for _, kind in ipairs(AUTO_ORDER) do
            table.insert(kinds, { value = kind; text = string.format(L("Automatic bar: %s"), L(AUTO[kind].name)); });
        end
        local newKind = "empty";
        UI.Label(page, 0, y + 4, labelWidth, 18, L("Create a bar:"));
        UI.Dropdown(page, labelWidth, y, listWidth, kinds, newKind, function(value) newKind = value; end);
        UI.Button(page, labelWidth + listWidth + 10, y, 120, L("Create"), function()
            selectedBar = NewBar(newKind ~= "empty" and newKind or nil).id;
            Changed();
            Reopen();
        end, "accent");
    else
        UI.Label(page, 0, y + 4, width, 18, string.format(L("%d bars at most."), MAX_BARS), { role = "dim"; });
    end
    UI.Separator(page, 0, y + 38, width);

    -- The bar being set up
    y = 102;
    if (#items > 0) then
        UI.Label(page, 0, y + 4, labelWidth, 18, L("Bar to set up:"));
        UI.Dropdown(page, labelWidth, y, listWidth, items, selectedBar, function(value) selectedBar = value; Reopen(); end);
    end
    if (selectedBar) then
        UI.Button(page, labelWidth + listWidth + 10, y, math.max(120, width - labelWidth - listWidth - 10), L("Delete this bar"), function()
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
        UI.Label(page, 0, 150, width, 20, L("No bar yet."), { role = "dim"; });
        return;
    end

    y = 150;
    UI.Toggle(page, 0, y, half, L("Show this bar"), bar.enabled, function(value) bar.enabled = value; Changed(); end);
    local auto = (AUTO[bar.kind] ~= nil);
    -- Automatic bars have no empty slots to show: their name option takes that place
    if (auto) then
        UI.Toggle(page, right, y, half, L("Name above the bar"), bar.showTitle == true, function(value) bar.showTitle = value; Changed(); end);
    else
        UI.Toggle(page, right, y, half, L("Show the empty slots"), bar.showEmpty, function(value) bar.showEmpty = value; Changed(); end);
        y = y + 32;
        UI.Toggle(page, 0, y, half, L("Name above the bar"), bar.showTitle == true, function(value) bar.showTitle = value; Changed(); end);
    end
    y = y + 40;
    -- The stances bar has as many slots as stances
    if (bar.kind ~= "stances") then
        UI.Slider(page, 0, y, half, auto and L("Maximum items") or L("Number of slots"), 1, 36, 1, bar.slots, function(value) bar.slots = value; Changed(); end);
    end
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

    if (bar.kind == "travel") then
        UI.Button(page, 0, y + 20, half, L("Choose the travel skills"), function() Grommey.Travel.OpenPicker(bar.travelSort); end, "accent");
        UI.Label(page, right, y, half, 18, L("Order"));
        UI.Dropdown(page, right, y + 20, half, Translated(Grommey.Travel.SORTS), bar.travelSort or "family", function(value)
            bar.travelSort = value;
            Changed();
        end);
        y = y + 60;
        UI.Toggle(page, 0, y, width, L("Travel items of the backpack after the skills"), bar.travelItems ~= false, function(value) bar.travelItems = value; Changed(); end);
        y = y + 40;
    end
    if (bar.kind == "consumables") then
        UI.Button(page, 0, y + 20, half, L("Set my order"), function()
            Grommey.ItemOrder.Open(bar,
                function() return ScanItems(bar.kind, bar.hidden or {}, bar); end,
                function()
                    Grommey.Profiles.RequestSave();
                    if (bars[bar.id]) then bars[bar.id].signature = nil; bars[bar.id].Scan(); end
                    Reopen();
                end);
        end, "accent");
        UI.Label(page, right, y, half, 18, L("Order"));
        UI.Dropdown(page, right, y + 20, half, Translated(Grommey.ItemOrder.SORTS), bar.itemSort or "category", function(value)
            bar.itemSort = value;
            Changed();
        end);
        y = y + 60;
    end
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
        UI.Note(page, 0, y, width, L(AUTO[bar.kind].description));
        return;
    end
    UI.Note(page, 0, y, width, L("Drag skills, items or chat commands onto the slots. Unlock the bars to see the empty slots and take shortcuts off with the cross. Place the bars with the move mode. The game does not let plugins use keys: these bars are clicked."));
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
        -- The travel bars show a change of the choice at once
        Grommey.Travel.Start(player);
        Grommey.Stances.Start(player);
        Grommey.Travel.OnChange(function()
            for id, window in pairs(bars) do
                local barSettings = BarSettings(id);
                if (barSettings and barSettings.kind == "travel") then window.Scan(); end
            end
        end);
        EnsureBars(settings);
        -- The stances bar comes once on its own, the first time a character with stances logs in
        if (not settings.stancesAdded and #Grommey.Stances.Known() > 0 and #settings.bars < MAX_BARS) then
            settings.stancesAdded = true;
            NewBar("stances", settings);
        end
        Grommey.Profiles.RequestSave();
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
        Grommey.Travel.Stop();
        DestroyBars();
        settingsRoot = nil;
    end;

    BuildOptions = BuildOptions;

    SetupOptions = function(page, width, settings)
        EnsureBars(settings);
        local y = 0;
        for _, bar in ipairs(settings.bars) do
            local text = bar.name;
            if (bar.kind == "consumables") then text = L("Consumables bar (fills itself from the backpack)"); end
            if (bar.kind == "travel") then text = L("Travel bar (fills itself from the backpack)"); end
            if (bar.kind == "stances") then text = L("Stances bar (fills itself with your stances)"); end
            UI.Toggle(page, 0, y, width, text, bar.enabled, function(value) bar.enabled = value; end);
            y = y + 34;
            if (y > 240) then break; end
        end
        UI.Toggle(page, 0, y + 10, width, L("Locked (no empty slots or crosses)"), settings.locked, function(value) settings.locked = value; end);
        UI.Note(page, 0, y + 54, width, L("Drag skills and items onto the bars. These bars are used with the mouse, the game does not let plugins use keys. More bars can be added in the options."));
    end;
});

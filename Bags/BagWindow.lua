-- The bag window: every item of the backpack sorted into category sections.
-- The layout is rebuilt from the backpack each time something changes, so it can never drift
-- out of sync. Slot controls are created once per backpack slot and only moved around.

local Theme = Grommey.Theme;
local UI = Grommey.UI;

local PAD = 10;            -- inner margin of the window
local GAP = 4;             -- space between two slots
local HEADER_HEIGHT = 24;  -- category title
local SECTION_GAP = 8;     -- space under a category box
local COLUMN_GAP = 14;     -- space between two columns of categories
local TOOLBAR_HEIGHT = 36; -- search and buttons
local FOOTER_HEIGHT = 30;  -- free slots and currencies
local TITLE_HEIGHT = 32;   -- title bar of Grommey.Window
local SCROLLBAR_WIDTH = 14;
-- The game item control draws its 32 pixel icon about 3 pixels in from its top left corner
local ICON_SIZE = 32;
local ICON_INSET = 3;

-- Items added this many seconds after loading are the login, not new loot
local LOGIN_GRACE = 15;
local PULSE_SPEED = 5;      -- border of the new items, like the game bag
local CURRENCY_GAP = 18;    -- between two currencies of the footer
local MONEY_GAP = 28;       -- around the money of the footer
local STACK_DELAY = 0.3;   -- seconds between two stack merges, the server needs time
local STACK_MAX_DROPS = 200;
local STACK_MAX_TRIES = 2;

Grommey.Bags.Window = class(Grommey.Window);

------------------------------------------------------------------------------------------------------------------------------------------
-- Construction

function Grommey.Bags.Window:Constructor(settings)
    Grommey.Window.Constructor(self, "bags", L("Bags"), 300, 200);
    -- The bag stays where it is, it only moves in move mode
    self.movable = false;
    self.settings = settings;
    self.backpack = Turbine.Gameplay.LocalPlayer.GetInstance():GetBackpack();
    self.wallet = Turbine.Gameplay.LocalPlayer.GetInstance():GetWallet();

    self.slots = {};
    self.headers = {};
    self.newSlots = {};
    -- Names of the items the character already has: one coming back to the bag (an item taken
    -- off when another is put on, a stack growing) is not new
    self.knownNames = {};
    self.callbacks = {};
    self.createdAt = Turbine.Engine.GetGameTime();
    self.dirty = true;

    self:CreateToolbar();
    self:CreateList();
    self:CreateFooter();
    self:CreateSlots();
    self:RememberItems();
    self:RegisterEvents();
    self:SetupKeys();

    -- Dropping an item anywhere on the window puts it in the first free slot
    self:SetAllowDrop(true);
    self.DragDrop = function(sender, args) self:DropOnFreeSlot(args); end

    self.VisibleChanged = function()
        if (self:IsVisible()) then
            self:Activate();
            self:Layout();
        else
            -- Items stop being "new" once the bag has been seen
            self.newSlots = {};
            self:SetWantsUpdates(false);
            self.dirty = true;
            UI.ClosePopup();
        end
    end

    -- Moved by someone else (move mode, reset): take the corner again at the next layout
    self.PositionChanged = function()
        if (not self.positioning and self.sizedOnce) then
            self.anchorDirty = true;
            self:RequestLayout();
        end
    end

    Grommey.Movers.Register("bags", self, L("Bags"),
        function() return Turbine.UI.Display.GetWidth() - self:GetWidth() - 40; end,
        function() return Turbine.UI.Display.GetHeight() - self:GetHeight() - 140; end);

    -- Build once hidden so the first opening is instant
    self.forceLayout = true;
    self:Layout();
    self.sizedOnce = true;
end

function Grommey.Bags.Window:CreateToolbar()
    self.toolbar = Turbine.UI.Control();
    self.toolbar:SetParent(self.content);
    self.toolbar:SetPosition(PAD, 6);

    self.searchBox = UI.TextInput(self.toolbar, 0, 0, 200, "");
    self.searchHint = UI.Label(self.searchBox.frame.inner, 8, 0, 190, 24, L("Search..."), { role = "dim"; });
    self.searchBox.TextChanged = function()
        local text = self.searchBox:GetText() or "";
        self.searchHint:SetVisible(text == "");
        self.searchText = string.lower(text);
        self:ApplySearch();
    end

    self.stackButton = UI.Button(self.toolbar, 210, 0, 90, L("Stack"), function() self:StartStacking(); end);

    -- Switch between the category view and all the bags in their real order
    self.viewButton = UI.Button(self.toolbar, 310, 0, 120, "", function()
        self.settings.groupByCategory = not self.settings.groupByCategory;
        Grommey.Profiles.RequestSave();
        self:Layout();
    end);
end

function Grommey.Bags.Window:CreateList()
    -- The sections live on a canvas inside a list box, which gives scrolling when the bag is very full
    self.list = Turbine.UI.ListBox();
    self.list:SetParent(self.content);
    self.list:SetPosition(PAD, TOOLBAR_HEIGHT + 4);
    self.list:SetAllowDrop(true);
    self.list.DragDrop = function(sender, args) self:DropOnFreeSlot(args); end

    self.scrollBar = Turbine.UI.Lotro.ScrollBar();
    self.scrollBar:SetOrientation(Turbine.UI.Orientation.Vertical);
    self.scrollBar:SetParent(self.content);
    self.scrollBar:SetVisible(false);
    self.list:SetVerticalScrollBar(self.scrollBar);

    self.canvas = Turbine.UI.Control();
    self.canvas:SetAllowDrop(true);
    self.canvas.DragDrop = function(sender, args) self:DropOnFreeSlot(args); end
end

function Grommey.Bags.Window:CreateFooter()
    self.footer = Turbine.UI.Control();
    self.footer:SetParent(self.content);
    Theme.Track(function() self.footer:SetBackColor(Theme.Color("panel")); end);

    self.freeLabel = UI.Label(self.footer, PAD, 0, 160, FOOTER_HEIGHT, "", { size = 13; role = "dim"; });
    self.currencyControls = {};
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Slots

function Grommey.Bags.Window:CreateSlot(index)
    local slot = Turbine.UI.Control();
    slot.index = index;
    slot:SetParent(self.canvas);
    slot:SetVisible(false);

    slot.inner = Turbine.UI.Control();
    slot.inner:SetParent(slot);
    slot.inner:SetPosition(1, 1);
    slot.inner:SetMouseVisible(false);

    slot.itemControl = Turbine.UI.Lotro.ItemControl();
    slot.itemControl:SetParent(slot);

    -- Search: items that do not match are dimmed
    slot.dim = Turbine.UI.Control();
    slot.dim:SetParent(slot);
    slot.dim:SetMouseVisible(false);
    slot.dim:SetVisible(false);


    -- Number of free slots, only on the free slot
    slot.countLabel = UI.Label(slot, 0, 0, 10, 14, "", { size = 12; bold = true; align = Turbine.UI.ContentAlignment.BottomRight; });
    slot.countLabel:SetFontStyle(Turbine.UI.FontStyle.Outline);
    slot.countLabel:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    slot.countLabel:SetVisible(false);

    local function OnDrop(sender, args)
        local shortcut = args.DragDropInfo:GetShortcut();
        if (shortcut == nil) then return; end
        local target = slot.index;
        if (slot.isFreeSlot) then target = self:FirstFreeIndex(); end
        if (target) then
            self.backpack:PerformShortcutDrop(shortcut, target, Turbine.UI.Control.IsShiftKeyDown());
        end
    end
    slot:SetAllowDrop(true);
    slot.DragDrop = OnDrop;
    slot.itemControl:SetAllowDrop(true);
    slot.itemControl.DragDrop = OnDrop;

    self.slots[index] = slot;
    return slot;
end

function Grommey.Bags.Window:CreateSlots()
    for index = 1, self.backpack:GetSize() do
        if (self.slots[index] == nil) then self:CreateSlot(index); end
    end
end

-- Size, colours and content of one slot
function Grommey.Bags.Window:SlotSize()
    -- Never smaller than the icon with a small margin
    return math.max(self.settings.slotSize, ICON_SIZE + 4);
end

function Grommey.Bags.Window:PaintSlot(slot, item)
    local size = self:SlotSize();
    slot:SetSize(size, size);
    slot.inner:SetSize(size - 2, size - 2);
    slot.inner:SetBackColor(Theme.Color("field"));
    -- Centre the icon itself, not the control around it
    local offset = math.floor((size - ICON_SIZE) / 2) - ICON_INSET;
    slot.itemControl:SetPosition(offset, offset);
    slot.itemControl:SetItem(item);
    slot.dim:SetSize(size, size);
    slot.dim:SetBackColor(Theme.Color("background", 0.75));
    slot.countLabel:SetSize(size - 4, size - 2);

    slot:SetBackColor(Theme.Color("border"));
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Sections

function Grommey.Bags.Window:GetHeader(key, title)
    local header = self.headers[key];
    if (header == nil) then
        header = Turbine.UI.Control();
        header:SetParent(self.canvas);
        header.key = key;
        header.sign = UI.Label(header, 0, 0, 16, HEADER_HEIGHT, "-", { bold = true; role = "accent"; });
        header.label = UI.Label(header, 16, 0, 300, HEADER_HEIGHT - 2, "", { size = 13; bold = true; });
        header.line = Turbine.UI.Control();
        header.line:SetParent(header);
        header.line:SetMouseVisible(false);
        Theme.Track(function() header.line:SetBackColor(Theme.Color("border")); end);

        -- An item dropped on a title goes into that category (a game category takes it back)
        header:SetAllowDrop(true);
        header.DragDrop = function(sender, args) self:DropOnHeader(key, args); end

        -- Click a title to fold or unfold its section
        header.MouseClick = function()
            local collapsed = self.settings.collapsed;
            collapsed[key] = not collapsed[key] or nil;
            Grommey.Profiles.RequestSave();
            self:Layout();
        end
        header.MouseEnter = function() header.label:SetForeColor(Theme.Color("accent")); end
        header.MouseLeave = function() header.label:SetForeColor(Theme.Color("text")); end
        self.headers[key] = header;
    end
    header.title = title;
    return header;
end

local function SortSlots(window, indices)
    local names = {};
    for _, index in ipairs(indices) do
        names[index] = string.lower(window.backpack:GetItem(index):GetName() or "");
    end
    table.sort(indices, function(a, b)
        if (names[a] ~= names[b]) then return names[a] < names[b]; end
        return a < b;
    end);
end

-- Item dropped on a category title: into a category of the player, or back to its game category
function Grommey.Bags.Window:DropOnHeader(key, args)
    local ok, shortcut = pcall(function() return args.DragDropInfo:GetShortcut(); end);
    local item = ok and shortcut and shortcut.GetItem and shortcut:GetItem();
    local name = item and item:GetName();
    if (name == nil or key == "New" or key == "Free") then return; end
    local settings = self.settings;
    settings.itemCategory = settings.itemCategory or {};
    local id = string.match(key, "^custom:(.+)$");
    settings.itemCategory[name] = id;
    Grommey.Profiles.RequestSave();
    self:RequestLayout();
end

function Grommey.Bags.Window:RequestLayout()
    Grommey.Delay("BagsLayout", 0.05, function() self:Layout(); end);
end

function Grommey.Bags.Window:Layout()
    -- Nothing to draw while closed, done when it opens
    if (not self:IsVisible() and not self.forceLayout) then self.dirty = true; return; end
    self.forceLayout = false;
    self.dirty = false;
    UI.ClosePopup();

    local settings = self.settings;
    if (#self.slots < self.backpack:GetSize()) then self:CreateSlots(); end
    local size = self:SlotSize();
    local cell = size + GAP;
    local perRow = settings.itemsPerRow;
    local boxWidth = perRow * cell - GAP;

    -- Sort every slot into its section
    local groups = {};
    local free = {};
    local backpackSize = self.backpack:GetSize();
    if (#self.slots < backpackSize) then self:CreateSlots(); end

    for index = 1, backpackSize do
        local item = self.backpack:GetItem(index);
        local slot = self.slots[index];
        slot.isFreeSlot = false;
        slot.countLabel:SetVisible(false);
        self:PaintSlot(slot, item);
        if (item ~= nil) then
            local key = Grommey.Bags.CustomKey(settings, item) or Grommey.Bags.GetCategoryKey(item);
            if (settings.showNew and self.newSlots[index]) then key = "New"; end
            groups[key] = groups[key] or {};
            table.insert(groups[key], index);
        else
            table.insert(free, index);
        end
    end

    if (not settings.groupByCategory) then
        self:LayoutAllBags(size, cell, #free);
        return;
    end

    -- Sections in display order, the free slots come last as a single slot
    local sections = {};
    if (groups["New"]) then table.insert(sections, { key = "New"; title = L("New items"); indices = groups["New"]; }); end
    -- The player's categories first, shown even empty so items can be dropped on them
    for _, category in ipairs(settings.customCategories or {}) do
        local key = "custom:" .. category.id;
        table.insert(sections, { key = key; title = category.name; indices = groups[key] or {}; });
    end
    for _, category in ipairs(Grommey.Bags.Categories) do
        if (groups[category.key]) then table.insert(sections, { key = category.key; title = L(category.name); indices = groups[category.key]; }); end
    end
    if (#free > 0) then
        table.insert(sections, { key = "Free"; title = L("Free slots"); indices = { free[1] }; count = #free; isFree = true; });
    end

    for _, header in pairs(self.headers) do header:SetVisible(false); end
    for _, slot in pairs(self.slots) do slot:SetVisible(false); end

    -- Category boxes side by side: each box goes into the shortest column so there are no holes
    local columnCount = math.max(1, math.min(settings.categoryColumns, #sections));
    local columnHeights = {};
    for column = 1, columnCount do columnHeights[column] = 0; end

    for _, section in ipairs(sections) do
        if (not section.isFree) then SortSlots(self, section.indices); end
        local collapsed = settings.collapsed[section.key] == true;
        local rows = math.ceil(#section.indices / perRow);
        local boxHeight = HEADER_HEIGHT + 2 + (collapsed and 0 or rows * cell) + SECTION_GAP;

        local column = 1;
        for candidate = 2, columnCount do
            if (columnHeights[candidate] < columnHeights[column]) then column = candidate; end
        end
        local x = (column - 1) * (boxWidth + COLUMN_GAP);
        local y = columnHeights[column];
        columnHeights[column] = y + boxHeight;

        local header = self:GetHeader(section.key, section.title);
        header:SetPosition(x, y);
        header:SetSize(boxWidth, HEADER_HEIGHT);
        header.label:SetSize(boxWidth - 16, HEADER_HEIGHT - 2);
        header.label:SetText(section.title .. "  " .. (section.count or #section.indices));
        header.sign:SetText(collapsed and "+" or "-");
        header.line:SetPosition(0, HEADER_HEIGHT - 2);
        header.line:SetSize(boxWidth, 1);
        header:SetVisible(true);

        if (not collapsed) then
            local top = y + HEADER_HEIGHT + 2;
            for position, index in ipairs(section.indices) do
                local slot = self.slots[index];
                slot:SetPosition(x + ((position - 1) % perRow) * cell, top + math.floor((position - 1) / perRow) * cell);
                slot:SetVisible(true);
                if (section.isFree) then
                    slot.isFreeSlot = true;
                    slot.countLabel:SetText(tostring(section.count));
                    slot.countLabel:SetVisible(true);
                end
            end
        end
    end

    local contentHeight = 0;
    for column = 1, columnCount do contentHeight = math.max(contentHeight, columnHeights[column]); end
    local innerWidth = columnCount * boxWidth + (columnCount - 1) * COLUMN_GAP;

    self.canvas:SetSize(innerWidth, math.max(contentHeight, cell));
    self.freeCount = #free;
    self:ApplySearch();
    self:ResizeToContent(innerWidth, contentHeight);
    self:RefreshFooter();
    self:UpdatePulse();
end

-- Every slot in the real order of the bags, empty ones included, without categories
function Grommey.Bags.Window:LayoutAllBags(size, cell, freeCount)
    for _, header in pairs(self.headers) do header:SetVisible(false); end
    local columns = self.settings.flatColumns;
    local backpackSize = self.backpack:GetSize();
    for index = 1, backpackSize do
        local slot = self.slots[index];
        slot:SetPosition(((index - 1) % columns) * cell, math.floor((index - 1) / columns) * cell);
        slot:SetVisible(true);
    end

    local innerWidth = columns * cell - GAP;
    local contentHeight = math.ceil(backpackSize / columns) * cell;
    self.canvas:SetSize(innerWidth, math.max(contentHeight, cell));
    self.freeCount = freeCount;
    self:ApplySearch();
    self:ResizeToContent(innerWidth, contentHeight);
    self:RefreshFooter();
    self:UpdatePulse();
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Size and position

function Grommey.Bags.Window:ResizeToContent(innerWidth, contentHeight)
    local screenWidth = Turbine.UI.Display.GetWidth();
    local screenHeight = Turbine.UI.Display.GetHeight();
    local chrome = TITLE_HEIGHT + TOOLBAR_HEIGHT + 4 + FOOTER_HEIGHT + 6;
    local maxListHeight = math.floor(screenHeight * self.settings.maxHeight / 100) - chrome;
    local listHeight = math.max(self:SlotSize(), math.min(contentHeight, maxListHeight));
    local scrolling = contentHeight > listHeight;

    local width = innerWidth + 2 * PAD + 2 + (scrolling and SCROLLBAR_WIDTH or 0);
    width = math.max(width, 380);
    local height = chrome + listHeight;

    -- The bag keeps the corner chosen by the player (the one nearest to the screen edge) and grows
    -- from it. The corner is saved, so the bag does not drift when it changes size while loading.
    local anchor = self.settings.anchor;
    if (anchor == nil or self.anchorDirty) then
        local left, top = self:GetPosition();
        local oldWidth, oldHeight = self:GetSize();
        local right = left + oldWidth > screenWidth / 2 + oldWidth / 2;
        local bottom = top + oldHeight > screenHeight / 2 + oldHeight / 2;
        anchor = {
            right = right; bottom = bottom;
            x = right and (left + oldWidth) or left;
            y = bottom and (top + oldHeight) or top;
        };
        self.settings.anchor = anchor;
        self.anchorDirty = false;
        Grommey.Profiles.RequestSave();
    end
    local left = anchor.right and (anchor.x - width) or anchor.x;
    local top = anchor.bottom and (anchor.y - height) or anchor.y;
    left = Grommey.Clamp(left, 0, math.max(0, screenWidth - width));
    top = Grommey.Clamp(top, 0, math.max(0, screenHeight - height));

    self:Resize(width, height);
    self.positioning = true;
    self:SetPosition(left, top);
    self.positioning = false;
    Grommey.Movers.SavePosition("bags", left, top);

    -- Toolbar
    local contentWidth = width - 2;
    self.toolbar:SetSize(contentWidth - 2 * PAD, 28);
    local searchWidth = contentWidth - 2 * PAD - 100 - 130;
    self.searchBox.frame.Resize(searchWidth, 26);
    self.searchBox:SetSize(searchWidth - 14, 20);
    self.searchHint:SetSize(searchWidth - 16, 24);
    self.stackButton:SetPosition(searchWidth + 10, 0);
    self.viewButton:SetPosition(searchWidth + 110, 0);
    self.viewButton:SetText(self.settings.groupByCategory and L("All bags") or L("By category"));

    -- List: the canvas is put back in so the list box takes its new size into account
    self.list:SetSize(innerWidth, listHeight);
    self.list:ClearItems();
    self.list:AddItem(self.canvas);
    self.scrollBar:SetPosition(PAD + innerWidth + 2, TOOLBAR_HEIGHT + 4);
    self.scrollBar:SetSize(10, listHeight);
    self.scrollBar:SetVisible(scrolling);

    -- Footer
    self.footer:SetPosition(0, TOOLBAR_HEIGHT + 4 + listHeight + 6);
    self.footer:SetSize(contentWidth, FOOTER_HEIGHT);
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Footer: free slots and currencies

function Grommey.Bags.Window:RefreshFooter()
    local total = self.backpack:GetSize();
    self.freeLabel:SetText(string.format(L("%d / %d free"), self.freeCount or 0, total));

    for _, control in ipairs(self.currencyControls) do control:SetParent(nil); end
    self.currencyControls = {};

    -- Tracked currencies from right to left, then the money of the character
    local x = self.footer:GetWidth() - PAD;
    for index = self.wallet:GetSize(), 1, -1 do
        local walletItem = self.wallet:GetItem(index);
        if (self.settings.currencies[walletItem:GetName()]) then
            local text = tostring(walletItem:GetQuantity());
            local textWidth = 8 * string.len(text) + 4;
            x = x - textWidth;
            local amount = UI.Label(self.footer, x, 0, textWidth, FOOTER_HEIGHT, text, { size = 13; align = Turbine.UI.ContentAlignment.MiddleRight; });
            x = x - 18;
            local icon = Turbine.UI.Control();
            icon:SetParent(self.footer);
            icon:SetPosition(x, math.floor((FOOTER_HEIGHT - 16) / 2));
            icon:SetSize(16, 16);
            icon:SetBlendMode(Turbine.UI.BlendMode.Overlay);
            icon:SetBackground(walletItem:GetSmallImage());
            icon:SetMouseVisible(false);
            x = x - CURRENCY_GAP;
            table.insert(self.currencyControls, amount);
            table.insert(self.currencyControls, icon);
        end
    end

    -- The money sits in the middle of the space left between the free slots and the currencies,
    -- with a thin line before the currencies
    local total = (self.settings.showMoney ~= false) and Grommey.Money.Total();
    if (total) then
        local hasCurrencies = (#self.currencyControls > 0);
        local rightLimit = hasCurrencies and (x + CURRENCY_GAP - MONEY_GAP) or (self.footer:GetWidth() - PAD);
        local leftLimit = PAD + string.len(self.freeLabel:GetText() or "") * 7 + MONEY_GAP;
        local text = Grommey.Money.Text(total, false);
        local visible = string.gsub(text, "<[^>]*>", "");
        local textWidth = math.floor(string.len(visible) * 7.5) + 6;
        local left = math.floor((leftLimit + rightLimit - textWidth) / 2);
        left = math.max(leftLimit, math.min(left, rightLimit - textWidth));
        local money = UI.Label(self.footer, left, 0, textWidth, FOOTER_HEIGHT, text, { size = 13; markup = true; align = Turbine.UI.ContentAlignment.MiddleCenter; });
        table.insert(self.currencyControls, money);
        if (hasCurrencies) then
            local line = Turbine.UI.Control();
            line:SetParent(self.footer);
            line:SetPosition(rightLimit + math.floor(MONEY_GAP / 2), 6);
            line:SetSize(1, FOOTER_HEIGHT - 12);
            line:SetBackColor(Theme.Color("border"));
            line:SetMouseVisible(false);
            table.insert(self.currencyControls, line);
        end
    end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Search

function Grommey.Bags.Window:ApplySearch()
    local text = self.searchText or "";
    for index, slot in pairs(self.slots) do
        local item = self.backpack:GetItem(index);
        if (text == "" or item == nil or slot.isFreeSlot) then
            slot.dim:SetVisible(false);
            slot:SetBackColor(Theme.Color("border"));
        else
            local match = string.find(string.lower(item:GetName() or ""), text, 1, true) ~= nil;
            slot.dim:SetVisible(not match);
            slot:SetBackColor(match and Theme.Color("accent") or Theme.Color("border"));
        end
    end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Drag and drop, stacking

function Grommey.Bags.Window:FirstFreeIndex()
    for index = 1, self.backpack:GetSize() do
        if (self.backpack:GetItem(index) == nil) then return index; end
    end
    return nil;
end

function Grommey.Bags.Window:DropOnFreeSlot(args)
    local shortcut = args.DragDropInfo:GetShortcut();
    local target = self:FirstFreeIndex();
    if (shortcut ~= nil and target ~= nil) then
        self.backpack:PerformShortcutDrop(shortcut, target, Turbine.UI.Control.IsShiftKeyDown());
    end
end

-- First pair of slots (source, target) whose stacks can be merged
function Grommey.Bags.Window:FindStackPair()
    local size = self.backpack:GetSize();
    local names = {};
    local open = {};
    for index = 1, size do
        local item = self.backpack:GetItem(index);
        if (item and item:GetItemInfo():GetMaxStackSize() > 1) then
            names[index] = item:GetName();
            open[index] = item:GetQuantity() < item:GetItemInfo():GetMaxStackSize();
        end
    end
    for first = 1, size do
        if (names[first] and open[first]) then
            for second = first + 1, size do
                -- Give up on a pair after a few tries, the game may refuse to merge them
                if (names[second] == names[first] and (self.stackTries[second .. ":" .. first] or 0) < STACK_MAX_TRIES) then
                    return second, first;
                end
            end
        end
    end
    return nil;
end

-- Merges stacks one drop at a time, giving the server time to answer between drops
function Grommey.Bags.Window:StartStacking()
    if (self.stacking) then return; end
    self.stacking = true;
    self.stackDrops = 0;
    self.stackTries = {};

    local function Step()
        local source, target = self:FindStackPair();
        if (source == nil or self.stackDrops >= STACK_MAX_DROPS) then
            self.stacking = false;
            Grommey.Print(string.format(L("Stacking done (%d merges)."), self.stackDrops));
            return;
        end
        local key = source .. ":" .. target;
        self.stackTries[key] = (self.stackTries[key] or 0) + 1;
        self.backpack:PerformItemDrop(self.backpack:GetItem(source), target, false);
        self.stackDrops = self.stackDrops + 1;
        Grommey.Delay("BagsStack", STACK_DELAY, Step);
    end
    Step();
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Events

-- Everything in the bag and worn right now is known
function Grommey.Bags.Window:RememberItems()
    for index = 1, self.backpack:GetSize() do
        local item = self.backpack:GetItem(index);
        if (item ~= nil) then self.knownNames[item:GetName() or ""] = true; end
    end
    local ok, equipment = pcall(function() return Turbine.Gameplay.LocalPlayer.GetInstance():GetEquipment(); end);
    if (ok and equipment) then
        for index = 1, equipment:GetSize() do
            local item = equipment:GetItem(index);
            if (item ~= nil) then self.knownNames[item:GetName() or ""] = true; end
        end
    end
end

-- New items: their border pulses between the border and the theme colour while the bag is open
function Grommey.Bags.Window:UpdatePulse()
    local pulsing = self:IsVisible() and next(self.newSlots) ~= nil;
    self:SetWantsUpdates(pulsing);
    if (not pulsing) then return; end
    self.Update = function()
        local amount = (math.sin(Turbine.Engine.GetGameTime() * PULSE_SPEED) + 1) / 2;
        local color = Theme.Mix("border", "accent", amount);
        for index in pairs(self.newSlots) do
            local slot = self.slots[index];
            if (slot and slot:IsVisible()) then slot:SetBackColor(color); end
        end
    end
end

function Grommey.Bags.Window:RegisterEvents()
    local function Add(object, eventName, callback)
        table.insert(self.callbacks, { object = object; eventName = eventName; callback = Grommey.AddCallback(object, eventName, callback); });
    end

    Add(self.backpack, "ItemAdded", function(sender, args)
        local item = self.backpack:GetItem(args.Index);
        local name = (item and item:GetName()) or "";
        -- While logging in the game adds every item one by one, they are not new;
        -- neither is an item the character already had (taken off, stack growing)
        if (Turbine.Engine.GetGameTime() - self.createdAt >= LOGIN_GRACE and not self.knownNames[name]) then
            self.newSlots[args.Index] = true;
        end
        self.knownNames[name] = true;
        self:RequestLayout();
    end);
    Add(self.backpack, "ItemRemoved", function(sender, args)
        self.newSlots[args.Index] = nil;
        self:RequestLayout();
    end);
    Add(self.backpack, "ItemMoved", function(sender, args)
        local oldNew, newNew = self.newSlots[args.OldIndex], self.newSlots[args.NewIndex];
        self.newSlots[args.NewIndex], self.newSlots[args.OldIndex] = oldNew, newNew;
        self:RequestLayout();
    end);
    Add(self.backpack, "SizeChanged", function()
        self:CreateSlots();
        self:RequestLayout();
    end);

    -- Money and currency amounts in the footer
    local attributes = Turbine.Gameplay.LocalPlayer.GetInstance():GetAttributes();
    if (attributes) then
        Add(attributes, "MoneyChanged", function() if (self:IsVisible()) then self:RefreshFooter(); end end);
    end
    for index = 1, self.wallet:GetSize() do
        Add(self.wallet:GetItem(index), "QuantityChanged", function()
            if (self:IsVisible()) then self:RefreshFooter(); end
        end);
    end
end

function Grommey.Bags.Window:SetupKeys()
    local Action = Turbine.UI.Lotro.Action;
    local bagActions = {};
    for _, name in ipairs({ "ToggleBags", "ToggleBag1", "ToggleBag2", "ToggleBag3", "ToggleBag4", "ToggleBag5", "ToggleBag6" }) do
        if (Action[name] ~= nil) then bagActions[Action[name]] = true; end
    end

    self.KeyDown = function(sender, args)
        if (args.Action == Action.Escape) then
            if (self:IsVisible()) then self:SetVisible(false); end
        elseif (bagActions[args.Action]) then
            self:Toggle();
        end
    end
end

function Grommey.Bags.Window:Destroy()
    for _, entry in ipairs(self.callbacks) do
        Grommey.RemoveCallback(entry.object, entry.eventName, entry.callback);
    end
    self.callbacks = {};
    self.stacking = false;
    Grommey.Movers.Unregister("bags");
    self:SetVisible(false);
end

-- Order of the items of an automatic bar (consumables): a small window listing the items the bar
-- shows, each with arrows to move it. The order is a list of item names in the bar settings
-- (itemOrder); an item missing from the backpack keeps its place, new items come at the end.

local UI = Grommey.UI;

Grommey.ItemOrder = {};
local ItemOrder = Grommey.ItemOrder;

local WIDTH, HEIGHT = 420, 520;
local PAD = 16;
local ROW = 28;
local IMAGES = "GrommeyUI/ActionBars/Resources/";

ItemOrder.SORTS = {
    { value = "category"; text = "By category"; },
    { value = "name"; text = "By name"; },
    { value = "custom"; text = "My order"; },
};

-- "Potion 2" before "Potion 10"
local function Natural(text)
    return (string.gsub(string.lower(text or ""), "%d+", function(number) return string.rep("0", 6 - #number) .. number; end));
end

-- Sorts the entries of a bar ({ name, ... } already in category order) as its settings ask
function ItemOrder.Sort(entries, barSettings)
    local sort = barSettings.itemSort or "category";
    if (sort == "name") then
        table.sort(entries, function(a, b) return Natural(a.name) < Natural(b.name); end);
    elseif (sort == "custom") then
        local position = {};
        for index, name in ipairs(barSettings.itemOrder or {}) do position[name] = index; end
        -- Items without a place keep the category order, after the others
        local original = {};
        for index, entry in ipairs(entries) do original[entry] = index; end
        table.sort(entries, function(a, b)
            local pa, pb = position[a.name], position[b.name];
            if (pa and pb) then return pa < pb; end
            if (pa or pb) then return pa ~= nil; end
            return original[a] < original[b];
        end);
    end
    return entries;
end

local window = nil;
local current = nil;        -- { settings, entries function, changed function }

local function Move(name, delta)
    local barSettings = current.settings;
    local names = {};
    for _, entry in ipairs(current.Entries()) do table.insert(names, entry.name); end
    -- Items of the saved order that are not in the backpack right now keep their place at the end
    local present = {};
    for _, itemName in ipairs(names) do present[itemName] = true; end
    for index, itemName in ipairs(names) do
        if (itemName == name) then
            local target = index + delta;
            if (target < 1 or target > #names) then return; end
            names[index], names[target] = names[target], names[index];
            break;
        end
    end
    for _, itemName in ipairs(barSettings.itemOrder or {}) do
        if (not present[itemName]) then table.insert(names, itemName); end
    end
    barSettings.itemOrder = names;
    barSettings.itemSort = "custom";
    current.Changed();
end

local function Fill()
    local list = window.list;
    list:ClearItems();
    local width = list:GetWidth();
    local entries = current.Entries();
    if (#entries == 0) then
        local line = Turbine.UI.Control();
        line:SetSize(width, 40);
        UI.Label(line, 0, 6, width, 30, L("No item on this bar at the moment."), { role = "dim"; });
        list:AddItem(line);
        return;
    end
    for _, entry in ipairs(entries) do
        local line = Turbine.UI.Control();
        line:SetSize(width, ROW);
        UI.Label(line, 0, 0, width - 64, ROW, entry.name);
        -- Images: the game fonts have no arrow characters
        for index, arrow in ipairs({ { image = "up"; delta = -1; }, { image = "down"; delta = 1; } }) do
            local button = Turbine.UI.Control();
            button:SetParent(line);
            button:SetSize(16, 16);
            button:SetPosition(width - 54 + (index - 1) * 26, math.floor((ROW - 16) / 2));
            button:SetBlendMode(Turbine.UI.BlendMode.AlphaBlend);
            local function Image(hover) button:SetBackground(IMAGES .. arrow.image .. (hover and "_hover" or "") .. ".tga"); end
            Image(false);
            button.MouseEnter = function() Image(true); end
            button.MouseLeave = function() Image(false); end
            button.MouseClick = function() Move(entry.name, arrow.delta); Fill(); end
        end
        list:AddItem(line);
    end
end

local function Create()
    -- Moved freely by its title bar while it is open, like the travel skills window
    window = Grommey.Window("itemOrder", L("Order of the items"), WIDTH, HEIGHT);
    local saved = Grommey.Profile.positions["itemOrder"];
    local screenWidth, screenHeight = Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
    local x = saved and saved.x or math.floor((screenWidth - WIDTH) / 2);
    local y = saved and saved.y or math.floor((screenHeight - HEIGHT) / 2);
    window:SetPosition(Grommey.Clamp(x, 0, math.max(0, screenWidth - WIDTH)), Grommey.Clamp(y, 0, math.max(0, screenHeight - HEIGHT)));
    local contentWidth, contentHeight = window.content:GetSize();

    local note = UI.Note(window.content, PAD, 10, contentWidth - 2 * PAD, L("The items of the bar, in the order they are shown. Move them with the arrows; new items come at the end."));
    local top = 10 + note:GetHeight() + 10;
    window.list = Turbine.UI.ListBox();
    window.list:SetParent(window.content);
    window.list:SetPosition(PAD, top);
    window.list:SetSize(contentWidth - 2 * PAD - 14, contentHeight - top - 56);
    window.scrollBar = Turbine.UI.Lotro.ScrollBar();
    window.scrollBar:SetOrientation(Turbine.UI.Orientation.Vertical);
    window.scrollBar:SetParent(window.content);
    window.scrollBar:SetPosition(contentWidth - PAD - 10, top);
    window.scrollBar:SetSize(10, contentHeight - top - 56);
    window.list:SetVerticalScrollBar(window.scrollBar);

    UI.Separator(window.content, 0, contentHeight - 50, contentWidth);
    UI.Button(window.content, contentWidth - PAD - 140, contentHeight - 38, 140, L("Close"), function() window:SetVisible(false); end, "accent");
    Grommey.On("HudToggled", function(hidden) if (hidden and window) then window:SetVisible(false); end end);
    -- A global keeps the window alive
    Grommey.ItemOrderWindow = window;
end

-- barSettings: the bar, entries(): what the bar shows now, changed(): called after a move
function ItemOrder.Open(barSettings, entries, changed)
    if (window == nil) then Create(); end
    current = { settings = barSettings; Entries = entries; Changed = changed; };
    window:SetTitle(L("Order of the items") .. "  ·  " .. barSettings.name);
    Fill();
    window:SetVisible(true);
    window:Activate();
end

function ItemOrder.Close()
    if (window) then window:SetVisible(false); end
end

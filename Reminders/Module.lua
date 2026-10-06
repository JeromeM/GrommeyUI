-- Buff reminders: warns when a chosen buff is missing or about to end, with icons in an area of
-- their own placed with the move mode. A reminder matches every effect whose name contains it,
-- so "Food" covers all the foods.
-- settings.list = { { name, icon, missing (warn when missing), before (seconds before the end, 0 = never),
--                     when ("always", "combat" or "peace") }, ... } in display order

local UI = Grommey.UI;
local Theme = Grommey.Theme;

local CHECK_DELAY = 0.5;   -- seconds between two looks at the effects
local ICON = 32;           -- the game does not scale effect icons, the box around them grows instead
local PULSE_SPEED = 5;
local CHAT_GRACE = 10;     -- no chat message while the buffs come back after loading
local PERMANENT = 86400;   -- longer effects have no end

local settingsRoot = nil;
local player = nil;
local area = nil;
local tiles = {};
local announced = {};      -- reminder name = state already said in the chat
local enabledAt = 0;
local preview = false;
local previewBeforeMove = false;

local function Read(object, method)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, value = pcall(object[method], object);
    if (ok) then return value; end
    return nil;
end

-- 42 -> "42s", 150 -> "2m"
local function ShortTime(seconds)
    if (seconds >= 3600) then return math.floor(seconds / 3600) .. "h"; end
    if (seconds >= 60) then return math.floor(seconds / 60) .. "m"; end
    return math.floor(seconds) .. "s";
end

-- 252 -> "4 min 12 s"
local function LongTime(seconds)
    seconds = math.floor(seconds);
    if (seconds >= 60) then return string.format(L("%d min %d s"), math.floor(seconds / 60), seconds % 60); end
    return string.format(L("%d s"), seconds);
end

------------------------------------------------------------------------------------------------------------------------------------------
-- What to warn about

-- Time left of an effect, nil when it has no end
local function Remaining(effect, now)
    local duration = Read(effect, "GetDuration") or 0;
    local start = Read(effect, "GetStartTime");
    if (duration <= 0 or duration >= PERMANENT or start == nil) then return nil; end
    return start + duration - now;
end

-- Reminders to show right now: { reminder, state ("missing" or "ending"), left }
local function Evaluate()
    local now = Turbine.Engine.GetGameTime();
    local found = {};
    local effects = Read(player, "GetEffects");
    for index = 1, (Read(effects, "GetCount") or 0) do
        local ok, effect = pcall(effects.Get, effects, index);
        local name = ok and Read(effect, "GetName");
        if (name) then table.insert(found, { lower = string.lower(name); effect = effect; }); end
    end
    local inCombat = Read(player, "IsInCombat") == true;

    local results = {};
    for _, reminder in ipairs(settingsRoot.list) do
        local when = reminder.when or "always";
        if (when == "always" or (when == "combat") == inCombat) then
            local needle = string.lower(reminder.name or "");
            local best, bestEffect = nil, nil;
            for _, entry in ipairs(found) do
                if (needle ~= "" and string.find(entry.lower, needle, 1, true)) then
                    local left = Remaining(entry.effect, now) or math.huge;
                    if (best == nil or left > best) then best, bestEffect = left, entry.effect; end
                end
            end
            -- Remember the icon, a missing buff is shown with it
            local icon = bestEffect and Read(bestEffect, "GetIcon");
            if (icon and reminder.icon ~= icon) then reminder.icon = icon; Grommey.Profiles.RequestSave(); end

            local state = nil;
            if (best == nil) then
                if (reminder.missing ~= false) then state = "missing"; end
            elseif ((reminder.before or 0) > 0 and best <= reminder.before) then
                state = "ending";
            end
            if (state) then table.insert(results, { reminder = reminder; state = state; left = best; }); end
        end
    end
    return results;
end

-- Fake reminders for the preview and the move mode
local function Samples()
    local results = {};
    local list = settingsRoot.list;
    if (#list == 0) then
        list = { { name = L("Example buff"); }, { name = L("Food"); } };
    end
    for index, reminder in ipairs(list) do
        local ending = (index % 2 == 0);
        table.insert(results, { reminder = reminder; state = ending and "ending" or "missing"; left = ending and 42 or nil; });
    end
    return results;
end

-- One chat line when a reminder starts, not again until the buff is back
local function Announce(results)
    local current = {};
    for _, result in ipairs(results) do
        local name = result.reminder.name;
        current[name] = true;
        if (announced[name] ~= result.state) then
            announced[name] = result.state;
            if (settingsRoot.chat and Turbine.Engine.GetGameTime() - enabledAt >= CHAT_GRACE) then
                if (result.state == "missing") then
                    Grommey.Print(string.format(L("Buff missing: %s"), name));
                else
                    Grommey.Print(string.format(L("%s ends in %s"), name, LongTime(result.left)));
                end
            end
        end
    end
    for name in pairs(announced) do
        if (not current[name]) then announced[name] = nil; end
    end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Area

local function IsList() return settingsRoot.layout == "list"; end

-- Box around the icon, its border and the text sizes grow with it
local function Box() return settingsRoot.size; end
local function BorderWidth() return (Box() >= 48) and 2 or 1; end
local function TimeHeight() return (Box() >= 44) and 18 or 14; end

local function TileSize()
    if (IsList()) then return Box() + 8 + settingsRoot.listWidth, Box(); end
    return Box(), Box() + TimeHeight();
end

local function Horizontal() return settingsRoot.growth == "right" or settingsRoot.growth == "left"; end

-- Room for every reminder, so the area does not jump when they come and go
local function AreaSize()
    local count = math.max(2, #settingsRoot.list);
    local width, height = TileSize();
    local spacing = settingsRoot.spacing;
    if (Horizontal()) then return count * (width + spacing) - spacing, height; end
    return width, count * (height + spacing) - spacing;
end

-- The game scales an image only when a control is set up once: a new control for each new icon
local function SetImage(tile, image)
    if (tile.imageKey == image) then return; end
    tile.imageKey = image;
    if (tile.image) then tile.image:SetParent(nil); tile.image = nil; end
    tile.swatch:SetVisible(image == nil);
    if (image == nil) then return; end
    local control = Turbine.UI.Control();
    control:SetParent(tile);
    control:SetSize(ICON, ICON);
    control:SetMouseVisible(false);
    control:SetBackground(image);
    tile.image = control;
    tile.time:SetZOrder(2);
end

local function CreateTile()
    local tile = Turbine.UI.Control();
    tile:SetParent(area);
    tile:SetMouseVisible(false);

    tile.box = Turbine.UI.Control();
    tile.box:SetParent(tile);
    tile.box:SetMouseVisible(false);
    tile.fill = Turbine.UI.Control();
    tile.fill:SetParent(tile);
    tile.fill:SetMouseVisible(false);
    tile.fill:SetBackColor(Theme.Color("field"));

    -- Unknown icon (a name typed by hand, never seen yet)
    tile.swatch = Turbine.UI.Control();
    tile.swatch:SetParent(tile);
    tile.swatch:SetSize(ICON, ICON);
    tile.swatch:SetMouseVisible(false);
    tile.swatch:SetBackColor(Theme.Color("raised"));
    UI.Label(tile.swatch, 0, 0, 32, 32, "?", { size = 16; bold = true; role = "dim"; align = Turbine.UI.ContentAlignment.MiddleCenter; });

    tile.time = Turbine.UI.Label();
    tile.time:SetParent(tile);
    tile.time:SetFontStyle(Turbine.UI.FontStyle.Outline);
    tile.time:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    tile.time:SetForeColor(Turbine.UI.Color(1, 1, 1));
    tile.time:SetMouseVisible(false);

    tile.name = UI.Label(tile, 0, 0, 10, 18, "", { size = 14; bold = true; });
    tile.status = UI.Label(tile, 0, 0, 10, 18, "", { size = 13; });
    tile.name:SetFontStyle(Turbine.UI.FontStyle.Outline);
    tile.name:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    tile.status:SetFontStyle(Turbine.UI.FontStyle.Outline);
    tile.status:SetOutlineColor(Turbine.UI.Color(0, 0, 0));
    return tile;
end

local function Draw(results)
    local width, height = TileSize();
    local areaWidth, areaHeight = area:GetSize();
    local spacing = settingsRoot.spacing;
    local list = IsList();

    for index = 1, math.max(#results, #tiles) do
        local tile = tiles[index];
        local result = results[index];
        if (result == nil) then
            if (tile) then tile:SetVisible(false); tile.state = nil; end
        else
            if (tile == nil) then tile = CreateTile(); tiles[index] = tile; end
            tile.state = result.state;
            tile:SetSize(width, height);
            SetImage(tile, result.reminder.icon);

            local ending = (result.state == "ending");
            local timeText = ending and ShortTime(result.left) or "";
            local box, border = Box(), BorderWidth();
            local inset = math.floor((box - ICON) / 2);
            tile.box:SetSize(box, box);
            tile.fill:SetPosition(border, border);
            tile.fill:SetSize(box - 2 * border, box - 2 * border);
            tile.swatch:SetPosition(inset, inset);
            if (tile.image) then tile.image:SetPosition(inset, inset); end
            tile.time:SetFont(Theme.Font((box >= 44) and 14 or 12, false));
            tile.time:SetPosition(0, list and 0 or box);
            tile.time:SetSize(box, list and (box - 1) or TimeHeight());
            tile.time:SetTextAlignment(list and Turbine.UI.ContentAlignment.BottomCenter or Turbine.UI.ContentAlignment.MiddleCenter);
            tile.time:SetText(list and "" or timeText);

            tile.name:SetVisible(list);
            tile.status:SetVisible(list);
            if (list) then
                local middle = math.floor(box / 2);
                tile.name:SetPosition(box + 8, middle - 18);
                tile.status:SetPosition(box + 8, middle);
                tile.name:SetSize(settingsRoot.listWidth, 18);
                tile.name:SetText(result.reminder.name or "");
                tile.status:SetSize(settingsRoot.listWidth, 18);
                tile.status:SetText(ending and string.format(L("Ends in %s"), LongTime(result.left)) or L("Missing"));
                tile.status:SetForeColor(ending and Theme.Color("accent") or Theme.Color("danger"));
            end

            -- Placed along the direction, from the side the area grows from
            local step = index - 1;
            local x, y = 0, 0;
            local growth = settingsRoot.growth;
            if (growth == "right") then x = step * (width + spacing);
            elseif (growth == "left") then x = areaWidth - width - step * (width + spacing);
            elseif (growth == "down") then y = step * (height + spacing);
            else y = areaHeight - height - step * (height + spacing); end
            tile:SetPosition(x, y);
            tile:SetVisible(true);
        end
    end
    area:SetVisible(#results > 0 and not Grommey.HudHidden);
end

-- Border of a tile: red when missing, theme colour when ending, pulsing if asked
local function PaintBorders()
    local amount = 1;
    if (settingsRoot.pulse) then amount = (math.sin(Turbine.Engine.GetGameTime() * PULSE_SPEED) + 1) / 2; end
    local missing = Theme.Mix("border", "danger", amount);
    local ending = Theme.Mix("border", "accent", amount);
    for _, tile in ipairs(tiles) do
        if (tile.state) then tile.box:SetBackColor(tile.state == "missing" and missing or ending); end
    end
end

local function Refresh()
    local results = preview and Samples() or Evaluate();
    if (not preview) then Announce(results); end
    Draw(results);
end

local function Destroy()
    if (area == nil) then return; end
    area:SetWantsUpdates(false);
    area:SetVisible(false);
    Grommey.Movers.Unregister("reminders");
    area = nil;
    tiles = {};
end

local function Build()
    Destroy();
    area = Turbine.UI.Window();
    area:SetMouseVisible(false);
    area:SetSize(AreaSize());
    area.nextCheck = 0;
    area:SetWantsUpdates(true);
    area.Update = function()
        local now = Turbine.Engine.GetGameTime();
        if (now >= area.nextCheck) then
            area.nextCheck = now + CHECK_DELAY;
            Refresh();
        end
        PaintBorders();
    end
    Grommey.Movers.Register("reminders", area, L("Buff reminders"),
        function() return math.floor((Turbine.UI.Display.GetWidth() - area:GetWidth()) / 2); end,
        function() return math.floor(Turbine.UI.Display.GetHeight() * 0.25); end);
    Refresh();
end

local function SetPreview(enabled)
    preview = enabled;
    if (area) then Refresh(); end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Options

local selectedSection = "reminders";
local selectedName = nil;

local function Translated(items)
    local list = {};
    for _, item in ipairs(items) do table.insert(list, { value = item.value; text = L(item.text); }); end
    return list;
end

local function Find(name)
    for position, reminder in ipairs(settingsRoot.list) do
        if (reminder.name == name) then return reminder, position; end
    end
    return nil;
end

local function BuildReminderOptions(page, width, settings, Changed, Reopen)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    local function Add(name, icon)
        name = string.match(name or "", "^%s*(.-)%s*$");
        if (name == "" or Find(name)) then return; end
        table.insert(settings.list, { name = name; icon = icon; missing = true; before = 0; when = "always"; });
        selectedName = name;
        Changed();
        Reopen();
    end

    -- Buffs on the character right now, one click to be reminded of it
    UI.Label(page, 0, 0, half, 20, L("Your buffs right now"), { bold = true; role = "accent"; });
    local names, icons = {}, {};
    local effects = Read(player, "GetEffects");
    for index = 1, (Read(effects, "GetCount") or 0) do
        local ok, effect = pcall(effects.Get, effects, index);
        local name = ok and Read(effect, "GetName");
        if (name and Read(effect, "IsDebuff") ~= true and not icons[name]) then
            table.insert(names, name);
            icons[name] = Read(effect, "GetIcon") or true;
        end
    end
    table.sort(names);

    -- A name typed by hand, for a buff you do not have right now
    local nameBox = UI.TextInput(page, 0, 28, half - 90, "");
    UI.Button(page, half - 82, 28, 82, L("Add"), function() Add(nameBox:GetText()); end, "accent");

    local y = 66;
    if (#names == 0) then
        UI.Label(page, 0, y, half, 36, L("No buff on you at the moment."), { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end
    for _, name in ipairs(names) do
        local known = Find(name) ~= nil;
        UI.Label(page, 0, y, half - 96, 26, name, { size = 12; });
        -- A second click forgets it
        UI.Button(page, half - 90, y, 90, L("Remind"), function()
            local _, position = Find(name);
            if (position) then table.remove(settings.list, position); Changed(); Reopen(); return; end
            local icon = icons[name];
            Add(name, (icon ~= true) and icon or nil);
        end, known and "accent" or nil);
        y = y + 30;
        if (y > page:GetHeight() - 30) then break; end
    end

    -- My reminders, click one to set it up, the cross removes it
    UI.Label(page, right, 0, half, 20, L("My reminders"), { bold = true; role = "accent"; });
    if (Find(selectedName or "") == nil) then selectedName = settings.list[1] and settings.list[1].name; end
    local settingsTop = page:GetHeight() - 190;
    local rowY = 28;
    if (#settings.list == 0) then
        UI.Label(page, right, rowY, half, 60, L("No reminder yet. Pick one of your buffs or type a name."), { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end
    for position, reminder in ipairs(settings.list) do
        if (rowY + 28 > settingsTop - 10) then
            UI.Label(page, right, rowY, half, 20, string.format(L("And %d more"), #settings.list - position + 1), { size = 12; role = "dim"; });
            break;
        end
        local selected = (reminder.name == selectedName);
        local row = UI.Frame(page, right, rowY, half - 30, 26, selected and "raised" or "panel", selected and "accent" or "border");
        UI.Label(row.inner, 8, 0, half - 46, 24, reminder.name, { size = 12; mouse = false; });
        row.inner.MouseClick = function() selectedName = reminder.name; Reopen(); end
        local remove = UI.Label(page, width - 24, rowY + 2, 22, 22, "x", { role = "danger"; mouse = true; align = Turbine.UI.ContentAlignment.MiddleCenter; });
        remove.MouseClick = function()
            table.remove(settings.list, position);
            Changed();
            Reopen();
        end
        rowY = rowY + 30;
    end

    local reminder, position = Find(selectedName or "");
    if (reminder == nil) then return; end

    -- Settings of the selected reminder
    local top = settingsTop;
    UI.Separator(page, right, top, half);
    UI.Label(page, right, top + 8, half - 60, 20, reminder.name, { bold = true; });
    UI.Button(page, width - 56, top + 6, 26, "^", function()
        if (position > 1) then
            settings.list[position], settings.list[position - 1] = settings.list[position - 1], settings.list[position];
            Changed(); Reopen();
        end
    end);
    UI.Button(page, width - 26, top + 6, 26, "v", function()
        if (position < #settings.list) then
            settings.list[position], settings.list[position + 1] = settings.list[position + 1], settings.list[position];
            Changed(); Reopen();
        end
    end);
    UI.Toggle(page, right, top + 38, half, L("Warn when it is missing"), reminder.missing ~= false, function(value)
        reminder.missing = value;
        Changed();
    end);
    UI.Slider(page, right, top + 72, half, L("Warn before it ends"), 0, 600, 15, reminder.before or 0, function(value)
        reminder.before = value;
        Changed();
    end, " s");
    UI.Label(page, right, top + 124, half, 18, L("When"));
    UI.Dropdown(page, right, top + 144, half, Translated({
        { value = "always"; text = "Always"; }, { value = "combat"; text = "In combat only"; }, { value = "peace"; text = "Out of combat only"; },
    }), reminder.when or "always", function(value) reminder.when = value; Changed(); end);
end

local function BuildDisplayOptions(page, width, settings, Changed)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    local y = 0;
    UI.Label(page, 0, y, half, 18, L("Layout"));
    UI.Dropdown(page, 0, y + 20, half, Translated({
        { value = "icons"; text = "Icons"; }, { value = "list"; text = "List with names"; },
    }), settings.layout, function(value) settings.layout = value; Changed(); end);
    UI.Label(page, right, y, half, 18, L("Direction"));
    UI.Dropdown(page, right, y + 20, half, Translated({
        { value = "right"; text = "Toward the right"; }, { value = "left"; text = "Toward the left"; },
        { value = "down"; text = "Downward"; }, { value = "up"; text = "Upward"; },
    }), settings.growth, function(value) settings.growth = value; Changed(); end);
    y = y + 64;
    UI.Slider(page, 0, y, half, L("Space between reminders"), 0, 20, 1, settings.spacing, function(value) settings.spacing = value; Changed(); end, " px");
    UI.Slider(page, right, y, half, L("Width of the names (list)"), 100, 320, 10, settings.listWidth, function(value) settings.listWidth = value; Changed(); end, " px");
    y = y + 54;
    UI.Slider(page, 0, y, half, L("Size of the reminders"), 34, 64, 2, settings.size, function(value) settings.size = value; Changed(); end, " px");
    y = y + 60;
    UI.Toggle(page, 0, y, half, L("Pulsing border"), settings.pulse, function(value) settings.pulse = value; Changed(); end);
    UI.Toggle(page, right, y, half, L("Message in the chat"), settings.chat, function(value) settings.chat = value; Changed(); end);
    y = y + 44;
    UI.Note(page, 0, y, width, L("A red border: the buff is missing. In the theme colour: it ends soon. A reminder covers every effect whose name contains it, so one word can cover several buffs. Place the reminders with the move mode."));
end

local function BuildOptions(page, width, settings)
    local function Reopen() Grommey.Options.ShowPage("module:Reminders"); end
    local function Changed() Grommey.Profiles.RequestSave(); Build(); end

    UI.Header(page, 0, 16, width, L("Buff reminders"));
    UI.Button(page, width - 200, 12, 200, preview and L("Preview: on") or L("Preview: off"), function()
        SetPreview(not preview);
        Reopen();
    end, preview and "accent" or nil);

    local x = 0;
    for _, section in ipairs({ { key = "reminders"; text = L("Reminders"); }, { key = "display"; text = L("Display"); } }) do
        UI.Button(page, x, 52, 170, section.text, function() selectedSection = section.key; Reopen(); end,
            (selectedSection == section.key) and "accent" or nil);
        x = x + 178;
    end

    local holder = Turbine.UI.Control();
    holder:SetParent(page);
    holder:SetPosition(0, 100);
    holder:SetSize(width, page:GetHeight() - 100);
    if (selectedSection == "display") then
        BuildDisplayOptions(holder, width, settings, Changed);
    else
        BuildReminderOptions(holder, width, settings, Changed, Reopen);
    end
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Module

Grommey.Modules.Register({
    id = "Reminders";
    name = "Buff reminders";
    description = "Warns you when a buff you chose is missing or about to end.";
    enabledByDefault = true;
    defaults = {
        list = {};
        layout = "icons";
        size = 48;
        growth = "right";
        spacing = 6;
        listWidth = 180;
        pulse = true;
        chat = true;
    };

    Enable = function(settings)
        settingsRoot = settings;
        player = Turbine.Gameplay.LocalPlayer.GetInstance();
        enabledAt = Turbine.Engine.GetGameTime();
        announced = {};
        Build();

        -- Fake reminders in move mode so the area has something to show
        Grommey.On("MoveModeChanged", function(active)
            if (settingsRoot == nil) then return; end
            if (active) then
                previewBeforeMove = preview;
                SetPreview(true);
            else
                SetPreview(previewBeforeMove == true);
            end
        end);
        Grommey.On("HudToggled", function() if (settingsRoot and area) then Refresh(); end end);
        Grommey.On("ThemeChanged", function() if (settingsRoot) then Build(); end end);
    end;

    Disable = function()
        Destroy();
        settingsRoot = nil;
    end;

    BuildOptions = BuildOptions;
});

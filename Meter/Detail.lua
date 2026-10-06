-- Detail window of the combat meter, opened by a click on a bar: everything known about one person
-- in one view, as Combat Analysis shows it. On the left the skills (or the targets, or the damage
-- types) with "All" first, on the right every counter of the one selected: hits, critical and
-- devastating hits, average, biggest and smallest, each kind of avoidance, damage types.
-- Fixed size, moved freely by its title bar, it follows the fight chosen in the main window.

local UI = Grommey.UI;
local Theme = Grommey.Theme;
local Combats = Grommey.Meter.Combats;
local Meter = Grommey.Meter;
local Align = Turbine.UI.ContentAlignment;

local WIDTH, HEIGHT = 700, 470;
local LIST_X, LIST_WIDTH = 12, 320;
local PANEL_X = LIST_X + LIST_WIDTH + 18;
local TOP = 46;
local ROW_HEIGHT, ROW_STEP = 20, 22;
local LINE_HEIGHT = 19;

local Detail = {};
Meter.Detail = Detail;

local window = nil;
local state = { mode = "damage"; actor = nil; tab = "skills"; selected = nil; listOffset = 0; panelOffset = 0; };

local DAMAGE_TYPES = {
    { key = "common"; name = "Common"; }, { key = "fire"; name = "Fire"; }, { key = "lightning"; name = "Lightning"; },
    { key = "frost"; name = "Frost"; }, { key = "acid"; name = "Acid"; }, { key = "shadow"; name = "Shadow"; },
    { key = "light"; name = "Light"; }, { key = "beleriand"; name = "Beleriand"; }, { key = "westernesse"; name = "Westernesse"; },
    { key = "dwarf"; name = "Ancient Dwarf-make"; }, { key = "orc"; name = "Orc-craft"; }, { key = "fell"; name = "Fell-wrought"; },
};

local AVOIDS = {
    { key = "miss"; name = "Missed"; }, { key = "deflect"; name = "Deflected"; }, { key = "block"; name = "Blocked"; },
    { key = "parry"; name = "Parried"; }, { key = "evade"; name = "Evaded"; }, { key = "resist"; name = "Resisted"; },
    { key = "immune"; name = "Immune"; }, { key = "other"; name = "Other"; },
};

local PARTIALS = {
    { key = "block"; name = "Partly blocked"; }, { key = "parry"; name = "Partly parried"; }, { key = "evade"; name = "Partly evaded"; },
};

local BUCKETS = {
    { key = "normal"; name = "Normal hits"; }, { key = "crit"; name = "Critical hits"; }, { key = "devastating"; name = "Devastating hits"; },
};

local function TypeName(key)
    for _, damageType in ipairs(DAMAGE_TYPES) do
        if (damageType.key == key) then return L(damageType.name); end
    end
    -- A type the reader does not know: the text of the game
    return tostring(key);
end

local function Now()
    return Turbine.Engine.GetGameTime();
end

local function Fight()
    return Meter.DisplayedFight();
end

local function Actor(fight)
    if (fight == nil or state.actor == nil) then return nil; end
    return fight.data[state.mode][state.actor];
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Lines of the right panel

local function StatsLines(stats, parentTotal, duration, withTypes)
    local Short, Percent = Meter.Short, Meter.Percent;
    local lines = {};
    local function Header(text) table.insert(lines, { header = text; }); end
    local function Line(label, value) table.insert(lines, { label = label; value = value; }); end

    local landed = stats.normal.count + stats.crit.count + stats.devastating.count;
    local max, min = Combats.Extremes(stats);

    Header(L("General"));
    Line(L("Total"), Short(stats.total));
    Line(L("Per second"), Meter.PerSecond(stats.total / duration));
    if (parentTotal ~= nil) then Line(L("Share of the total"), Percent(stats.total, parentTotal)); end
    Line(L("Attempts"), tostring(stats.count));
    Line(L("Landed"), stats.hits .. "  (" .. Percent(stats.hits, stats.count) .. ")");
    if (landed > 0) then
        Line(L("Average"), Short(stats.total / landed));
        Line(L("Biggest / smallest"), Short(max) .. " / " .. Short(min));
    end

    for _, bucketInfo in ipairs(BUCKETS) do
        local bucket = stats[bucketInfo.key];
        if (bucket.count > 0) then
            Header(L(bucketInfo.name));
            Line(L("Count"), bucket.count .. "  (" .. Percent(bucket.count, landed) .. ")");
            Line(L("Total"), Short(bucket.total) .. "  (" .. Percent(bucket.total, stats.total) .. ")");
            Line(L("Average"), Short(bucket.total / bucket.count));
            Line(L("Biggest / smallest"), Short(bucket.max) .. " / " .. Short(bucket.min or 0));
        end
    end

    if (stats.avoided > 0 or stats.partialCount > 0 or stats.noDamage > 0) then
        Header(L("Avoidance"));
        if (stats.avoided > 0) then Line(L("Fully avoided"), stats.avoided .. "  (" .. Percent(stats.avoided, stats.count) .. ")"); end
        for _, avoid in ipairs(AVOIDS) do
            local count = stats.avoid[avoid.key];
            if (count ~= nil and count > 0) then Line("   " .. L(avoid.name), count .. "  (" .. Percent(count, stats.count) .. ")"); end
        end
        if (stats.partialCount > 0) then Line(L("Partly avoided"), stats.partialCount .. "  (" .. Percent(stats.partialCount, stats.count) .. ")"); end
        for _, partial in ipairs(PARTIALS) do
            local count = stats.partial[partial.key];
            if (count ~= nil and count > 0) then Line("   " .. L(partial.name), count .. "  (" .. Percent(count, stats.count) .. ")"); end
        end
        if (stats.noDamage > 0) then Line(L("Landed without damage"), stats.noDamage .. "  (" .. Percent(stats.noDamage, stats.count) .. ")"); end
    end

    if (withTypes and next(stats.types) ~= nil) then
        Header(L("Damage types"));
        for _, entry in ipairs(Combats.Types(stats)) do
            Line(TypeName(entry.name), Short(entry.total) .. "  (" .. Meter.Percent(entry.total, stats.total) .. ")");
        end
    end
    return lines;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Window

local function TabsFor(mode)
    local targets = (mode == "enemies") and L("Attackers") or L("Targets");
    local tabs = { { key = "skills"; text = L("Skills"); }, { key = "targets"; text = targets; } };
    if (mode == "damage" or mode == "taken" or mode == "enemies") then table.insert(tabs, { key = "types"; text = L("Damage types"); }); end
    return tabs;
end

local function BuildTabs()
    for _, button in ipairs(window.tabButtons or {}) do button:SetParent(nil); button:SetVisible(false); end
    window.tabButtons = {};
    local x = LIST_X;
    for _, tab in ipairs(TabsFor(state.mode)) do
        local button = UI.Button(window.content, x, 10, 150, tab.text, function()
            state.tab = tab.key;
            state.selected = nil;
            state.listOffset = 0;
            state.panelOffset = 0;
            BuildTabs();
            Detail.Refresh();
        end, (state.tab == tab.key) and "accent" or nil);
        table.insert(window.tabButtons, button);
        x = x + 158;
    end
end

local function CreateWindow()
    -- Moved freely by its title bar while it is open, not part of the move mode.
    -- The id keeps the place it was dragged to in the profile.
    local w = Grommey.Window("meterDetail", "", WIDTH, HEIGHT);
    local saved = Grommey.Profile.positions["meterDetail"];
    local screenWidth, screenHeight = Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
    local x = saved and saved.x or math.floor((screenWidth - WIDTH) / 2);
    local y = saved and saved.y or math.floor((screenHeight - HEIGHT) / 2);
    w:SetPosition(Grommey.Clamp(x, 0, math.max(0, screenWidth - WIDTH)), Grommey.Clamp(y, 0, math.max(0, screenHeight - HEIGHT)));
    local content = w.content;
    local contentHeight = content:GetHeight();

    -- Left list
    w.list = Turbine.UI.Control();
    w.list:SetParent(content);
    w.list:SetPosition(LIST_X, TOP);
    w.list:SetSize(LIST_WIDTH, contentHeight - TOP - 10);
    w.rows = {};
    local count = math.floor((contentHeight - TOP - 10 + ROW_STEP - ROW_HEIGHT) / ROW_STEP);
    local function ScrollList(sender, args)
        state.listOffset = math.max(0, state.listOffset - (args.Direction or 0));
        Detail.Refresh();
    end
    w.list.MouseWheel = ScrollList;
    local font = Theme.Font(12, false);
    for index = 1, count do
        local row = Turbine.UI.Control();
        row:SetParent(w.list);
        row:SetPosition(0, (index - 1) * ROW_STEP);
        row:SetSize(LIST_WIDTH, ROW_HEIGHT);
        row.fill = Turbine.UI.Control();
        row.fill:SetParent(row);
        row.fill:SetMouseVisible(false);
        row.fill:SetHeight(ROW_HEIGHT);
        -- The selected line has a mark of the theme colour on its left, the bars keep the meter colours
        row.marker = Turbine.UI.Control();
        row.marker:SetParent(row);
        row.marker:SetMouseVisible(false);
        row.marker:SetSize(3, ROW_HEIGHT);
        row.left = Meter.OutlinedLabel(row, Align.MiddleLeft);
        row.left:SetPosition(8, 0);
        row.left:SetSize(LIST_WIDTH - 120, ROW_HEIGHT);
        row.left:SetFont(font);
        row.right = Meter.OutlinedLabel(row, Align.MiddleRight);
        row.right:SetPosition(LIST_WIDTH - 114, 0);
        row.right:SetSize(110, ROW_HEIGHT);
        row.right:SetFont(font);
        row.MouseWheel = ScrollList;
        row.MouseClick = function()
            if (row.entry == nil) then return; end
            state.selected = row.entry.key;
            state.panelOffset = 0;
            Detail.Refresh();
        end
        w.rows[index] = row;
    end

    -- Right panel
    w.panel = Turbine.UI.Control();
    w.panel:SetParent(content);
    w.panel:SetPosition(PANEL_X, TOP);
    local panelWidth = WIDTH - 2 - PANEL_X - 14;
    w.panel:SetSize(panelWidth, contentHeight - TOP - 10);
    w.panel.MouseWheel = function(sender, args)
        state.panelOffset = math.max(0, state.panelOffset - (args.Direction or 0));
        Detail.Refresh();
    end
    w.panelTitle = UI.Label(w.panel, 0, 0, panelWidth, 22, "", { bold = true; size = 14; });
    w.lines = {};
    local lineCount = math.floor((contentHeight - TOP - 10 - 28) / LINE_HEIGHT);
    for index = 1, lineCount do
        local y = 28 + (index - 1) * LINE_HEIGHT;
        local line = {};
        line.label = UI.Label(w.panel, 0, y, panelWidth - 130, LINE_HEIGHT, "", { size = 12; role = "dim"; });
        line.value = UI.Label(w.panel, panelWidth - 130, y, 130, LINE_HEIGHT, "", { size = 12; align = Align.MiddleRight; });
        line.header = UI.Label(w.panel, 0, y, panelWidth, LINE_HEIGHT, "", { size = 13; bold = true; role = "accent"; });
        w.lines[index] = line;
    end
    w.empty = UI.Label(content, LIST_X, TOP, WIDTH - 40, 40, L("Nothing for this person in this fight."), { role = "dim"; });

    Theme.Track(function()
        for _, row in ipairs(w.rows) do row:SetBackColor(Theme.Color("field")); end
    end);

    Grommey.On("HudToggled", function(hidden) if (hidden and window) then window:SetVisible(false); end end);
    return w;
end

-- Entries of the left list for the tab
local function ListEntries(fight, actor)
    local entries = {};
    if (actor == nil) then return entries; end
    if (state.tab == "types") then
        for _, entry in ipairs(Combats.Types(actor.all)) do
            table.insert(entries, { key = entry.name; name = TypeName(entry.name); total = entry.total; percent = entry.percent; });
        end
        return entries;
    end
    table.insert(entries, { key = "*all"; name = L("All"); total = actor.total; percent = 100; stats = actor.all; all = true; });
    local source = (state.tab == "targets") and actor.targets or actor.skills;
    for _, entry in ipairs(Combats.Entries(fight, source, actor.total)) do
        local name = (state.tab == "skills") and Meter.SkillName(entry.name) or entry.name;
        table.insert(entries, { key = entry.name; name = name; total = entry.total; percent = entry.percent; stats = entry.stats; });
    end
    return entries;
end

function Detail.Refresh()
    if (window == nil or not window:IsVisible()) then return; end
    local fight = Fight();
    local actor = Actor(fight);
    local now = Now();
    window:SetTitle(tostring(state.actor) .. "  ·  " .. Meter.ViewName(state.mode) .. "  ·  " .. Meter.FightText(fight, Meter.SelectedFight()));
    window.drawnVersion = Combats.version;
    window.drawnAt = now;

    window.empty:SetVisible(actor == nil);
    window.list:SetVisible(actor ~= nil);
    window.panel:SetVisible(actor ~= nil);
    if (actor == nil) then return; end

    -- Left list
    local entries = ListEntries(fight, actor);
    if (state.selected == nil and entries[1] ~= nil) then state.selected = entries[1].key; end
    state.listOffset = math.max(0, math.min(state.listOffset, #entries - #window.rows));
    local best = 0;
    for _, entry in ipairs(entries) do
        if (not entry.all and entry.total > best) then best = entry.total; end
    end
    local selectedEntry = nil;
    for index, entry in ipairs(entries) do
        if (entry.key == state.selected) then
            selectedEntry = entry;
            -- Opened on this entry: the list scrolls to it
            if (state.scrollToSelected and index > #window.rows) then state.listOffset = index - #window.rows; end
        end
    end
    state.scrollToSelected = false;
    -- Same colours as the meter: red for what enemies did or received, class colour for what is yours
    local you = Meter.Log.PlayerName();
    local enemyBars;
    if (state.mode == "taken") then
        enemyBars = (state.tab ~= "targets");
    elseif (state.mode == "damage") then
        enemyBars = (state.tab == "targets");
    else
        enemyBars = false;
    end
    local mine = (state.actor == you) or (state.mode == "enemies") or (state.mode == "taken" and state.tab == "targets");
    for index, row in ipairs(window.rows) do
        local entry = entries[index + state.listOffset];
        row.entry = entry;
        if (entry == nil) then
            row:SetVisible(false);
        else
            row:SetVisible(true);
            local ratio = entry.all and 1 or ((best > 0) and entry.total / best or 0);
            row.fill:SetWidth(math.floor(LIST_WIDTH * ratio + 0.5));
            local selected = (entry.key == state.selected);
            row.fill:SetBackColor(Meter.BarColor(enemyBars, not enemyBars and mine));
            row.marker:SetBackColor(Theme.Color("accent"));
            row.marker:SetVisible(selected);
            row.left:SetForeColor(Theme.Color("text"));
            row.left:SetText(entry.name);
            row.right:SetForeColor(Theme.Color("text"));
            row.right:SetText(Meter.Short(entry.total) .. "  " .. math.floor(entry.percent + 0.5) .. "%");
        end
    end

    -- Right panel: counters of the selected entry (for a damage type, the whole person)
    local stats = (selectedEntry and selectedEntry.stats) or actor.all;
    local title = (selectedEntry and not selectedEntry.all and selectedEntry.stats) and selectedEntry.name or L("All");
    window.panelTitle:SetText(title);
    local parentTotal = (stats ~= actor.all) and actor.total or nil;
    local lines = StatsLines(stats, parentTotal, Combats.Duration(fight, now), state.tab ~= "types");
    state.panelOffset = math.max(0, math.min(state.panelOffset, #lines - #window.lines));
    for index, line in ipairs(window.lines) do
        local item = lines[index + state.panelOffset];
        line.header:SetText((item and item.header) or "");
        line.label:SetText((item and item.label) or "");
        line.value:SetText((item and item.value) or "");
    end
end

-- tab: "skills", "targets" or "types", key: the skill or target to select (optional)
function Detail.Open(mode, actorName, tab, key)
    if (window == nil) then Detail.Create(); end
    state.mode = mode;
    state.actor = actorName;
    state.tab = tab or "skills";
    state.selected = key;
    state.scrollToSelected = (key ~= nil);
    state.listOffset = 0;
    state.panelOffset = 0;
    BuildTabs();
    window:SetVisible(true);
    window:Activate();
    Detail.Refresh();
end

-- Called by the meter window four times a second
function Detail.Tick(now)
    if (window == nil or not window:IsVisible()) then return; end
    if (window.drawnVersion ~= Combats.version and now - (window.drawnAt or 0) >= 1) then Detail.Refresh(); end
end

function Detail.Create()
    if (window ~= nil) then return; end
    window = CreateWindow();
    -- A global keeps the window alive
    Meter.DetailWindow = window;
end

function Detail.Destroy()
    if (window == nil) then return; end
    window:SetVisible(false);
    window = nil;
    Meter.DetailWindow = nil;
end

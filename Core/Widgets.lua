-- Flat widgets in the GrommeyUI style. Every widget follows the theme by itself.
-- Positions are relative to the parent, like any Turbine control.

Grommey.UI = {};

local Theme = Grommey.Theme;
local Align = Turbine.UI.ContentAlignment;

-- Screen position of a control, adding the offsets of all its parents
function Grommey.UI.ScreenPosition(control)
    local x, y = 0, 0;
    local current = control;
    while (current ~= nil) do
        x = x + current:GetLeft();
        y = y + current:GetTop();
        current = current:GetParent();
    end
    return x, y;
end

function Grommey.UI.Label(parent, x, y, width, height, text, options)
    options = options or {};
    local label = Turbine.UI.Label();
    label:SetParent(parent);
    label:SetPosition(x, y);
    label:SetSize(width, height);
    label:SetTextAlignment(options.align or Align.MiddleLeft);
    label:SetMultiline(options.multiline == true);
    label:SetMarkupEnabled(options.markup == true);
    label:SetMouseVisible(options.mouse == true);
    label:SetText(text or "");
    Theme.Track(function()
        label:SetFont(Theme.Font(options.size or 14, options.bold));
        label:SetForeColor(Theme.Color(options.role or "text"));
    end);
    return label;
end

-- Section title in the accent colour with a thin line under it
function Grommey.UI.Header(parent, x, y, width, text)
    local label = Grommey.UI.Label(parent, x, y, width, 22, text, { size = 16; bold = true; role = "accent"; });
    local line = Turbine.UI.Control();
    line:SetParent(parent);
    line:SetPosition(x, y + 24);
    line:SetSize(width, 1);
    line:SetMouseVisible(false);
    Theme.Track(function() line:SetBackColor(Theme.Color("border")); end);
    return label;
end

-- A box with a 1 pixel border. Children go into frame.inner.
function Grommey.UI.Frame(parent, x, y, width, height, role, borderRole)
    local frame = Turbine.UI.Control();
    frame:SetParent(parent);
    frame:SetPosition(x, y);
    frame:SetSize(width, height);

    frame.inner = Turbine.UI.Control();
    frame.inner:SetParent(frame);
    frame.inner:SetPosition(1, 1);
    frame.inner:SetSize(width - 2, height - 2);

    frame.role = role or "panel";
    frame.borderRole = borderRole or "border";
    frame.Paint = function()
        frame:SetBackColor(Theme.Color(frame.borderRole));
        frame.inner:SetBackColor(Theme.Color(frame.role));
    end
    Theme.Track(frame.Paint);

    frame.Resize = function(newWidth, newHeight)
        frame:SetSize(newWidth, newHeight);
        frame.inner:SetSize(newWidth - 2, newHeight - 2);
    end
    return frame;
end

-- Help text in a box that invites to read it: panel background tinted with the theme colour, a line
-- of that colour on the left, a bigger text. The game neither spaces lines nor justifies a text, and
-- does not tell how wide a text is: the note lays its text out itself, word by word, from the widths
-- of the Verdana letters (Core/FontMetrics.lua). Lines get more space between them and all of them
-- but the last are justified. Returns the box, its height is box:GetHeight().
local NOTE_PAD = 10;
local NOTE_SIZE = 15;
local NOTE_SPACING = 5;             -- added between two lines
local PIXELS_PER_EM_14 = 12.8;      -- measured in game: Verdana 14 is 12.8 pixels to the em
local VERDANA_SIZES = { 10, 12, 13, 14, 15, 16, 18, 20, 22, 23 };

-- The Verdana font of the notes, at the size chosen in the theme
local function NoteFont()
    local wanted = NOTE_SIZE + (Grommey.Profile.theme.fontOffset or 0);
    local best = nil;
    for _, size in ipairs(VERDANA_SIZES) do
        if (Turbine.UI.Lotro.Font["Verdana" .. size] and (best == nil or math.abs(size - wanted) < math.abs(best - wanted))) then best = size; end
    end
    best = best or 14;
    return Turbine.UI.Lotro.Font["Verdana" .. best] or Turbine.UI.Lotro.Font.Verdana14, best;
end

local function TextWidth(text, size)
    local metrics = Grommey.FontMetrics;
    local units = 0;
    -- One UTF-8 letter at a time: accented letters take two bytes
    for letter in string.gmatch(text, "[%z\1-\127\194-\244][\128-\191]*") do
        units = units + (metrics.widths[letter] or metrics.average);
    end
    return units / metrics.unitsPerEm * PIXELS_PER_EM_14 * size / 14;
end

-- The words of the text in lines no wider than width: { { words = { { text, width } }, width, last } }
local function Wrap(text, width, size)
    local lines = {};
    local space = TextWidth(" ", size);
    for paragraph in string.gmatch((text or "") .. "\n", "(.-)\n") do
        local line = { words = {}; width = 0; };
        for word in string.gmatch(paragraph, "%S+") do
            local wordWidth = TextWidth(word, size);
            if (#line.words > 0 and line.width + space + wordWidth > width) then
                table.insert(lines, line);
                line = { words = {}; width = 0; };
            end
            if (#line.words > 0) then line.width = line.width + space; end
            table.insert(line.words, { text = word; width = wordWidth; });
            line.width = line.width + wordWidth;
        end
        line.last = true;
        table.insert(lines, line);
    end
    return lines, space;
end

local function TextArea(width)
    return width - 2 * NOTE_PAD - 5;
end

function Grommey.UI.NoteHeight(width, text)
    local _, size = NoteFont();
    local lines = Wrap(text, TextArea(width), size);
    return #lines * (size + 1) + (#lines - 1) * NOTE_SPACING + 2 * NOTE_PAD + 2;
end

function Grommey.UI.Note(parent, x, y, width, text)
    local font, size = NoteFont();
    local lines, space = Wrap(text, TextArea(width), size);
    local lineHeight = size + 1;
    local height = #lines * lineHeight + (#lines - 1) * NOTE_SPACING + 2 * NOTE_PAD + 2;
    local box = Grommey.UI.Frame(parent, x, y, width, height, "panel", "border");
    box.inner:SetMouseVisible(false);
    box:SetMouseVisible(false);

    local mark = Turbine.UI.Control();
    mark:SetParent(box.inner);
    mark:SetPosition(0, 0);
    mark:SetSize(3, height - 2);
    mark:SetMouseVisible(false);

    -- One label per word, placed by hand
    local labels = {};
    local area = TextArea(width);
    for index, line in ipairs(lines) do
        local gap = space;
        if (not line.last and #line.words > 1) then
            local wordsWidth = line.width - space * (#line.words - 1);
            gap = (area - wordsWidth) / (#line.words - 1);
        end
        local left = NOTE_PAD + 3;
        local top = NOTE_PAD - 1 + (index - 1) * (lineHeight + NOTE_SPACING);
        for _, word in ipairs(line.words) do
            local label = Turbine.UI.Label();
            label:SetParent(box.inner);
            label:SetPosition(math.floor(left + 0.5), top);
            -- A little wider than measured, so a letter is never cut
            label:SetSize(math.ceil(word.width) + 4, lineHeight + 2);
            label:SetFont(font);
            label:SetMultiline(false);
            label:SetTextAlignment(Align.MiddleLeft);
            label:SetMouseVisible(false);
            label:SetText(word.text);
            table.insert(labels, label);
            left = left + word.width + gap;
        end
    end

    -- A light tint of the theme colour, on the box and on the text, so it stands out from the page
    Theme.Track(function()
        mark:SetBackColor(Theme.Color("accent"));
        box.inner:SetBackColor(Theme.Mix("panel", "accent", 0.1));
        box:SetBackColor(Theme.Mix("border", "accent", 0.35));
        local color = Theme.Mix("text", "accent", 0.25);
        for _, label in ipairs(labels) do label:SetForeColor(color); end
    end);
    return box;
end

-- Area that scrolls when its content is taller than it: put the children in area.content (width
-- area.contentWidth, room left for the scroll bar), then call area.Fit(height of the content)
function Grommey.UI.ScrollArea(parent, x, y, width, height)
    local area = Turbine.UI.Control();
    area:SetParent(parent);
    area:SetPosition(x, y);
    area:SetSize(width, height);
    area.contentWidth = width - 16;

    local list = Turbine.UI.ListBox();
    list:SetParent(area);
    list:SetSize(area.contentWidth, height);
    local scrollBar = Turbine.UI.Lotro.ScrollBar();
    scrollBar:SetOrientation(Turbine.UI.Orientation.Vertical);
    scrollBar:SetParent(area);
    scrollBar:SetPosition(width - 10, 0);
    scrollBar:SetSize(10, height);
    scrollBar:SetVisible(false);
    list:SetVerticalScrollBar(scrollBar);

    area.content = Turbine.UI.Control();
    area.content:SetSize(area.contentWidth, height);
    area.Fit = function(contentHeight)
        area.content:SetSize(area.contentWidth, math.max(1, contentHeight));
        -- The list takes the new size into account when the content is put back in
        list:ClearItems();
        list:AddItem(area.content);
        scrollBar:SetVisible(contentHeight > height);
    end
    area.Fit(height);
    return area;
end

function Grommey.UI.Separator(parent, x, y, width)
    local line = Turbine.UI.Control();
    line:SetParent(parent);
    line:SetPosition(x, y);
    line:SetSize(width, 1);
    line:SetMouseVisible(false);
    Theme.Track(function() line:SetBackColor(Theme.Color("border")); end);
    return line;
end

-- Flat button. style "accent" fills it with the accent colour, "danger" uses red text.
function Grommey.UI.Button(parent, x, y, width, text, onClick, style)
    local button = Grommey.UI.Frame(parent, x, y, width, 26, "raised", "border");
    button.inner:SetMouseVisible(false);

    local label = Turbine.UI.Label();
    label:SetParent(button.inner);
    label:SetSize(width - 2, 24);
    label:SetTextAlignment(Align.MiddleCenter);
    label:SetMouseVisible(false);
    label:SetText(text);
    button.label = label;

    local hovered = false;
    local function Paint()
        label:SetFont(Theme.Font(14, false));
        if (style == "accent") then
            button:SetBackColor(Theme.Color("accent"));
            button.inner:SetBackColor(Theme.Mix("raised", "accent", hovered and 0.85 or 0.65));
            label:SetForeColor(Theme.Color("text"));
        else
            button:SetBackColor(Theme.Color(hovered and "accent" or "border"));
            button.inner:SetBackColor(Theme.Color("raised"));
            if (style == "danger") then
                label:SetForeColor(Theme.Color("danger"));
            else
                label:SetForeColor(Theme.Color(hovered and "accent" or "text"));
            end
        end
    end
    button.Paint = Paint;
    Theme.Track(Paint);

    button.MouseEnter = function() hovered = true; Paint(); end
    button.MouseLeave = function() hovered = false; Paint(); end
    button.MouseClick = function(sender, args)
        if (button:IsEnabled() and onClick) then onClick(); end
    end

    button.SetText = function(_, newText) label:SetText(newText); end
    return button;
end

-- On/off switch with its text on the right
function Grommey.UI.Toggle(parent, x, y, width, text, value, onChange)
    local toggle = Turbine.UI.Control();
    toggle:SetParent(parent);
    toggle:SetPosition(x, y);
    toggle:SetSize(width, 22);
    toggle.value = (value == true);

    local track = Turbine.UI.Control();
    track:SetParent(toggle);
    track:SetPosition(0, 4);
    track:SetSize(32, 14);
    track:SetMouseVisible(false);

    local knob = Turbine.UI.Control();
    knob:SetParent(track);
    knob:SetSize(10, 10);
    knob:SetMouseVisible(false);

    local label = Grommey.UI.Label(toggle, 42, 0, width - 42, 22, text);

    local function Paint()
        if (toggle.value) then
            track:SetBackColor(Theme.Color("accent"));
            knob:SetBackColor(Theme.Color("text"));
            knob:SetPosition(20, 2);
        else
            track:SetBackColor(Theme.Color("border"));
            knob:SetBackColor(Theme.Color("dim"));
            knob:SetPosition(2, 2);
        end
    end
    Theme.Track(Paint);

    toggle.MouseClick = function()
        toggle.value = not toggle.value;
        Paint();
        if (onChange) then onChange(toggle.value); end
    end
    toggle.SetValue = function(_, newValue) toggle.value = (newValue == true); Paint(); end
    toggle.GetValue = function() return toggle.value; end
    toggle.label = label;
    return toggle;
end

-- Horizontal slider with its title on the left and the value on the right
function Grommey.UI.Slider(parent, x, y, width, text, minValue, maxValue, step, value, onChange, suffix)
    local slider = Turbine.UI.Control();
    slider:SetParent(parent);
    slider:SetPosition(x, y);
    slider:SetSize(width, 40);
    slider.value = value;
    suffix = suffix or "";

    Grommey.UI.Label(slider, 0, 0, width - 60, 18, text);
    local valueLabel = Grommey.UI.Label(slider, width - 60, 0, 60, 18, "", { align = Align.MiddleRight; role = "accent"; });

    -- The hit area is taller than the track so it is easy to grab
    local hitArea = Turbine.UI.Control();
    hitArea:SetParent(slider);
    hitArea:SetPosition(0, 20);
    hitArea:SetSize(width, 18);

    local track = Turbine.UI.Control();
    track:SetParent(hitArea);
    track:SetPosition(0, 7);
    track:SetSize(width, 4);
    track:SetMouseVisible(false);

    local fill = Turbine.UI.Control();
    fill:SetParent(track);
    fill:SetPosition(0, 0);
    fill:SetMouseVisible(false);

    local thumb = Turbine.UI.Control();
    thumb:SetParent(hitArea);
    thumb:SetSize(8, 16);
    thumb:SetMouseVisible(false);

    local function Paint()
        local ratio = (slider.value - minValue) / (maxValue - minValue);
        local position = math.floor(ratio * (width - 8));
        fill:SetSize(position + 4, 4);
        thumb:SetPosition(position, 1);
        valueLabel:SetText(tostring(slider.value) .. suffix);
        track:SetBackColor(Theme.Color("border"));
        fill:SetBackColor(Theme.Color("accent"));
        thumb:SetBackColor(Theme.Color("text"));
    end
    Theme.Track(Paint);

    local function SetFromX(mouseX)
        local ratio = Grommey.Clamp((mouseX - 4) / (width - 8), 0, 1);
        local newValue = minValue + math.floor(ratio * (maxValue - minValue) / step + 0.5) * step;
        newValue = Grommey.Clamp(newValue, minValue, maxValue);
        if (newValue ~= slider.value) then
            slider.value = newValue;
            Paint();
            if (onChange) then onChange(newValue); end
        end
    end

    hitArea.MouseDown = function(sender, args) slider.dragging = true; SetFromX(args.X); end
    hitArea.MouseMove = function(sender, args) if (slider.dragging) then SetFromX(args.X); end end
    hitArea.MouseUp = function() slider.dragging = false; end

    slider.SetValue = function(_, newValue) slider.value = newValue; Paint(); end
    return slider;
end

-- One line text input in a bordered box
function Grommey.UI.TextInput(parent, x, y, width, text)
    local frame = Grommey.UI.Frame(parent, x, y, width, 26, "field", "border");
    local box = Turbine.UI.TextBox();
    box:SetParent(frame.inner);
    box:SetPosition(6, 3);
    box:SetSize(width - 14, 20);
    box:SetMultiline(false);
    box:SetText(text or "");
    Theme.Track(function()
        box:SetFont(Theme.Font(14, false));
        box:SetForeColor(Theme.Color("text"));
        box:SetBackColor(Theme.Color("field"));
    end);
    box.FocusGained = function() frame.borderRole = "accent"; frame.Paint(); end
    box.FocusLost = function() frame.borderRole = "border"; frame.Paint(); end
    box.frame = frame;
    return box;
end

-- Shared popup used by the drop downs, only one is open at a time
local popup = nil;

function Grommey.UI.ClosePopup()
    if (popup ~= nil) then popup:SetVisible(false); popup.owner = nil; end
end

local function GetPopup()
    if (popup ~= nil) then return popup; end
    popup = Turbine.UI.Window();
    popup:SetVisible(false);
    popup:SetZOrder(2000);
    popup.frame = Grommey.UI.Frame(popup, 0, 0, 10, 10, "raised", "accent");
    popup.list = Turbine.UI.ListBox();
    popup.list:SetParent(popup.frame.inner);
    popup.list:SetPosition(0, 0);
    popup.Deactivated = function() Grommey.UI.ClosePopup(); end
    return popup;
end

-- Opens the shared popup as a list at a screen position, a second click from the same owner closes it.
-- items = { { value = ..., text = "..." }, ... }, onPick(value) when one is chosen
function Grommey.UI.OpenMenu(owner, screenX, screenY, width, items, currentValue, onPick)
    local menu = GetPopup();
    if (menu:IsVisible() and menu.owner == owner) then Grommey.UI.ClosePopup(); return; end

    menu.owner = owner;
    menu.list:ClearItems();
    local rowHeight = 24;
    local visibleRows = math.min(#items, 12);
    for _, item in ipairs(items) do
        local row = Turbine.UI.Label();
        row:SetSize(width - 2, rowHeight);
        row:SetTextAlignment(Align.MiddleLeft);
        row:SetFont(Theme.Font(14, false));
        row:SetText("  " .. item.text);
        local selected = (item.value == currentValue);
        row:SetForeColor(Theme.Color(selected and "accent" or (item.role or "text")));
        row:SetBackColor(Theme.Color("raised"));
        row.MouseEnter = function() row:SetBackColor(Theme.Color("accentSoft")); end
        row.MouseLeave = function() row:SetBackColor(Theme.Color("raised")); end
        row.MouseClick = function()
            Grommey.UI.ClosePopup();
            if (onPick) then onPick(item.value); end
        end
        menu.list:AddItem(row);
    end

    local height = visibleRows * rowHeight + 2;
    menu:SetSize(width, height);
    menu.frame.Resize(width, height);
    menu.list:SetSize(width - 2, height - 2);
    -- Kept on the screen
    local screenWidth, screenHeight = Turbine.UI.Display.GetWidth(), Turbine.UI.Display.GetHeight();
    if (screenY + height > screenHeight) then screenY = math.max(0, screenY - height - 30); end
    menu:SetPosition(math.min(screenX, screenWidth - width), screenY);
    menu:SetVisible(true);
    menu:Activate();
end

-- items = { { value = ..., text = "..." }, ... }
function Grommey.UI.Dropdown(parent, x, y, width, items, currentValue, onChange)
    local dropdown = Grommey.UI.Frame(parent, x, y, width, 26, "raised", "border");
    dropdown.inner:SetMouseVisible(false);
    dropdown.items = items;
    dropdown.value = currentValue;

    local label = Grommey.UI.Label(dropdown.inner, 8, 0, width - 30, 24, "");
    local arrow = Grommey.UI.Label(dropdown.inner, width - 22, 0, 16, 24, "v", { align = Align.MiddleCenter; role = "accent"; });

    local function TextOf(value)
        for _, item in ipairs(dropdown.items) do
            if (item.value == value) then return item.text; end
        end
        return "";
    end
    label:SetText(TextOf(currentValue));

    dropdown.MouseEnter = function() dropdown.borderRole = "accent"; dropdown.Paint(); end
    dropdown.MouseLeave = function() dropdown.borderRole = "border"; dropdown.Paint(); end

    dropdown.MouseClick = function()
        local screenX, screenY = Grommey.UI.ScreenPosition(dropdown);
        Grommey.UI.OpenMenu(dropdown, screenX, screenY + 27, width, dropdown.items, dropdown.value, function(value)
            dropdown:SetValue(value);
            if (onChange) then onChange(value); end
        end);
    end

    dropdown.SetValue = function(_, value) dropdown.value = value; label:SetText(TextOf(value)); end
    dropdown.SetItems = function(_, newItems, value)
        dropdown.items = newItems;
        dropdown:SetValue(value);
    end
    return dropdown;
end

-- Colour square, selected draws a thicker border in the text colour
function Grommey.UI.Swatch(parent, x, y, size, colour, onClick, isSelected)
    local swatch = Turbine.UI.Control();
    swatch:SetParent(parent);
    swatch:SetPosition(x, y);
    swatch:SetSize(size, size);

    local inner = Turbine.UI.Control();
    inner:SetParent(swatch);
    inner:SetMouseVisible(false);
    inner:SetBackColor(Turbine.UI.Color(colour.r / 255, colour.g / 255, colour.b / 255));

    local hovered = false;
    local function Paint()
        local selected = isSelected and isSelected();
        local borderSize = (selected or hovered) and 2 or 1;
        inner:SetPosition(borderSize, borderSize);
        inner:SetSize(size - 2 * borderSize, size - 2 * borderSize);
        swatch:SetBackColor(Theme.Color((selected or hovered) and "text" or "border"));
    end
    Theme.Track(Paint);

    swatch.MouseEnter = function() hovered = true; Paint(); end
    swatch.MouseLeave = function() hovered = false; Paint(); end
    swatch.MouseClick = function() if (onClick) then onClick(); end end
    swatch.Paint = Paint;
    return swatch;
end

-- Profile sharing: the active profile as a text code to copy, and a code pasted back as a new profile.
--
-- Code: "GrommeyUI1|<checksum>|<data>", cut in lines of LINE_LENGTH characters. Data, read by hand
-- (a pasted code is never run as Lua):
--   s<length>:<text>   text, its length in bytes first so it needs no escaping
--   i<integer>;        whole number
--   f<integer>;        decimal number times 1000 (French and German clients write decimals with a comma)
--   T / F              true / false
--   { key value ... }  table
-- Line breaks are never part of the data, they are removed before reading.

Grommey.ProfileShare = {};

local PREFIX = "GrommeyUI1";
local LINE_LENGTH = 64;
local UI = Grommey.UI;

------------------------------------------------------------------------------------------------------------------------------------------
-- Code

local function Encode(value, out)
    local valueType = type(value);
    if (valueType == "string") then
        -- Texts of a profile have no line break, the code relies on it
        value = string.gsub(value, "[\r\n]", " ");
        table.insert(out, "s" .. string.len(value) .. ":" .. value);
    elseif (valueType == "number") then
        if (value == math.floor(value) and math.abs(value) < 2147483647) then
            table.insert(out, "i" .. string.format("%d", value) .. ";");
        else
            table.insert(out, "f" .. string.format("%d", math.floor(value * 1000 + 0.5)) .. ";");
        end
    elseif (valueType == "boolean") then
        table.insert(out, value and "T" or "F");
    elseif (valueType == "table") then
        table.insert(out, "{");
        for key, item in pairs(value) do
            local keyType, itemType = type(key), type(item);
            -- Functions and game objects are never part of the settings
            if ((keyType == "string" or keyType == "number") and (itemType == "string" or itemType == "number" or itemType == "boolean" or itemType == "table")) then
                Encode(key, out);
                Encode(item, out);
            end
        end
        table.insert(out, "}");
    end
end

local function Checksum(text)
    local sum = 0;
    for index = 1, string.len(text) do sum = (sum * 31 + string.byte(text, index)) % 65521; end
    return sum;
end

-- Reads one value at position, returns the value and the next position, or nil when the data is broken
local function Decode(data, position, depth)
    if (depth > 30) then return nil; end
    local mark = string.sub(data, position, position);
    if (mark == "s") then
        local _, last, length = string.find(data, "^(%d+):", position + 1);
        if (length == nil) then return nil; end
        length = tonumber(length);
        local text = string.sub(data, last + 1, last + length);
        if (string.len(text) ~= length) then return nil; end
        return text, last + length + 1;
    elseif (mark == "i" or mark == "f") then
        local _, last, number = string.find(data, "^(%-?%d+);", position + 1);
        if (number == nil) then return nil; end
        number = tonumber(number);
        if (mark == "f") then number = number / 1000; end
        return number, last + 1;
    elseif (mark == "T" or mark == "F") then
        return mark == "T", position + 1;
    elseif (mark == "{") then
        local result = {};
        position = position + 1;
        while (string.sub(data, position, position) ~= "}") do
            if (position > string.len(data)) then return nil; end
            local key, item;
            key, position = Decode(data, position, depth + 1);
            if (key == nil or type(key) == "table" or type(key) == "boolean") then return nil; end
            item, position = Decode(data, position, depth + 1);
            if (item == nil) then return nil; end
            result[key] = item;
        end
        return result, position + 1;
    end
    return nil;
end

-- Text code of a profile table
function Grommey.ProfileShare.Export(profile)
    local out = {};
    Encode(profile, out);
    local data = table.concat(out);
    local code = PREFIX .. "|" .. Checksum(data) .. "|" .. data;
    local lines = {};
    for start = 1, string.len(code), LINE_LENGTH do table.insert(lines, string.sub(code, start, start + LINE_LENGTH - 1)); end
    return table.concat(lines, "\n");
end

-- Profile table of a code, or nil and the reason
function Grommey.ProfileShare.Import(code)
    code = string.gsub(code or "", "[\r\n]", "");
    code = string.gsub(code, "^%s+", "");
    code = string.gsub(code, "%s+$", "");
    local prefix, checksum, data = string.match(code, "^([^|]+)|(%d+)|(.*)$");
    if (prefix ~= PREFIX) then return nil, L("This is not a GrommeyUI profile code."); end
    if (tonumber(checksum) ~= Checksum(data)) then return nil, L("The code is incomplete or changed, copy it again in full."); end
    local profile, position = Decode(data, 1, 0);
    if (type(profile) ~= "table" or position ~= string.len(data) + 1 or type(profile.theme) ~= "table") then
        return nil, L("The code could not be read.");
    end
    return profile;
end

------------------------------------------------------------------------------------------------------------------------------------------
-- Window

local WIDTH = 620;
local HEIGHT = 470;
local PAD = 20;
local window = nil;
local holder = nil;
local mode = "export";

-- The game styled text box: unlike the plain one, its text can be selected and copied
local function CodeBox(parent, x, y, width, height, text)
    local frame = UI.Frame(parent, x, y, width, height, "field", "border");
    local box = Turbine.UI.Lotro.TextBox();
    box:SetParent(frame.inner);
    box:SetPosition(6, 4);
    box:SetSize(width - 14, height - 10);
    box:SetMultiline(true);
    box:SetFont(Grommey.Theme.Font(12, false));
    box:SetForeColor(Grommey.Theme.Color("text"));
    box:SetBackColor(Grommey.Theme.Color("field"));
    box:SetText(text or "");
    return box;
end

-- Selects the whole text so Ctrl+C copies it
local function SelectAll(box)
    box:Focus();
    pcall(box.SelectAll, box);
end

-- The code is also written to a file of the account, to copy it from a text editor
local EXPORT_FILE = "GrommeyUI_ProfileExport";
local function SaveExportFile(code)
    local ok = pcall(Turbine.PluginData.Save, Turbine.DataScope.Account, EXPORT_FILE, { code = string.gsub(code, "\n", ""); });
    return ok;
end

local function Build()
    if (holder) then holder:SetParent(nil); end
    local contentWidth, contentHeight = window.content:GetSize();
    holder = Turbine.UI.Control();
    holder:SetParent(window.content);
    holder:SetPosition(PAD, 14);
    holder:SetSize(contentWidth - 2 * PAD, contentHeight - 20);
    local width = contentWidth - 2 * PAD;

    UI.Button(holder, 0, 0, 160, L("Export"), function() mode = "export"; Build(); end, (mode == "export") and "accent" or nil);
    UI.Button(holder, 168, 0, 160, L("Import"), function() mode = "import"; Build(); end, (mode == "import") and "accent" or nil);

    if (mode == "export") then
        local note = UI.Note(holder, 0, 36, width, string.format(L("Code of the profile \"%s\". Select it, copy it with Ctrl+C and share it."), Grommey.ProfileName));
        local code = Grommey.ProfileShare.Export(Grommey.Profile);
        local boxTop = 36 + note:GetHeight() + 6;
        local box = CodeBox(holder, 0, boxTop, width, 330 - boxTop, code);
        -- Clicking in the code selects all of it
        box.FocusGained = function() pcall(box.SelectAll, box); end
        UI.Button(holder, 0, 342, 200, L("Select all"), function() SelectAll(box); end, "accent");
        if (SaveExportFile(code)) then
            UI.Label(holder, 0, 378, width, 36, L("Also saved in: PluginData > (account) > AllServers > GrommeyUI_ProfileExport.plugindata"),
                { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
        end
        return;
    end

    local note = UI.Note(holder, 0, 36, width, L("Paste a profile code with Ctrl+V. It becomes a new profile, your current ones stay as they are."));
    local boxTop = 36 + note:GetHeight() + 6;
    local box = CodeBox(holder, 0, boxTop, width, 300 - boxTop, "");
    UI.Label(holder, 0, 312, 200, 18, L("Name of the new profile"));
    local nameBox = UI.TextInput(holder, 0, 332, 240, L("Imported"));
    local status = UI.Label(holder, 0, 368, width, 22, "", { size = 12; role = "danger"; });
    UI.Button(holder, 252, 332, 200, L("Import"), function()
        local profile, reason = Grommey.ProfileShare.Import(box:GetText());
        if (profile == nil) then status:SetText(reason); return; end
        local name = string.match(nameBox:GetText() or "", "^%s*(.-)%s*$");
        if (name == "") then name = L("Imported"); end
        -- A free name: "Imported", "Imported 2"...
        local base, number = name, 2;
        while (Grommey.Profiles.Exists(name)) do name = base .. " " .. number; number = number + 1; end
        Grommey.Profiles.Import(name, profile);
        window:SetVisible(false);
        -- Every module takes the new settings cleanly after a reload
        Grommey.Reload();
    end, "accent");
end

function Grommey.ProfileShare.Show(startMode)
    if (window == nil) then
        window = Grommey.Window(nil, "GrommeyUI  ·  " .. L("Share a profile"), WIDTH, HEIGHT);
        window:SetPosition(math.floor((Turbine.UI.Display.GetWidth() - WIDTH) / 2), math.floor((Turbine.UI.Display.GetHeight() - HEIGHT) / 2));
        window:SetZOrder(10);
        Grommey.On("HudToggled", function(hidden) if (hidden) then window:SetVisible(false); end end);
    end
    mode = startMode or "export";
    Build();
    window:SetVisible(true);
    window:Activate();
end

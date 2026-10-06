-- What's new: the changes of each version, shown once after an update.
-- Add the new version at the top of Grommey.Changelog, its texts in English with L() and their
-- translations in Locales/*.lua.

Grommey.Changelog = {
    { version = "1.1.1"; items = {
        L("Fixes an \"invalid key to 'next'\" error that could show up after using an item of the bag.");
    }; };
    { version = "1.1.0"; items = {
        L("New module: Combat meter, to replace Combat Analysis. Damage done and taken, enemies, healing and power of your character, fight by fight.");
        L("Key figures at the top (DPS, critical hits, avoided attacks...), bars by skill, target, attacker or healer, and a summary whose lines you choose.");
        L("Click a bar for the detail window: hits, critical and devastating hits, average, biggest, every kind of avoidance and damage type.");
        L("Fights are kept between reloads. A preview shows a made up fight to set the window up without fighting.");
        L("The meter reads the combat log of the English, French and German clients.");
    }; };
    { version = "1.0.1"; items = {
        L("GrommeyUI can now be recognised and updated by LOTRO Plugin Compendium.");
    }; };
    { version = "1.0.0"; items = {
        L("First stable version of GrommeyUI.");
        L("Bags: one window sorted by category, your own categories, search, money and currencies at the bottom.");
        L("Unit frames: player, target, target of target and party, click a frame to target.");
        L("Info bar: money, currencies, bags, durability, FPS, time, session and character.");
        L("Auras: buffs and debuffs next to the minimap, with important and hidden effects.");
        L("Action bars: extra bars, and a consumables bar that fills itself from your backpack.");
        L("Themes, fonts and text size, profiles to export and import.");
        L("A setup assistant, in English, French and German.");
        L("This window shows what is new after each update. Open it again from the General page of the options.");
    }; };
};

Grommey.WhatsNew = {};

local WIDTH = 580;
local HEIGHT = 470;
local PAD = 20;
local UI = Grommey.UI;
local window = nil;

-- "1.10.2" -> 1, 10, 2 so versions compare as numbers
local function Parts(version)
    local major, minor, patch = string.match(version or "", "^(%d+)%.(%d+)%.?(%d*)");
    return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0;
end

local function IsNewer(version, than)
    if (than == nil) then return true; end
    local a1, a2, a3 = Parts(version);
    local b1, b2, b3 = Parts(than);
    if (a1 ~= b1) then return a1 > b1; end
    if (a2 ~= b2) then return a2 > b2; end
    return a3 > b3;
end

-- Versions to show: the ones newer than "since", or all of them
local function Entries(since)
    local list = {};
    for _, entry in ipairs(Grommey.Changelog) do
        if (since == nil or IsNewer(entry.version, since)) then table.insert(list, entry); end
    end
    return list;
end

local function Create()
    window = Grommey.Window(nil, "GrommeyUI  ·  " .. L("What's new"), WIDTH, HEIGHT);
    window:SetPosition(math.floor((Turbine.UI.Display.GetWidth() - WIDTH) / 2), math.floor((Turbine.UI.Display.GetHeight() - HEIGHT) / 2));
    window:SetZOrder(10);
    local contentWidth, contentHeight = window.content:GetSize();

    -- Lines of text in a list box, which scrolls when the changes are long
    window.list = Turbine.UI.ListBox();
    window.list:SetParent(window.content);
    window.list:SetPosition(PAD, 14);
    window.list:SetSize(contentWidth - 2 * PAD - 14, contentHeight - 14 - 60);
    window.scrollBar = Turbine.UI.Lotro.ScrollBar();
    window.scrollBar:SetOrientation(Turbine.UI.Orientation.Vertical);
    window.scrollBar:SetParent(window.content);
    window.scrollBar:SetPosition(contentWidth - PAD - 10, 14);
    window.scrollBar:SetSize(10, contentHeight - 14 - 60);
    window.list:SetVerticalScrollBar(window.scrollBar);

    UI.Separator(window.content, 0, contentHeight - 56, contentWidth);
    UI.Button(window.content, contentWidth - PAD - 160, contentHeight - 42, 160, L("Close"), function() window:SetVisible(false); end, "accent");
    Grommey.On("HudToggled", function(hidden) if (hidden) then window:SetVisible(false); end end);
end

local function Fill(entries)
    window.list:ClearItems();
    local width = window.list:GetWidth();
    local function Add(height, text, options)
        local line = Turbine.UI.Control();
        line:SetSize(width, height);
        UI.Label(line, 0, 0, width, height, text, options);
        window.list:AddItem(line);
    end
    for index, entry in ipairs(entries) do
        if (index > 1) then Add(14, ""); end
        Add(30, string.format(L("Version %s"), entry.version), { size = 16; bold = true; role = "accent"; });
        for _, text in ipairs(entry.items) do
            -- Height from the length of the text, the label wraps it
            local lines = math.max(1, math.ceil(string.len(text) * 7 / (width - 24)));
            Add(lines * 18 + 6, "-  " .. text, { multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
        end
    end
end

-- Shows the changes since "since" (all of them when nil)
function Grommey.WhatsNew.Show(since)
    if (window == nil) then Create(); end
    local entries = Entries(since);
    if (#entries == 0) then entries = Entries(nil); end
    Fill(entries);
    window:SetVisible(true);
    window:Activate();
end

-- At load: once per new version, never on a first install (the setup assistant comes instead)
function Grommey.WhatsNew.CheckOnLoad()
    local current = plugin:GetVersion();
    local seen = Grommey.Profiles.GetSeenVersion();
    Grommey.Profiles.SetSeenVersion(current);
    if (not Grommey.Profiles.IsSetupDone()) then return; end
    if (seen ~= nil and not IsNewer(current, seen)) then return; end
    if (#Entries(seen) == 0) then return; end
    Grommey.Delay("WhatsNew", 2, function() Grommey.WhatsNew.Show(seen); end);
end

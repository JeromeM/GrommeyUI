-- Profiles hold every setting of the interface. They are shared by all characters of the account,
-- and each character remembers which profile it uses.
-- Grommey.Profile is the active profile table, modules keep their settings in Grommey.Profile.modules[id].

Grommey.Profiles = {};

local DEFAULT_NAME = "Default";
local ACCOUNT_FILE = "GrommeyUI_Profiles";
local CHARACTER_FILE = "GrommeyUI_Character";

-- Settings of a brand new profile. Colours are 0-255 and opacity a percentage so only whole numbers are saved.
Grommey.Defaults = {
    theme = {
        accent = { r = 12; g = 210; b = 159; };
        background = "Charcoal";
        opacity = 100;
        font = "Verdana";
    };
    movers = {
        snap = true;
        grid = 8;
        showGrid = true;
    };
    launcher = {
        shown = true;
    };
    -- frame id = { x = left, y = top }
    positions = {};
    -- module id = { enabled = true/false, ...module settings }
    modules = {};
};

local accountData = nil;

local function NewProfile()
    return Grommey.DeepCopy(Grommey.Defaults);
end

function Grommey.Profiles.Load()
    accountData = Grommey.Storage.Load(Turbine.DataScope.Account, ACCOUNT_FILE) or {};
    accountData.profiles = accountData.profiles or {};
    if (accountData.profiles[DEFAULT_NAME] == nil) then
        accountData.profiles[DEFAULT_NAME] = NewProfile();
    end

    local characterData = Grommey.Storage.Load(Turbine.DataScope.Character, CHARACTER_FILE) or {};
    local name = characterData.profile;
    if (name == nil or accountData.profiles[name] == nil) then name = DEFAULT_NAME; end

    Grommey.ProfileName = name;
    Grommey.Profile = Grommey.MergeDefaults(accountData.profiles[name], Grommey.Defaults);

    -- 0.1.0 started see-through, move existing profiles to opaque once
    if (Grommey.Profile.opaqueByDefault == nil) then
        Grommey.Profile.opaqueByDefault = true;
        if (Grommey.Profile.theme.opacity == 92) then Grommey.Profile.theme.opacity = 100; end
    end
end

function Grommey.Profiles.Save()
    if (accountData == nil) then return; end
    Grommey.Storage.Save(Turbine.DataScope.Account, ACCOUNT_FILE, accountData);
    Grommey.Storage.Save(Turbine.DataScope.Character, CHARACTER_FILE, { profile = Grommey.ProfileName; });
end

-- Saves a moment after the last change, so dragging a slider does not write the file at every step
function Grommey.Profiles.RequestSave()
    Grommey.Delay("SaveProfiles", 2, Grommey.Profiles.Save);
end

function Grommey.Profiles.List()
    local names = {};
    for name, _ in pairs(accountData.profiles) do table.insert(names, name); end
    table.sort(names, function(a, b)
        -- Default always first, then alphabetical
        if (a == DEFAULT_NAME) then return true; end
        if (b == DEFAULT_NAME) then return false; end
        return string.lower(a) < string.lower(b);
    end);
    return names;
end

function Grommey.Profiles.Exists(name)
    return accountData.profiles[name] ~= nil;
end

function Grommey.Profiles.IsDefault(name)
    return name == DEFAULT_NAME;
end

-- Makes the given profile the active one for this character and tells everyone about it
function Grommey.Profiles.Use(name)
    if (accountData.profiles[name] == nil) then return false; end
    Grommey.ProfileName = name;
    Grommey.Profile = Grommey.MergeDefaults(accountData.profiles[name], Grommey.Defaults);
    Grommey.Modules.ApplyDefaults();
    Grommey.Profiles.RequestSave();
    Grommey.Fire("ProfileChanged", name);
    return true;
end

-- New profile, copied from the active one, and switched to
function Grommey.Profiles.Create(name)
    if (name == nil or name == "" or accountData.profiles[name] ~= nil) then return false; end
    accountData.profiles[name] = Grommey.DeepCopy(Grommey.Profile);
    return Grommey.Profiles.Use(name);
end

-- Replaces the active profile settings with a copy of another profile
function Grommey.Profiles.CopyFrom(name)
    if (accountData.profiles[name] == nil or name == Grommey.ProfileName) then return false; end
    accountData.profiles[Grommey.ProfileName] = Grommey.DeepCopy(accountData.profiles[name]);
    return Grommey.Profiles.Use(Grommey.ProfileName);
end

function Grommey.Profiles.Reset()
    accountData.profiles[Grommey.ProfileName] = NewProfile();
    return Grommey.Profiles.Use(Grommey.ProfileName);
end

-- Deletes the active profile (never Default) and goes back to Default
function Grommey.Profiles.DeleteCurrent()
    if (Grommey.ProfileName == DEFAULT_NAME) then return false; end
    accountData.profiles[Grommey.ProfileName] = nil;
    return Grommey.Profiles.Use(DEFAULT_NAME);
end

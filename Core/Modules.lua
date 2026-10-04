-- Registry of the GrommeyUI modules.
-- A module registers itself with:
--   Grommey.Modules.Register({
--       id = "UnitFrames";                 -- settings live in Grommey.Profile.modules.UnitFrames
--       name = "Unit frames";              -- shown in the options, translated with L()
--       description = "Player, target...";
--       enabledByDefault = true;
--       defaults = { ... };                -- default settings of the module
--       Enable = function(settings) end;   -- builds its frames
--       Disable = function() end;          -- removes them (also called on unload)
--       BuildOptions = function(page, width) return height end;  -- optional options page
--   });

Grommey.Modules = {};

local modules = {};
local order = {};

function Grommey.Modules.Register(module)
    if (modules[module.id] == nil) then table.insert(order, module.id); end
    modules[module.id] = module;
end

function Grommey.Modules.List()
    local list = {};
    for _, id in ipairs(order) do table.insert(list, modules[id]); end
    return list;
end

function Grommey.Modules.Get(id)
    return modules[id];
end

-- Makes sure the active profile has settings for every module
function Grommey.Modules.ApplyDefaults()
    for _, id in ipairs(order) do
        local module = modules[id];
        local settings = Grommey.Profile.modules[id] or {};
        if (settings.enabled == nil) then settings.enabled = (module.enabledByDefault ~= false); end
        Grommey.MergeDefaults(settings, module.defaults or {});
        Grommey.Profile.modules[id] = settings;
    end
end

function Grommey.Modules.Settings(id)
    return Grommey.Profile.modules[id];
end

function Grommey.Modules.IsEnabled(id)
    local settings = Grommey.Profile.modules[id];
    return settings ~= nil and settings.enabled == true;
end

-- Turning a module on or off takes effect after a reload, so its frames are built cleanly
function Grommey.Modules.SetEnabled(id, enabled)
    Grommey.Profile.modules[id].enabled = enabled;
    Grommey.Profiles.RequestSave();
end

local function Call(module, functionName, ...)
    if (module[functionName] == nil) then return; end
    local ok, message = pcall(module[functionName], ...);
    if (not ok) then Grommey.Print("<rgb=#FF6060>" .. module.id .. "." .. functionName .. ": " .. tostring(message) .. "</rgb>"); end
end

function Grommey.Modules.StartAll()
    Grommey.Modules.ApplyDefaults();
    for _, id in ipairs(order) do
        if (Grommey.Modules.IsEnabled(id)) then
            modules[id].started = true;
            Call(modules[id], "Enable", Grommey.Profile.modules[id]);
        end
    end
end

function Grommey.Modules.StopAll()
    for _, id in ipairs(order) do
        if (modules[id].started) then
            modules[id].started = false;
            Call(modules[id], "Disable");
        end
    end
end

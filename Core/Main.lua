-- GrommeyUI entry point: loads the profile, builds the core windows, starts the modules
-- and registers the /gui command.

import "GrommeyUI.Core";
-- Modules are imported here, after the core. They register themselves with Grommey.Modules.
import "GrommeyUI.Bags";
import "GrommeyUI.UnitFrames";
import "GrommeyUI.InfoBar";

local RELOADER = "~GrommeyUIReloader";

function Grommey.Reload()
    Grommey.Profiles.Save();
    Turbine.PluginManager.LoadPlugin(RELOADER);
end

-- The reloader has done its job once we are running again, unload it on the first frame
local cleanup = Turbine.UI.Control();
cleanup:SetWantsUpdates(true);
cleanup.Update = function()
    cleanup:SetWantsUpdates(false);
    pcall(Turbine.PluginManager.UnloadScriptState, RELOADER);
end

Grommey.Profiles.Load();
Grommey.Modules.ApplyDefaults();
Grommey.Options.Create();
Grommey.Launcher.Create();
Grommey.Modules.StartAll();

-- Chat command: /gui and /grommey
Grommey.Command = Turbine.ShellCommand();

function Grommey.Command:Execute(command, arguments)
    local action = string.lower(string.match(arguments or "", "^%s*(%S*)") or "");
    if (action == "move") then
        Grommey.Movers.Toggle();
    elseif (action == "reload") then
        Grommey.Reload();
    elseif (action == "reset") then
        Grommey.Movers.ResetAll();
    elseif (action == "target") then
        -- What the game tells about the target, to check class and type detection
        local target = Turbine.Gameplay.LocalPlayer.GetInstance():GetTarget();
        if (target == nil) then Grommey.Print("no target"); return; end
        Grommey.Print("name: " .. tostring(target:GetName()));
        Grommey.Print("GetClass: " .. tostring(target.GetClass ~= nil) .. "  GetLevel: " .. tostring(target.GetLevel ~= nil) .. "  GetMorale: " .. tostring(target.GetMorale ~= nil));
        if (target.GetClass ~= nil) then
            local ok, class = pcall(target.GetClass, target);
            Grommey.Print("class value: " .. tostring(class) .. " (" .. tostring(ok) .. ")");
            local names = {};
            for name, value in pairs(Turbine.Gameplay.Class or {}) do
                if (type(value) == "number") then table.insert(names, name .. "=" .. value); end
            end
            table.sort(names);
            Grommey.Print("classes: " .. table.concat(names, ", "));
        end
    elseif (action == "elements") then
        -- Game windows a plugin is allowed to switch off
        local names = {};
        for name, value in pairs(Turbine.UI.Lotro.LotroUIElement or {}) do
            if (type(value) == "number") then table.insert(names, name .. " = " .. value); end
        end
        table.sort(names);
        Grommey.Print(L("Game windows that can be replaced:") .. " " .. #names);
        for _, line in ipairs(names) do Grommey.Print("  " .. line); end
    else
        Grommey.Options.Toggle();
    end
end

function Grommey.Command:GetHelp()
    return "/gui [move | reload | reset | elements]";
end

function Grommey.Command:GetShortHelp()
    return "GrommeyUI";
end

for _, name in ipairs({ "gui", "grommey" }) do
    -- Another plugin may already use the name, keep going with the other one
    pcall(Turbine.Shell.AddCommand, name, Grommey.Command);
end

plugin.Unload = function()
    Grommey.Movers.Exit();
    Grommey.Modules.StopAll();
    Grommey.StopDelays();
    Grommey.Profiles.Save();
    pcall(Turbine.Shell.RemoveCommand, Grommey.Command);
end

plugin.GetOptionsPanel = function()
    local panel = Turbine.UI.Control();
    panel:SetSize(300, 80);
    local button = Turbine.UI.Lotro.Button();
    button:SetParent(panel);
    button:SetPosition(20, 20);
    button:SetSize(220, 20);
    button:SetText(L("Options"));
    button.Click = function() Grommey.Options.Show(); end
    return panel;
end

Grommey.Print(L("GrommeyUI loaded. Type /gui for the options."));

import "Turbine";
import "Turbine.UI";

-- Unloads GrommeyUI on the first frame and loads it again on the next one
local reloader = Turbine.UI.Control();
reloader.unloaded = false;
reloader:SetWantsUpdates(true);
reloader.Update = function()
    if (reloader.unloaded) then
        reloader:SetWantsUpdates(false);
        Turbine.PluginManager.LoadPlugin("GrommeyUI");
    else
        Turbine.PluginManager.UnloadScriptState("GrommeyUI");
        reloader.unloaded = true;
    end
end

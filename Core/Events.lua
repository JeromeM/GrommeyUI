-- Small event bus shared by the core and the modules.
-- Grommey.On("ThemeChanged", fn) registers a listener, Grommey.Fire("ThemeChanged", ...) calls them.

local listeners = {};

function Grommey.On(eventName, callback)
    listeners[eventName] = listeners[eventName] or {};
    table.insert(listeners[eventName], callback);
    return callback;
end

function Grommey.Off(eventName, callback)
    local list = listeners[eventName];
    if (list == nil) then return; end
    for index = #list, 1, -1 do
        if (list[index] == callback) then table.remove(list, index); end
    end
end

function Grommey.Fire(eventName, ...)
    local list = listeners[eventName];
    if (list == nil) then return; end
    for _, callback in ipairs(list) do
        -- One broken listener must not stop the others
        local ok, message = pcall(callback, ...);
        if (not ok) then Grommey.Print("<rgb=#FF6060>" .. eventName .. ": " .. tostring(message) .. "</rgb>"); end
    end
end

function Grommey.Print(text)
    Turbine.Shell.WriteLine("<rgb=#0CD29F>GrommeyUI</rgb> " .. tostring(text));
end

-- Runs a function once, a little later. Repeated calls with the same key only run it once.
local delayed = {};
local delayControl = Turbine.UI.Control();
delayControl.Update = function()
    local now = Turbine.Engine.GetGameTime();
    local pending = false;
    for key, entry in pairs(delayed) do
        if (now >= entry.at) then
            delayed[key] = nil;
            local ok, message = pcall(entry.callback);
            if (not ok) then Grommey.Print("<rgb=#FF6060>" .. tostring(message) .. "</rgb>"); end
        else
            pending = true;
        end
    end
    if (not pending and next(delayed) == nil) then delayControl:SetWantsUpdates(false); end
end

function Grommey.Delay(key, seconds, callback)
    delayed[key] = { at = Turbine.Engine.GetGameTime() + seconds; callback = callback; };
    delayControl:SetWantsUpdates(true);
end

function Grommey.StopDelays()
    delayed = {};
    delayControl:SetWantsUpdates(false);
end

-- Saving and loading of plugin data.
-- French and German clients write decimal numbers with a comma, which breaks the saved files.
-- Every number (key or value) is therefore stored as text with a "#" prefix, and plain texts
-- that start with "#" or "$" get a "$" prefix so they cannot be mistaken for numbers.

Grommey.Storage = {};

local function EncodeValue(value)
    local valueType = type(value);
    if (valueType == "number") then return "#" .. tostring(value); end
    if (valueType == "string") then
        local first = string.sub(value, 1, 1);
        if (first == "#" or first == "$") then return "$" .. value; end
        return value;
    end
    if (valueType == "table") then
        local copy = {};
        for key, item in pairs(value) do
            copy[EncodeValue(key)] = EncodeValue(item);
        end
        return copy;
    end
    -- booleans are safe as they are, functions and controls are never saved
    if (valueType == "boolean") then return value; end
    return nil;
end

local function DecodeValue(value)
    local valueType = type(value);
    if (valueType == "string") then
        local first = string.sub(value, 1, 1);
        if (first == "#") then return tonumber(string.sub(value, 2)); end
        if (first == "$") then return string.sub(value, 2); end
        return value;
    end
    if (valueType == "table") then
        local copy = {};
        for key, item in pairs(value) do
            local decodedKey = DecodeValue(key);
            if (decodedKey ~= nil) then copy[decodedKey] = DecodeValue(item); end
        end
        return copy;
    end
    return value;
end

function Grommey.Storage.Save(scope, name, data)
    local ok, message = pcall(Turbine.PluginData.Save, scope, name, EncodeValue(data));
    if (not ok) then Grommey.Print("<rgb=#FF6060>Save " .. name .. ": " .. tostring(message) .. "</rgb>"); end
end

function Grommey.Storage.Load(scope, name)
    local ok, data = pcall(Turbine.PluginData.Load, scope, name);
    if (not ok or data == nil) then return nil; end
    return DecodeValue(data);
end

-- Table helpers used by the profiles and the modules

function Grommey.DeepCopy(value)
    if (type(value) ~= "table") then return value; end
    local copy = {};
    for key, item in pairs(value) do copy[key] = Grommey.DeepCopy(item); end
    return copy;
end

-- Adds to target every key of defaults it does not have yet, at every depth
function Grommey.MergeDefaults(target, defaults)
    for key, item in pairs(defaults) do
        if (target[key] == nil) then
            target[key] = Grommey.DeepCopy(item);
        elseif (type(target[key]) == "table" and type(item) == "table") then
            Grommey.MergeDefaults(target[key], item);
        end
    end
    return target;
end

function Grommey.Clamp(value, minValue, maxValue)
    if (value < minValue) then return minValue; end
    if (value > maxValue) then return maxValue; end
    return value;
end

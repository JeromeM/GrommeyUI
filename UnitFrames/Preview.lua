-- Preview mode: fake units and effects so the frames can be set up without a target,
-- without a party and without buffs. They answer the same calls as the game objects.

local UF = Grommey.UnitFrames;

UF.Preview = false;

-- Plain colour squares stand in for effect icons: soft colours for buffs, dark red for debuffs
local BUFF_COLORS = {
    Turbine.UI.Color(0.20, 0.55, 0.50),
    Turbine.UI.Color(0.25, 0.42, 0.70),
    Turbine.UI.Color(0.62, 0.52, 0.25),
    Turbine.UI.Color(0.45, 0.33, 0.66),
};
local DEBUFF_COLOR = Turbine.UI.Color(0.55, 0.16, 0.16);

-- The class resource of the real character with a sample state (fervour 3 of 5...), or the
-- champion's for a class without one, so the resource can be set up out of combat
function UF.DummyClassAttributes()
    local player = Turbine.Gameplay.LocalPlayer.GetInstance();
    local ok, attributes = pcall(player.GetClassAttributes, player);
    for _, resource in ipairs(UF.ClassResources or {}) do
        if (ok and attributes ~= nil and attributes[resource.detect] ~= nil) then
            return { isSample = true; [resource.detect] = true; };
        end
    end
    return { isSample = true; GetFervor = true; };
end

local function DummyUnit(name, level, morale, maxMorale, power, maxPower, className)
    return {
        GetClassAttributes = UF.DummyClassAttributes;
        GetClass = function()
            if (className == nil or Turbine.Gameplay.Class == nil) then return nil; end
            return Turbine.Gameplay.Class[className];
        end;
        GetName = function() return name; end;
        GetLevel = function() return level; end;
        GetMorale = function() return morale; end;
        GetMaxMorale = function() return maxMorale; end;
        GetPower = function() return power; end;
        GetMaxPower = function() return maxPower; end;
    };
end

local function DummyEffects(count)
    local now = Turbine.Engine.GetGameTime();
    local effects = {};
    for index = 1, count do
        -- Every third effect is a debuff, durations from 20 seconds to 20 minutes
        local duration = 20 * index * index;
        local start = now;
        effects[index] = {
            GetName = function() return string.format(L("Test effect %d"), index); end;
            GetDescription = function() return L("Fake effect to set up the icons. The real description of the buff or debuff is shown here."); end;
            GetPreviewColor = function()
                if (index % 3 == 0) then return DEBUFF_COLOR; end
                return BUFF_COLORS[(index - 1) % #BUFF_COLORS + 1];
            end;
            GetDuration = function() return duration; end;
            GetStartTime = function() return start; end;
            IsDebuff = function() return index % 3 == 0; end;
        };
    end
    return {
        GetCount = function() return #effects; end;
        Get = function(self, index) return effects[index]; end;
    };
end

-- Stand-in for the target when nothing is selected
UF.DummyTarget = DummyUnit(L("Training dummy"), 150, 312400, 480000, 5200, 8000);

-- Party members when solo, with varied values to see the bars at work
UF.DummyParty = {
    DummyUnit("Aragorn", 150, 98000, 112000, 9000, 11000, "Captain"),
    DummyUnit("Legolas", 150, 54000, 96000, 4000, 10500, "Hunter"),
    DummyUnit("Gimli", 150, 132000, 140000, 2500, 9000, "Guardian"),
    DummyUnit("Samsagace", 148, 22000, 88000, 7600, 8000, "Burglar"),
    DummyUnit("Gandalf", 150, 0, 92000, 0, 12000, "LoreMaster"),
};

-- Unit whose only job is to give fake effects to an effects bar
function UF.DummyEffectsUnit()
    local list = DummyEffects(12);
    return { GetEffects = function() return list; end; };
end

-- Turns preview on or off and refreshes every frame
function UF.SetPreview(enabled)
    if (UF.Preview == enabled) then return; end
    UF.Preview = enabled;
    Grommey.Fire("UnitFramesPreviewChanged", enabled);
end

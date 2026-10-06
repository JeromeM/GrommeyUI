-- Options page of the effect filters, shared by the auras and the timer bars:
-- important effects (shown first), hidden effects, and with withOnly a mode showing only the
-- chosen effects. settings.important / hidden / shown = { effect name = true }, settings.filterMode
-- = "all" or "only". Changed() saves, rebuilds and draws the page again.

local UI = Grommey.UI;

Grommey.Auras = Grommey.Auras or {};

function Grommey.Auras.BuildFilterOptions(page, width, settings, Changed, withOnly)
    local half = math.floor((width - 30) / 2);
    local right = half + 30;
    settings.hidden = settings.hidden or {};
    settings.important = settings.important or {};
    settings.shown = settings.shown or {};
    local onlyMode = withOnly and settings.filterMode == "only";
    -- Second list: the effects never shown, or the only ones shown
    local second = onlyMode and settings.shown or settings.hidden;
    local secondButton = onlyMode and L("Show") or L("Hide");

    local function Toggle(list, name)
        list[name] = (not list[name]) or nil;
        -- An effect is either hidden or important
        if (list[name] and not onlyMode) then
            if (list == settings.hidden) then settings.important[name] = nil; else settings.hidden[name] = nil; end
        end
        Changed();
    end

    local top = 0;
    if (withOnly) then
        UI.Label(page, 0, 0, half, 18, L("Effects shown"));
        UI.Dropdown(page, 0, 20, half, {
            { value = "all"; text = L("All, except the hidden ones"); },
            { value = "only"; text = L("Only the chosen ones"); },
        }, settings.filterMode or "all", function(value) settings.filterMode = value; Changed(); end);
        top = 64;
    end

    -- Effects on the character right now, each can be marked
    UI.Label(page, 0, top, half, 20, L("Your effects right now"), { bold = true; role = "accent"; });
    local names, isDebuff = {}, {};
    local player = Turbine.Gameplay.LocalPlayer.GetInstance();
    local effects = player and player:GetEffects();
    for index = 1, (effects and effects:GetCount()) or 0 do
        local effect = effects:Get(index);
        local name = effect and effect:GetName();
        if (name and not names[name]) then
            names[name] = true;
            isDebuff[name] = effect:IsDebuff() == true;
        end
    end
    local sorted = {};
    for name in pairs(names) do table.insert(sorted, name); end
    table.sort(sorted);
    local y = top + 28;
    if (#sorted == 0) then
        UI.Label(page, 0, y, half, 36, L("No effect on you at the moment."), { size = 12; role = "dim"; multiline = true; align = Turbine.UI.ContentAlignment.TopLeft; });
    end
    local buttonWidth = 76;
    for _, name in ipairs(sorted) do
        UI.Label(page, 0, y, half - 2 * (buttonWidth + 6), 26, name, { size = 12; role = isDebuff[name] and "danger" or "text"; });
        UI.Button(page, half - 2 * buttonWidth - 6, y, buttonWidth, L("Important"), function() Toggle(settings.important, name); end,
            settings.important[name] and "accent" or nil);
        UI.Button(page, half - buttonWidth, y, buttonWidth, secondButton, function() Toggle(second, name); end,
            second[name] and "accent" or nil);
        y = y + 30;
        if (y > page:GetHeight() - 30) then break; end
    end

    -- The two lists, the cross takes a name off
    local function List(listTop, title, list)
        UI.Label(page, right, listTop, half, 20, title, { bold = true; role = "accent"; });
        local entries = {};
        for name in pairs(list) do table.insert(entries, name); end
        table.sort(entries);
        local rowY = listTop + 26;
        if (#entries == 0) then UI.Label(page, right, rowY, half, 20, L("None"), { size = 12; role = "dim"; }); rowY = rowY + 22; end
        for _, name in ipairs(entries) do
            UI.Label(page, right, rowY, half - 26, 22, name, { size = 12; });
            local remove = UI.Label(page, width - 22, rowY, 22, 22, "x", { role = "danger"; mouse = true; align = Turbine.UI.ContentAlignment.MiddleCenter; });
            remove.MouseClick = function() list[name] = nil; Changed(); end
            rowY = rowY + 22;
        end
        return rowY;
    end
    local listY = List(top, L("Important (shown first)"), settings.important);
    listY = List(listY + 12, onlyMode and L("Shown effects (only these)") or L("Hidden effects"), second);

    -- A name typed by hand, for an effect you do not have right now
    listY = listY + 14;
    local nameBox = UI.TextInput(page, right, listY, half, "");
    local addWidth = math.floor((half - 8) / 2);
    local function Add(list)
        local name = string.match(nameBox:GetText() or "", "^%s*(.-)%s*$");
        if (name ~= "" and not list[name]) then Toggle(list, name); end
    end
    UI.Button(page, right, listY + 32, addWidth, L("Important"), function() Add(settings.important); end);
    UI.Button(page, right + addWidth + 8, listY + 32, addWidth, secondButton, function() Add(second); end);
end

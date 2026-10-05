-- Texts are written in English in the code and translated in GrommeyUI/Locales/<language>.lua.
-- L("text") returns the text in the chosen language, or the English text when it has no translation.
-- The game has English, French and German clients; the language follows the client unless one is
-- chosen in the options.

Grommey = Grommey or {};

local translations = {};        -- language code = { english text = translated text }
local LANGUAGE_FILE = "GrommeyUI_Language";

-- Language names stay in their own language
Grommey.Languages = {
    { code = "auto"; name = "Automatic (game language)"; translated = true; };
    { code = "en"; name = "English"; };
    { code = "fr"; name = "Français"; };
    { code = "de"; name = "Deutsch"; };
};

function Grommey.AddTranslations(language, list)
    translations[language] = translations[language] or {};
    for english, translated in pairs(list) do translations[language][english] = translated; end
end

local function GameLanguage()
    local language = Turbine.Engine.GetLanguage();
    if (Turbine.Language ~= nil) then
        if (language == Turbine.Language.French) then return "fr"; end
        if (language == Turbine.Language.German) then return "de"; end
    end
    return "en";
end

-- The choice is read now, before the modules load, since some texts are made while loading.
-- It has a small file of its own for the account: the profiles are not loaded yet.
local ok, saved = pcall(Turbine.PluginData.Load, Turbine.DataScope.Account, LANGUAGE_FILE);
Grommey.LanguageChoice = (ok and type(saved) == "table" and saved.language) or "auto";
-- The combat log is always in the language of the client, whatever the choice
Grommey.GameLanguage = GameLanguage();
Grommey.Language = (Grommey.LanguageChoice == "auto") and Grommey.GameLanguage or Grommey.LanguageChoice;

-- Saved at once, used after the next reload
function Grommey.SetLanguage(choice)
    Grommey.LanguageChoice = choice;
    pcall(Turbine.PluginData.Save, Turbine.DataScope.Account, LANGUAGE_FILE, { language = choice; });
end

-- Items for a drop down of the languages
function Grommey.LanguageItems()
    local items = {};
    for _, language in ipairs(Grommey.Languages) do
        table.insert(items, { value = language.code; text = language.translated and L(language.name) or language.name; });
    end
    return items;
end

function L(text)
    local list = translations[Grommey.Language];
    if (list ~= nil and list[text] ~= nil) then return list[text]; end
    return text;
end

-- Texts are written in English in the code and translated here.
-- L("text") returns the client language version, or the English text without a translation.

Grommey = Grommey or {};

local French = {
    -- General
    ["GrommeyUI loaded. Type /gui for the options."] = "GrommeyUI chargé. Tape /gui pour les options.",
    ["Options"] = "Options",
    ["General"] = "Général",
    ["Theme"] = "Thème",
    ["Profiles"] = "Profils",
    ["Layout"] = "Déplacement",
    ["Modules"] = "Modules",
    ["Close"] = "Fermer",
    ["Reload UI"] = "Recharger l'interface",
    ["Show the GrommeyUI button"] = "Afficher le bouton GrommeyUI",
    ["Left click: options. Right click: move frames."] = "Clic gauche : options. Clic droit : déplacer les fenêtres.",
    ["Chat commands"] = "Commandes du chat",
    ["/gui - open or close the options"] = "/gui - ouvre ou ferme les options",
    ["/gui move - move the frames"] = "/gui move - déplace les fenêtres (ou Ctrl + \\ comme dans le jeu)",
    ["/gui reload - reload the interface"] = "/gui reload - recharge l'interface",
    ["/gui reset - put every frame back in place"] = "/gui reset - remet toutes les fenêtres à leur place",
    ["Welcome to GrommeyUI. Pick a theme, then add modules as they come."] = "Bienvenue dans GrommeyUI. Choisis un thème, puis ajoute les modules au fur et à mesure.",

    -- Theme
    ["Accent colour"] = "Couleur d'accent",
    ["Presets"] = "Préréglages",
    ["Red"] = "Rouge",
    ["Green"] = "Vert",
    ["Blue"] = "Bleu",
    ["Background"] = "Fond",
    ["Background opacity"] = "Opacité du fond",
    ["Font"] = "Police",
    ["Preview"] = "Aperçu",
    ["Button"] = "Bouton",
    ["Option"] = "Option",
    ["Value"] = "Valeur",
    ["Teal"] = "Turquoise",
    ["Gold"] = "Or",
    ["Azure"] = "Azur",
    ["Amethyst"] = "Améthyste",
    ["Ruby"] = "Rubis",
    ["Forest"] = "Forêt",
    ["Charcoal"] = "Anthracite",
    ["Night"] = "Nuit",
    ["Slate"] = "Ardoise",
    ["Modern (Verdana)"] = "Moderne (Verdana)",
    ["Middle-earth (Trajan)"] = "Terre du Milieu (Trajan)",

    -- Profiles
    ["Current profile"] = "Profil actuel",
    ["Each character chooses its profile. Profiles are shared by all your characters."] = "Chaque personnage choisit son profil. Les profils sont partagés entre tous tes personnages.",
    ["New profile"] = "Nouveau profil",
    ["Create (copy of the current one)"] = "Créer (copie de l'actuel)",
    ["Copy settings from"] = "Copier les réglages de",
    ["Copy"] = "Copier",
    ["Reset this profile"] = "Réinitialiser ce profil",
    ["Delete this profile"] = "Supprimer ce profil",
    ["The name is empty or already used."] = "Ce nom est vide ou déjà utilisé.",
    ["Profile created."] = "Profil créé.",
    ["Settings copied."] = "Réglages copiés.",
    ["Profile reset."] = "Profil réinitialisé.",
    ["Profile deleted."] = "Profil supprimé.",
    ["The Default profile cannot be deleted."] = "Le profil Default ne peut pas être supprimé.",
    ["Some modules need a reload to follow the new profile."] = "Certains modules demandent un rechargement pour suivre le nouveau profil.",

    -- Layout
    ["Move frames"] = "Déplacer les fenêtres",
    ["Drag the coloured frames to place them. Right click a frame to put it back in place."] = "Fais glisser les cadres colorés pour les placer. Clic droit sur un cadre pour le remettre à sa place.",
    ["Snap to grid"] = "Aimanter à la grille",
    ["Grid size"] = "Taille de la grille",
    ["Show the grid"] = "Afficher la grille",
    ["Reset all positions"] = "Réinitialiser toutes les positions",
    ["Done"] = "Terminer",
    ["Move mode"] = "Mode déplacement",
    ["GrommeyUI button"] = "Bouton GrommeyUI",
    ["Options window"] = "Fenêtre d'options",

    -- Modules
    ["No module yet. They will show up here: unit frames, bags, buffs..."] = "Aucun module pour l'instant. Ils apparaîtront ici : cadres d'unités, sacs, buffs…",
    ["Changes to modules are applied after a reload."] = "Les changements de modules s'appliquent après un rechargement.",
}

local language = Turbine.Engine.GetLanguage();
Grommey.IsFrench = (Turbine.Language ~= nil and language == Turbine.Language.French);

function L(text)
    if (Grommey.IsFrench and French[text]) then return French[text]; end
    return text;
end

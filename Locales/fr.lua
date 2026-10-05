-- French texts of GrommeyUI. Keys are the English texts of the code, a missing one shows in English.
-- Check with: python3 tools/check_translations.py

Grommey.AddTranslations("fr", {
    -- General
    ["GrommeyUI loaded. Type /gui for the options."] = "GrommeyUI chargé. Tape /gui pour les options.";
    ["Options"] = "Options";
    ["General"] = "Général";
    ["Theme"] = "Thème";
    ["Profiles"] = "Profils";
    ["Layout"] = "Déplacement";
    ["Modules"] = "Modules";
    ["Reload UI"] = "Recharger l'interface";
    ["Show the GrommeyUI button"] = "Afficher le bouton GrommeyUI";
    ["Left click: options. Right click: move frames."] = "Clic gauche : options. Clic droit : déplacer les fenêtres.";
    ["Chat commands"] = "Commandes du chat";
    ["/gui - open or close the options"] = "/gui - ouvre ou ferme les options";
    ["/gui move - move the frames"] = "/gui move - déplace les fenêtres";
    ["/gui reload - reload the interface"] = "/gui reload - recharge l'interface";
    ["Game windows that can be replaced:"] = "Fenêtres du jeu remplaçables :";
    ["/gui reset - put every frame back in place"] = "/gui reset - remet toutes les fenêtres à leur place";
    ["Welcome to GrommeyUI. Pick a theme, then add modules as they come."] = "Bienvenue dans GrommeyUI. Choisis un thème, puis ajoute les modules au fur et à mesure.";
    ["Accent colour"] = "Couleur du thème";
    ["Red"] = "Rouge";
    ["Green"] = "Vert";
    ["Blue"] = "Bleu";
    ["Background"] = "Fond";
    ["Background opacity"] = "Opacité du fond";
    ["Font"] = "Police";
    ["Preview"] = "Aperçu";
    ["Button"] = "Bouton";
    ["Option"] = "Option";
    ["Value"] = "Valeur";
    ["Teal"] = "Turquoise";
    ["Gold"] = "Or";
    ["Azure"] = "Azur";
    ["Amethyst"] = "Améthyste";
    ["Ruby"] = "Rubis";
    ["Forest"] = "Forêt";
    ["Charcoal"] = "Anthracite";
    ["Night"] = "Nuit";
    ["Slate"] = "Ardoise";
    ["Modern (Verdana)"] = "Moderne (Verdana)";
    ["Middle-earth (Trajan)"] = "Terre du Milieu (Trajan)";
    ["Classic (Book Antiqua)"] = "Classique (Book Antiqua)";
    ["Current profile"] = "Profil actuel";
    ["Each character chooses its profile. Profiles are shared by all your characters."] = "Chaque personnage choisit son profil. Les profils sont partagés entre tous tes personnages.";
    ["New profile"] = "Nouveau profil";
    ["Create (copy of the current one)"] = "Créer (copie de l'actuel)";
    ["Copy settings from"] = "Copier les réglages de";
    ["Copy"] = "Copier";
    ["Reset this profile"] = "Réinitialiser ce profil";
    ["Delete this profile"] = "Supprimer ce profil";
    ["The name is empty or already used."] = "Ce nom est vide ou déjà utilisé.";
    ["Profile created."] = "Profil créé.";
    ["Settings copied."] = "Réglages copiés.";
    ["Profile reset."] = "Profil réinitialisé.";
    ["Profile deleted."] = "Profil supprimé.";
    ["The Default profile cannot be deleted."] = "Le profil Default ne peut pas être supprimé.";
    ["Some modules need a reload to follow the new profile."] = "Certains modules demandent un rechargement pour suivre le nouveau profil.";
    ["Move frames"] = "Déplacer les fenêtres";
    ["Drag the coloured frames to place them. Right click a frame to put it back in place."] = "Fais glisser les cadres colorés pour les placer. Clic droit sur un cadre pour le remettre à sa place.";
    ["Snap to grid"] = "Aimanter à la grille";
    ["Grid size"] = "Taille de la grille";
    ["Show the grid"] = "Afficher la grille";
    ["Reset all positions"] = "Réinitialiser toutes les positions";
    ["Done"] = "Terminer";
    ["Move mode"] = "Mode déplacement";
    ["GrommeyUI button"] = "Bouton GrommeyUI";
    ["Options window"] = "Fenêtre d'options";
    ["No module yet. They will show up here: unit frames, bags, buffs..."] = "Aucun module pour l'instant. Ils apparaîtront ici : cadres d'unités, sacs, buffs…";
    ["Changes to modules are applied after a reload."] = "Les changements de modules s'appliquent après un rechargement.";

    -- Setup assistant
    ["Setup"] = "Configuration";
    ["Welcome to GrommeyUI! This assistant sets up the interface in a few steps. Everything can be changed later in the options (/gui)."] = "Bienvenue dans GrommeyUI ! Cet assistant prépare l'interface en quelques étapes. Tout peut être changé ensuite dans les options (/gui).";
    ["Profile"] = "Profil";
    ["A profile holds every setting. Several characters can share one, or each can have its own."] = "Un profil contient tous les réglages. Plusieurs personnages peuvent partager le même, ou chacun avoir le sien.";
    ["Use the profile"] = "Utiliser le profil";
    ["Or create a new one"] = "Ou en créer un nouveau";
    ["Create"] = "Créer";
    ["This character uses: %s"] = "Ce personnage utilise : %s";
    ["Choose the parts of the interface you want. A module that is off leaves the game window it replaces."] = "Choisis les parties de l'interface que tu veux. Un module désactivé laisse la fenêtre du jeu qu'il remplace.";
    ["All set!"] = "C'est prêt !";
    ["Finishing reloads the interface so every choice applies. Then place your frames with the move mode: drag the coloured boxes, right click one to put it back."] = "Terminer recharge l'interface pour appliquer tous les choix. Place ensuite tes fenêtres avec le mode déplacement : fais glisser les cadres colorés, clic droit pour en remettre un à sa place.";
    ["This assistant can be started again from the General page of the options."] = "Cet assistant peut être relancé depuis la page Général des options.";
    ["Finish"] = "Fin";
    ["Back"] = "Précédent";
    ["Next"] = "Suivant";
    ["Skip the assistant"] = "Passer l'assistant";
    ["Step %d of %d"] = "Étape %d sur %d";
    ["Finish and reload"] = "Terminer et recharger";
    ["Start the setup assistant again"] = "Relancer l'assistant de configuration";

    -- Bags: categories
    ["Quest items"] = "Objets de quête";
    ["Consumables"] = "Consommables";
    ["Weapons"] = "Armes";
    ["Armour"] = "Armures";
    ["Jewellery"] = "Bijoux";
    ["Legendary items"] = "Objets légendaires";
    ["Essences"] = "Essences";
    ["Class items"] = "Objets de classe";
    ["Crafting"] = "Artisanat";
    ["Crafting scrolls"] = "Parchemins d'artisanat";
    ["Barter"] = "Troc";
    ["Reputation"] = "Réputation";
    ["Travel"] = "Voyage";
    ["Skirmish"] = "Escarmouche";
    ["Lootboxes"] = "Coffres";
    ["Deconstructable"] = "Déconstructibles";
    ["Trophies"] = "Trophées";
    ["Cosmetics"] = "Cosmétiques";
    ["Decorations"] = "Décorations";
    ["Instruments"] = "Instruments";
    ["Fishing"] = "Pêche";
    ["Festival"] = "Festival";
    ["Kinship"] = "Confrérie";
    ["Social"] = "Social";
    ["Usable items"] = "Utilisables";
    ["Tasks"] = "Tâches";
    ["Miscellaneous"] = "Divers";

    -- Bags: window
    ["Bags"] = "Sacs";
    ["Search..."] = "Rechercher...";
    ["Stack"] = "Empiler";
    ["All bags"] = "Tous les sacs";
    ["By category"] = "Par catégorie";
    ["New items"] = "Nouveaux objets";
    ["Free slots"] = "Emplacements libres";
    ["%d / %d free"] = "%d / %d libres";
    ["Stacking done (%d merges)."] = "Empilement terminé (%d fusions).";

    -- Bags: options
    ["The bag replaces the game bags. Open it with the usual bag key."] = "Le sac remplace les sacs du jeu. Ouvre-le avec la touche habituelle des sacs.";
    ["All your bags in one window, sorted by category."] = "Tous tes sacs dans une seule fenêtre, triés par catégorie.";
    ["Open the bags"] = "Ouvrir les sacs";
    ["Categories side by side"] = "Catégories côte à côte";
    ["Sort items by category"] = "Ranger les objets par catégorie";
    ["Columns without categories"] = "Colonnes sans catégories";
    ["Items per row"] = "Objets par ligne";
    ["Slot size"] = "Taille des emplacements";
    ["Maximum height"] = "Hauteur maximale";
    ["Show new items in their own section"] = "Afficher les nouveaux objets dans leur propre section";
    ["Currencies shown at the bottom"] = "Monnaies affichées en bas";
    ["Your wallet is empty for now."] = "Ton portefeuille est vide pour l'instant.";
    ["%s is also loaded, unload it to avoid two bag windows: /plugins unload %s"] = "%s est aussi chargé, décharge-le pour éviter deux fenêtres de sacs : /plugins unload %s";

    -- Unit frames: bars
    ["Number and percent"] = "Nombre et pourcentage";
    ["Number"] = "Nombre";
    ["Percent"] = "Pourcentage";
    ["Nothing"] = "Rien";
    ["White"] = "Blanc";
    ["Light grey"] = "Gris clair";
    ["Accent"] = "Couleur du thème";
    ["Black outline"] = "Contour noir";
    ["Shadow"] = "Ombre";
    ["Violet"] = "Violet";
    ["Fixed colour"] = "Couleur fixe";
    ["Class colour"] = "Couleur de classe";
    ["Following morale (green to red)"] = "Selon le moral (vert à rouge)";
    ["Theme accent"] = "Couleur du thème";
    ["Level difference"] = "Selon la différence de niveau";
    ["Morale bar colour"] = "Couleur de la barre de moral";
    ["Colours"] = "Couleurs";
    ["None"] = "Aucun";

    -- Unit frames: effects
    ["Below"] = "En dessous";
    ["Above"] = "Au-dessus";
    ["Left"] = "À gauche";
    ["Right"] = "À droite";
    ["Toward the right"] = "Vers la droite";
    ["Toward the left"] = "Vers la gauche";
    ["Downward"] = "Vers le bas";
    ["Upward"] = "Vers le haut";
    ["Buff"] = "Buff";
    ["Debuff"] = "Débuff";
    ["Disease"] = "Maladie";
    ["Fear"] = "Peur";
    ["Poison"] = "Poison";
    ["Wound"] = "Blessure";
    ["Corruption"] = "Corruption";
    ["%d h %d min"] = "%d h %d min";
    ["%d min %d s"] = "%d min %d s";
    ["%d s"] = "%d s";

    -- Unit frames: preview
    ["Test effect %d"] = "Effet de test %d";
    ["Fake effect to set up the icons. The real description of the buff or debuff is shown here."] = "Effet fictif pour régler les icônes. La vraie description du buff ou du débuff s'affiche ici.";
    ["Training dummy"] = "Mannequin d'entraînement";

    -- Unit frames: party
    ["Party"] = "Groupe";

    -- Unit frames: options
    ["Player frame"] = "Cadre du joueur";
    ["Target frame"] = "Cadre de la cible";
    ["Party frames"] = "Cadres du groupe";
    ["Each frame replaces the game one. Bars, effects and colours are set in the options."] = "Chaque cadre remplace celui du jeu. Barres, effets et couleurs se règlent dans les options.";
    ["Unit frames"] = "Cadres d'unités";
    ["Player, target and party frames, with buffs and debuffs."] = "Cadres du joueur, de la cible et du groupe, avec buffs et débuffs.";
    ["Player"] = "Joueur";
    ["Target"] = "Cible";
    ["Show this frame"] = "Afficher ce cadre";
    ["Copy the player, mirrored"] = "Copier le joueur en miroir";
    ["Mirrored (right to left)"] = "Miroir (de droite à gauche)";
    ["Bars"] = "Barres";
    ["Width"] = "Largeur";
    ["Name and level"] = "Nom et niveau";
    ["Morale height"] = "Hauteur du moral";
    ["Morale text"] = "Texte du moral";
    ["Power bar"] = "Barre de puissance";
    ["Power height"] = "Hauteur de la puissance";
    ["Power text"] = "Texte de la puissance";
    ["Class resource"] = "Ressource de classe";
    ["Arrangement"] = "Disposition";
    ["One under the other"] = "Les uns sous les autres";
    ["Side by side"] = "Côte à côte";
    ["Spacing"] = "Espacement";
    ["Include me"] = "M'inclure";
    ["Effects"] = "Effets";
    ["Show buffs and debuffs"] = "Afficher buffs et débuffs";
    ["Position"] = "Position";
    ["Direction"] = "Direction";
    ["Icons per line"] = "Icônes par ligne";
    ["Maximum icons"] = "Nombre maximum d'icônes";
    ["Debuffs first"] = "Débuffs en premier";
    ["Space between icons"] = "Espace entre les icônes";
    ["Preview: on"] = "Aperçu : activé";
    ["Preview: off"] = "Aperçu : désactivé";
    ["Space between bars"] = "Espace entre les barres";
    ["Name and level colour"] = "Couleur du nom et du niveau";
    ["Bar text colour"] = "Couleur du texte des barres";
    ["Text style"] = "Style du texte";

    -- Info bar
    ["Shown elements"] = "Éléments affichés";
    ["Info bar"] = "Barre d'infos";
    ["Money, currencies, bags, durability, FPS and time along the edge of the screen."] = "Argent, monnaies, sacs, durabilité, FPS et heure sur le bord de l'écran.";
    ["Money"] = "Argent";
    ["Currencies"] = "Monnaies";
    ["Durability"] = "Durabilité";
    ["Free bag slots"] = "Emplacements des sacs";
    ["Frames per second"] = "Images par seconde (FPS)";
    ["Time"] = "Heure";
    [" g"] = " o";
    [" s"] = " a";
    [" c"] = " c";
    ["Gold, silver and copper"] = "Or, argent et cuivre";
    ["Gold only"] = "Or seulement";
    ["Used / total"] = "Occupés / total";
    ["Average"] = "Moyenne";
    ["Most worn piece"] = "Pièce la plus usée";
    ["24 hours"] = "24 heures";
    ["12 hours"] = "12 heures";
    ["Elements"] = "Éléments";
    ["Top bar"] = "Barre du haut";
    ["Bottom bar"] = "Barre du bas";
    ["Height"] = "Hauteur";
    ["Bar"] = "Barre";
    ["Hidden"] = "Masqué";
    ["Zone"] = "Zone";
    ["Centre"] = "Centre";
    ["Order in the zone"] = "Ordre dans la zone";
    ["Text size"] = "Taille du texte";
    ["Show the label"] = "Afficher le libellé";
    ["Show the icons"] = "Afficher les icônes";
    ["Format"] = "Format";
    ["Text colour"] = "Couleur du texte";

    -- Auras
    ["Remaining time under the icon"] = "Temps restant sous l'icône";
    ["Two areas at the top right, next to the minimap. Place them with the move mode."] = "Deux zones en haut à droite, à côté de la minimap. Place-les avec le mode déplacement.";
    ["Auras"] = "Auras";
    ["Your buffs and debuffs in two areas of their own, next to the minimap."] = "Tes buffs et débuffs dans deux zones à part, à côté de la minimap.";
    ["Buffs"] = "Buffs";
    ["Debuffs"] = "Débuffs";
    ["Show this area"] = "Afficher cette zone";
    ["Border colour by type"] = "Contour selon le type";
    ["New lines"] = "Nouvelles lignes";
    ["Remaining time"] = "Temps restant";
    ["Under the icon"] = "Sous l'icône";
    ["On the icon"] = "Sur l'icône";
    ["Also show the effects under the player frame"] = "Afficher aussi les effets sous le cadre du joueur";
    ["Place the areas with the move mode. The game does not let plugins cancel a buff."] = "Place les zones avec le mode déplacement. Le jeu ne permet pas aux plugins d'annuler un buff.";

    -- Action bars
    ["Action bars"] = "Barres d'action";
    ["Extra bars for your skills, items and commands, used with the mouse."] = "Barres supplémentaires pour tes compétences, objets et commandes, à la souris.";
    ["Bar %d"] = "Barre %d";
    ["Locked"] = "Verrouillées";
    ["New bar"] = "Nouvelle barre";
    ["Delete"] = "Supprimer";
    ["Maximum items"] = "Nombre maximum d'objets";
    ["Consumables bar (fills itself from the backpack)"] = "Barre Consommables (se remplit toute seule depuis le sac)";
    ["Locked (no empty slots or crosses)"] = "Verrouillées (sans emplacements vides ni croix)";
    ["Drag skills and items onto the bars. These bars are used with the mouse, the game does not let plugins use keys. More bars can be added in the options."] = "Glisse compétences et objets sur les barres. Elles s'utilisent à la souris, le jeu ne permet pas aux plugins d'utiliser les touches. D'autres barres s'ajoutent dans les options.";
    ["Report written to the plugin data folder."] = "Rapport écrit dans le dossier PluginData.";
    ["Consumables bar: the game refuses item shortcuts."] = "Barre Consommables : le jeu refuse les raccourcis d'objets.";
    ["Show the hidden items again (%d)"] = "Réafficher les objets masqués (%d)";
    ["This bar fills itself with the food, potions and scrolls of your backpack, with their total quantity. Unlock the bars and use the cross to hide an item you do not want here."] = "Cette barre se remplit toute seule avec la nourriture, les potions et les parchemins de ton sac, avec leur quantité totale. Déverrouille les barres et utilise la croix pour masquer un objet que tu ne veux pas ici.";
    ["No bar yet."] = "Aucune barre pour l'instant.";
    ["Show this bar"] = "Afficher cette barre";
    ["Show the empty slots"] = "Afficher les emplacements vides";
    ["Number of slots"] = "Nombre d'emplacements";
    ["Slots per line"] = "Emplacements par ligne";
    ["Shown"] = "Affichée";
    ["Always"] = "Toujours";
    ["In combat only"] = "En combat seulement";
    ["Out of combat only"] = "Hors combat seulement";
    ["With a target"] = "Avec une cible";
    ["Faded until the mouse is over it"] = "Estompée tant que la souris n'est pas dessus";
    ["Drag skills, items or chat commands onto the slots. Unlock the bars to see the empty slots and take shortcuts off with the cross. Place the bars with the move mode. The game does not let plugins use keys: these bars are clicked."] = "Glisse des compétences, objets ou commandes sur les emplacements. Déverrouille les barres pour voir les emplacements vides et retirer un raccourci avec la croix. Place les barres avec le mode déplacement. Le jeu ne permet pas aux plugins d'utiliser les touches : ces barres s'utilisent au clic.";

    -- General
    ["Language"] = "Langue";
    ["Automatic (game language)"] = "Automatique (langue du jeu)";
    ["The language changes after a reload."] = "La langue change après un rechargement.";

    -- Profile sharing
    ["Share"] = "Partager";
    ["Export this profile"] = "Exporter ce profil";
    ["Import a profile"] = "Importer un profil";
    ["Share a profile"] = "Partager un profil";
    ["Export"] = "Exporter";
    ["Import"] = "Importer";
    ["Select all"] = "Tout sélectionner";
    ["Imported"] = "Importé";
    ["Name of the new profile"] = "Nom du nouveau profil";
    ["Code of the profile \"%s\". Select it, copy it with Ctrl+C and share it."] = "Code du profil « %s ». Sélectionne-le, copie-le avec Ctrl+C et partage-le.";
    ["Paste a profile code with Ctrl+V. It becomes a new profile, your current ones stay as they are."] = "Colle un code de profil avec Ctrl+V. Il devient un nouveau profil, tes profils actuels ne changent pas.";
    ["This is not a GrommeyUI profile code."] = "Ce n'est pas un code de profil GrommeyUI.";
    ["The code is incomplete or changed, copy it again in full."] = "Le code est incomplet ou modifié, copie-le à nouveau en entier.";
    ["The code could not be read."] = "Le code n'a pas pu être lu.";
    ["Also saved in: PluginData > (account) > AllServers > GrommeyUI_ProfileExport.plugindata"] = "Aussi enregistré dans : PluginData > (compte) > AllServers > GrommeyUI_ProfileExport.plugindata";

    -- Bags: custom categories
    ["Display"] = "Affichage";
    ["My categories"] = "Mes catégories";
    ["Rename"] = "Renommer";
    ["Move up"] = "Monter";
    ["Move down"] = "Descendre";
    ["No category yet. Give it a name and create it."] = "Aucune catégorie pour l'instant. Donne-lui un nom et crée-la.";
    ["Drag an item here to put it in this category. You can also drop it on a category title in the bag."] = "Glisse un objet ici pour le ranger dans cette catégorie. Tu peux aussi le déposer sur le titre d'une catégorie dans le sac.";
    ["No item in this category yet."] = "Aucun objet dans cette catégorie pour l'instant.";

    -- Unit frames: target of target
    ["Target of target"] = "Cible de la cible";
    ["Shown when the game tells who your target is targeting. If it never shows up, the game does not give it."] = "S'affiche quand le jeu indique qui ta cible vise. S'il n'apparaît jamais, c'est que le jeu ne le donne pas.";

    -- Info bar: session, memory, character
    ["Session time"] = "Durée de session";
    ["Money of the session"] = "Argent de la session";
    ["GrommeyUI memory"] = "Mémoire de GrommeyUI";
    ["Character"] = "Personnage";
    ["Since the login"] = "Depuis la connexion";
    ["Per hour"] = "Par heure";
    ["Name only"] = "Nom seulement";
    ["Session"] = "Session";
    ["Gained"] = "Gain";
    ["Memory"] = "Mémoire";
    [" MB"] = " Mo";
    ["/ h"] = "/ h";
    ["%d h %02d"] = "%d h %02d";
    ["%d min"] = "%d min";

    -- Auras: filters
    ["Filters"] = "Filtres";
    ["Hide permanent effects (no duration or an hour and more)"] = "Masquer les effets permanents (sans durée ou d'une heure et plus)";
    ["Your effects right now"] = "Tes effets actuels";
    ["No effect on you at the moment."] = "Aucun effet sur toi pour le moment.";
    ["Important"] = "Important";
    ["Hide"] = "Masquer";
    ["Important (shown first)"] = "Importants (affichés en premier)";
    ["Hidden effects"] = "Masqués";
    ["Show my money"] = "Afficher mon argent";

    -- What's new
    ["What's new"] = "Nouveautés";
    ["Version %s"] = "Version %s";
    ["First stable version of GrommeyUI."] = "Première version stable de GrommeyUI.";
    ["Bags: one window sorted by category, your own categories, search, money and currencies at the bottom."] = "Sacs : une seule fenêtre triée par catégorie, tes propres catégories, la recherche, l'argent et les monnaies en bas.";
    ["Unit frames: player, target, target of target and party, click a frame to target."] = "Cadres d'unités : joueur, cible, cible de la cible et groupe, clic sur un cadre pour cibler.";
    ["Info bar: money, currencies, bags, durability, FPS, time, session and character."] = "Barre d'infos : argent, monnaies, sacs, durabilité, FPS, heure, session et personnage.";
    ["Auras: buffs and debuffs next to the minimap, with important and hidden effects."] = "Auras : buffs et débuffs à côté de la minimap, avec effets importants et masqués.";
    ["Action bars: extra bars, and a consumables bar that fills itself from your backpack."] = "Barres d'action : barres supplémentaires, et une barre de consommables qui se remplit toute seule depuis ton sac.";
    ["Themes, fonts and text size, profiles to export and import."] = "Thèmes, polices et taille du texte, profils à exporter et importer.";
    ["A setup assistant, in English, French and German."] = "Un assistant de configuration, en anglais, français et allemand.";
    ["This window shows what is new after each update. Open it again from the General page of the options."] = "Cette fenêtre montre les nouveautés après chaque mise à jour. Rouvre-la depuis la page Général des options.";
    ["Close"] = "Fermer";
    ["GrommeyUI can now be recognised and updated by LOTRO Plugin Compendium."] = "GrommeyUI peut maintenant être reconnu et mis à jour par LOTRO Plugin Compendium.";

    -- Combat meter: combat log
    ["Combat log: %d lines, %d read, %d not recognised."] = "Journal de combat : %d lignes, %d lues, %d non reconnues.";
    ["Combat log: test on. Every combat line is shown here and saved in %s."] = "Journal de combat : test activé. Chaque ligne de combat s'affiche ici et est enregistrée dans %s.";
    ["Combat log: test off."] = "Journal de combat : test désactivé.";
});

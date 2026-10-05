-- Item categories of the bag, in display order.
-- ids are the game item categories (item:GetItemInfo():GetCategory()), unknown ones go to Misc.

Grommey.Bags = Grommey.Bags or {};

Grommey.Bags.Categories = {
    { key = "Quest";           name = "Quest items";      ids = { 27 }; };
    { key = "Consumables";     name = "Consumables";      ids = { 28, 55, 57, 189, 190, 292, 25 }; };
    { key = "Weapons";         name = "Weapons";          ids = { 46, 30, 12, 36, 29, 42, 44, 110, 24, 34, 1, 40, 10, 290 }; };
    { key = "Armour";          name = "Armour";           ids = { 7, 15, 23, 3, 6, 33, 5, 18, 45 }; };
    { key = "Jewelry";         name = "Jewellery";        ids = { 49 }; };
    { key = "Legendary";       name = "Legendary items";  ids = { 194, 108, 176, 166, 168, 206, 107, 193, 167, 51, 233 }; };
    { key = "Essences";        name = "Essences";         ids = { 235 }; };
    { key = "Class";           name = "Class items";      ids = { 17, 26, 19, 22, 4, 48, 288, 106, 13, 111, 105, 171, 179, 187, 14, 163 }; };
    { key = "Crafting";        name = "Crafting";         ids = { 56, 38, 188, 35, 32 }; };
    { key = "CraftingScrolls"; name = "Crafting scrolls"; ids = { 67, 120, 64, 145, 134, 113, 148, 61, 131, 149, 119, 129, 115, 125, 143, 158, 198, 118, 156, 137, 58, 123, 142, 199, 136, 152, 196, 204, 127, 202, 162, 135, 139, 197, 201, 200, 203, 66, 144, 114, 126, 153, 147, 155, 138, 141, 63, 130, 124, 128, 150, 159, 161, 62, 117, 151, 65, 59, 60, 133, 146, 160, 157, 195, 132, 121, 154, 140, 116, 122 }; };
    { key = "Barter";          name = "Barter";           ids = { 178 }; };
    { key = "Reputation";      name = "Reputation";       ids = { 89 }; };
    { key = "Travel";          name = "Travel";           ids = { 191, 175, 186 }; };
    { key = "Skirmish";        name = "Skirmish";         ids = { 177 }; };
    { key = "Lootbox";         name = "Lootboxes";        ids = { 251 }; };
    { key = "Deconstructable"; name = "Deconstructable";  ids = { 109 }; };
    { key = "Trophy";          name = "Trophies";         ids = { 172, 170, 47, 287 }; };
    { key = "Cosmetics";       name = "Cosmetics";        ids = { 192, 183, 185, 180, 182, 184, 96, 181, 97, 253 }; };
    { key = "Decorations";     name = "Decorations";      ids = { 87, 86, 21, 88, 85, 98, 83, 99, 82, 84, 285, 291 }; };
    { key = "Instruments";     name = "Instruments";      ids = { 11 }; };
    { key = "Fishing";         name = "Fishing";          ids = { 100, 101, 102, 103 }; };
    { key = "Festival";        name = "Festival";         ids = { 205 }; };
    { key = "Kinship";         name = "Kinship";          ids = { 43 }; };
    { key = "Social";          name = "Social";           ids = { 174, 41, 54, 173, 39 }; };
    { key = "Useables";        name = "Usable items";     ids = { 37, 50, 16, 20, 8 }; };
    { key = "Task";            name = "Tasks";            ids = { 207 }; };
    { key = "Misc";            name = "Miscellaneous";    ids = { 0, 31, 52, 91, 53, 2, 104, 9, 164, 279 }; };
};

-- Game category id -> category key, and key -> display position
Grommey.Bags.CategoryOfId = {};
Grommey.Bags.CategoryOrder = {};
Grommey.Bags.CategoryByKey = {};
for position, category in ipairs(Grommey.Bags.Categories) do
    Grommey.Bags.CategoryOrder[category.key] = position;
    Grommey.Bags.CategoryByKey[category.key] = category;
    for _, id in ipairs(category.ids) do Grommey.Bags.CategoryOfId[id] = category.key; end
end

-- Categories made by the player: settings.customCategories = { { id, name }, ... } in display order,
-- settings.itemCategory = { item name = category id }
function Grommey.Bags.FindCustom(settings, id)
    for position, category in ipairs(settings.customCategories or {}) do
        if (category.id == id) then return category, position; end
    end
    return nil;
end

-- "custom:<id>" when the player put this item in one of their categories
function Grommey.Bags.CustomKey(settings, item)
    local id = (settings.itemCategory or {})[item:GetName() or ""];
    if (id ~= nil and Grommey.Bags.FindCustom(settings, id)) then return "custom:" .. id; end
    return nil;
end

function Grommey.Bags.GetCategoryKey(item)
    local id = item:GetItemInfo():GetCategory();
    return Grommey.Bags.CategoryOfId[id] or "Misc";
end

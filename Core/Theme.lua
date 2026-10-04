-- Visual theme: an accent colour, a background tint with its opacity and a font family.
-- Controls ask for colours by role (Grommey.Theme.Color("panel")) and register with
-- Grommey.Theme.Track(fn) to be repainted when the theme or the profile changes.

Grommey.Theme = {};

Grommey.Theme.AccentPresets = {
    { name = "Teal";     r = 12;  g = 210; b = 159; };
    { name = "Gold";     r = 226; g = 184; b = 92;  };
    { name = "Azure";    r = 64;  g = 156; b = 255; };
    { name = "Amethyst"; r = 166; g = 110; b = 255; };
    { name = "Ruby";     r = 232; g = 72;  b = 85;  };
    { name = "Forest";   r = 96;  g = 190; b = 90;  };
};

Grommey.Theme.Backgrounds = {
    { name = "Charcoal"; r = 18; g = 19; b = 22; };
    { name = "Night";    r = 10; g = 12; b = 22; };
    { name = "Slate";    r = 30; g = 34; b = 40; };
};

Grommey.Theme.Fonts = {
    { name = "Verdana"; label = "Modern (Verdana)"; };
    { name = "Trajan";  label = "Middle-earth (Trajan)"; };
};

local function GetBackground()
    local wanted = Grommey.Profile.theme.background;
    for _, background in ipairs(Grommey.Theme.Backgrounds) do
        if (background.name == wanted) then return background; end
    end
    return Grommey.Theme.Backgrounds[1];
end

local function Lighten(colour, amount)
    return {
        r = Grommey.Clamp(colour.r + amount, 0, 255);
        g = Grommey.Clamp(colour.g + amount, 0, 255);
        b = Grommey.Clamp(colour.b + amount, 0, 255);
    };
end

-- Returns { r, g, b, a } for a role, values 0-255 and alpha 0-1
local function GetRole(role)
    local theme = Grommey.Profile.theme;
    local background = GetBackground();
    local opacity = Grommey.Clamp(theme.opacity, 20, 100) / 100;

    -- Only the window background follows the opacity setting. Controls inside a window must be
    -- opaque, a see-through control shows what is behind it instead of its parent.
    if (role == "background") then
        local colour = Lighten(background, 0); colour.a = opacity; return colour;
    elseif (role == "field") then
        local colour = Lighten(background, -4); colour.a = 1; return colour;
    elseif (role == "panel") then
        local colour = Lighten(background, 10); colour.a = 1; return colour;
    elseif (role == "raised") then
        local colour = Lighten(background, 24); colour.a = 1; return colour;
    elseif (role == "border") then
        local colour = Lighten(background, 38); colour.a = 1; return colour;
    elseif (role == "text") then
        return { r = 234; g = 234; b = 230; a = 1; };
    elseif (role == "dim") then
        return { r = 150; g = 153; b = 158; a = 1; };
    elseif (role == "accent") then
        return { r = theme.accent.r; g = theme.accent.g; b = theme.accent.b; a = 1; };
    elseif (role == "accentSoft") then
        -- Accent mixed into the raised colour, opaque
        local raised = Lighten(background, 24);
        return {
            r = math.floor(raised.r + (theme.accent.r - raised.r) * 0.3);
            g = math.floor(raised.g + (theme.accent.g - raised.g) * 0.3);
            b = math.floor(raised.b + (theme.accent.b - raised.b) * 0.3);
            a = 1;
        };
    elseif (role == "accentGlass") then
        -- See-through accent, only for top level windows such as the move mode boxes
        return { r = theme.accent.r; g = theme.accent.g; b = theme.accent.b; a = 0.35; };
    elseif (role == "danger") then
        return { r = 232; g = 84; b = 84; a = 1; };
    end
    return { r = 255; g = 0; b = 255; a = 1; };
end

-- Turbine colour for a role, alpha can be overridden (0-1)
function Grommey.Theme.Color(role, alpha)
    local colour = GetRole(role);
    return Turbine.UI.Color(alpha or colour.a, colour.r / 255, colour.g / 255, colour.b / 255);
end

-- Opaque mix of two roles, amount 0 gives the first one and 1 the second one
function Grommey.Theme.Mix(firstRole, secondRole, amount)
    local first = GetRole(firstRole);
    local second = GetRole(secondRole);
    return Turbine.UI.Color(
        1,
        (first.r + (second.r - first.r) * amount) / 255,
        (first.g + (second.g - first.g) * amount) / 255,
        (first.b + (second.b - first.b) * amount) / 255);
end

-- Colour as markup for labels with SetMarkupEnabled(true)
function Grommey.Theme.Hex(role)
    local colour = GetRole(role);
    return string.format("#%02X%02X%02X", colour.r, colour.g, colour.b);
end

-- Font sizes the game actually has, the nearest one is picked
local FontSizes = {
    Verdana = { 10, 12, 13, 14, 15, 16, 18, 20, 22, 23 };
    Trajan = { 13, 14, 15, 16, 18, 19, 20, 21, 23, 24, 25, 26, 28 };
};

local function FontByName(name)
    return Turbine.UI.Lotro.Font[name];
end

function Grommey.Theme.Font(size, bold)
    local family = Grommey.Profile.theme.font;
    if (FontSizes[family] == nil) then family = "Verdana"; end

    if (bold) then
        local boldFont = nil;
        if (family == "Verdana") then boldFont = FontByName("VerdanaBold16");
        else boldFont = FontByName("TrajanProBold16"); end
        if (boldFont) then return boldFont; end
    end

    local best = nil;
    for _, available in ipairs(FontSizes[family]) do
        if (best == nil or math.abs(available - size) < math.abs(best - size)) then best = available; end
    end

    local fontName = (family == "Verdana") and ("Verdana" .. best) or ("TrajanPro" .. best);
    return FontByName(fontName) or Turbine.UI.Lotro.Font.Verdana14;
end

-- Calls paint now and every time the look changes
function Grommey.Theme.Track(paint)
    paint();
    Grommey.On("ThemeChanged", paint);
    Grommey.On("ProfileChanged", paint);
    return paint;
end

-- To call after changing Grommey.Profile.theme
function Grommey.Theme.Changed()
    Grommey.Profiles.RequestSave();
    Grommey.Fire("ThemeChanged");
end

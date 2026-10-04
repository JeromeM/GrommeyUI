-- Small floating "G" button: left click opens the options, right click starts move mode.

Grommey.Launcher = {};

local SIZE = 34;
local button = nil;

function Grommey.Launcher.Create()
    local Theme = Grommey.Theme;

    button = Turbine.UI.Window();
    button:SetSize(SIZE, SIZE);
    button:SetZOrder(10);

    local frame = Grommey.UI.Frame(button, 0, 0, SIZE, SIZE, "background", "border");
    frame:SetMouseVisible(false);
    frame.inner:SetMouseVisible(false);

    local letter = Grommey.UI.Label(button, 0, 0, SIZE, SIZE, "G", { size = 20; bold = true; role = "accent"; align = Turbine.UI.ContentAlignment.MiddleCenter; });

    local hovered = false;
    local function Paint()
        frame.borderRole = hovered and "accent" or "border";
        frame.role = hovered and "raised" or "background";
        frame.Paint();
    end
    Theme.Track(Paint);

    button.MouseEnter = function() hovered = true; Paint(); end
    button.MouseLeave = function() hovered = false; Paint(); end
    button.MouseClick = function(sender, args)
        if (Turbine.UI.MouseButton ~= nil and args.Button == Turbine.UI.MouseButton.Right) then
            Grommey.Movers.Toggle();
        else
            Grommey.Options.Toggle();
        end
    end

    -- Default place: top right, under the minimap area
    Grommey.Movers.Register("launcher", button, L("GrommeyUI button"),
        function() return Turbine.UI.Display.GetWidth() - SIZE - 260; end,
        function() return 12; end);

    Grommey.Launcher.Refresh();
    Grommey.On("ProfileChanged", Grommey.Launcher.Refresh);
    Grommey.On("HudToggled", Grommey.Launcher.Refresh);
end

function Grommey.Launcher.Refresh()
    if (button) then button:SetVisible(Grommey.Profile.launcher.shown == true and not Grommey.HudHidden); end
end

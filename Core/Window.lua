-- Flat window with a title bar, a close button and a 1 pixel border.
-- Drag the title bar to move it. With an id, its position is saved in the profile
-- and it can be placed in move mode like any other frame.
-- Content goes into window.content.

Grommey.Window = class(Turbine.UI.Window);

local TITLE_HEIGHT = 30;

function Grommey.Window:Constructor(id, title, width, height)
    Turbine.UI.Window.Constructor(self);
    self.id = id;
    self:SetSize(width, height);
    self:SetVisible(false);

    local Theme = Grommey.Theme;

    self.frame = Grommey.UI.Frame(self, 0, 0, width, height, "background", "border");
    self.frame.inner:SetMouseVisible(false);
    self.frame:SetMouseVisible(false);

    -- Title bar
    self.titleBar = Turbine.UI.Control();
    self.titleBar:SetParent(self);
    self.titleBar:SetPosition(1, 1);
    self.titleBar:SetSize(width - 2, TITLE_HEIGHT);

    self.accentLine = Turbine.UI.Control();
    self.accentLine:SetParent(self.titleBar);
    self.accentLine:SetPosition(0, 0);
    self.accentLine:SetSize(width - 2, 2);
    self.accentLine:SetMouseVisible(false);

    self.titleLabel = Grommey.UI.Label(self.titleBar, 12, 2, width - 60, TITLE_HEIGHT - 2, title, { size = 16; bold = true; });

    self.closeButton = Grommey.UI.Label(self.titleBar, width - 34, 2, 30, TITLE_HEIGHT - 2, "×", { size = 18; align = Turbine.UI.ContentAlignment.MiddleCenter; role = "dim"; mouse = true; });
    self.closeButton.MouseEnter = function() self.closeButton:SetForeColor(Theme.Color("danger")); end
    self.closeButton.MouseLeave = function() self.closeButton:SetForeColor(Theme.Color("dim")); end
    self.closeButton.MouseClick = function() self:SetVisible(false); end

    Theme.Track(function()
        self.titleBar:SetBackColor(Theme.Color("panel"));
        self.accentLine:SetBackColor(Theme.Color("accent"));
    end);

    -- Dragging by the title bar
    self.titleBar.MouseDown = function(sender, args)
        -- Fixed windows only move in move mode
        if (self.movable == false) then return; end
        self.dragging = true;
        self.dragX = args.X;
        self.dragY = args.Y;
    end
    self.titleBar.MouseMove = function(sender, args)
        if (not self.dragging) then return; end
        local x = self:GetLeft() + args.X - self.dragX;
        local y = self:GetTop() + args.Y - self.dragY;
        self:SetPosition(x, y);
    end
    self.titleBar.MouseUp = function()
        if (not self.dragging) then return; end
        self.dragging = false;
        if (self.id) then Grommey.Movers.SavePosition(self.id, self:GetLeft(), self:GetTop()); end
    end

    self.content = Turbine.UI.Control();
    self.content:SetParent(self);
    self.content:SetPosition(1, TITLE_HEIGHT + 1);
    self.content:SetSize(width - 2, height - TITLE_HEIGHT - 2);

    -- Escape closes the window
    self:SetWantsKeyEvents(true);
    self.KeyDown = function(sender, args)
        if (args.Action == Turbine.UI.Lotro.Action.Escape and self:IsVisible()) then self:SetVisible(false); end
    end
end

-- Changes the size of the window and of its title bar and content
function Grommey.Window:Resize(width, height)
    self:SetSize(width, height);
    self.frame.Resize(width, height);
    self.titleBar:SetSize(width - 2, 30);
    self.accentLine:SetSize(width - 2, 2);
    self.titleLabel:SetSize(width - 60, 28);
    self.closeButton:SetPosition(width - 34, 2);
    self.content:SetSize(width - 2, height - 32);
end

function Grommey.Window:SetTitle(title)
    self.titleLabel:SetText(title);
end

function Grommey.Window:Toggle()
    self:SetVisible(not self:IsVisible());
    if (self:IsVisible()) then self:Activate(); end
end

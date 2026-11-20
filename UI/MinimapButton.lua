local _, ns = ...

-- The button on the edge of the minimap: the game's own yellow "!" for a
-- quest on offer. Left-click opens the Onward window, right-click the
-- options, and it can be dragged around the rim. The options can hide it.
--
-- Built by hand like Goldwise's and Creel's: the same art and size as other
-- minimap buttons, and a name with "MinimapButton" in it, which button
-- tidying addons such as MinimapButtonButton look for.

-- How far outside the minimap's edge the button's centre sits.
local EDGE_OFFSET = 5

-- The game's icon for a quest on offer, as in a quest giver's list.
local ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local button

-- Puts the button on the minimap's rim at the saved angle.
local function Place()
    local angle = math.rad(ns.settings.minimapAngle)
    local x, y = math.cos(angle), math.sin(angle)
    local halfWidth = Minimap:GetWidth() / 2 + EDGE_OFFSET
    local halfHeight = Minimap:GetHeight() / 2 + EDGE_OFFSET

    -- Minimap addons that reshape the map (BasicMinimap's square one, say)
    -- say so through this function. On a square map the button follows the
    -- edges and corners instead of cutting across them on a circle.
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "ROUND" then
        x, y = x * halfWidth, y * halfHeight
    else
        local reach = math.sqrt(2)
        x = math.max(-halfWidth, math.min(x * halfWidth * reach, halfWidth))
        y = math.max(-halfHeight, math.min(y * halfHeight * reach, halfHeight))
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging: point the button at wherever the cursor is, measured as
-- an angle from the minimap's centre.
local function FollowCursor()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.settings.minimapAngle =
        math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    Place()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip_SetTitle(GameTooltip, ns.TITLE)
    GameTooltip_AddHighlightLine(GameTooltip, "Left-click for quests worth a second look.")
    GameTooltip_AddHighlightLine(GameTooltip, "Right-click for options.")
    GameTooltip_AddDisabledLine(GameTooltip, "Drag to move.")
    GameTooltip:Show()
end

local function Create()
    local frame = CreateFrame("Button", "OnwardMinimapButton", Minimap)
    frame:SetSize(31, 31)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(8)
    frame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The standard look: a dark disc, the icon, and the gold ring on top.
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- The "!" is drawn on a clear background already, so it needs no mask
    -- to sit inside the ring.
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON)

    local ring = frame:CreateTexture(nil, "OVERLAY")
    ring:SetSize(50, 50)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.OpenOptions()
        else
            ns.Window.Toggle()
        end
    end)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    frame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", GameTooltip_Hide)
    return frame
end

-- Shows or hides the button to match the player's setting.
local function Update()
    if ns.settings.minimapButton then
        button = button or Create()
        Place()
        button:Show()
    elseif button then
        button:Hide()
    end
end

ns.OnEvent("PLAYER_LOGIN", Update)
ns.Listen("SETTINGS_CHANGED", Update)

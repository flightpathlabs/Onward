local _, ns = ...

-- A small number beside Questie's "!" icons on the world map and the
-- minimap: how many quests follow the one on offer there.
--
-- Questie has no public way in. Its world map icons sit in map pins of a
-- template it names after itself, each pin holding the icon; its minimap
-- icons sit on the minimap. Either way the icon carries Questie's data for
-- it: the quest's ID, and "available" for a quest on offer. Onward finds
-- them that way and adds a number of its own. If a Questie update changes
-- any of this, the numbers just don't appear.
--
-- The counts come from Chain.Count, which asks the server nothing.

-- Questie's world map pin template, from its copy of HereBeDragons-Pins.
local WORLD_MAP_PIN = "HereBeDragonsPins-Questie-WorldMapPin"

-- Seconds between looks while the world map is open, and at the minimap.
-- Questie adds and moves its icons over a few frames, and reuses them.
local WORLD_MAP_EVERY = 0.5
local MINIMAP_EVERY = 1

local numbers = setmetatable({}, { __mode = "k" }) -- Questie's icon -> our number

local function QuestOnOffer(icon)
    local data = icon.data
    if type(data) == "table" and data.Type == "available" and type(data.Id) == "number" then
        return data.Id
    end
    return nil
end

local function Number(icon)
    local count = 0
    local questID = icon:IsShown() and QuestOnOffer(icon)
    if questID then
        count = ns.Chain.Count(questID)
    end

    local number = numbers[icon]
    if count == 0 then
        if number then
            number:Hide()
        end
        return
    end
    if not number then
        number = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        number:SetPoint("LEFT", icon, "RIGHT", -3, -4)
        numbers[icon] = number
        -- Questie hides an icon before using it for something else, so the
        -- number goes with it rather than waiting for the next look.
        icon:HookScript("OnHide", function()
            number:Hide()
        end)
    end
    number:SetText(count)
    number:Show()
end

local function HideAll()
    for _, number in pairs(numbers) do
        number:Hide()
    end
end

local function UpdateWorldMap()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end
    for pin in WorldMapFrame:EnumeratePinsByTemplate(WORLD_MAP_PIN) do
        if pin.icon then
            Number(pin.icon)
        end
    end
end

local function UpdateMinimap()
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if type(child.data) == "table" and child.data.Type ~= nil then
            Number(child)
        end
    end
end

local worldMapTicker, minimapTicker

local function Safely(func)
    local ok, message = pcall(func)
    if not ok then
        geterrorhandler()(message)
    end
end

local function StopWorldMap()
    if worldMapTicker then
        worldMapTicker:Cancel()
        worldMapTicker = nil
    end
end

local function StartWorldMap()
    StopWorldMap()
    if not ns.settings.mapNumbers or not _G.Questie then
        return
    end
    Safely(UpdateWorldMap)
    worldMapTicker = C_Timer.NewTicker(WORLD_MAP_EVERY, function()
        Safely(UpdateWorldMap)
    end)
end

local function Apply()
    if minimapTicker then
        minimapTicker:Cancel()
        minimapTicker = nil
    end
    if not ns.settings.mapNumbers or not _G.Questie then
        StopWorldMap()
        HideAll()
        return
    end
    minimapTicker = C_Timer.NewTicker(MINIMAP_EVERY, function()
        Safely(UpdateMinimap)
    end)
    if WorldMapFrame and WorldMapFrame:IsShown() then
        StartWorldMap()
    end
end

ns.OnEvent("PLAYER_LOGIN", function()
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", StartWorldMap)
        WorldMapFrame:HookScript("OnHide", StopWorldMap)
    end
    Apply()
end)

ns.Listen("SETTINGS_CHANGED", Apply)

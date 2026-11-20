local _, ns = ...

-- The Worth It window, from /worth or the minimap's addon menu: quests worth
-- a second look, in three tabs.
--
--   Dropped        quests you abandoned that you can still take
--   Missed         quests below your level you never did, whose chains
--                  still lead somewhere worth going
--   Worth seeking  chains you can start now, best first
--
-- Each row shows the quest, how many follow it and what the chain gives,
-- where its giver is, and the chain's first few reward items. Pointing at
-- a row lists the chain; clicking it marks the giver on the world map.

local Window = {}
ns.Window = Window

local Text = ns.Text
local Open = ns.Open

local WIDTH, HEIGHT = 460, 520
local ROW_HEIGHT = 58
local ICON_SIZE = 18
local MAX_ICONS = 5

local TABS = {
    {
        key = "dropped",
        name = "Dropped",
        intro = "Quests you abandoned that you can still take again.",
        empty = "No dropped quests you could take again.",
    },
    {
        key = "missed",
        name = "Missed",
        intro = "Quests below your level you never did, that still lead somewhere worth going.",
        empty = "Nothing missed: no low-level quest you skipped leads anywhere worth it.",
    },
    {
        key = "seek",
        name = "Worth seeking",
        intro = "Chains you can start now, best first.",
        empty = "No chains to suggest right now.",
    },
}

-- What each tab can't know, said plainly under the list.
local function Footnote(key)
    if key == "dropped" then
        if Open.HasQuestieJourney() then
            return "From Questie's journey, and Worth It's own record from now on. "
                .. "Quests dropped before Questie was installed can't be known."
        end
        return "Worth It keeps track of quests you abandon from now on. "
            .. "Quests dropped before can't be known."
    end
    return "Ranked by XP for your level and by what each chain leads to. "
        .. "Money and items count once Worth It has seen them."
end

local window, scrollBox, intro, empty, footnote
local selected = 1

-- Showing a place -------------------------------------------------------------------

--- Opens the world map on a zone with the game's waypoint pin on a spot.
local function ShowOnMap(mapID, x, y)
    if C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    -- The world map is one of the panels the game won't open in a fight;
    -- the waypoint is set, and the map can be opened after.
    if InCombatLockdown() then
        UIErrorsFrame:AddExternalErrorMessage(ERR_NOT_IN_COMBAT)
        return
    end
    OpenWorldMap(mapID)
end

-- Rows ----------------------------------------------------------------------------------

local function Ago(at)
    local seconds = time() - (at or 0)
    if at == nil or at <= 0 then
        return nil
    end
    local days = math.floor(seconds / 86400)
    if days >= 2 then
        return ("dropped %d days ago"):format(days)
    elseif days == 1 then
        return "dropped yesterday"
    end
    return "dropped today"
end

local function ItemOnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    if self.stepName then
        local text = self.isChoice and ("One of the choices from %s"):format(self.stepName)
            or ("From %s"):format(self.stepName)
        GameTooltip_AddColoredLine(GameTooltip, text, GRAY_FONT_COLOR, true)
    end
    GameTooltip:Show()
end

local function ItemOnClick(self)
    local _, link = C_Item.GetItemInfo(self.itemID)
    if link then
        HandleModifiedItemClick(link)
    end
end

local function CreateIcon(row)
    local icon = CreateFrame("Button", nil, row)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    icon.border:SetAllPoints()
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    icon:SetScript("OnEnter", ItemOnEnter)
    icon:SetScript("OnLeave", GameTooltip_Hide)
    icon:SetScript("OnClick", ItemOnClick)
    return icon
end

local function RowOnEnter(row)
    local summary = row.summary
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if summary and #summary.steps > 0 then
        Text.FillSteps(GameTooltip, summary)
    else
        GameTooltip_SetTitle(GameTooltip, row.title:GetText())
        local verdict = summary and Text.Verdict(summary, true)
        if verdict then
            GameTooltip_AddNormalLine(GameTooltip, verdict, true)
        end
    end
    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    if row.giver and row.giver.mapID then
        GameTooltip_AddInstructionLine(GameTooltip, "Click to mark the quest giver on your map.")
    elseif row.giver and row.giver.fromItem then
        GameTooltip_AddDisabledLine(
            GameTooltip,
            "This quest starts from an item, so there's no giver to mark.",
            true
        )
    else
        GameTooltip_AddDisabledLine(
            GameTooltip,
            "Worth It doesn't know where this quest starts.",
            true
        )
    end
    GameTooltip:Show()
end

local function RowOnClick(row)
    local giver = row.giver
    if giver and giver.mapID then
        ShowOnMap(giver.mapID, giver.x, giver.y)
    end
end

local function CreateRow(row)
    row.created = true
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 8, -6)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.note:SetPoint("TOPRIGHT", -8, -6)
    row.note:SetJustifyH("RIGHT")
    row.title:SetPoint("TOPRIGHT", row.note, "TOPLEFT", -8, 0)

    row.totals = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.totals:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.totals:SetPoint("TOPRIGHT", row.note, "BOTTOMRIGHT", 0, -4)
    row.totals:SetJustifyH("LEFT")
    row.totals:SetWordWrap(false)

    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.where:SetPoint("TOPLEFT", row.totals, "BOTTOMLEFT", 0, -5)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)

    row.icons = {}
    for index = 1, MAX_ICONS do
        local icon = CreateIcon(row)
        if index == 1 then
            icon:SetPoint("BOTTOMRIGHT", -8, 5)
        else
            icon:SetPoint("RIGHT", row.icons[index - 1], "LEFT", -3, 0)
        end
        row.icons[index] = icon
    end
    row.where:SetPoint("TOPRIGHT", row.icons[MAX_ICONS], "TOPLEFT", -6, 0)

    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", RowOnClick)
end

local function DifficultyColor(level)
    if level and level > 0 and GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(level)
        if color then
            return color.r, color.g, color.b
        end
    end
    return NORMAL_FONT_COLOR:GetRGB()
end

local function FillIcons(row, summary)
    local items = {}
    if summary and ns.settings.items then
        for _, item in ipairs(summary.items) do
            table.insert(items, { id = item.id, stepName = item.step.name })
        end
        for _, group in ipairs(summary.choiceGroups) do
            for _, item in ipairs(group.items) do
                table.insert(items, { id = item.id, stepName = group.step.name, isChoice = true })
            end
        end
    end
    for index, icon in ipairs(row.icons) do
        local item = items[index]
        if item then
            local _, _, _, _, texture = C_Item.GetItemInfoInstant(item.id)
            icon.itemID = item.id
            icon.stepName = item.stepName
            icon.isChoice = item.isChoice
            icon.texture:SetTexture(texture or 134400)
            local quality = C_Item.GetItemQualityByID(item.id)
            local color = quality
                and quality >= Enum.ItemQuality.Uncommon
                and ITEM_QUALITY_COLORS[quality]
            if color then
                icon.border:SetVertexColor(color.r, color.g, color.b)
                icon.border:Show()
            else
                icon.border:Hide()
            end
            icon:Show()
        else
            icon:Hide()
        end
    end
end

local function FillRow(row, entry)
    row.summary, row.giver = nil, nil
    local summary = ns.Chain.Build(entry.id)
    row.summary = summary
    if entry.giver == nil then
        entry.giver = Open.Giver(entry.id) or false
    end
    row.giver = entry.giver or nil

    local name = entry.name
        or C_QuestLog.GetTitleForQuestID(entry.id)
        or ("Quest %d"):format(entry.id)
    if entry.level and entry.level > 0 then
        name = ("[%d] %s"):format(entry.level, name)
    end
    row.title:SetText(name)
    row.title:SetTextColor(DifficultyColor(entry.level))
    row.note:SetText(ns.Lists.Note(entry.id) or "")

    local parts = {}
    local totals = summary and Text.Totals(summary)
    table.insert(parts, totals or "No more quests after it")
    local marks = summary and ns.settings.marks and Text.Marks(summary.marks)
    if marks then
        table.insert(parts, marks)
    elseif summary then
        local verdict = Text.Verdict(summary)
        if verdict then
            table.insert(parts, verdict)
        end
    end
    row.totals:SetText(table.concat(parts, "  ·  "))

    local where = {}
    local giver = row.giver
    if giver and giver.fromItem then
        table.insert(
            where,
            giver.name and ("Starts from %s"):format(giver.name) or "Starts from an item"
        )
    elseif giver then
        if giver.zone then
            table.insert(where, giver.zone)
        end
        if giver.name then
            table.insert(where, giver.name)
        end
    end
    local ago = entry.abandonedAt and Ago(entry.abandonedAt)
    if ago then
        table.insert(where, ago)
    end
    row.where:SetText(#where > 0 and table.concat(where, "  ·  ") or "Giver unknown")

    FillIcons(row, summary)
end

-- The window ----------------------------------------------------------------------------

local function Redraw()
    if not window or not window:IsShown() then
        return
    end
    local tab = TABS[selected]
    intro:SetText(tab.intro)
    footnote:SetText(Footnote(tab.key))

    if not ns.Source.Available() then
        scrollBox:SetDataProvider(CreateDataProvider({}))
        empty:SetText("This page needs Questie's quest data. Install Questie to use it.")
        empty:Show()
        return
    end

    local lists = Open.Lists()
    local rows = lists and lists[tab.key] or {}
    scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    if not lists then
        empty:SetText("Looking through quests...")
        empty:Show()
    elseif #rows == 0 then
        empty:SetText(tab.empty)
        empty:Show()
    else
        empty:Hide()
    end
end

local function Select(index)
    selected = index
    PanelTemplates_SetTab(window, index)
    scrollBox:ScrollToBegin()
    Redraw()
end

local function CreateWindow()
    window = CreateFrame("Frame", "WorthItQuestsWindow", UIParent, "ButtonFrameTemplate")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER", 0, 40)
    window:SetFrameStrata("HIGH")
    window:SetTitle(ns.TITLE)
    ButtonFrameTemplate_HidePortrait(window)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    table.insert(UISpecialFrames, "WorthItQuestsWindow")

    intro = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", 16, -32)
    intro:SetPoint("TOPRIGHT", -16, -32)
    intro:SetJustifyH("LEFT")

    local inset = window.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 8, -56)
    inset:SetPoint("BOTTOMRIGHT", -6, 58)

    scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, entry)
        if not row.created then
            CreateRow(row)
        end
        local ok, message = pcall(FillRow, row, entry)
        if not ok then
            geterrorhandler()(message)
        end
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    empty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("LEFT", 24, 0)
    empty:SetPoint("RIGHT", -24, 0)
    empty:SetJustifyH("CENTER")

    footnote = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footnote:SetPoint("BOTTOMLEFT", 14, 30)
    footnote:SetPoint("BOTTOMRIGHT", -14, 30)
    footnote:SetJustifyH("LEFT")

    local options = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    options:SetSize(96, 22)
    options:SetPoint("BOTTOMRIGHT", -8, 4)
    options:SetText("Options")
    options:SetScript("OnClick", function()
        window:Hide()
        ns.OpenOptions()
    end)

    for index, tab in ipairs(TABS) do
        local button = CreateFrame(
            "Button",
            "WorthItQuestsWindowTab" .. index,
            window,
            "PanelTabButtonTemplate"
        )
        button:SetID(index)
        button:SetText(tab.name)
        button:SetScript("OnClick", function(self)
            Select(self:GetID())
        end)
        if index == 1 then
            button:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12, 2)
        end
    end
    PanelTemplates_SetNumTabs(window, #TABS)
    PanelTemplates_SetTab(window, selected)

    window:SetScript("OnShow", function()
        Open.Refresh()
        Redraw()
    end)
end

function Window.Toggle()
    if not window then
        CreateWindow()
    end
    window:SetShown(not window:IsShown())
end

function Window.Show()
    if not window then
        CreateWindow()
    end
    window:Show()
end

-- The lists are built again when something changes while the window is
-- open, and the rows redrawn when rewards come in, once, a moment after
-- the last change.
local pending = false

local function QueueRedraw()
    if not pending then
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            Redraw()
        end)
    end
end

ns.Listen("QUESTS_CHANGED", Redraw)
ns.Listen("QUESTS_DIRTY", function()
    if window and window:IsShown() then
        Open.Refresh()
        Redraw()
    end
end)
ns.Listen("REWARDS_CHANGED", QueueRedraw)
ns.Listen("SETTINGS_CHANGED", QueueRedraw)

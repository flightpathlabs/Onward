local _, ns = ...

-- The few lines under a quest's rewards, in the quest window and the quest
-- log:
--
--   Leads on
--   4 more quests  ·  6,150 XP  ·  3g 20s
--   Attunement: Molten Core  ·  Class quest
--   [item] [item]   One of: [item] [item] [item]
--
-- Blizzard draws the quest page as a column of pieces, each anchored below
-- the last, with a spacer at the bottom that sets how far the page
-- scrolls. Onward's block goes in just above that spacer, and the spacer
-- moves down below it, so the page still scrolls to the end. The next
-- time Blizzard draws the page it puts the spacer back itself.

local Text = ns.Text

local GAP = 15
local LINE_GAP = 4
local ICON_SIZE = 30
local ICON_GAP = 4
-- More icons than this and the rest are only counted, so a long chain
-- doesn't push the page down by a screen.
local MAX_ICONS = 16

local blocks = {} -- the quest page frame -> its block

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
    -- Shift-click links the item and ctrl-click tries it on, as anywhere
    -- else in the game.
    local _, link = C_Item.GetItemInfo(self.itemID)
    if link then
        HandleModifiedItemClick(link)
    end
end

local function CreateItemButton(block)
    local button = CreateFrame("Button", nil, block)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button:RegisterForClicks("LeftButtonUp")

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- The same quality border the game puts round reward icons.
    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetTexture("Interface\\Common\\WhiteIconFrame")
    button.border:SetAllPoints()

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -1, 1)

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    button:SetScript("OnEnter", ItemOnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", ItemOnClick)
    return button
end

local function SetItem(button, item, stepName, isChoice)
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(item.id)
    button.itemID = item.id
    button.stepName = stepName
    button.isChoice = isChoice
    button.icon:SetTexture(icon or 134400) -- the question mark
    button.count:SetText((item.count or 1) > 1 and item.count or "")

    local quality = C_Item.GetItemQualityByID(item.id)
    local color = quality and quality >= Enum.ItemQuality.Uncommon and ITEM_QUALITY_COLORS[quality]
    if color then
        button.border:SetVertexColor(color.r, color.g, color.b)
        button.border:Show()
    else
        button.border:Hide()
    end
    button:Show()
end

local function TotalsOnEnter(self)
    local summary = self:GetParent().summary
    if not summary or #summary.steps == 0 then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    Text.FillSteps(GameTooltip, summary)
    GameTooltip:Show()
end

local function CreateBlock(parent)
    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(1, 1)

    block.header = block:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
    block.header:SetJustifyH("LEFT")

    -- The totals are a button so hovering them lists each step.
    block.totals = CreateFrame("Button", nil, block)
    block.totals.text = block.totals:CreateFontString(nil, "ARTWORK", "QuestFont")
    block.totals.text:SetPoint("TOPLEFT")
    block.totals.text:SetJustifyH("LEFT")
    block.totals:SetScript("OnEnter", TotalsOnEnter)
    block.totals:SetScript("OnLeave", GameTooltip_Hide)

    block.marks = block:CreateFontString(nil, "ARTWORK", "QuestFont")
    block.marks:SetJustifyH("LEFT")

    block.verdict = block:CreateFontString(nil, "ARTWORK", "QuestFont")
    block.verdict:SetJustifyH("LEFT")

    block.more = block:CreateFontString(nil, "ARTWORK", "QuestFont")

    block.buttons = {}
    block.labels = {}

    block.fade = block:CreateAnimationGroup()
    block.fade:SetToFinalAlpha(true)
    block.fadeIn = block.fade:CreateAnimation("Alpha")
    block.fadeIn:SetFromAlpha(0)
    block.fadeIn:SetToAlpha(1)
    return block
end

-- Takes the font and colour of Blizzard's own headers and text on this
-- page, which change with the page's background.
local function MatchQuestText(block)
    local header, body = QuestInfoDescriptionHeader, QuestInfoDescriptionText
    if header then
        block.header:SetFontObject(header:GetFontObject())
        block.header:SetTextColor(header:GetTextColor())
    end
    if body then
        local font = body:GetFontObject()
        local r, g, b = body:GetTextColor()
        for _, text in ipairs({ block.totals.text, block.marks, block.verdict, block.more }) do
            text:SetFontObject(font)
            text:SetTextColor(r, g, b)
        end
        for _, label in ipairs(block.labels) do
            label:SetFontObject(font)
            label:SetTextColor(r, g, b)
        end
    end
end

local function Label(block, index)
    local label = block.labels[index]
    if not label then
        label = block:CreateFontString(nil, "ARTWORK", "QuestFont")
        block.labels[index] = label
    end
    return label
end

-- Lays the item icons out in rows from the top offset y; returns the
-- offset below the last row.
local function LayOutItems(block, summary, width, y)
    local shown, labelsUsed = 0, 0
    local x = 0
    local rowHeight = ICON_SIZE + ICON_GAP
    local hidden = 0

    local function Place(item, stepName, isChoice)
        if shown >= MAX_ICONS then
            hidden = hidden + 1
            return
        end
        if x > 0 and x + ICON_SIZE > width then
            x = 0
            y = y - rowHeight
        end
        shown = shown + 1
        local button = block.buttons[shown] or CreateItemButton(block)
        block.buttons[shown] = button
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", x, y)
        SetItem(button, item, stepName, isChoice)
        x = x + ICON_SIZE + ICON_GAP
    end

    for _, item in ipairs(summary.items) do
        Place(item, item.step.name)
    end
    -- Each set of choices starts a row of its own, after "One of:".
    for _, group in ipairs(summary.choiceGroups) do
        if shown < MAX_ICONS then
            if x > 0 then
                x = 0
                y = y - rowHeight
            end
            labelsUsed = labelsUsed + 1
            local label = Label(block, labelsUsed)
            label:ClearAllPoints()
            label:SetPoint("LEFT", block, "TOPLEFT", 0, y - ICON_SIZE / 2)
            label:SetText("One of:")
            label:Show()
            x = label:GetStringWidth() + ICON_GAP * 2
        end
        for _, item in ipairs(group.items) do
            Place(item, group.step.name, true)
        end
    end

    for index = shown + 1, #block.buttons do
        block.buttons[index]:Hide()
    end
    for index = labelsUsed + 1, #block.labels do
        block.labels[index]:Hide()
    end

    if hidden > 0 then
        block.more:ClearAllPoints()
        block.more:SetPoint("LEFT", block, "TOPLEFT", x, y - ICON_SIZE / 2)
        block.more:SetText(("+%d more"):format(hidden))
        block.more:Show()
    else
        block.more:Hide()
    end

    if shown == 0 then
        return y
    end
    return y - ICON_SIZE
end

--- Draws the summary into the block. Returns false when there's nothing
--- to show with the current settings.
local function Fill(block, summary, width)
    local totals = Text.Totals(summary)
    local marks = ns.settings.marks and Text.Marks(summary.marks) or nil
    local verdict = Text.Verdict(summary, true)
    if not totals and not marks and not verdict then
        return false
    end

    block.summary = summary
    MatchQuestText(block)
    block:SetWidth(width)

    local y = 0
    block.header:ClearAllPoints()
    block.header:SetPoint("TOPLEFT", 0, y)
    block.header:SetText(totals and "Leads on" or "Of note")
    y = y - block.header:GetStringHeight() - LINE_GAP

    if totals then
        block.totals.text:SetWidth(width)
        block.totals.text:SetText(totals)
        local height = block.totals.text:GetStringHeight()
        block.totals:ClearAllPoints()
        block.totals:SetPoint("TOPLEFT", 0, y)
        block.totals:SetSize(math.min(width, block.totals.text:GetStringWidth() + 4), height)
        block.totals:Show()
        y = y - height - LINE_GAP
    else
        block.totals:Hide()
    end

    if verdict then
        block.verdict:ClearAllPoints()
        block.verdict:SetPoint("TOPLEFT", 0, y)
        block.verdict:SetWidth(width)
        block.verdict:SetText(verdict)
        block.verdict:Show()
        y = y - block.verdict:GetStringHeight() - LINE_GAP
    else
        block.verdict:Hide()
    end

    if marks then
        block.marks:ClearAllPoints()
        block.marks:SetPoint("TOPLEFT", 0, y)
        block.marks:SetWidth(width)
        block.marks:SetText(marks)
        block.marks:Show()
        y = y - block.marks:GetStringHeight() - LINE_GAP
    else
        block.marks:Hide()
    end

    if ns.settings.items and totals then
        y = LayOutItems(block, summary, width, y - 2)
    else
        LayOutItems(block, { items = {}, choiceGroups = {} }, width, y)
    end

    block:SetHeight(math.max(1, -y))
    return true
end

local function UpdateScroll(parent)
    local scroll = parent and parent:GetParent()
    if scroll and scroll.UpdateScrollChildRect then
        scroll:UpdateScrollChildRect()
    end
end

-- Puts the spacer back where Blizzard had it, if it's still hanging off
-- the block.
local function Hide(block)
    if not block or not block:IsShown() then
        return
    end
    block:Hide()
    local _, relativeTo = QuestInfoSpacerFrame:GetPoint(1)
    if relativeTo == block and block.spacerAnchor then
        local anchor = block.spacerAnchor
        QuestInfoSpacerFrame:ClearAllPoints()
        QuestInfoSpacerFrame:SetPoint("TOPLEFT", anchor[1], "BOTTOMLEFT", anchor[2], anchor[3])
    end
    UpdateScroll(block.page)
end

local function HasSpacer(template)
    local elements = template and template.elements
    if not elements then
        return false
    end
    for index = 1, #elements, 3 do
        if elements[index] == QuestInfo_ShowSpacer then
            return true
        end
    end
    return false
end

local function Enabled(template)
    if template.questLog then
        return ns.settings.questLog
    end
    return ns.settings.questFrame
end

-- Shows the block and hangs the spacer below it, while the spacer is still
-- on the block's page: the quest window and the quest log share one, and
-- it belongs to whichever Blizzard drew last.
local function Show(block)
    block:Show()
    if QuestInfoSpacerFrame:GetParent() == block.page then
        local anchor = block.spacerAnchor
        QuestInfoSpacerFrame:ClearAllPoints()
        QuestInfoSpacerFrame:SetPoint("TOPLEFT", block, "BOTTOMLEFT", anchor[2], anchor[3])
    end
    UpdateScroll(block.page)
end

-- Draws the block again for the quest it was placed for, after rewards or
-- chain data came in, or a setting changed.
local function Draw(block)
    local summary = Enabled(block.template) and ns.Chain.Build(block.questID)
    if not summary or not Fill(block, summary, block.width) then
        Hide(block)
        return
    end
    Show(block)
end

local function Place(template, page)
    if not ns.settings or not HasSpacer(template) then
        return
    end
    local block = blocks[page]

    local questID
    if template.questLog then
        questID = C_QuestLog.GetSelectedQuest()
    else
        questID = GetQuestID()
        -- The quest window's rewards, read before the chain is built so
        -- the marks can use them. The event that opened the window may not
        -- have reached Onward yet.
        ns.Learn.FromDialog()
    end

    local _, relativeTo, _, x, y = QuestInfoSpacerFrame:GetPoint(1)
    if not Enabled(template) or not questID or questID == 0 or not relativeTo then
        if block then
            block:Hide()
            block.questID = nil
        end
        return
    end

    block = block or CreateBlock(page)
    blocks[page] = block
    block.page = page
    block.template = template
    block.questID = questID
    block.width = (template.contentWidth or 285) - 10
    block.spacerAnchor = { relativeTo, x or 0, y or 0 }

    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, -GAP)

    local summary = ns.Chain.Build(questID)
    if not summary or not Fill(block, summary, block.width) then
        block:Hide()
        return
    end
    Show(block)
end

hooksecurefunc("QuestInfo_Display", function(template, page)
    local ok, message = pcall(Place, template, page)
    if not ok then
        geterrorhandler()(message)
    end
end)

-- While a quest's text writes itself out, Blizzard keeps the objectives
-- and rewards hidden and fades them in at the end. The block follows them,
-- without touching Blizzard's own list of what fades.
-- The block fades with an animation of its own rather than Blizzard's
-- shared fade list, which addon code shouldn't add to.
hooksecurefunc("QuestInfo_HideAlphaDependentText", function(page)
    local block = blocks[page]
    if block then
        block.fade:Stop()
        block:SetAlpha(0)
    end
end)

hooksecurefunc("QuestInfo_ShowAlphaDependentText", function(page)
    local block = blocks[page]
    if block then
        block.fade:Stop()
        block:SetAlpha(1)
    end
end)

hooksecurefunc("QuestInfo_FadeInAlphaDependentText", function(page, fadeTime)
    local block = blocks[page]
    if not block then
        return
    end
    block.fade:Stop()
    if block:IsShown() and fadeTime and fadeTime > 0 then
        block.fadeIn:SetDuration(fadeTime)
        block.fade:Play()
    else
        block:SetAlpha(1)
    end
end)

-- The server answers about rewards a moment after it's asked, and several
-- answers often come together, so the blocks redraw once after the last.
local redrawPending = false

-- Hidden blocks are drawn again too while their page is open: a quest
-- that seemed to lead nowhere may turn out to once the chain data is in.
local function RedrawAll()
    redrawPending = false
    for _, block in pairs(blocks) do
        if block.questID and block.page:IsVisible() then
            Draw(block)
        end
    end
end

local function QueueRedraw()
    if not redrawPending then
        redrawPending = true
        C_Timer.After(0.2, RedrawAll)
    end
end

ns.Listen("REWARDS_CHANGED", QueueRedraw)
ns.Listen("CHAINS_CHANGED", QueueRedraw)

ns.Listen("SETTINGS_CHANGED", RedrawAll)

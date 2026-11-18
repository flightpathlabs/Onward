local _, ns = ...

-- One line per quest on the tooltips of Questie's quest-giver icons:
--
--   Leads on: 4 more quests  ·  6,150 XP  ·  3g 20s  ·  Class quest
--
-- Questie's own tooltip already lists the next quests one by one when Shift
-- is held, each with its XP and money, so Onward adds only what that list
-- doesn't say: the total, the items and the marks.
--
-- Questie has no public hook for its map tooltips. It fills GameTooltip and
-- leaves the quests it listed on the tooltip (npcAndObjectOrder), with the
-- icon it belongs to (_owner), then calls Show. Onward reads those after
-- Show; if a Questie update changes them, the line just doesn't appear.

local Text = ns.Text

-- Lines at most, so a busy quest hub doesn't double the tooltip's height.
local MAX_LINES = 4

local adding = false
local lastLine -- the text of the last line Onward added, to spot a repeat Show

local function QuestieQuests(tooltip)
    local order = tooltip.npcAndObjectOrder
    local owner = tooltip:GetOwner()
    if type(order) ~= "table" or not owner then
        return nil
    end
    if owner ~= tooltip._owner and owner ~= tooltip._showOwner then
        return nil
    end

    local ids, seen = {}, {}
    for _, quests in pairs(order) do
        if type(quests) == "table" then
            for _, tip in pairs(quests) do
                local id = type(tip) == "table" and tip.questId
                if type(id) == "number" and not seen[id] then
                    seen[id] = true
                    table.insert(ids, id)
                end
            end
        end
    end
    table.sort(ids)
    return ids
end

local function LineFor(summary, title)
    local parts = {}
    local totals = Text.Totals(summary)
    if totals then
        local items = #summary.items + #summary.choiceGroups
        if ns.settings.items and items > 0 then
            totals = totals
                .. ("  ·  %s"):format(items == 1 and "1 item" or ("%d items"):format(items))
        end
        table.insert(parts, totals)
    end
    local marks = ns.settings.marks and Text.Marks(summary.marks)
    if marks then
        table.insert(parts, marks)
    end
    if #parts == 0 then
        return nil
    end
    local label = title and ("%s:"):format(title) or (totals and "Leads on:" or "Of note:")
    return NORMAL_FONT_COLOR:WrapTextInColorCode(label) .. " " .. table.concat(parts, "  ·  ")
end

local function LastLineText(tooltip)
    local count = tooltip:NumLines()
    local line = count > 0 and _G[tooltip:GetName() .. "TextLeft" .. count]
    return line and line:GetText()
end

local function AddLines(tooltip)
    if adding or not ns.settings or not ns.settings.mapTooltip then
        return
    end
    local ids = QuestieQuests(tooltip)
    if not ids or #ids == 0 then
        return
    end
    -- Something called Show again without Questie redrawing first: the
    -- lines are already there.
    if lastLine and LastLineText(tooltip) == lastLine then
        return
    end

    local lines = {}
    local extra = 0
    for _, id in ipairs(ids) do
        local summary = ns.Chain.Build(id)
        if summary then
            -- With one quest on the tooltip the line needs no name; with
            -- several each says whose it is.
            local title
            if #ids > 1 then
                local info = ns.Source.Quest(id)
                title = (info and info.name) or C_QuestLog.GetTitleForQuestID(id)
            end
            local line = LineFor(summary, title)
            if line then
                if #lines < MAX_LINES then
                    table.insert(lines, line)
                else
                    extra = extra + 1
                end
            end
        end
    end
    if #lines == 0 then
        return
    end
    if extra > 0 then
        table.insert(lines, GRAY_FONT_COLOR:WrapTextInColorCode(("and %d more"):format(extra)))
    end

    adding = true
    for _, line in ipairs(lines) do
        tooltip:AddLine(line, 1, 1, 1, true)
    end
    lastLine = LastLineText(tooltip)
    tooltip:Show()
    adding = false
end

hooksecurefunc(GameTooltip, "Show", function(tooltip)
    local ok, message = pcall(AddLines, tooltip)
    adding = false
    if not ok then
        geterrorhandler()(message)
    end
end)

GameTooltip:HookScript("OnHide", function()
    lastLine = nil
end)

local _, ns = ...

-- The words and figures Onward shows, shared by the quest window, the
-- quest log and the map tooltips so they always say the same thing.

local Text = {}
ns.Text = Text

local SEPARATOR = "  ·  "
local MARK_ICON_SIZE = 14
local WORTH_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

local function Number(value)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end
    return tostring(value)
end

---@param copper number
---@return string
function Text.Money(copper)
    return C_CurrencyInfo.GetCoinTextureString(math.floor(copper + 0.5))
end

---@param xp number
---@return string
function Text.XP(xp)
    return ("%s XP"):format(Number(xp))
end

local function QuestCount(count, fork)
    if fork then
        return count == 1 and "Opens 1 quest" or ("Opens %d quests"):format(count)
    end
    return count == 1 and "1 more quest" or ("%d more quests"):format(count)
end

--- "4 more quests  ·  6,150 XP  ·  3g 20s", or just the parts that apply.
---@param summary table
---@return string|nil
function Text.Totals(summary)
    local count = #summary.steps
    if count == 0 then
        return nil
    end
    local parts = { QuestCount(count, summary.fork) }
    if summary.xp > 0 then
        table.insert(parts, Text.XP(summary.xp))
    end
    if summary.money > 0 then
        table.insert(parts, Text.Money(summary.money))
    end
    return table.concat(parts, SEPARATOR)
end

local function Icon(icon)
    if not icon then
        return ""
    end
    return CreateTextureMarkup(icon, 64, 64, MARK_ICON_SIZE, MARK_ICON_SIZE, 0.07, 0.93, 0.07, 0.93)
        .. " "
end

--- "Worth doing" or "Safe to skip", with the reason when asked for and
--- when a mark doesn't already say the same, or nil.
---@param summary table
---@param withReason boolean|nil
---@return string|nil
function Text.Verdict(summary, withReason)
    if not ns.settings.verdict or not summary.verdict then
        return nil
    end
    local said = false
    for _, mark in ipairs(summary.marks or {}) do
        if summary.reasonKind and mark.kind == summary.reasonKind then
            said = ns.settings.marks
        end
    end
    local text = summary.verdict == "worth" and (WORTH_ICON .. " Worth doing") or "Safe to skip"
    if withReason and summary.reason and not said then
        text = ("%s: %s"):format(text, summary.reason)
    end
    return text
end

--- The marks on one line, each with its icon when it has one.
---@param marks table[]
---@return string|nil
function Text.Marks(marks)
    if not marks or #marks == 0 then
        return nil
    end
    local parts = {}
    for _, mark in ipairs(marks) do
        table.insert(parts, Icon(mark.icon) .. mark.text)
    end
    return table.concat(parts, SEPARATOR)
end

local function StepRewards(rewards)
    local parts = {}
    if rewards.xp and rewards.xp > 0 then
        table.insert(parts, Text.XP(rewards.xp))
    end
    if rewards.known then
        if (rewards.money or 0) > 0 then
            table.insert(parts, Text.Money(rewards.money))
        end
        local items = #rewards.items + (#rewards.choices > 0 and 1 or 0)
        if items > 0 then
            table.insert(parts, items == 1 and "1 item" or ("%d items"):format(items))
        end
    end
    return table.concat(parts, "  ")
end

local function StepName(step)
    local name = step.name or ("Quest %d"):format(step.id)
    if step.level and step.level > 0 then
        name = ("[%d] %s"):format(step.level, name)
    end
    return name
end

local function DifficultyColor(level)
    if level and level > 0 and GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(level)
        if color then
            return CreateColor(color.r, color.g, color.b)
        end
    end
    return HIGHLIGHT_FONT_COLOR
end

local function QuestName(id)
    local info = ns.Source.Quest(id)
    return (info and info.name) or C_QuestLog.GetTitleForQuestID(id) or ("Quest %d"):format(id)
end

--- Fills a tooltip with each step of the chain and what it gives.
---@param tooltip GameTooltip
---@param summary table
function Text.FillSteps(tooltip, summary)
    GameTooltip_SetTitle(tooltip, summary.fork and "Quests this opens" or "Where this leads")
    local verdict = Text.Verdict(summary, true)
    if verdict then
        GameTooltip_AddNormalLine(tooltip, verdict, true)
    end

    for _, step in ipairs(summary.steps) do
        local name = StepName(step)
        if step.inLog then
            name = name .. GRAY_FONT_COLOR:WrapTextInColorCode(" (in your log)")
        end
        GameTooltip_AddColoredDoubleLine(
            tooltip,
            name,
            StepRewards(step.rewards),
            DifficultyColor(step.level),
            HIGHLIGHT_FONT_COLOR
        )
        for _, id in ipairs(step.needs or {}) do
            GameTooltip_AddColoredLine(tooltip, "    Also needs " .. QuestName(id), GRAY_FONT_COLOR)
        end
    end

    if #summary.branches > 0 then
        GameTooltip_AddBlankLineToTooltip(tooltip)
        GameTooltip_AddNormalLine(tooltip, "Also opens:")
        for _, branch in ipairs(summary.branches) do
            GameTooltip_AddColoredLine(tooltip, "    " .. StepName({
                id = branch.id,
                name = branch.name,
                level = branch.level,
            }), DifficultyColor(branch.level))
        end
    end

    local notes = {}
    if summary.endsFor == "race" then
        table.insert(notes, "The chain goes on for other races.")
    elseif summary.endsFor == "class" then
        table.insert(notes, "The chain goes on for other classes.")
    end
    if summary.unknown > 0 then
        table.insert(
            notes,
            summary.unknown == 1 and "One quest's rewards aren't known yet."
                or ("%d quests' rewards aren't known yet."):format(summary.unknown)
        )
    end
    if ns.AtMaxLevel() then
        table.insert(
            notes,
            "At the level cap XP is paid as money. Onward adds it in once it has seen a hand-in."
        )
    elseif summary.xp > 0 then
        table.insert(notes, "XP is for your level now, before any bonus.")
    end
    if #notes > 0 then
        GameTooltip_AddBlankLineToTooltip(tooltip)
        for _, note in ipairs(notes) do
            GameTooltip_AddColoredLine(tooltip, note, GRAY_FONT_COLOR, true)
        end
    end
end

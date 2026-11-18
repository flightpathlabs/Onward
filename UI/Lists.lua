local _, ns = ...

-- A short note after each quest's name in the lists where you pick quests:
-- the quest log beside the map, a quest giver's chat window, and the older
-- greeting window some givers use.
--
--   The Defias Brotherhood  +6 ✓
--
-- "+6" is how many quests follow it. A tick means Onward thinks it's worth
-- doing, and a grey "skip" that it's safe to skip; the quest window and
-- the chain's tooltip say why.
--
-- The note is a text of Onward's own laid after the title, in the title's
-- font and colour. Blizzard's own text and layout aren't touched.

local Lists = {}
ns.Lists = Lists

local WORTH_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
local GAP = 6

-- button -> its note, and the title text and quest it was placed for, so
-- the notes can be redrawn when rewards or chain data come in.
local notes = setmetatable({}, { __mode = "k" })
local placed = setmetatable({}, { __mode = "k" })

-- quest ID -> its note (false for none). The quest log redraws its list on
-- every quest log update, often in a fight, so a note is worked out once
-- and kept until something that could change it happens.
local cache = {}

local function Forget()
    cache = {}
end

local function Build(questID)
    local summary = ns.Chain.Build(questID)
    if not summary then
        return nil
    end
    local count = #summary.steps
    local verdict = ns.settings.verdict and summary.verdict or nil
    local text = count > 0 and ("+%d"):format(count) or nil
    if verdict == "worth" then
        return text and (text .. " " .. WORTH_ICON) or WORTH_ICON
    elseif verdict == "skip" then
        return GRAY_FONT_COLOR:WrapTextInColorCode(text and (text .. " skip") or "skip")
    end
    return text
end

--- The note for one quest, or nil when there's nothing to say.
---@param questID number
---@return string|nil
function Lists.Note(questID)
    local note = cache[questID]
    if note == nil then
        note = Build(questID) or false
        cache[questID] = note
    end
    return note or nil
end

local function Width(text)
    if text.GetUnboundedStringWidth then
        return text:GetUnboundedStringWidth()
    end
    return text:GetStringWidth()
end

-- Puts the note after the title's text, or at the end of the title's line
-- when the title fills it.
local function Place(button, title, questID)
    placed[button] = { title = title, questID = questID }
    local note = notes[button]
    local text = questID and ns.settings and ns.settings.listCounts and Lists.Note(questID)
    if not text then
        if note then
            note:Hide()
        end
        return
    end
    if not note then
        note = button:CreateFontString(nil, "OVERLAY")
        notes[button] = note
    end
    note:SetFontObject(title:GetFontObject())
    note:SetTextColor(title:GetTextColor())
    note:SetText(text)

    -- Only where it fits on the title's own line: a long name that wraps
    -- has no known end to put it after, and laying it over the name, or
    -- over Blizzard's icons beside it, would be worse than leaving it out.
    note:ClearAllPoints()
    local room = title:GetWidth()
    local used = Width(title)
    local oneLine = not title.GetNumLines or title:GetNumLines() <= 1
    if not oneLine or (room > 0 and used + GAP + note:GetStringWidth() > room) then
        note:Hide()
        return
    end
    note:SetPoint("LEFT", title, "LEFT", used + GAP, 0)
    note:Show()
end

local function Safely(func, ...)
    local ok, message = pcall(func, ...)
    if not ok then
        geterrorhandler()(message)
    end
end

-- The quest log beside the map. Blizzard rebuilds the whole list in
-- QuestLogQuests_Update, so the notes are placed again each time.
local function UpdateQuestLog()
    if not QuestScrollFrame or not QuestScrollFrame.titleFramePool then
        return
    end
    for button in QuestScrollFrame.titleFramePool:EnumerateActive() do
        if button.Text and button.questID then
            Place(button, button.Text, button.questID)
        end
    end
end

-- A quest giver's chat window. Blizzard sets up each quest's row through
-- these two calls, by name, so the hooks see every row.
local function UpdateGossipButton(button, questInfo)
    local title = button.GetFontString and button:GetFontString()
    if title and type(questInfo) == "table" then
        Place(button, title, questInfo.questID)
    end
end

-- The older greeting window: a list of quests in progress, then ones on
-- offer, each a button with its index as its ID.
local function UpdateGreeting()
    local pool = QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool
    if not pool then
        return
    end
    for button in pool:EnumerateActive() do
        local questID
        if button.isActive == 1 then
            questID = GetActiveQuestID(button:GetID())
        else
            questID = select(5, GetAvailableQuestInfo(button:GetID()))
        end
        local title = button:GetFontString()
        if title then
            Place(button, title, questID)
        end
    end
end

hooksecurefunc("QuestLogQuests_Update", function()
    Safely(UpdateQuestLog)
end)

if GossipSharedAvailableQuestButtonMixin then
    hooksecurefunc(GossipSharedAvailableQuestButtonMixin, "Setup", function(button, questInfo)
        Safely(UpdateGossipButton, button, questInfo)
    end)
end
if GossipSharedActiveQuestButtonMixin then
    hooksecurefunc(GossipSharedActiveQuestButtonMixin, "Setup", function(button, questInfo)
        Safely(UpdateGossipButton, button, questInfo)
    end)
end

-- The greeting panel's XML names its OnShow function directly, so a hook
-- on the global only sees the calls made by name (when the quest log
-- changes while it's open). A script hook sees it open.
hooksecurefunc("QuestFrameGreetingPanel_OnShow", function()
    Safely(UpdateGreeting)
end)
if QuestFrameGreetingPanel then
    QuestFrameGreetingPanel:HookScript("OnShow", function()
        Safely(UpdateGreeting)
    end)
end

-- When rewards or chain data come in, or a setting changes, the notes on
-- screen catch up, once, a moment after the last change.
local pending = false

local function Refresh()
    pending = false
    for button, where in pairs(placed) do
        if button:IsVisible() then
            Safely(Place, button, where.title, where.questID)
        end
    end
end

local function QueueRefresh()
    if not pending then
        pending = true
        C_Timer.After(0.3, Refresh)
    end
end

local function Changed()
    Forget()
    QueueRefresh()
end

ns.Listen("REWARDS_CHANGED", Changed)
ns.Listen("CHAINS_CHANGED", Changed)
ns.Listen("SETTINGS_CHANGED", Changed)
ns.Listen("LEARNED_FORGOTTEN", Changed)
ns.OnEvent("QUEST_ACCEPTED", Changed)
ns.OnEvent("QUEST_REMOVED", Changed)
ns.OnEvent("PLAYER_LEVEL_UP", Changed)

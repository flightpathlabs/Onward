local _, ns = ...

-- What one quest gives: its XP at your level, its money, its items and the
-- items you choose one of, and any spell it teaches.
--
-- In order of trust:
--   1. what Worth It saw in the quest window or quest log (Quests/Learn.lua)
--   2. what the game says when asked about the quest by ID; for a quest in
--      your log that's always right, for one you haven't taken it depends
--      on whether the game has it cached, so the answer is checked first
--   3. nothing yet: the game is asked to load the quest, and the chain
--      redraws when it answers
--
-- XP is figured from the base XP in QuestieDB, which was measured on
-- Forever, and the game's usual cut for quests below your level.

local Rewards = {}
ns.Rewards = Rewards

-- Seconds before asking the game about the same quest again.
local RETRY_AFTER = 30

-- At most this many quests asked about in any few seconds. A long chain,
-- or a map tooltip over a busy quest hub, would otherwise ask about dozens
-- at once; the rest are asked about the next time the chain is drawn.
local REQUESTS_PER_WINDOW = 10
local REQUEST_WINDOW = 3

local requested = {} -- quest ID -> GetTime() of the last request
local windowStart, windowCount = 0, 0
local retryPending = false

-- Rewards read from the game this session but not saved, when the player
-- has turned learning off.
local session = {}

--- The XP a quest pays a character of playerLevel, from its base XP.
---
--- The full amount up to five levels above the quest, then 80, 60, 40 and
--- 20 percent, and a tenth after that. The game rounds the cut amounts to
--- tidy figures: to 5 up to 100 XP, then 10, 25 and 50.
---@param base number
---@param questLevel number
---@param playerLevel number
---@return number
function Rewards.ScaleXP(base, questLevel, playerLevel)
    local over = playerLevel - questLevel
    if over <= 5 then
        return base
    end
    local factor = over >= 10 and 0.1 or (10 - 2 * (over - 5)) / 10
    local xp = base * factor
    local step
    if xp <= 100 then
        step = 5
    elseif xp <= 500 then
        step = 10
    elseif xp <= 1000 then
        step = 25
    else
        step = 50
    end
    return math.floor(xp / step + 0.5) * step
end

local function Saved(id)
    return (ns.db and ns.db.quests[id]) or session[id]
end

--- Keeps what was read about a quest, in the saved data when learning is
--- on. A record from the quest window or log replaces one the game gave
--- by ID, never the other way round.
---@param id number
---@param record table
function Rewards.Store(id, record)
    local existing = Saved(id)
    if existing and existing.from ~= "client" and record.from == "client" then
        return
    end
    if ns.db and ns.settings and ns.settings.learn then
        ns.db.quests[id] = record
    else
        session[id] = record
    end
end

--- What the game itself says about a quest's rewards, read by quest ID.
--- Nil when it doesn't have them, or what it says can't be trusted.
---@param id number
---@return table|nil
local function ReadFromClient(id)
    local inLog = C_QuestLog.IsOnQuest(id)
    if not inLog and not (HaveQuestRewardData and HaveQuestRewardData(id)) then
        return nil
    end

    local record = {
        from = inLog and "log" or "client",
        money = GetQuestLogRewardMoney(id) or 0,
        items = {},
        choices = {},
        spells = {},
        seen = time(),
    }
    for index = 1, GetNumQuestLogRewards(id) or 0 do
        local _, _, count, _, _, itemID = GetQuestLogRewardInfo(index, id)
        if itemID then
            table.insert(record.items, { id = itemID, count = count or 1 })
        end
    end
    for index = 1, GetNumQuestLogChoices(id, false) or 0 do
        local _, _, count, _, _, itemID = GetQuestLogChoiceInfo(index, id)
        if itemID then
            table.insert(record.choices, { id = itemID, count = count or 1 })
        end
    end
    local spells = C_QuestInfoSystem.GetQuestRewardSpells(id)
    for _, spellID in ipairs(spells or {}) do
        if spellID and spellID > 0 then
            table.insert(record.spells, spellID)
        end
    end
    local xp = GetQuestLogRewardXP(id)
    if xp and xp > 0 then
        record.xp = xp
        record.xpLevel = ns.PlayerLevel()
    end

    -- For a quest that isn't in the log, an answer of nothing at all is
    -- more likely the game not knowing than a quest that pays nothing.
    if
        not inLog
        and record.money == 0
        and #record.items == 0
        and #record.choices == 0
        and not record.xp
    then
        return nil
    end
    return record
end

local function Request(id)
    local now = GetTime()
    local last = requested[id]
    if last and now - last < RETRY_AFTER then
        return
    end
    if now - windowStart > REQUEST_WINDOW then
        windowStart, windowCount = now, 0
    end
    if windowCount >= REQUESTS_PER_WINDOW then
        -- Come back once the window is over, so the quests left out are
        -- asked about without the player having to reopen anything.
        if not retryPending then
            retryPending = true
            C_Timer.After(windowStart + REQUEST_WINDOW - now + 0.1, function()
                retryPending = false
                ns.Send("REWARDS_CHANGED")
            end)
        end
        return
    end
    windowCount = windowCount + 1
    requested[id] = now
    C_QuestLog.RequestLoadQuestByID(id)
    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        pcall(C_TaskQuest.RequestPreloadRewardData, id)
    end
end

ns.OnEvent("QUEST_DATA_LOAD_RESULT", function(questID, success)
    if requested[questID] then
        if success then
            ns.Send("REWARDS_CHANGED", questID)
        end
    end
end)

local function XPFor(id, record)
    if ns.AtMaxLevel() then
        return 0
    end
    local questLevel, base = ns.Source.BaseXP(id)
    if base then
        return Rewards.ScaleXP(base, questLevel, ns.PlayerLevel())
    end
    -- XP the game showed is only good for the level it was shown at.
    if record and record.xp and record.xpLevel == ns.PlayerLevel() then
        return record.xp
    end
    if C_QuestLog.IsOnQuest(id) then
        local xp = GetQuestLogRewardXP(id)
        if xp and xp > 0 then
            return xp
        end
    end
    return nil
end

--- The quest's XP for the character now, from what Worth It already has,
--- without asking the server anything.
---@param id number
---@return number|nil
function Rewards.XP(id)
    return XPFor(id, Saved(id))
end

--- Everything Worth It knows about what a quest gives.
---
--- known is false when the item and money rewards aren't known yet, and
--- money then is nil. At the level cap, money is what a hand-in paid if
--- Worth It has seen one, which includes what the XP turned into
--- (paidAtMax is then true).
---@param id number
---@return table
function Rewards.Get(id)
    local record = Saved(id)
    if not record or record.from == "client" then
        local fresh = ReadFromClient(id)
        if fresh then
            Rewards.Store(id, fresh)
            record = Saved(id)
        elseif not record then
            Request(id)
        end
    end

    local result = {
        known = record ~= nil,
        xp = XPFor(id, record),
        items = record and record.items or {},
        choices = record and record.choices or {},
        spells = record and record.spells or {},
    }
    if record then
        result.money = record.money or 0
    end
    local paid = ns.db and ns.db.paid[id]
    if paid and ns.AtMaxLevel() then
        result.money = paid
        result.paidAtMax = true
    end
    return result
end

-- Forgetting what was learned forgets this session's reads too, so every
-- quest is read afresh.
ns.Listen("LEARNED_FORGOTTEN", function()
    session = {}
    requested = {}
end)

local _, ns = ...

-- Learning from what the player sees, so the data gets better with play:
--
--   * the rewards in the quest window, read the moment it opens
--   * what a hand-in actually paid at the level cap, where XP turns into
--     money and nothing else says how much
--   * which quest the game offers straight after a hand-in, from the same
--     person, which is how the game itself hands out the next step of a
--     chain
--
-- What the player saw always beats the data.

local Learn = {}
ns.Learn = Learn

-- The game offers the next step of a chain the moment the last one is
-- handed in. Anything opened later than this is the player browsing.
local OFFER_WINDOW = 3

local lastHandIn -- { id, npc, at }
local completingNPC

local function ItemFromDialog(kind, index)
    local _, _, count, _, _, itemID = GetQuestItemInfo(kind, index)
    if not itemID then
        local link = GetQuestItemLink(kind, index)
        itemID = link and C_Item.GetItemInfoInstant(link)
    end
    if itemID then
        return { id = itemID, count = count or 1 }
    end
    return nil
end

--- Reads the rewards of the quest in the open quest window. Only call it
--- while the window shows a quest's details or its reward page; on the
--- "progress" page the game reports no rewards at all.
---@return number|nil questID
function Learn.FromDialog()
    local id = GetQuestID()
    if not id or id == 0 then
        return nil
    end

    local record = {
        from = "dialog",
        money = GetRewardMoney() or 0,
        items = {},
        choices = {},
        spells = {},
        seen = time(),
    }
    for index = 1, GetNumQuestRewards() or 0 do
        local item = ItemFromDialog("reward", index)
        if item then
            table.insert(record.items, item)
        end
    end
    for index = 1, GetNumQuestChoices() or 0 do
        local item = ItemFromDialog("choice", index)
        if item then
            table.insert(record.choices, item)
        end
    end
    for _, spellID in ipairs(C_QuestInfoSystem.GetQuestRewardSpells(id) or {}) do
        if spellID and spellID > 0 then
            table.insert(record.spells, spellID)
        end
    end
    local xp = GetRewardXP()
    if xp and xp > 0 then
        record.xp = xp
        record.xpLevel = ns.PlayerLevel()
    end

    ns.Rewards.Store(id, record)
    return id
end

-- Whether the data already says "to" comes after "from", so there's
-- nothing to learn.
local function AlreadyLinked(from, to)
    local info = ns.Source.Quest(from)
    if info and (info.next == to or info.breadcrumbFor == to) then
        return true
    end
    local target = ns.Source.Quest(to)
    if target then
        for _, list in ipairs({ target.preSingle or {}, target.preGroup or {} }) do
            for _, prerequisite in ipairs(list) do
                if math.abs(prerequisite) == from then
                    return true
                end
            end
        end
    end
    return false
end

ns.OnEvent("QUEST_DETAIL", function()
    local id = Learn.FromDialog()
    if not id or not lastHandIn or not ns.settings.learn then
        return
    end
    local offered = GetTime() - lastHandIn.at <= OFFER_WINDOW
        and UnitGUID("npc") == lastHandIn.npc
        and id ~= lastHandIn.id
    if offered and not AlreadyLinked(lastHandIn.id, id) then
        ns.db.links[lastHandIn.id] = id
        ns.Send("CHAINS_CHANGED")
    end
    lastHandIn = nil
end)

ns.OnEvent("QUEST_COMPLETE", function()
    Learn.FromDialog()
    completingNPC = UnitGUID("npc")
end)

ns.OnEvent("QUEST_TURNED_IN", function(questID, _, moneyReward)
    lastHandIn = { id = questID, npc = completingNPC, at = GetTime() }
    completingNPC = nil
    -- At the cap the hand-in pays the quest's money and its XP as money,
    -- in one sum. Below it, the money is already known from the window.
    if ns.AtMaxLevel() and moneyReward and moneyReward > 0 and ns.settings.learn then
        ns.db.paid[questID] = moneyReward
    end
    ns.Send("CHAINS_CHANGED")
end)

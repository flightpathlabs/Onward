local _, ns = ...

-- Two commands for testing, which print to chat:
--
--   /worth probe [questID]  what the game and QuestieDB say about a quest,
--                            then the same reads again once the game has
--                            been asked to load it
--   /worth chain [questID]  the chain Worth It builds for a quest
--
-- Without an ID they use the quest in the open quest window, else the one
-- selected in the quest log. Kept in the addon so a player reporting a
-- wrong chain can paste what Worth It saw.

local Probe = {}
ns.Probe = Probe

-- Seconds to wait for the game to answer a load request.
local WAIT = 5

local function Say(text, ...)
    print(("|cffffd100Worth It|r %s"):format(text:format(...)))
end

local function Value(value)
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

local function CurrentQuest(id)
    if id then
        return id
    end
    local fromWindow = GetQuestID()
    if fromWindow and fromWindow ~= 0 and QuestFrame and QuestFrame:IsShown() then
        return fromWindow
    end
    local selected = C_QuestLog.GetSelectedQuest()
    if selected and selected ~= 0 then
        return selected
    end
    return nil
end

local function ReadRewards(id, when)
    local hasData = HaveQuestRewardData and HaveQuestRewardData(id)
    Say(
        "%s: reward data %s, money %s, xp %s, items %s, choices %s",
        when,
        Value(hasData),
        Value(GetQuestLogRewardMoney(id)),
        Value(GetQuestLogRewardXP(id)),
        Value(GetNumQuestLogRewards(id)),
        Value(GetNumQuestLogChoices(id, false))
    )
    local name, _, count, _, _, itemID = GetQuestLogRewardInfo(1, id)
    if name or itemID then
        Say("  first item: %s x%s (item %s)", Value(name), Value(count), Value(itemID))
    end
    local choice, _, _, _, _, choiceID = GetQuestLogChoiceInfo(1, id)
    if choice or choiceID then
        Say("  first choice: %s (item %s)", Value(choice), Value(choiceID))
    end
    local spells = C_QuestInfoSystem.GetQuestRewardSpells(id)
    if spells and #spells > 0 then
        Say("  spells: %s", table.concat(spells, ", "))
    end
end

local waiter = CreateFrame("Frame")
local waitingFor

local function FinishWait(id, how)
    if waitingFor ~= id then
        return
    end
    waitingFor = nil
    waiter:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
    ReadRewards(id, how)
end

waiter:SetScript("OnEvent", function(_, _, questID, success)
    if questID == waitingFor then
        FinishWait(questID, ("after loading (%s)"):format(success and "loaded" or "failed"))
    end
end)

---@param id number|nil
function Probe.Run(id)
    id = CurrentQuest(id)
    local version, build, _, interface = GetBuildInfo()
    Say(
        "client %s (%s), interface %s, level %d of %s",
        version,
        build,
        interface,
        ns.PlayerLevel(),
        Value(GetMaxPlayerLevel and GetMaxPlayerLevel())
    )

    local lib = _G.LibQuestieDB
    Say(
        "QuestieDB %s, contract %s, read mode %s, follower index %s",
        ns.Source.Status(),
        Value(lib and lib.contractVersion),
        Value(lib and lib.readMode),
        ns.Source.IndexReady() and "ready" or "not ready"
    )
    local questie = _G.Questie
    Say(
        "Questie %s",
        type(questie) == "table" and questie.API and (questie.API.isReady and "ready" or "starting")
            or "not loaded"
    )

    if not id then
        Say("No quest: open one, select one in the quest log, or give an ID.")
        return
    end

    Say(
        "quest %d: %s, in log %s, done %s",
        id,
        Value(C_QuestLog.GetTitleForQuestID(id)),
        Value(C_QuestLog.IsOnQuest(id)),
        Value(C_QuestLog.IsQuestFlaggedCompleted(id))
    )
    local questLevel, baseXP = ns.Source.BaseXP(id)
    Say("  base XP %s at quest level %s", Value(baseXP), Value(questLevel))

    -- Whether the game says which professions the character has: the
    -- quest's own, else Cooking (185) and Blacksmithing (164).
    local info = ns.Source.Quest(id)
    for _, skillID in ipairs(info and info.skill and { info.skill } or { 185, 164 }) do
        local ok, skill = pcall(C_SkillInfo.GetSkillLineInfoByID, skillID)
        Say(
            "  skill %d: %s",
            skillID,
            ok
                    and type(skill) == "table"
                    and ("%s, rank %s"):format(Value(skill.name), Value(skill.rank))
                or Value(ok and skill)
        )
    end

    local classification = C_QuestInfoSystem.GetQuestClassification(id)
    Say("  classification %s", Value(classification))
    local line = C_QuestLine.GetQuestLineInfo(id)
    Say(
        "  quest line %s",
        line and ("%s (%d)"):format(line.questLineName, line.questLineID) or "none"
    )
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        Say("  quest lines on this map: %d", #(C_QuestLine.GetAvailableQuestLines(mapID) or {}))
    end

    ReadRewards(id, "now")

    local started = debugprofilestop()
    local summary = ns.Chain.Build(id)
    Say(
        "  chain built in %.1f ms: %s",
        debugprofilestop() - started,
        summary and ("%d steps"):format(#summary.steps) or "nothing to show"
    )

    waitingFor = id
    waiter:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    C_QuestLog.RequestLoadQuestByID(id)
    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        pcall(C_TaskQuest.RequestPreloadRewardData, id)
    end
    C_Timer.After(WAIT, function()
        FinishWait(id, ("after %d seconds with no answer"):format(WAIT))
    end)
end

---@param id number|nil
function Probe.Chain(id)
    id = CurrentQuest(id)
    if not id then
        Say("No quest: open one, select one in the quest log, or give an ID.")
        return
    end
    local summary = ns.Chain.Build(id)
    if not summary then
        Say("quest %d leads nowhere Worth It knows of.", id)
        return
    end
    Say("quest %d: %s", id, ns.Text.Totals(summary) or "no further quests")
    for index, step in ipairs(summary.steps) do
        local rewards = step.rewards
        Say(
            "  %d. [%s] %s (%d): xp %s, money %s, %d items, %d choices%s",
            index,
            Value(step.level),
            Value(step.name),
            step.id,
            Value(rewards.xp),
            rewards.known and Value(rewards.money) or "unknown",
            #rewards.items,
            #rewards.choices,
            step.inLog and ", in log" or ""
        )
    end
    for _, branch in ipairs(summary.branches) do
        Say("  also opens: %s (%d)", Value(branch.name), branch.id)
    end
    for _, mark in ipairs(summary.marks) do
        Say("  mark: %s", mark.text)
    end
    if summary.endsFor then
        Say("  goes on for other %s", summary.endsFor == "race" and "races" or "classes")
    end
end

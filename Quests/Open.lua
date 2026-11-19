local _, ns = ...

-- Which quests the character could pick up right now, where to find their
-- givers, and the three lists the Onward window shows:
--
--   dropped  quests the character abandoned and could take again
--   missed   quests below their level they never did, whose chains still
--            lead to quests at their level or to something that matters
--   seek     chains they can start now, best first
--
-- "Could pick up" is Questie's own judgement when Questie is loaded
-- (QuestieDB.IsDoable: finished, hidden, race, class, prerequisites,
-- professions, exclusive quests, breadcrumbs), plus the level check Questie
-- makes separately. Without Questie, Onward checks what it can itself.
--
-- Abandoned quests come from Questie's journey, which Questie keeps for
-- each character, and from Onward's own record from now on. Quests dropped
-- before either was installed can't be known; the window says so.

local Open = {}
ns.Open = Open

local Source = ns.Source

-- Quests looked at per frame while the lists are built, so opening the
-- window doesn't stall the game.
local SCAN_BATCH = 200

-- Rows kept in each list.
local MAX_ROWS = 40

-- How far above the character a chain may start and still be suggested:
-- further than this and its quests are red, too hard to go and seek out.
local SEEK_ABOVE = 4

-- A quest that leaves the log without being handed in within this many
-- seconds was abandoned (or failed and dropped). QUEST_REMOVED can come
-- just before QUEST_TURNED_IN, so the hand-in gets a moment to arrive.
local ABANDON_WAIT = 1.5

local function Done(id)
    return C_QuestLog.IsQuestFlaggedCompleted(id)
end

local function Lib()
    local lib = _G.LibQuestieDB
    return Source.Available() and lib or nil
end

local function Read(entity, field, id)
    local lib = Lib()
    local reader = lib and lib[entity] and lib[entity][field]
    if type(reader) ~= "function" then
        return nil
    end
    local ok, value = pcall(reader, id)
    return ok and value or nil
end

-- Questie's modules, read where Questie keeps them. Nil without Questie, or
-- if a Questie update moves them.
local function QuestieModule(name)
    local loader = _G.QuestieLoader
    local modules = type(loader) == "table" and loader._modules
    local module = type(modules) == "table" and modules[name]
    return type(module) == "table" and module or nil
end

local function PlayerFaction()
    local faction = UnitFactionGroup("player")
    return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

-- Whether an NPC would talk to this character, or would as far as Onward
-- can tell.
local function FriendlyNpc(npc)
    local friendly = Read("Npc", "friendlyToFaction", npc)
    local faction = PlayerFaction()
    return type(friendly) ~= "string" or not faction or friendly:find(faction, 1, true) ~= nil
end

-- Whether the people who give the quest would talk to this character. Some
-- quests carry no race mask and are only kept to one side by who offers
-- them.
local function GiverFriendly(id)
    local starters = Read("Quest", "startedBy", id)
    local npcs = type(starters) == "table" and starters[1]
    if type(npcs) ~= "table" or #npcs == 0 then
        return true
    end
    for _, npc in ipairs(npcs) do
        if FriendlyNpc(npc) then
            return true
        end
    end
    return false
end

local function PrerequisitesDone(info)
    if info.preSingle and #info.preSingle > 0 then
        local any = false
        for _, id in ipairs(info.preSingle) do
            if Done(math.abs(id)) then
                any = true
                break
            end
        end
        if not any then
            return false
        end
    end
    for _, id in ipairs(info.preGroup or {}) do
        if not Done(math.abs(id)) then
            return false
        end
    end
    return true
end

local function ShutOut(info)
    for _, other in ipairs(info.exclusive or {}) do
        if other ~= info.id and (Done(other) or C_QuestLog.IsOnQuest(other)) then
            return true
        end
    end
    return false
end

--- Whether the character could pick the quest up now.
---@param id number
---@return boolean
function Open.CanTake(id)
    if Done(id) or C_QuestLog.IsOnQuest(id) then
        return false
    end
    local info = Source.Quest(id)
    if not info then
        return false
    end
    local required = info.requiredLevel or info.level or 0
    if required > ns.PlayerLevel() then
        return false
    end
    if Source.IsRepeatable(info) or not GiverFriendly(id) then
        return false
    end

    local questieDB = QuestieModule("QuestieDB")
    if questieDB and type(questieDB.IsDoable) == "function" then
        local ok, doable = pcall(questieDB.IsDoable, id)
        if ok then
            return doable == true
        end
    end

    if not Source.CanTake(info) then
        return false
    end
    return PrerequisitesDone(info) and not ShutOut(info)
end

--- Where the quest's giver is: their name, the zone's name, and a map and
--- spot for a waypoint when Onward can work them out.
---@param id number
---@return table|nil  { name, zone, mapID, x, y }  x and y from 0 to 1
function Open.Giver(id)
    local starters = Read("Quest", "startedBy", id)
    if type(starters) ~= "table" then
        return nil
    end

    local kinds = { { "Npc", starters[1] }, { "Object", starters[2] } }
    for _, kind in ipairs(kinds) do
        local entity, list = kind[1], kind[2]
        for _, giverID in ipairs(type(list) == "table" and list or {}) do
            local spawns = Read(entity, "spawns", giverID)
            local friendly = entity ~= "Npc" or FriendlyNpc(giverID)
            if friendly and type(spawns) == "table" and next(spawns) then
                local areaID = entity == "Npc" and Read("Npc", "zoneID", giverID) or nil
                if not (areaID and spawns[areaID]) then
                    areaID = next(spawns)
                end
                local spot = areaID and spawns[areaID] and spawns[areaID][1]
                local giver = {
                    name = Read(entity, "name", giverID),
                    zone = areaID and C_Map.GetAreaInfo(areaID) or nil,
                }
                local zoneDB = QuestieModule("ZoneDB")
                if spot and spot[1] and spot[1] >= 0 and zoneDB and zoneDB.GetUiMapIdByAreaId then
                    local ok, mapID = pcall(zoneDB.GetUiMapIdByAreaId, zoneDB, areaID)
                    if ok and mapID and mapID > 0 then
                        giver.mapID, giver.x, giver.y = mapID, spot[1] / 100, spot[2] / 100
                    end
                end
                return giver
            end
        end
    end

    local items = starters[3]
    if type(items) == "table" and items[1] then
        return { name = C_Item.GetItemNameByID(items[1]), fromItem = true }
    end
    return nil
end

-- Abandoned quests --------------------------------------------------------------

local turnedIn = {}

local function Forgive(questID)
    local me = ns.Me()
    if me then
        me.abandoned[questID] = nil
    end
end

ns.OnEvent("QUEST_TURNED_IN", function(questID)
    turnedIn[questID] = GetTime()
    Forgive(questID)
end)

ns.OnEvent("QUEST_ACCEPTED", Forgive)

ns.OnEvent("QUEST_REMOVED", function(questID)
    C_Timer.After(ABANDON_WAIT, function()
        local handedIn = turnedIn[questID] and GetTime() - turnedIn[questID] < ABANDON_WAIT * 4
        turnedIn[questID] = nil
        if handedIn or Done(questID) or C_QuestLog.IsOnQuest(questID) then
            return
        end
        local me = ns.Me()
        if me then
            me.abandoned[questID] = time()
        end
        Open.MarkDirty()
    end)
end)

-- Questie's journey: every quest event for this character, abandons
-- included, since Questie was installed. Only an abandon with nothing
-- after it counts: a quest taken again or handed in since isn't dropped.
local function QuestieAbandons()
    local questie = _G.Questie
    local char = type(questie) == "table" and type(questie.db) == "table" and questie.db.char
    local journey = type(char) == "table" and char.journey
    local found = {}
    if type(journey) ~= "table" then
        return found
    end
    for _, entry in ipairs(journey) do
        if type(entry) == "table" and entry.Event == "Quest" and type(entry.Quest) == "number" then
            if entry.SubType == "Abandon" then
                found[entry.Quest] = entry.Timestamp or 0
            elseif entry.SubType == "Accept" or entry.SubType == "Complete" then
                found[entry.Quest] = nil
            end
        end
    end
    return found
end

--- Every quest this character is known to have abandoned, with when.
---@return table<number, number>
function Open.Abandoned()
    local all = QuestieAbandons()
    local me = ns.Me()
    for id, at in pairs(me and me.abandoned or {}) do
        all[id] = math.max(all[id] or 0, at)
    end
    return all
end

---@return boolean
function Open.HasQuestieJourney()
    local questie = _G.Questie
    return type(questie) == "table"
        and type(questie.db) == "table"
        and type(questie.db.char) == "table"
        and type(questie.db.char.journey) == "table"
end

-- The lists ------------------------------------------------------------------------

-- A chain's worth, for ranking: its XP as a share of a level, with a level's
-- worth added for an attunement, key or class quest, and a little for each
-- step.
local function Weigh(rootID, summary)
    local xp = ns.Rewards.XP(rootID) or 0
    for _, step in ipairs(summary.steps) do
        xp = xp + (step.rewards.xp or 0)
    end
    local needed = UnitXPMax("player")
    local share = (needed and needed > 0 and not ns.AtMaxLevel()) and xp / needed or 0
    return share + (summary.important and 1 or 0) + 0.05 * #summary.steps
end

-- An attunement, key or class quest anywhere in the chain, the quest's own
-- included, without asking the server anything.
local function Important(rootID, summary)
    local ids = { rootID }
    for _, step in ipairs(summary.steps) do
        table.insert(ids, step.id)
    end
    for _, id in ipairs(ids) do
        local opens = ns.ATTUNEMENTS[id]
        if opens then
            return opens.key and ("The %s key"):format(opens.place)
                or ("The %s attunement"):format(opens.place)
        end
        local info = Source.Quest(id)
        if info and Source.IsClassQuest(info) then
            return "A class quest"
        end
    end
    return nil
end

local function Grey(level)
    return ns.Chain.IsGrey(level)
end

local function LeadsToYourLevel(summary)
    for _, step in ipairs(summary.steps) do
        if step.level and step.level > 0 and not Grey(step.level) then
            return true
        end
    end
    return false
end

local lists
local scanning = false
local dirty = true

-- Something happened that could change the lists. The window builds them
-- again when it next shows, or now if it is open.
local function MarkDirty()
    dirty = true
    ns.Send("QUESTS_DIRTY")
end

---@return table|nil  { dropped, missed, seek }, each a list of rows
function Open.Lists()
    return lists
end

---@return boolean
function Open.Scanning()
    return scanning
end

local function Entry(id, info, summary)
    return {
        id = id,
        name = info.name,
        level = info.level,
        count = #summary.steps,
        important = summary.important,
        score = Weigh(id, summary),
        steps = summary.steps,
    }
end

-- A quest that is a later step of another row's chain is part of that row,
-- not a row of its own.
local function WithoutLaterSteps(list)
    local later = {}
    for _, entry in ipairs(list) do
        for _, step in ipairs(entry.steps) do
            later[step.id] = true
        end
    end
    local kept = {}
    for _, entry in ipairs(list) do
        if not later[entry.id] then
            table.insert(kept, entry)
        end
    end
    return kept
end

local function ByScore(a, b)
    if a.score ~= b.score then
        return a.score > b.score
    end
    return a.id < b.id
end

local function Trim(list)
    while #list > MAX_ROWS do
        table.remove(list)
    end
end

--- Builds the lists again if anything could have changed them, a batch of
--- quests a frame, and sends "QUESTS_CHANGED" when they're ready.
function Open.Refresh()
    if scanning or not dirty then
        return
    end
    local lib = Lib()
    if not lib or type(lib.Quest.GetAllIds) ~= "function" then
        lists = { dropped = {}, missed = {}, seek = {} }
        ns.Send("QUESTS_CHANGED")
        return
    end
    local ok, ids = pcall(lib.Quest.GetAllIds)
    if not ok or type(ids) ~= "table" then
        return
    end

    scanning = true
    dirty = false
    local abandoned = Open.Abandoned()
    local found = { dropped = {}, missed = {}, seek = {} }
    local position = 1

    local function Look(id)
        if not Open.CanTake(id) then
            return
        end
        local info = Source.Quest(id)
        local summary = ns.Chain.Build(id, true)
        if not info or not summary then
            return
        end
        summary.important = Important(id, summary)
        local entry = Entry(id, info, summary)

        if abandoned[id] then
            entry.abandonedAt = abandoned[id]
            table.insert(found.dropped, entry)
        elseif Grey(info.level) then
            if summary.important or LeadsToYourLevel(summary) then
                table.insert(found.missed, entry)
            end
        elseif
            (#summary.steps >= 2 or summary.important)
            and (info.level or 0) <= ns.PlayerLevel() + SEEK_ABOVE
        then
            table.insert(found.seek, entry)
        end
    end

    local function Step()
        local last = math.min(position + SCAN_BATCH - 1, #ids)
        for index = position, last do
            local done, message = pcall(Look, ids[index])
            if not done then
                geterrorhandler()(message)
            end
        end
        position = last + 1
        if position <= #ids then
            C_Timer.After(0, Step)
            return
        end

        found.missed = WithoutLaterSteps(found.missed)
        found.seek = WithoutLaterSteps(found.seek)
        table.sort(found.dropped, function(a, b)
            return a.abandonedAt > b.abandonedAt
        end)
        table.sort(found.missed, ByScore)
        table.sort(found.seek, ByScore)
        Trim(found.dropped)
        Trim(found.missed)
        Trim(found.seek)
        lists = found
        scanning = false
        ns.Send("QUESTS_CHANGED")
        if dirty then
            ns.Send("QUESTS_DIRTY")
        end
    end
    Step()
end

Open.MarkDirty = MarkDirty

ns.OnEvent("QUEST_TURNED_IN", MarkDirty)
ns.OnEvent("QUEST_ACCEPTED", MarkDirty)
ns.OnEvent("QUEST_REMOVED", MarkDirty)
-- UnitLevel still gives the old level while PLAYER_LEVEL_UP is handed out.
ns.OnEvent("PLAYER_LEVEL_UP", function()
    C_Timer.After(1, MarkDirty)
end)
-- Skill lines change with every weapon skill-up in a fight; only learning
-- or dropping a profession matters here, and that changes the line count.
local skillLines
ns.OnEvent("SKILL_LINES_CHANGED", function()
    local count = C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetNumSkillLines()
    if count ~= skillLines then
        skillLines = count
        MarkDirty()
    end
end)
ns.Listen("CHAINS_CHANGED", MarkDirty)

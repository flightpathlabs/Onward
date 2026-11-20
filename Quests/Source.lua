local _, ns = ...

-- Where the chains come from: QuestieDB, read through its public API while
-- the game runs. Nothing from it is copied into Worth Doing.
--
-- QuestieDB ships with Questie. Without it Worth Doing still knows the links it
-- has seen for itself (see Quests/Learn.lua), but little else, and the
-- settings page says so.

local Source = {}
ns.Source = Source

-- The QuestieDB contract Worth Doing was written against. RequireContract
-- accepts any release that still supports it.
local CONTRACT = 4

-- How many quests the follower index reads per frame while it's built.
local INDEX_BATCH = 250

local lib -- LibQuestieDB once checked, false if it can't be used
local cache = {}

-- quest ID -> the quests that list it as a prerequisite. QuestieDB only
-- links forward through nextQuestInChain, and most classic chains are
-- written the other way round, so this is how most of them are found.
local followers = {}
local indexState = "none" -- "none", "building" or "ready"

local function Library()
    if lib == nil then
        local candidate = _G.LibQuestieDB
        local usable = type(candidate) == "table"
            and type(candidate.RequireContract) == "function"
            and type(candidate.Quest) == "table"
            and candidate.RequireContract(CONTRACT)
        lib = usable and candidate or false
    end
    return lib or nil
end

--- "ready", "missing" (no QuestieDB) or "old" (a QuestieDB that doesn't
--- support the contract Worth Doing needs).
---@return string
function Source.Status()
    if Library() then
        return "ready"
    end
    return _G.LibQuestieDB and "old" or "missing"
end

---@return boolean
function Source.Available()
    return Library() ~= nil
end

local function Read(id, field)
    local reader = lib and lib.Quest[field]
    if type(reader) ~= "function" then
        return nil
    end
    local ok, value = pcall(reader, id)
    if ok then
        return value
    end
    return nil
end

-- QuestieDB marks "no next quest" with 0 as well as nil.
local function QuestID(value)
    if type(value) == "number" and value > 0 then
        return value
    end
    return nil
end

local function List(value)
    if type(value) == "table" then
        return value
    end
    return nil
end

--- What Worth Doing needs to know about a quest, or nil for one QuestieDB
--- doesn't have.
---@param id number
---@return table|nil
function Source.Quest(id)
    if not id or not Library() then
        return nil
    end
    local info = cache[id]
    if info ~= nil then
        return info or nil
    end

    local exists = lib.Quest.Exists
    if type(exists) == "function" and not exists(id) then
        cache[id] = false
        return nil
    end

    local skill = List(Read(id, "requiredSkill"))
    info = {
        id = id,
        name = Read(id, "name"),
        level = Read(id, "questLevel"),
        requiredLevel = Read(id, "requiredLevel"),
        races = Read(id, "requiredRaces"),
        classes = Read(id, "requiredClasses"),
        skill = skill and skill[1] or nil,
        next = QuestID(Read(id, "nextQuestInChain")),
        preGroup = List(Read(id, "preQuestGroup")),
        preSingle = List(Read(id, "preQuestSingle")),
        exclusive = List(Read(id, "exclusiveTo")),
        breadcrumbFor = QuestID(Read(id, "breadcrumbForQuestId")),
        questFlags = Read(id, "questFlags"),
        specialFlags = Read(id, "specialFlags"),
        availableUntilCompleted = QuestID(Read(id, "availableUntilCompleted")),
    }
    cache[id] = info
    return info
end

--- The quest's base XP and the level it's figured at, from the table
--- QuestieDB builds from what players were paid on Forever.
---@param id number
---@return number|nil questLevel
---@return number|nil xp
function Source.BaseXP(id)
    if not Library() or type(lib.Support) ~= "table" then
        return nil
    end
    local ok, support = pcall(lib.Support.Get, "QuestXP")
    local entry = ok and type(support) == "table" and type(support.db) == "table" and support.db[id]
    if type(entry) == "table" and (entry[1] or 0) > 0 and (entry[2] or 0) > 0 then
        return entry[1], entry[2]
    end
    return nil
end

-- Repeatable, daily and weekly quests aren't steps of a chain: doing them
-- again is the point.
local REPEATABLE = 1
local DAILY, WEEKLY, MONTHLY = 4096, 32768, 65536

---@param info table
---@return boolean
function Source.IsRepeatable(info)
    if ns.HasBit(info.specialFlags, REPEATABLE) then
        return true
    end
    local flags = info.questFlags
    return ns.HasBit(flags, DAILY) or ns.HasBit(flags, WEEKLY) or ns.HasBit(flags, MONTHLY)
end

--- Whether the quest is limited to some classes, not open to everyone.
---@param info table
---@return boolean
function Source.IsClassQuest(info)
    local mask = info.classes
    if not mask or mask == 0 then
        return false
    end
    local all = lib and lib.Enum and lib.Enum.classKeys and lib.Enum.classKeys.ALL_CLASSES
    return mask ~= all
end

--- Whether the current character can take the quest at all, going by
--- race and class. The second return says which one stops it.
---@param info table
---@return boolean
---@return string|nil reason  "race" or "class"
function Source.CanTake(info)
    local enum = lib and lib.Enum
    if not enum then
        return true
    end

    local classes = info.classes
    if classes and classes ~= 0 and enum.classKeys then
        local _, classFile = UnitClass("player")
        local bitValue = classFile and enum.classKeys[classFile]
        if bitValue and not ns.HasBit(classes, bitValue) then
            return false, "class"
        end
    end

    local races = info.races
    if races and races ~= 0 and enum.raceMaskById then
        local _, _, raceID = UnitRace("player")
        local bitValue = raceID and enum.raceMaskById[raceID]
        if bitValue and not ns.HasBit(races, bitValue) then
            return false, "race"
        end
    end

    return true
end

--- The quests that need this one done first, once the index is built.
---@param id number
---@return number[]|nil
function Source.Followers(id)
    return followers[id]
end

---@return boolean
function Source.IndexReady()
    return indexState == "ready"
end

local function AddFollower(prerequisite, id)
    if type(prerequisite) ~= "number" then
        return
    end
    -- A negative prerequisite in the old data means "taken", not "done";
    -- either way the quest follows on from it.
    prerequisite = math.abs(prerequisite)
    local list = followers[prerequisite]
    if not list then
        list = {}
        followers[prerequisite] = list
    end
    -- A quest can name the same prerequisite twice (in both lists, or as
    -- "taken" and "done"); it still follows on only once.
    for _, existing in ipairs(list) do
        if existing == id then
            return
        end
    end
    table.insert(list, id)
end

-- Reads every quest's prerequisites a batch at a time, so logging in
-- doesn't stall while thousands of quests are decoded.
local function BuildIndex()
    if indexState ~= "none" or not Library() or type(lib.Quest.GetAllIds) ~= "function" then
        return
    end
    local ok, ids = pcall(lib.Quest.GetAllIds)
    if not ok or type(ids) ~= "table" then
        return
    end

    indexState = "building"
    local position = 1
    local function Step()
        local last = math.min(position + INDEX_BATCH - 1, #ids)
        for index = position, last do
            local id = ids[index]
            for _, prerequisite in ipairs(List(Read(id, "preQuestSingle")) or {}) do
                AddFollower(prerequisite, id)
            end
            for _, prerequisite in ipairs(List(Read(id, "preQuestGroup")) or {}) do
                AddFollower(prerequisite, id)
            end
        end
        position = last + 1
        if position <= #ids then
            C_Timer.After(0, Step)
        else
            indexState = "ready"
            ns.Send("CHAINS_CHANGED")
        end
    end
    Step()
end

-- Questie adds its own corrections to QuestieDB while it starts up, so
-- anything read before then may be out of date. Its ready callback is the
-- sign to start again; without Questie, QuestieDB's own data is final at
-- login.
local function Start()
    cache = {}
    followers = {}
    indexState = "none"
    -- A short wait keeps the index off the busiest moments of logging in.
    C_Timer.After(2, BuildIndex)
end

ns.OnEvent("PLAYER_LOGIN", function()
    local questie = _G.Questie
    local api = type(questie) == "table" and questie.API
    if type(api) == "table" and type(api.RegisterOnReady) == "function" then
        api.RegisterOnReady(Start)
    else
        Start()
    end
end)

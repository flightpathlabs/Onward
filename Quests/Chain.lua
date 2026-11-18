local _, ns = ...

-- Walks a quest's chain forward and adds up what the rest of it gives.
--
-- The main line follows the data's "next quest", then a breadcrumb's
-- target, then a link Onward saw the game make, then the one quest that
-- needs this one done first. Where a quest opens several others, the main
-- line ends and the others are counted as branches: there's no telling
-- which way the player will go, so their rewards aren't added in.
--
-- Each step is checked against the current character: race, class,
-- profession, quests that shut each other out, and quests already done.

local Chain = {}
ns.Chain = Chain

local Source = ns.Source
local Rewards = ns.Rewards

-- A guard against loops in the data. No real chain on Forever comes close.
local MAX_STEPS = 40

-- How many marks a quest shows at most, so the line stays short.
local MAX_MARKS = 2

local KEY_CLASS = Enum.ItemClass.Key
local EPIC = Enum.ItemQuality.Epic

local function Done(id)
    return C_QuestLog.IsQuestFlaggedCompleted(id)
end

local function InLog(id)
    return C_QuestLog.IsOnQuest(id)
end

--- Whether the character has a profession (or other skill line), or nil
--- when the game won't say.
local function KnowsSkill(skillID)
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then
        return nil
    end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skillID)
    if not ok then
        return nil
    end
    return info ~= nil and (info.rank or 0) > 0
end

-- A quest is shut out once one of the quests it excludes is done or
-- taken, or the quest that ends it is done.
local function ShutOut(info)
    for _, other in ipairs(info.exclusive or {}) do
        if other ~= info.id and (Done(other) or InLog(other)) then
            return true
        end
    end
    return info.availableUntilCompleted ~= nil and Done(info.availableUntilCompleted)
end

--- Whether a quest can be a step of the chain for this character, and if
--- not, why: "repeatable", "race", "class", "skill" or "exclusive".
local function Usable(info)
    if Source.IsRepeatable(info) then
        return false, "repeatable"
    end
    local ok, reason = Source.CanTake(info)
    if not ok then
        return false, reason
    end
    if info.skill and KnowsSkill(info.skill) == false then
        return false, "skill"
    end
    if not Done(info.id) and ShutOut(info) then
        return false, "exclusive"
    end
    return true
end

local function Info(id)
    return Source.Quest(id) or { id = id }
end

local function Excludes(a, b)
    for _, other in ipairs(a.exclusive or {}) do
        if other == b.id then
            return true
        end
    end
    return false
end

--- The quests that open once this one is done and that this character
--- could take, one from each group that shuts the others out.
local function OpenedBy(info, visited)
    local opened = {}
    for _, id in ipairs(Source.Followers(info.id) or {}) do
        if not visited[id] then
            local follower = Info(id)
            local clash = false
            for _, chosen in ipairs(opened) do
                if Excludes(follower, chosen) or Excludes(chosen, follower) then
                    clash = true
                    break
                end
            end
            if not clash and Usable(follower) then
                table.insert(opened, follower)
            end
        end
    end
    return opened
end

-- Where a quest opens several at once, a later quest may need all of them
-- done (Onyxia's Horde chain: three Tests of Skulls, then a fourth). Those
-- are steps of one chain done side by side, not a fork. Returns that later
-- quest and the opened quests it needs, when there are at least two.
local function JoinOf(branches, visited)
    local opened = {}
    for _, branch in ipairs(branches) do
        opened[branch.id] = branch
    end

    local best, bestNeeds
    for _, branch in ipairs(branches) do
        for _, id in ipairs(Source.Followers(branch.id) or {}) do
            local join = Info(id)
            local needs = {}
            for _, prerequisite in ipairs(join.preGroup or {}) do
                local step = opened[math.abs(prerequisite)]
                if step then
                    table.insert(needs, step)
                end
            end
            if
                not visited[id]
                and #needs >= 2
                and (not bestNeeds or #needs > #bestNeeds)
                and Usable(join)
            then
                best, bestNeeds = join, needs
            end
        end
    end
    return best, bestNeeds
end

--- The next step of the main line after info, the quests to do side by
--- side before it, and the other quests that open beside it.
---@return number|nil nextID
---@return table[] branches
---@return table[]|nil parallel
---@return string|nil blocked  why the data's next quest was passed over
local function NextOf(info, visited)
    local nextID = info.next or info.breadcrumbFor or (ns.db and ns.db.links[info.id])
    if nextID and visited[nextID] then
        nextID = nil
    end

    -- The data's next quest may be another race's or class's version of
    -- the step. Then a quest of this character's that follows on is the
    -- step instead, if there is one.
    local blocked
    if nextID then
        local ok, reason = Usable(Info(nextID))
        if not ok then
            blocked = reason
            nextID = nil
        end
    end

    -- A quest that shuts out the next step is the other way of doing it,
    -- not another quest on top.
    local nextInfo = nextID and Info(nextID)
    local branches = {}
    for _, follower in ipairs(OpenedBy(info, visited)) do
        local rival = nextInfo and (Excludes(follower, nextInfo) or Excludes(nextInfo, follower))
        if follower.id ~= nextID and not rival then
            table.insert(branches, follower)
        end
    end

    -- With no explicit next quest, a single quest that needs this one is
    -- the next step. Several make a fork, unless they all lead to one.
    if not nextID and #branches == 1 then
        nextID = branches[1].id
        branches = {}
    elseif not nextID and #branches > 1 then
        local join, parallel = JoinOf(branches, visited)
        if join then
            local inJoin = {}
            for _, step in ipairs(parallel) do
                inJoin[step.id] = true
            end
            local others = {}
            for _, branch in ipairs(branches) do
                if not inJoin[branch.id] then
                    table.insert(others, branch)
                end
            end
            return join.id, others, parallel
        end
    end
    return nextID, branches, nil, not nextID and blocked or nil
end

-- The other quests a step needs done too, that aren't part of the chain
-- and aren't done yet.
local function AlsoNeeds(info, visited)
    local needs = {}
    for _, id in ipairs(info.preGroup or {}) do
        id = math.abs(id)
        if not visited[id] and not Done(id) then
            table.insert(needs, id)
        end
    end
    return needs
end

local requestedItems = {}

local function Quality(itemID)
    local quality = C_Item.GetItemQualityByID(itemID)
    if quality == nil and not requestedItems[itemID] then
        requestedItems[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return quality
end

ns.OnEvent("ITEM_DATA_LOAD_RESULT", function(itemID, success)
    if success and requestedItems[itemID] then
        requestedItems[itemID] = nil
        ns.Send("REWARDS_CHANGED")
    end
end)

local function AddMark(marks, kind, text, icon)
    for _, mark in ipairs(marks) do
        if mark.kind == kind then
            return
        end
    end
    table.insert(marks, { kind = kind, text = text, icon = icon })
end

-- The order marks are kept in when there are more than fit.
local MARK_ORDER = { attunement = 1, class = 2, key = 3, spell = 4, epic = 5 }

local function Marks(summary, root, rootRewards)
    local marks = {}
    local quests = { { info = root, rewards = rootRewards, isRoot = true } }
    for _, step in ipairs(summary.steps) do
        table.insert(quests, { info = step.info, rewards = step.rewards })
    end

    for _, quest in ipairs(quests) do
        local info, rewards = quest.info, quest.rewards
        local opens = ns.ATTUNEMENTS[info.id]
        if opens then
            local text
            if opens.key then
                text = quest.isRoot and ("Key: %s"):format(opens.place)
                    or ("Leads to the %s key"):format(opens.place)
            else
                text = quest.isRoot and ("Attunement: %s"):format(opens.place)
                    or ("Leads to the %s attunement"):format(opens.place)
            end
            AddMark(marks, "attunement", text)
        end
        if Source.IsClassQuest(info) then
            AddMark(marks, "class", quest.isRoot and "Class quest" or "Leads to a class quest")
        end
        if rewards then
            for _, list in ipairs({ rewards.items, rewards.choices }) do
                for _, item in ipairs(list) do
                    local _, _, _, _, icon, classID = C_Item.GetItemInfoInstant(item.id)
                    if classID == KEY_CLASS then
                        AddMark(marks, "key", "Gives a key", icon)
                    end
                    local quality = Quality(item.id)
                    if quality and quality >= EPIC then
                        AddMark(marks, "epic", "Epic reward", icon)
                    end
                end
            end
            for _, spellID in ipairs(rewards.spells) do
                local name = C_Spell.GetSpellName(spellID)
                local icon = C_Spell.GetSpellTexture(spellID)
                AddMark(
                    marks,
                    "spell",
                    name and ("Teaches %s"):format(name) or "Teaches a spell",
                    icon
                )
            end
        end
    end

    table.sort(marks, function(a, b)
        return MARK_ORDER[a.kind] < MARK_ORDER[b.kind]
    end)
    while #marks > MAX_MARKS do
        table.remove(marks)
    end
    return marks
end

local function AddStep(summary, info, needs, isBranch)
    local rewards = Rewards.Get(info.id)
    local step = {
        info = info,
        id = info.id,
        name = info.name or C_QuestLog.GetTitleForQuestID(info.id),
        level = info.level,
        inLog = InLog(info.id),
        needs = needs,
        isBranch = isBranch,
        rewards = rewards,
    }
    table.insert(summary.steps, step)

    if rewards.xp then
        summary.xp = summary.xp + rewards.xp
    else
        summary.xpMissing = summary.xpMissing + 1
    end
    if rewards.known then
        summary.money = summary.money + (rewards.money or 0)
    else
        summary.unknown = summary.unknown + 1
    end
    for _, item in ipairs(rewards.items) do
        table.insert(summary.items, { id = item.id, count = item.count, step = step })
    end
    if #rewards.choices > 0 then
        table.insert(summary.choiceGroups, { items = rewards.choices, step = step })
    end
end

--- Everything about where a quest leads, or nil when there's nothing to
--- say: no steps after it and nothing that marks it.
---
--- summary.steps        the quests still to do after this one, in order
--- summary.fork         true when the quest opens several quests at once
---                      and those are the steps (one level, no further)
--- summary.branches     other quests that open along the way
--- summary.xp / money   totals for the steps
--- summary.xpMissing    steps with no XP figure
--- summary.unknown      steps whose rewards aren't known yet
--- summary.items        fixed reward items, each with its step
--- summary.choiceGroups reward choices, one group per step
--- summary.marks        up to two { kind, text, icon }
--- summary.endsFor      "race" or "class" when the chain goes on for
---                      other characters but not this one
---@param rootID number
---@return table|nil
function Chain.Build(rootID)
    if not rootID or rootID == 0 then
        return nil
    end

    local root = Info(rootID)
    local summary = {
        root = rootID,
        steps = {},
        branches = {},
        xp = 0,
        money = 0,
        xpMissing = 0,
        unknown = 0,
        items = {},
        choiceGroups = {},
    }

    local visited = { [rootID] = true }
    local current = root
    for _ = 1, MAX_STEPS do
        local nextID, branches, parallel, blocked = NextOf(current, visited)
        if blocked == "race" or blocked == "class" then
            summary.endsFor = blocked
        end
        for _, branch in ipairs(branches) do
            visited[branch.id] = true
            if not Done(branch.id) then
                table.insert(summary.branches, branch)
            end
        end
        for _, step in ipairs(parallel or {}) do
            visited[step.id] = true
        end
        for _, step in ipairs(parallel or {}) do
            if not Done(step.id) then
                AddStep(summary, step, AlsoNeeds(step, visited))
            end
        end
        if not nextID then
            break
        end
        visited[nextID] = true

        local info = Info(nextID)
        local ok, reason = Usable(info)
        if not ok then
            if reason == "race" or reason == "class" then
                summary.endsFor = reason
            end
            break
        end
        -- A step already done (out of order, or shared with another
        -- chain) isn't counted, but the chain goes on past it.
        if not Done(nextID) then
            AddStep(summary, info, AlsoNeeds(info, visited))
        end
        current = info
    end

    -- A quest that opens several at once: those are the steps, one level
    -- down only.
    if #summary.steps == 0 and #summary.branches > 0 then
        summary.fork = true
        for _, branch in ipairs(summary.branches) do
            if not Done(branch.id) then
                AddStep(summary, branch, AlsoNeeds(branch, visited), true)
            end
        end
        summary.branches = {}
    end

    summary.marks = Marks(summary, root, Rewards.Get(rootID))

    if #summary.steps == 0 and #summary.marks == 0 then
        return nil
    end
    return summary
end

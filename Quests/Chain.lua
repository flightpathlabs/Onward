local _, ns = ...

-- Walks a quest's chain forward and adds up what the rest of it gives.
--
-- The main line follows the data's "next quest", then a breadcrumb's
-- target, then the one quest that needs this one done first, and only
-- where the data has nothing, a link Onward saw the game make. Where a
-- quest opens several others, the main line ends and the others are
-- counted as branches: there's no telling which way the player will go,
-- so their rewards aren't added in. Unless a later quest needs them all:
-- then they're steps done side by side.
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
local RARE = Enum.ItemQuality.Rare
local EPIC = Enum.ItemQuality.Epic

-- A chain is worth doing on XP alone when it pays at least this share of
-- a level, counting the quest itself.
local WORTH_LEVEL_SHARE = 0.5

-- What a step gives when only the chain's shape is wanted, for the counts
-- in lists and on the map, which shouldn't ask the server about rewards.
local NO_REWARDS = { known = false, items = {}, choices = {}, spells = {} }

local function Done(id)
    return C_QuestLog.IsQuestFlaggedCompleted(id)
end

local function InLog(id)
    return C_QuestLog.IsOnQuest(id)
end

--- Whether the character has a profession (or other skill line), or nil
--- when the game won't say. Only a clear no cuts a step: cutting a step
--- the player can do is worse than showing one they can't.
local function KnowsSkill(skillID)
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then
        return nil
    end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skillID)
    if not ok or type(info) ~= "table" or info.rank == nil then
        return nil
    end
    return info.rank > 0
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
    local nextID
    for _, candidate in ipairs({ info.next or false, info.breadcrumbFor or false }) do
        if candidate and not visited[candidate] then
            nextID = candidate
            break
        end
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
    -- not another quest on top. Quests already done don't make a fork:
    -- the walk goes through one only when it's the only way on.
    local nextInfo = nextID and Info(nextID)
    local branches, done = {}, {}
    for _, follower in ipairs(OpenedBy(info, visited)) do
        local rival = nextInfo and (Excludes(follower, nextInfo) or Excludes(nextInfo, follower))
        if follower.id ~= nextID and not rival then
            table.insert(Done(follower.id) and done or branches, follower)
        end
    end

    -- A link Onward saw the game make counts only where the data has
    -- nothing at all, so a wrong one can't turn a chain the data knows.
    if not nextID and #branches == 0 and #done == 0 then
        local link = ns.db and ns.db.links[info.id]
        if link and not visited[link] and Usable(Info(link)) then
            nextID = link
        end
    end

    -- Several opened quests that a later one needs all of are steps side
    -- by side, whether or not some are done already; the done ones aren't
    -- counted, but the walk goes on to the later quest.
    if not nextID and #branches + #done >= 2 then
        local candidates = {}
        for _, list in ipairs({ branches, done }) do
            for _, follower in ipairs(list) do
                table.insert(candidates, follower)
            end
        end
        local join, parallel = JoinOf(candidates, visited)
        if join then
            local inJoin = { [join.id] = true }
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

    -- With no explicit next quest, a single quest that needs this one is
    -- the next step. Several make a fork.
    if not nextID and #branches == 0 and #done == 1 then
        nextID = done[1].id
    elseif not nextID and #branches == 1 then
        nextID = branches[1].id
        branches = {}
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
    local rewards
    if summary.light then
        rewards = {
            known = false,
            items = NO_REWARDS.items,
            choices = NO_REWARDS.choices,
            spells = NO_REWARDS.spells,
            xp = Rewards.XP(info.id),
        }
    else
        rewards = Rewards.Get(info.id)
    end
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

-- Whether a quest of this level shows grey for the character: too far
-- below them to give much, and hidden by Questie by default.
local function IsGrey(level)
    if not level or level <= 0 or not GetQuestDifficultyColor or not QuestDifficultyColors then
        return false
    end
    return GetQuestDifficultyColor(level) == QuestDifficultyColors.trivial
end

Chain.IsGrey = IsGrey

-- QuestieDB marks some quests' levels as 0 or -1 (events, scaled quests).
local function KnownLevel(level)
    return level ~= nil and level > 0
end

local function QuestLevel(info)
    if info.level and info.level > 0 then
        return info.level
    end
    if C_QuestLog.IsOnQuest(info.id) then
        return C_QuestLog.GetQuestDifficultyLevel(info.id)
    end
    return nil
end

-- The best item quality anywhere in a set of rewards, or nil.
local function BestQuality(rewards)
    local best
    for _, list in ipairs({ rewards.items, rewards.choices }) do
        for _, item in ipairs(list) do
            local quality = Quality(item.id)
            if quality and (not best or quality > best) then
                best = quality
            end
        end
    end
    return best
end

--- "worth" or "skip", the reason, and the kind of mark the reason comes
--- from if any (so the reason isn't shown twice), or nil when there's
--- nothing to say either way.
---
--- Worth doing: the chain reaches an attunement, a key or a class quest,
--- teaches a spell, gives a rare or better item, pays half a level of XP or
--- more, or is grey now but leads on to quests at the character's level.
--- Safe to skip: the quest is grey and so is everything after it, with none
--- of the above. Quests of unknown level don't count either way.
local WORTH_MARKS = { attunement = true, class = true, key = true, spell = true }

local function Verdict(summary, root, rootRewards)
    for _, mark in ipairs(summary.marks) do
        if WORTH_MARKS[mark.kind] then
            return "worth", mark.text, mark.kind
        end
    end

    local best = BestQuality(rootRewards)
    for _, step in ipairs(summary.steps) do
        local quality = BestQuality(step.rewards)
        if quality and (not best or quality > best) then
            best = quality
        end
    end
    if best and best >= RARE then
        if best >= EPIC then
            return "worth", "An epic reward", "epic"
        end
        return "worth", "A rare reward"
    end

    local needed = UnitXPMax("player")
    local xp = summary.xp + (rootRewards.xp or 0)
    if not ns.AtMaxLevel() and needed and needed > 0 and xp >= needed * WORTH_LEVEL_SHARE then
        local levels = xp / needed
        if levels >= 1 then
            return "worth", ("About %.1f levels of XP"):format(levels)
        end
        return "worth", ("About %d%% of a level in XP"):format(math.floor(levels * 100 + 0.5))
    end

    if IsGrey(QuestLevel(root)) then
        local known = 0
        for _, step in ipairs(summary.steps) do
            if KnownLevel(step.level) then
                known = known + 1
                if not IsGrey(step.level) then
                    return "worth", "Grey for you, but it leads to quests at your level"
                end
            end
        end
        if #summary.steps == 0 then
            return "skip", "Grey for you, and it leads nowhere"
        end
        if known == #summary.steps then
            return "skip", "Grey for you, and so is the rest of its chain"
        end
    end
    return nil
end

--- Everything about where a quest leads, or nil when there's nothing to
--- say: no steps after it, nothing that marks it and no verdict.
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
--- summary.verdict      "worth", "skip" or nil, with summary.reason
---
--- With light set, only the steps and their XP are worked out: no other
--- rewards, marks or verdict, and nothing is asked of the server.
---@param rootID number
---@param light boolean|nil
---@return table|nil
function Chain.Build(rootID, light)
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
        light = light,
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

    if light then
        summary.marks = {}
        return summary
    end

    local rootRewards = Rewards.Get(rootID)
    summary.marks = Marks(summary, root, rootRewards)
    summary.verdict, summary.reason, summary.reasonKind = Verdict(summary, root, rootRewards)

    if #summary.steps == 0 and #summary.marks == 0 and not summary.verdict then
        return nil
    end
    return summary
end

-- Step counts for the lists and the map, kept until something that could
-- change a chain happens.
local counts = {}

local function ForgetCounts()
    counts = {}
end

ns.Listen("CHAINS_CHANGED", ForgetCounts)
ns.Listen("LEARNED_FORGOTTEN", ForgetCounts)
ns.OnEvent("QUEST_ACCEPTED", ForgetCounts)
ns.OnEvent("QUEST_REMOVED", ForgetCounts)
ns.OnEvent("SKILL_LINES_CHANGED", ForgetCounts)

--- How many quests follow this one for the character, without asking the
--- server anything. Cheap enough for every icon on a map.
---@param rootID number
---@return number
function Chain.Count(rootID)
    local count = counts[rootID]
    if count == nil then
        local summary = Chain.Build(rootID, true)
        count = summary and #summary.steps or 0
        counts[rootID] = count
    end
    return count
end

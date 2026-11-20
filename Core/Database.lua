local addonName, ns = ...

-- The saved data. Everything is account-wide: a quest's rewards are the
-- same whoever opens it.
--
--   settings  see ns.DEFAULT_SETTINGS
--   quests    quest ID -> what the game showed for it; see Quests/Learn.lua
--   links     quest ID -> the quest the game offered straight after it was
--             handed in, for chains the data doesn't know about
--   paid      quest ID -> the money a hand-in paid at the level cap, where
--             the quest's XP is paid as money too
--   characters  "Name - Realm" -> { abandoned = { quest ID -> time } }, the
--             one thing kept per character: which quests they dropped

-- Bumped when the shape of the saved data changes, so an older table can
-- be brought up to date in Upgrade below instead of being thrown away.
local VERSION = 1

local function Upgrade(db)
    -- Nothing to do yet: version 1 is the first shape. Later versions add
    -- their steps here, oldest first, each guarded by the version it fixes.
    db.version = VERSION
end

local function Fill(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        end
    end
end

ns.OnEvent("ADDON_LOADED", function(name)
    if name ~= addonName then
        return
    end

    WorthItQuestsDB = type(WorthItQuestsDB) == "table" and WorthItQuestsDB or {}
    local db = WorthItQuestsDB

    db.settings = type(db.settings) == "table" and db.settings or {}
    Fill(db.settings, ns.DEFAULT_SETTINGS)

    db.quests = type(db.quests) == "table" and db.quests or {}
    db.links = type(db.links) == "table" and db.links or {}
    db.paid = type(db.paid) == "table" and db.paid or {}
    db.characters = type(db.characters) == "table" and db.characters or {}

    if (db.version or 0) < VERSION then
        Upgrade(db)
    end

    ns.db = db
    ns.settings = db.settings
    ns.Send("DATABASE_READY")
end)

--- This character's own record, made the first time it's asked for.
---@return table|nil
function ns.Me()
    if not ns.db then
        return nil
    end
    local key = ("%s - %s"):format(UnitName("player") or "?", GetRealmName() or "")
    local me = ns.db.characters[key]
    if type(me) ~= "table" then
        me = {}
        ns.db.characters[key] = me
    end
    me.abandoned = type(me.abandoned) == "table" and me.abandoned or {}
    return me
end

--- Forgets every reward and link Worth It has learned. Settings stay, and so
--- does each character's record of what they abandoned.
function ns.ForgetLearned()
    if not ns.db then
        return
    end
    ns.db.quests = {}
    ns.db.links = {}
    ns.db.paid = {}
    ns.Send("LEARNED_FORGOTTEN")
    ns.Send("REWARDS_CHANGED")
end

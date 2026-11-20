local addonName, ns = ...

-- Onward
--
-- Says where a quest leads: how many quests follow it, and what finishing
-- the whole chain gives. The chain itself comes from QuestieDB when it's
-- installed; the rewards come from the game, and from what you've seen in
-- quest windows.
--
-- Everything hangs off the private table the client hands every file in
-- the addon (ns). The only globals are the saved data, the slash command
-- and the function the minimap's addon menu calls.

ns.name = addonName
ns.TITLE = "Onward"

ns.DEFAULT_SETTINGS = {
    -- Where the chain shows.
    questFrame = true,
    questLog = true,
    mapTooltip = true,
    -- "+4" after each quest in the quest log and quest givers' lists.
    listCounts = true,
    -- The number beside Questie's "!" on the map and minimap.
    mapNumbers = true,

    -- The row of reward items under the totals.
    items = true,
    -- Class quest, attunement, key, spell and epic marks.
    marks = true,
    -- "Worth doing" and "Safe to skip".
    verdict = true,
    -- Remember the rewards of quests you open, so later chains know them.
    learn = true,

    -- The button on the minimap's rim, and where on the rim it sits, in
    -- degrees anticlockwise from the right. Goldwise's sits at 215 and
    -- Creel's at 240, so Onward's starts a little the other way.
    minimapButton = true,
    minimapAngle = 190,
}

local frame = CreateFrame("Frame")
local handlers = {}

-- One handler failing shouldn't stop the others hearing the same event, so
-- each runs on its own and an error is reported without unwinding the rest.
local function Dispatch(list, ...)
    for _, handler in ipairs(list) do
        local ok, message = pcall(handler, ...)
        if not ok then
            geterrorhandler()(message)
        end
    end
end

--- Calls handler(...) with the event's payload whenever the client fires it.
---@param event string
---@param handler fun(...)
function ns.OnEvent(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end

frame:SetScript("OnEvent", function(_, event, ...)
    Dispatch(handlers[event], ...)
end)

-- Messages between Onward's own files, so the quest window can redraw when
-- the reward code hears back from the server without either knowing about
-- the other.
local listeners = {}

---@param message string
---@param listener fun(...)
function ns.Listen(message, listener)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], listener)
end

---@param message string
function ns.Send(message, ...)
    if listeners[message] then
        Dispatch(listeners[message], ...)
    end
end

--- A value the client may hand back as secret is treated as unknown.
function ns.Readable(value)
    if issecretvalue and issecretvalue(value) then
        return nil
    end
    return value
end

--- Whether a bit is set in a mask, without the client's bit library:
--- QuestieDB's race masks on Forever go past 32 bits, which bit.band
--- would cut short.
---@param mask number|nil
---@param bitValue number  a power of two
---@return boolean
function ns.HasBit(mask, bitValue)
    if not mask or not bitValue or bitValue <= 0 then
        return false
    end
    return math.floor(mask / bitValue) % 2 == 1
end

---@return number
function ns.PlayerLevel()
    return UnitLevel("player") or 1
end

--- At the level cap quest XP is paid as money instead.
---@return boolean
function ns.AtMaxLevel()
    local cap = GetMaxPlayerLevel and GetMaxPlayerLevel()
    return cap ~= nil and ns.PlayerLevel() >= cap
end

local _, ns = ...

-- Quests that open a dungeon or raid: the attunements, and the quests that
-- hand over a dungeon's key. Written by hand from what each quest is for;
-- the IDs were checked against the quest names in the game's data on
-- 2026-11-18.
--
-- Only the quest that grants the attunement or key is listed. Any quest
-- that leads to one is marked "Leads to ..." by the chain walk, so the
-- start of a long chain like Onyxia's shows it too.
--
-- Other keys are found from the rewards themselves: an item of the Key
-- class anywhere in a chain gets the key mark.

local function Attunement(place)
    return { place = place }
end

local function Key(place)
    return { place = place, key = true }
end

ns.ATTUNEMENTS = {
    -- Attunement to the Core
    [7848] = Attunement("Molten Core"),
    -- Drakefire Amulet (Alliance), Blood of the Black Dragon Champion
    -- (Horde)
    [6502] = Attunement("Onyxia's Lair"),
    [6602] = Attunement("Onyxia's Lair"),
    -- Blackhand's Command
    [7761] = Attunement("Blackwing Lair"),
    -- Seal of Ascension
    [4743] = Key("Upper Blackrock Spire"),
    -- The Key to Scholomance (Alliance, Horde)
    [5505] = Key("Scholomance"),
    [5511] = Key("Scholomance"),
    -- Dark Iron Legacy, which gives the Shadowforge Key
    [3802] = Key("Blackrock Depths"),
    -- The Dread Citadel, at Honored, Revered and Exalted
    [9121] = Attunement("Naxxramas"),
    [9122] = Attunement("Naxxramas"),
    [9123] = Attunement("Naxxramas"),
}

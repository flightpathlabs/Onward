local _, ns = ...

-- Worth It's page in the game's Options window, the /worth command and the
-- entry in the minimap's addon menu. A change takes effect as it's made,
-- like the game's own options.

-- Each setting is registered with the game under a name of its own: this,
-- followed by its key in the saved settings.
local PREFIX = "WorthItQuests_"

local CONFIRM = "WORTHITQUESTS_CONFIRM"

StaticPopupDialogs[CONFIRM] = {
    text = "%s",
    button1 = "Yes",
    button2 = "Cancel",
    OnAccept = function(_, onAccept)
        onAccept()
    end,
    hideOnEscape = true,
    timeout = 0,
    whileDead = true,
    showAlert = true,
}

local category, layout

local function Changed()
    ns.Send("SETTINGS_CHANGED")
end

local function AddHeader(title)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
end

local function AddCheckbox(key, label, tooltip)
    local setting = Settings.RegisterAddOnSetting(
        category,
        PREFIX .. key,
        key,
        ns.settings,
        Settings.VarType.Boolean,
        label,
        ns.DEFAULT_SETTINGS[key]
    )
    Settings.SetOnValueChangedCallback(PREFIX .. key, Changed)
    Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddButton(label, buttonText, onClick, tooltip)
    local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, false)
    initializer:AddSearchTags(label)
    layout:AddInitializer(initializer)
end

-- What the page says about where the chains come from.
local SOURCE_NOTES = {
    ready = "Chains come from Questie's quest data",
    missing = "Questie isn't installed: Worth It only knows chains it has seen",
    old = "This Questie is too old or too new for Worth It: update the older one",
}

local function AddOptions()
    AddHeader("Where it shows")
    AddCheckbox(
        "questFrame",
        "In the quest window",
        "Under the rewards when someone offers you a quest, and when you hand one in."
    )
    AddCheckbox(
        "questLog",
        "In the quest log",
        "Under a quest's description in the quest log beside the map."
    )
    AddCheckbox(
        "mapTooltip",
        "On Questie's map icons",
        "One line on the tooltip of a quest giver's icon on the map and minimap. Needs Questie."
    )
    AddCheckbox(
        "listCounts",
        "In quest lists",
        "A short note after each quest in the quest log and in a quest giver's list: "
            .. '"+4" for four more quests in its chain, a tick if it\'s worth doing, "skip" '
            .. "if it's safe to skip."
    )
    AddCheckbox(
        "mapNumbers",
        "Numbers on Questie's map icons",
        'A small number beside each "!" on the map and minimap: how many quests follow '
            .. "the one on offer there. Needs Questie."
    )

    AddCheckbox(
        "minimapButton",
        "Minimap button",
        "A button with a quest mark on the edge of the minimap: left-click opens the Worth It "
            .. "window, right-click these options. Drag it to move it round the edge."
    )

    AddHeader("What it shows")
    AddCheckbox(
        "items",
        "Reward items",
        "The items the rest of the chain gives, with their tooltips. A quest that lets you "
            .. 'choose shows all of its choices after "One of".'
    )
    AddCheckbox(
        "verdict",
        "Say what's worth doing",
        "Worth doing: the chain opens a dungeon or raid, is a class quest, gives a rare or "
            .. "epic item, pays half a level of XP, or leads from grey quests to ones at your "
            .. "level. Safe to skip: the quest is grey for you and so is everything after it."
    )
    AddCheckbox(
        "marks",
        "Mark quests that matter",
        "Class quests, attunements and dungeon keys, spells a quest teaches, and epic rewards, "
            .. "for the quest itself or anywhere further along its chain."
    )

    AddHeader("Learning")
    AddCheckbox(
        "learn",
        "Remember what quests give",
        "Keeps the rewards of quests you open, and which quest follows which, so later chains "
            .. "can count them. Kept for all your characters."
    )
    AddButton("Forget what Worth It has learned", "Forget", function()
        StaticPopup_Show(
            CONFIRM,
            "Forget every reward and link Worth It has learned? This can't be undone.",
            nil,
            ns.ForgetLearned
        )
    end, "Empties what Worth It has learned. Your options stay as they are. It asks first.")

    AddHeader(SOURCE_NOTES[ns.Source.Status()])
end

--- Opens the game's Options window on Worth It's page.
function ns.OpenOptions()
    -- The Options window is one of the panels the game won't open in a
    -- fight. Say so the way the game does, not in chat.
    if InCombatLockdown() then
        if UIErrorsFrame and UIErrorsFrame.AddExternalErrorMessage then
            UIErrorsFrame:AddExternalErrorMessage(ERR_NOT_IN_COMBAT)
        end
        return
    end
    if category then
        Settings.OpenToCategory(category:GetID())
    end
end

-- Registered at login rather than when the addon loads, so the Options
-- window has finished setting itself up.
ns.OnEvent("PLAYER_LOGIN", function()
    category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
    AddOptions()
    Settings.RegisterAddOnCategory(category)
end)

SLASH_WORTHITQUESTS1 = "/worth"
SlashCmdList.WORTHITQUESTS = function(message)
    local word, rest = strtrim(message or ""):match("^(%S*)%s*(.-)$")
    word = (word or ""):lower()
    if word == "probe" and ns.Probe then
        ns.Probe.Run(tonumber(rest))
    elseif word == "chain" and ns.Probe then
        ns.Probe.Chain(tonumber(rest))
    elseif word == "options" or word == "config" then
        ns.OpenOptions()
    else
        ns.Window.Toggle()
    end
end

-- Named in the TOC, so the minimap's addon menu can call it. Left-click
-- opens the window, right-click the options.
function WorthItQuests_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.OpenOptions()
    else
        ns.Window.Toggle()
    end
end

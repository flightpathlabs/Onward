-- Luacheck configuration for Onward.
-- Run from the addon's folder:  luacheck .
--
-- There is no maintained luacheck "std" for the 12.x / Forever API, so we
-- list the globals we actually touch. A typo in an API name then shows up
-- as a lint warning instead of a nil error in game.

std = "lua51"
max_line_length = 100
max_string_line_length = false
max_comment_line_length = 100
codes = true

exclude_files = {
    "Libs/**",
    ".release/**",
}

ignore = {
    "212/self", -- unused "self" on script handlers is normal
}

-- The only globals Onward creates: its saved data, its slash command, its
-- confirm dialog and the function the minimap's addon menu calls.
globals = {
    "SlashCmdList",
    "StaticPopupDialogs",

    -- Ours
    "OnwardDB",
    "SLASH_ONWARD1",
    "Onward_OnAddonCompartmentClick",
}

read_globals = {
    -- Lua extensions the client adds
    "strtrim",
    "debugprofilestop",
    "geterrorhandler",
    "time",

    -- Client constants
    "Enum",
    "ERR_NOT_IN_COMBAT",
    "GRAY_FONT_COLOR",
    "HIGHLIGHT_FONT_COLOR",
    "ITEM_QUALITY_COLORS",
    "NORMAL_FONT_COLOR",

    -- Blizzard's shared Lua helpers
    "BreakUpLargeNumbers",
    "CreateColor",
    "CreateSettingsButtonInitializer",
    "CreateSettingsListSectionHeaderInitializer",
    "CreateTextureMarkup",
    "GameTooltip_AddBlankLineToTooltip",
    "GameTooltip_AddColoredDoubleLine",
    "GameTooltip_AddColoredLine",
    "GameTooltip_AddNormalLine",
    "GameTooltip_Hide",
    "GameTooltip_SetTitle",
    "GetQuestDifficultyColor",
    "HandleModifiedItemClick",
    "QuestInfo_ShowSpacer",
    "Settings",
    "StaticPopup_Show",
    "hooksecurefunc",

    -- Frames and widgets
    "CreateFrame",
    "GameTooltip",
    "QuestFrame",
    "QuestInfoDescriptionHeader",
    "QuestInfoDescriptionText",
    "QuestInfoSpacerFrame",
    "UIErrorsFrame",

    -- Namespaced API
    "C_CurrencyInfo",
    "C_Item",
    "C_Map",
    "C_QuestInfoSystem",
    "C_QuestLine",
    "C_QuestLog",
    "C_SkillInfo",
    "C_Spell",
    "C_TaskQuest",
    "C_Timer",

    -- Loose API functions
    "GetBuildInfo",
    "GetMaxPlayerLevel",
    "GetNumQuestChoices",
    "GetNumQuestLogChoices",
    "GetNumQuestLogRewards",
    "GetNumQuestRewards",
    "GetQuestID",
    "GetQuestItemInfo",
    "GetQuestItemLink",
    "GetQuestLogChoiceInfo",
    "GetQuestLogRewardInfo",
    "GetQuestLogRewardMoney",
    "GetQuestLogRewardXP",
    "GetRewardMoney",
    "GetRewardXP",
    "GetTime",
    "HaveQuestRewardData",
    "InCombatLockdown",
    "UnitClass",
    "UnitGUID",
    "UnitLevel",
    "UnitRace",
    "issecretvalue",
}

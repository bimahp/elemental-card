-- QuestConfig: canonical quest ID constants and stage definitions.
-- Both server and client reference QuestConfig.IDs.* — never inline quest ID strings.
local QuestConfig = {}

QuestConfig.IDs = {
	ONBOARDING = "quest_onboarding",
	-- Future: DAILY_BATTLE = "quest_daily_battle", EVENT_SUMMER = "quest_event_summer_2026"
}

QuestConfig.Defs = {
	[QuestConfig.IDs.ONBOARDING] = {
		stages = { "intro", "find_trainer", "deck_chosen", "complete" },
	},
}

return QuestConfig

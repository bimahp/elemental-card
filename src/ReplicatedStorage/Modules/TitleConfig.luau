-- TitleConfig: shared title metadata and unlock requirements.
local TitleConfig = {}

local TITLES = {
	{
		id = "beta_tester",
		displayName = "Beta Tester",
		description = "Here before the crystals settled.",
		unlockText = "Available to all players",
		order = 10,
		requirement = { kind = "default" },
	},
	{
		id = "mighty_disciple",
		displayName = "Mighty Disciple",
		description = "Strength tempered through the first trial.",
		unlockText = "Complete onboarding with MIGHTY",
		order = 20,
		requirement = { kind = "onboarding_archetype", value = "MIGHTY" },
	},
	{
		id = "swift_disciple",
		displayName = "Swift Disciple",
		description = "A quick mind guided through the first trial.",
		unlockText = "Complete onboarding with SWIFT",
		order = 30,
		requirement = { kind = "onboarding_archetype", value = "SWIFT" },
	},
	{
		id = "vital_disciple",
		displayName = "Vital Disciple",
		description = "Renewal mastered through the first trial.",
		unlockText = "Complete onboarding with VITAL",
		order = 40,
		requirement = { kind = "onboarding_archetype", value = "VITAL" },
	},
	{
		id = "trainer_champion",
		displayName = "Trainer Champion",
		description = "Proven against every elemental trainer.",
		unlockText = "Defeat all 3 trainers",
		order = 50,
		requirement = { kind = "trainer_clears", value = 3 },
	},
	{
		id = "duelist",
		displayName = "Duelist",
		description = "A familiar face across the battle tables.",
		unlockText = "Win 10 PvP battles",
		order = 60,
		requirement = { kind = "pvp_wins", value = 10 },
	},
	{
		id = "battle_veteran",
		displayName = "Battle Veteran",
		description = "Hardened by victories earned crystal by crystal.",
		unlockText = "Win 50 PvP battles",
		order = 70,
		requirement = { kind = "pvp_wins", value = 50 },
	},
	{
		id = "crystal_collector",
		displayName = "Crystal Collector",
		description = "A growing archive of elemental allies.",
		unlockText = "Own 50 unique collectible cards",
		order = 80,
		requirement = { kind = "unique_collectible", value = 50 },
	},
	{
		id = "crystal_archivist",
		displayName = "Crystal Archivist",
		description = "A collection worthy of the grand archive.",
		unlockText = "Own 100 unique collectible cards",
		order = 90,
		requirement = { kind = "unique_collectible", value = 100 },
	},
}

local BY_ID = {}
for _, title in ipairs(TITLES) do
	BY_ID[title.id] = title
end

function TitleConfig.list()
	return TITLES
end

function TitleConfig.get(titleId)
	return BY_ID[titleId]
end

function TitleConfig.displayName(titleId)
	local title = BY_ID[titleId] or BY_ID.beta_tester
	return title.displayName
end

TitleConfig.DEFAULT_ID = "beta_tester"

return TitleConfig

-- Headless checks for UIFeedback.resolve (PLAN_UI_FOUNDATIONS step 7).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFeedback = require(ReplicatedStorage.Modules.UIFeedback)
local AssetIds = require(ReplicatedStorage.Modules.AssetIds)

local Spec = {}

function Spec.run()
	for code, entry in pairs(UIFeedback.MESSAGES) do
		assert(entry.text ~= nil, code .. " has no text")
		assert(AssetIds.Icons[entry.icon], code .. " names a missing icon " .. tostring(entry.icon))
		local resolved = UIFeedback.resolve({ code = code })
		assert(type(resolved.text) == "string" and resolved.text ~= "", code .. " resolves to text with no values")
	end

	local cooldown = UIFeedback.resolve({ code = "MatchmakingCooldown", values = { seconds = 125 } })
	assert(cooldown.text == "Matchmaking cooldown: 2m 5s left (too many early forfeits today).", "values fill the sentence")
	assert(cooldown.image == AssetIds.Icons.MATCHMAKING and cooldown.tone == "refusal", "the entry's icon and tone come through")
	local odd = UIFeedback.resolve({ code = "MatchmakingCooldown", values = { seconds = "soon" } })
	assert(odd.text:find("0m 0s"), "a bad value never errors")

	local plain = UIFeedback.resolve("All tables are busy")
	assert(plain.text == "All tables are busy" and plain.image == "" and plain.tone == "info", "plain text passes through")
	local unknown = UIFeedback.resolve({ code = "NoSuchCode" })
	assert(unknown.text ~= "" and unknown.tone == "refusal", "an unknown code shows the fallback")
	assert(UIFeedback.resolve(42).text == "42", "other values show as text")
	return "UIFeedbackSpec: all checks passed"
end

return Spec

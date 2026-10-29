-- Shim: exposes the Cards definitions table and CardText helpers under the
-- CardData name that BattleUIController expects.
local RS = game:GetService("ReplicatedStorage")
local Cards    = require(RS.Definitions.Cards)
local CardText = require(RS.Modules.CardText)

local CardData = {}
CardData.Cards            = Cards
CardData.getAbilityDisplay = CardText.getAbilityDisplay
CardData.playTarget        = CardText.playTarget

return CardData
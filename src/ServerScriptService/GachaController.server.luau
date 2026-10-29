-- GachaController: validates vending proximity and safely serializes pack purchases.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local SSS               = game:GetService("ServerScriptService")

local GachaService = require(SSS.Modules.GachaService)
local SaveService  = require(SSS.Modules.SaveService)
local Config       = require(ReplicatedStorage.Modules.GachaConfig)
local remotes      = ReplicatedStorage:WaitForChild("Remotes")
local OpenCardPack = remotes:WaitForChild("OpenCardPack")
local GetPackOdds  = remotes:WaitForChild("GetPackOdds")

local machine = workspace:WaitForChild("Card Vending Machine")
local anchor  = machine:WaitForChild("InteractionAnchor")

local rolling = {}
local lastRollAt = {}
local lastOddsAt = {}

local function isNearMachine(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local allowed = Config.MAX_ACTIVATION_DISTANCE + Config.SERVER_DISTANCE_TOLERANCE
	return (root.Position - anchor.Position).Magnitude <= allowed
end

GetPackOdds.OnServerInvoke = function(player)
	local userId = player.UserId
	if not isNearMachine(player) then
		return { ok = false, error = "Move closer to the Card Vending Machine" }
	end
	local now = os.clock()
	if now - (lastOddsAt[userId] or -math.huge) < 0.25 then
		return { ok = false, error = "Please wait before refreshing odds" }
	end
	lastOddsAt[userId] = now
	local ownedCounts = SaveService.getCollectionCounts(player)
	if not ownedCounts then return { ok = false, error = "Profile not loaded" } end
	return {
		ok = true,
		packId = "standard",
		cards = GachaService.computeDisplayOdds(ownedCounts),
	}
end

OpenCardPack.OnServerInvoke = function(player)
	local userId = player.UserId
	if not isNearMachine(player) then
		return { ok = false, error = "Move closer to the Card Vending Machine" }
	end
	if rolling[userId] then
		return { ok = false, error = "A pack is already being opened" }
	end

	local now = os.clock()
	local elapsed = now - (lastRollAt[userId] or -math.huge)
	if elapsed < Config.ROLL_COOLDOWN_SECONDS then
		return { ok = false, error = "Please wait before opening another pack" }
	end

	rolling[userId] = true
	lastRollAt[userId] = now
	local ok, result = xpcall(function()
		return GachaService.roll(player)
	end, debug.traceback)
	rolling[userId] = nil

	if not ok then
		warn("[GachaController] roll failed for " .. player.Name .. ": " .. tostring(result))
		return { ok = false, error = "Pack service temporarily unavailable" }
	end
	if type(result) ~= "table" then
		warn("[GachaController] roll returned invalid result for " .. player.Name)
		return { ok = false, error = "Pack service temporarily unavailable" }
	end
	return result
end

Players.PlayerRemoving:Connect(function(player)
	rolling[player.UserId] = nil
	lastRollAt[player.UserId] = nil
	lastOddsAt[player.UserId] = nil
end)

print("[GachaController] OpenCardPack + live GetPackOdds wired with proximity and error guards")

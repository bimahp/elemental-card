local RunService = game:GetService("RunService")

local npc      = workspace:WaitForChild("Noob", 10)
local humanoid = npc:WaitForChild("Humanoid", 10)
local hrp      = npc:WaitForChild("HumanoidRootPart", 10)
local torso    = npc:WaitForChild("Torso", 10)

if not (npc and humanoid and hrp and torso) then
	warn("[NpcSit] Missing NPC parts") return
end

local function findNpcSeat()
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("IsNPCSeat") then
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("Seat") then return d end
			end
		end
	end
end

local function findPlayerSeat()
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("IsPlayerSeat") then
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("Seat") then return d end
			end
		end
	end
end

local seat       = findNpcSeat()
local playerSeat = findPlayerSeat()
if not seat then warn("[NpcSit] No NPC seat found") return end

-- ── Apply R6 sitting joint angles ─────────────────────────────────────────────
-- Default R6 standing C0:
--   Right Hip: CFrame.new(1,-1,0) * CFrame.fromEulerAnglesXYZ(0, pi/2, 0)
--   Left Hip:  CFrame.new(-1,-1,0)* CFrame.fromEulerAnglesXYZ(0,-pi/2, 0)
-- Sitting = add -pi/2 around local X (folds legs from hanging-down to horizontal-forward)

local function applySitPose()
	local rh = torso:FindFirstChild("Right Hip")
	local lh = torso:FindFirstChild("Left Hip")
	local rs = torso:FindFirstChild("Right Shoulder")
	local ls = torso:FindFirstChild("Left Shoulder")

	if rh then
		rh.C0 = CFrame.new(1, -1, 0)
			* CFrame.fromEulerAnglesXYZ(-math.pi/2, math.pi/2, math.pi)
	end
	if lh then
		lh.C0 = CFrame.new(-1, -1, 0)
			* CFrame.fromEulerAnglesXYZ(-math.pi/2, -math.pi/2, math.pi)
	end
	-- Slightly lower arms to resting position
	if rs then
		rs.C0 = CFrame.new(1, 0.5, 0)
			* CFrame.fromEulerAnglesXYZ(0, math.pi/2, 0)
			* CFrame.Angles(0, 0, math.pi/6)
	end
	if ls then
		ls.C0 = CFrame.new(-1, 0.5, 0)
			* CFrame.fromEulerAnglesXYZ(0, -math.pi/2, 0)
			* CFrame.Angles(0, 0, -math.pi/6)
	end
end

-- ── Position NPC at seat, face toward player seat ─────────────────────────────
local seatPos = seat.Position
local lookTarget = playerSeat and playerSeat.Position or (seatPos + Vector3.new(0, 0, 10))

-- Place HRP above seat, facing the player chair
hrp.CFrame = CFrame.lookAt(
	Vector3.new(seatPos.X, seatPos.Y + seat.Size.Y/2 + hrp.Size.Y/2 + 0.05, seatPos.Z),
	Vector3.new(lookTarget.X, seatPos.Y + seat.Size.Y/2 + hrp.Size.Y/2 + 0.05, lookTarget.Z)
)

-- ── Force sit ─────────────────────────────────────────────────────────────────
seat:Sit(humanoid)

-- Apply pose after one frame (SeatWeld needs a moment to create)
task.wait(0.05)
applySitPose()

-- ── Maintain pose via Heartbeat (Motor6D can drift without Animate script) ───
local tick = 0
RunService.Heartbeat:Connect(function()
	tick += 1
	if tick % 6 == 0 then
		applySitPose()
		-- Keep HRP locked to seat if SeatWeld was broken
		if humanoid.SeatPart ~= seat then
			hrp.CFrame = CFrame.lookAt(
				Vector3.new(seatPos.X, seatPos.Y + seat.Size.Y/2 + hrp.Size.Y/2 + 0.05, seatPos.Z),
				Vector3.new(lookTarget.X, seatPos.Y + seat.Size.Y/2 + hrp.Size.Y/2 + 0.05, lookTarget.Z)
			)
			seat:Sit(humanoid)
		end
	end
end)

print("[NpcSit] Noob seated and facing player side.")

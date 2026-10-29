local WS = game:GetService("Workspace")
local RS = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TableManager = {}

local FREE="FREE"; local RESERVED="RESERVED"; local OCCUPIED="OCCUPIED"
local tables={}; local playerTable={}; local playerChair={}
local onStartPvE, onStartPvP, getBattleForPlayer, Remotes

local function awaitSeated(hum, seat, timeout)
	local hrp=hum.RootPart
	local deadline=os.clock()+(timeout or 1.5)
	while os.clock()<deadline do
		RS.Heartbeat:Wait()
		if hum.Sit and hum.SeatPart==seat then
			if not hrp then return true end
			if (hrp.Position-seat.Position).Magnitude<4 then return true end
		end
	end
	return hum.Sit and hum.SeatPart==seat
end

local function lockMovement(hum)
	hum.WalkSpeed=0; hum.JumpPower=0; hum.JumpHeight=0
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
end
-- Restores the place's character defaults, never fixed numbers.
local function unlockMovement(hum)
	hum.WalkSpeed=StarterPlayer.CharacterWalkSpeed; hum.JumpPower=StarterPlayer.CharacterJumpPower; hum.JumpHeight=StarterPlayer.CharacterJumpHeight
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,true)
end

local function refreshPrompt(tbl)
	local p=tbl.prompt; if not p then return end
	if tbl.state==OCCUPIED then p.Enabled=false
	elseif (not tbl.chairs[1].player) or (not tbl.chairs[2].player) then p.ActionText="Sit"; p.Enabled=true
	else p.Enabled=false end
end

local function handleTablePrompt(player, tbl)
	if getBattleForPlayer(player) then return end
	if playerTable[player.UserId] then return end
	if tbl.state==OCCUPIED then return end
	local emptyIdx=(not tbl.chairs[1].player) and 1 or (not tbl.chairs[2].player) and 2 or nil
	if not emptyIdx then return end
	TableManager.seatPlayerAt(player,tbl,emptyIdx)
	if playerTable[player.UserId] then Remotes.BattleSeated:FireClient(player,tbl.tableId,emptyIdx) end
end

function TableManager.seatPlayerAt(player, tbl, chairIdx)
	local chair=tbl.chairs[chairIdx]
	local char=player.Character; if not char then return false end
	local hum=char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
	unlockMovement(hum)
	if hum.Sit or hum.SeatPart then hum.Sit=false; task.wait() end
	chair.player=player
	playerTable[player.UserId]=tbl.tableId
	playerChair[player.UserId]=chairIdx
	tbl.state=(tbl.chairs[1].player and tbl.chairs[2].player) and OCCUPIED or RESERVED
	refreshPrompt(tbl)
	local seated=false
	if chair.seat then
		for _=1,2 do
			chair.seat:Sit(hum)
			if awaitSeated(hum,chair.seat,3) then seated=true;break end
			if not playerTable[player.UserId] then break end
		end
	end
	if not playerTable[player.UserId] then return false end
	if not seated then TableManager.unseatPlayer(player); return false end
	lockMovement(hum)
	return true
end

function TableManager.spawnNpcAt(tbl, chairIdx)
	local chair=tbl.chairs[chairIdx]; if not chair or not chair.seat then return end
	local trainerName = tbl._trainerName; tbl._trainerName = nil
	local template
	if trainerName then
		local tf = WS:FindFirstChild("Trainers")
		template = tf and tf:FindFirstChild(trainerName)
	end
	if not template then template = WS:FindFirstChild("Noob") end
	if not template then return end
	local clone=template:Clone()
	clone.Name="BenchNpc"
	for _,d in ipairs(clone:GetDescendants()) do
		if d:IsA("ProximityPrompt") then d:Destroy() end
		if d:IsA("BasePart") then d.Anchored=false end
	end
	clone:PivotTo(chair.seat.CFrame*CFrame.new(0,1.5,0))
	clone.Parent=WS
	local hum=clone:FindFirstChildOfClass("Humanoid")
	if hum then
		chair.seat:Sit(hum); awaitSeated(hum,chair.seat,1.5)
		hum.WalkSpeed=0; hum.JumpPower=0
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
	end
	tbl.npc=clone
	return clone
end

local function despawnNpc(tbl) if tbl.npc then tbl.npc:Destroy(); tbl.npc=nil end end

function TableManager.unseatPlayer(player)
	local tableId=playerTable[player.UserId]; if not tableId then return end
	local tbl=tables[tableId]; if not tbl then return end
	local chairIdx=playerChair[player.UserId]
	local previousSeat=chairIdx and tbl.chairs[chairIdx] and tbl.chairs[chairIdx].seat
	if chairIdx then tbl.chairs[chairIdx].player=nil end
	playerTable[player.UserId]=nil; playerChair[player.UserId]=nil
	tbl.readySet[player.UserId]=nil
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		unlockMovement(hum)
		hum.Sit=false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if char and hum and previousSeat then
		-- Never move the character while it is welded to the Seat: doing so moves
		-- the anchored Seat itself and corrupts the next battle's camera position.
		local seatWeld=previousSeat:FindFirstChild("SeatWeld")
		if seatWeld then seatWeld:Destroy() end
		local released=false
		for _=1,30 do
			RS.Heartbeat:Wait()
			if not hum.SeatPart and not previousSeat:FindFirstChild("SeatWeld") then
				released=true
				break
			end
		end
		if released then
			local right=previousSeat.CFrame.RightVector
			local flatRight=Vector3.new(right.X,0,right.Z)
			if flatRight.Magnitude<0.01 then flatRight=Vector3.new(1,0,0) end
			local sidePos=previousSeat.Position+flatRight.Unit*3.5
			local pivot=char:GetPivot()
			char:PivotTo(CFrame.new(sidePos.X,pivot.Position.Y,sidePos.Z)*pivot.Rotation)
		else
			warn("[TableManager] Seat release timed out for "..player.Name.."; skipped exit reposition")
		end
	end
	local c1,c2=tbl.chairs[1].player,tbl.chairs[2].player
	if not c1 and not c2 then tbl.state=FREE; tbl.battleId=nil; tbl.model:SetAttribute("BattleId","")
	elseif tbl.state==OCCUPIED then tbl.state=RESERVED end
	refreshPrompt(tbl)
end

function TableManager.markOccupied(tbl,battleId) tbl.state=OCCUPIED; tbl.battleId=battleId; tbl.model:SetAttribute("BattleId",battleId); refreshPrompt(tbl) end
function TableManager.markFree(tableId) local tbl=tables[tableId]; if not tbl then return end; despawnNpc(tbl); tbl.state=FREE; tbl.battleId=nil; tbl.model:SetAttribute("BattleId",""); refreshPrompt(tbl) end
function TableManager.getTableForPlayer(player) local id=playerTable[player.UserId]; return id and tables[id] or nil end
function TableManager.getChairForPlayer(player) return playerChair[player.UserId] end
function TableManager.findFreeTable() for _,tbl in pairs(tables) do if tbl.state==FREE then return tbl end end end
function TableManager.getTableById(tableId) return tables[tableId] end

-- PLAN_MATCHMAKING Phase 1: free-table count for the cross-server registry hint.
function TableManager.countFree()
	local n = 0
	for _, tbl in pairs(tables) do if tbl.state == FREE then n += 1 end end
	return n
end

function TableManager.handleReadyUp(player)
	local tbl=TableManager.getTableForPlayer(player); if not tbl then return end
	if getBattleForPlayer(player) then return end
	local c1,c2=tbl.chairs[1].player,tbl.chairs[2].player
	if not (c1 and c2) then return end
	tbl.readySet[player.UserId]=true
	if tbl.readySet[c1.UserId] and tbl.readySet[c2.UserId] then tbl.readySet={}; onStartPvP(tbl) end
end

local function notify(player, msg)
	local n=Remotes and Remotes:FindFirstChild("Notify")
	if n then n:FireClient(player,msg) end
end

-- npcDeckKey is optional; nil means random
function TableManager.handleTalkToNpc(player, npcDeckKey, trainerName)
	if playerTable[player.UserId] then return false end
	if getBattleForPlayer(player) then return false end
	local tbl=TableManager.findFreeTable()
	if not tbl then
		Remotes.BattleUnseated:FireClient(player)
		notify(player,{ code = "TablesBusy" })
		return false
	end
	Remotes.BattleLoading:FireClient(player)
	local ok=TableManager.seatPlayerAt(player,tbl,1)
	if not ok or not playerTable[player.UserId] then
		Remotes.BattleUnseated:FireClient(player)
		notify(player,{ code = "SeatFailed" })
		return false
	end
	tbl._npcDeckKey=npcDeckKey
	tbl._trainerName=trainerName
	TableManager.spawnNpcAt(tbl,2)
	onStartPvE(tbl)
	return true
end

function TableManager.handleStandUp(player)
	if getBattleForPlayer(player) then return end
	TableManager.unseatPlayer(player)
	Remotes.BattleUnseated:FireClient(player)
end

function TableManager.init(deps)
	Remotes=deps.Remotes; onStartPvE=deps.onStartPvE; onStartPvP=deps.onStartPvP; getBattleForPlayer=deps.getBattleForPlayer
	local folder=WS:FindFirstChild("Battle Stations")
	assert(folder,"[TableManager] Workspace.'Battle Stations' not found")
	local count=0
	for _,model in ipairs(folder:GetChildren()) do
		if not model:IsA("Model") then continue end
		count+=1; local tableId="table_"..count
		local chair1Model=model:FindFirstChild("Chair 1")
		local chair2Model=model:FindFirstChild("Chair 2")
		if not chair1Model or not chair2Model then warn("[TableManager] "..model.Name.." missing chairs, skipped"); count-=1; continue end
		local surfacePart
		local tableModel=model:FindFirstChild("Table")
		if tableModel and tableModel:IsA("Model") then
			for _,child in ipairs(tableModel:GetChildren()) do if child:IsA("BasePart") then surfacePart=child;break end end
		end
		if not surfacePart then for _,child in ipairs(model:GetDescendants()) do if child:IsA("BasePart") and child.Name~="Seat" then surfacePart=child;break end end end
		local tbl={model=model,tableId=tableId,state=FREE,battleId=nil,prompt=nil,npc=nil,
			chairs={[1]={model=chair1Model,seat=chair1Model:FindFirstChild("Seat"),player=nil},
			        [2]={model=chair2Model,seat=chair2Model:FindFirstChild("Seat"),player=nil}},
			readySet={}}
		for _,ch in ipairs(tbl.chairs) do if ch.seat then ch.seat.Disabled=true end end
		tables[tableId]=tbl
		if surfacePart then
			local pp=Instance.new("ProximityPrompt")
			pp.Name="TablePrompt"; pp.ActionText="Sit"; pp.KeyboardKeyCode=Enum.KeyCode.E
			pp.MaxActivationDistance=8; pp.HoldDuration=0; pp.RequiresLineOfSight=false; pp.Parent=surfacePart
			pp.Triggered:Connect(function(player) handleTablePrompt(player,tbl) end)
			tbl.prompt=pp
		else warn("[TableManager] "..model.Name.." has no BasePart for prompt anchor") end
		print("[TableManager] Registered "..model.Name.." as "..tableId)
	end
	print("[TableManager] Loaded "..count.." tables")
end

return TableManager

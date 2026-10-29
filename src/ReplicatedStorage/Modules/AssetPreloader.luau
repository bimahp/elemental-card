-- AssetPreloader: callback-verified, per-asset image warming with bounded concurrency.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")

local AssetPreloader = {}

local function uniqueArray(ids)
	if type(ids) ~= "table" then
		error("AssetPreloader.preload expects an array of content IDs", 3)
	end
	local seen, list = {}, {}
	for _, id in ipairs(ids) do
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			list[#list + 1] = id
		end
	end
	for key in pairs(ids) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #ids then
			error("AssetPreloader.preload does not accept dictionary or sparse tables", 3)
		end
	end
	return list
end

local function makeHolder(parent)
	local holder = Instance.new("ScreenGui")
	holder.Name = "AssetPreloadHolder"
	holder.Enabled = true
	holder.ResetOnSpawn = false
	holder.IgnoreGuiInset = true
	holder.DisplayOrder = -1000
	holder.Parent = parent or Players.LocalPlayer:WaitForChild("PlayerGui")
	return holder
end

local function preloadOne(holder, id, timeout)
	local image = Instance.new("ImageLabel")
	image.Name = "PreloadImage"
	image.Size = UDim2.fromOffset(1, 1)
	image.Position = UDim2.fromOffset(0, 0)
	image.BackgroundTransparency = 1
	image.ImageTransparency = 0
	image.Image = id
	image.Visible = true
	image.Parent = holder

	local finished = false
	local callbackStatus = nil
	local preloadError = nil
	local preloadThread = task.spawn(function()
		local ok, message = pcall(function()
			-- PreloadAsync requires an array. One instance per call lets this exact
			-- authored ID own the callback's final AssetFetchStatus.
			ContentProvider:PreloadAsync({ image }, function(_contentId, status)
				callbackStatus = status
			end)
		end)
		if not ok then preloadError = tostring(message) end
		finished = true
	end)

	local deadline = os.clock() + timeout
	local observedSuccess = false
	while not finished and os.clock() < deadline do
		local ok, status = pcall(ContentProvider.GetAssetFetchStatus, ContentProvider, id)
		if ok and status == Enum.AssetFetchStatus.Success then
			observedSuccess = true
			break
		end
		task.wait(0.05)
	end
	if not finished then pcall(task.cancel, preloadThread) end
	image:Destroy()

	if observedSuccess then return true, "SuccessStatus" end
	if not finished then return false, "TimedOut" end
	if preloadError then return false, preloadError end
	if callbackStatus == Enum.AssetFetchStatus.Success then return true, "Success" end
	return false, callbackStatus and callbackStatus.Name or "NoCallbackStatus"
end

-- ids MUST be a dense array: { "rbxassetid://...", ... }.
-- Completion uses only PreloadAsync's documented AssetFetchStatus callback.
function AssetPreloader.preload(ids, opts)
	opts = opts or {}
	local queue = uniqueArray(ids)
	local total = #queue
	local attempts = math.max(1, math.floor(opts.attempts or 3))
	local assetTimeout = math.max(1, opts.assetTimeout or 8)
	local concurrency = math.max(1, math.floor(opts.concurrency or 4))
	local onProgress = opts.onProgress

	if total == 0 then
		if onProgress then onProgress(0, 0) end
		return { ok = true, total = 0, loaded = 0, failed = {}, failureReasons = {} }
	end

	local holder = makeHolder(opts.parent)
	local nextIndex, completed, loaded = 0, 0, 0
	local failedByIndex, failureReasons = {}, {}
	local workersRemaining = math.min(concurrency, total)

	local function worker()
		while true do
			nextIndex += 1
			local index = nextIndex
			if index > total then break end
			local id = queue[index]
			local succeeded, reason = false, "NotAttempted"
			for attempt = 1, attempts do
				succeeded, reason = preloadOne(holder, id, assetTimeout)
				if succeeded then break end
				if attempt < attempts then task.wait(0.2 * attempt) end
			end
			if succeeded then
				loaded += 1
			else
				failedByIndex[index] = id
				failureReasons[id] = reason
			end
			completed += 1
			if onProgress then
				local ok, message = pcall(onProgress, completed, total)
				if not ok then warn("[AssetPreloader] progress callback failed: " .. tostring(message)) end
			end
		end
	end

	for _ = 1, workersRemaining do
		task.spawn(function()
			worker()
			workersRemaining -= 1
		end)
	end
	while workersRemaining > 0 do task.wait(0.05) end
	holder:Destroy()

	local failed = {}
	for index = 1, total do
		if failedByIndex[index] then failed[#failed + 1] = failedByIndex[index] end
	end
	return {
		ok = #failed == 0,
		total = total,
		loaded = loaded,
		failed = failed,
		failureReasons = failureReasons,
	}
end

-- Best-effort environment warm; it never gates the loading screen.
function AssetPreloader.describeFailures(summary)
	local parts = {}
	for _, id in ipairs(summary and summary.failed or {}) do
		local reason = summary.failureReasons and summary.failureReasons[id] or "Unknown"
		parts[#parts + 1] = ("%s [%s]"):format(id, tostring(reason))
	end
	return table.concat(parts, ", ")
end

function AssetPreloader.preloadInstances(instances)
	if type(instances) ~= "table" or #instances == 0 then return end
	task.spawn(function()
		local ok, message = pcall(function()
			ContentProvider:PreloadAsync(instances, function(contentId, status)
				if status == Enum.AssetFetchStatus.Failure then
					warn("[AssetPreloader] environment asset failed: " .. tostring(contentId))
				end
			end)
		end)
		if not ok then warn("[AssetPreloader] environment preload failed: " .. tostring(message)) end
	end)
end

return AssetPreloader

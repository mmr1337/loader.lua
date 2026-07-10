local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ReplicatedFirst    = game:GetService("ReplicatedFirst")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer
local config      = getgenv().TDX_Config or {}

local FIREBASE_URL = "https://apirobloxuser-default-rtdb.firebaseio.com"

local function httpRequest(method, url, body)
	local requestData = {
		Url     = url,
		Method  = method,
		Headers = {["Content-Type"] = "application/json"},
	}
	if body then
		requestData.Body = HttpService:JSONEncode(body)
	end
	local success, result = pcall(function()
		if syn and syn.request then
			return syn.request(requestData)
		elseif request then
			return request(requestData)
		elseif http and http.request then
			return http.request(requestData)
		else
			return HttpService:RequestAsync(requestData)
		end
	end)
	if success and result and result.StatusCode
		and result.StatusCode >= 200 and result.StatusCode < 300
	then
		if result.Body and result.Body ~= "null" and result.Body ~= "" then
			local ok, decoded = pcall(HttpService.JSONDecode, HttpService, result.Body)
			if ok then return decoded end
		end
		return nil
	end
	return nil
end

local function fbSet(path, data)
	print("[FB] SET:", path)
	return httpRequest("PUT", FIREBASE_URL .. path .. ".json", data)
end

local function fbGet(path)
	return httpRequest("GET", FIREBASE_URL .. path .. ".json")
end

local function fbDelete(path)
	print("[FB] DELETE:", path)
	return httpRequest("DELETE", FIREBASE_URL .. path .. ".json")
end

local function fbUpdate(path, updateFn)
	local data = fbGet(path)
	if data then
		updateFn(data)
		fbSet(path, data)
	end
end

local function waitForData(path, validator)
	while true do
		local data = fbGet(path)
		if data and validator(data) then return data end
		task.wait(2)
	end
end

local isVIP = false
for _ = 1, 30 do
	local attr = LocalPlayer:GetAttribute("VIP")
	if attr ~= nil then
		isVIP = (attr == true)
		break
	end
	task.wait(0.5)
end

local mapAliases = {
	["nm"]         = "NightmareWithMapVoting",
	["NM"]         = "NightmareWithMapVoting",
	["Nightmare"]  = "NightmareWithMapVoting",
	["Inter"]      = "Intermediate",
	["HW24Part1"]  = "Halloween24Part1",
	["HW24Part2"]  = "Halloween24Part2",
	["HW24Part3"]  = "Halloween24Part3",
	["HW24Part4"]  = "Halloween24Part4",
	["xmas24Part1"]  = "Christmas24Part1",
	["xmas24Part2"]  = "Christmas24Part2",
	["xmas25part1"]  = "Christmas25Part1",
	["tb"]           = "Tower Battles",
}

local specialMaps = {}
pcall(function()
	local common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
	local enums = require(common:WaitForChild("Enums"))
	for _, displayName in pairs(enums.LobbyTypes) do
		specialMaps[displayName] = true
	end
end)

local targetMapName = mapAliases[config["Map"] or "Tower Battles"]
	or config["Map"] or "Tower Battles"

local partyHost      = config["Party Host"]
local partyJoins     = config["Party Join"] or {}
local isHost         = partyHost and LocalPlayer.Name == partyHost
local isJoin         = false
local isSolo         = not partyHost or partyHost == ""

for _, name in ipairs(partyJoins) do
	if LocalPlayer.Name == name then
		isJoin = true
		break
	end
end

local expectedPlayers = (partyHost and partyHost ~= "" and 1 or 0) + #partyJoins
local sessionId       = partyHost and partyHost:gsub("%W","_") or LocalPlayer.Name:gsub("%W","_")
local sessionPath     = "/sessions/" .. sessionId

local function fbJoinPath(name)
	return sessionPath .. "/joins/" .. name:gsub("%W","_")
end

local function waitForAllJoins(field)
	waitForData(sessionPath, function(session)
		if not session.joins then return false end
		for _, joinName in ipairs(partyJoins) do
			local entry = session.joins[joinName:gsub("%W","_")]
			if not entry or not entry[field] then return false end
		end
		return true
	end)
end

local function runAPCLoop(onCount)
	local LeaveQueue = ReplicatedStorage:FindFirstChild("Network")
		and ReplicatedStorage.Network:FindFirstChild("LeaveQueue")

	while game.PlaceId == 9503261072 do
		for _, rootName in ipairs({"APCs","APCs2","BasementElevators"}) do
			local root = workspace:FindFirstChild(rootName)
			if root then
				for _, folder in ipairs(root:GetChildren()) do
					if folder:IsA("Folder") then
						local apc = folder:FindFirstChild("APC")
						local detector = apc and apc:FindFirstChild("Detector")
						local mapdisp  = folder:FindFirstChild("mapdisplay")
						local screen   = mapdisp
							and mapdisp:FindFirstChild("screen")
							and mapdisp.screen:FindFirstChild("displayscreen")

						if detector and screen then
							local mapLabel    = screen:FindFirstChild("map")
							local plrLabel    = screen:FindFirstChild("plrcount")
							local statusLabel = screen:FindFirstChild("status")

							if mapLabel and plrLabel and statusLabel
								and tostring(mapLabel.Text) == tostring(targetMapName)
								and statusLabel.Text ~= "TRANSPORTING..."
							then
								local cur, max = (plrLabel.Text or ""):match("(%d+)%s*/%s*(%d+)")
								cur, max = tonumber(cur), tonumber(max)
								if cur and max then
									onCount(cur, max, detector, LeaveQueue)
								end
							end
						end
					end
				end
			end
		end
		task.wait()
	end
end

local PATH_AGENT  = { AgentCanJump = true, AgentRadius = 2, AgentHeight = 5 }
local STEP_TIMEOUT = 6
local RECOMPUTE_DIST = 4

local function walkPath(humanoid, hrp, path)
	local waypoints = path:GetWaypoints()
	local i = 1

	if #waypoints > 1 then i = 2 end

	while i <= #waypoints do
		local wp = waypoints[i]

		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end

		humanoid:MoveTo(wp.Position)

		local done = false
		local conn = humanoid.MoveToFinished:Connect(function(reached)
			done = true
		end)

		local t0 = tick()
		repeat
			task.wait()

			if (hrp.Position - wp.Position).Magnitude < 2 then
				break
			end
		until done or (tick() - t0 >= STEP_TIMEOUT)

		conn:Disconnect()

		if not done and (tick() - t0 >= STEP_TIMEOUT) then
			return false
		end

		i += 1
	end
	return true
end

local function findApproachPoint(hrpPos, target)
	local angles = {0, 45, 90, 135, 180, 225, 270, 315}

	for _, r in ipairs({4, 8, 14}) do
		for _, deg in ipairs(angles) do
			local rad       = math.rad(deg)
			local candidate = Vector3.new(
				target.X + math.cos(rad) * r,
				target.Y,
				target.Z + math.sin(rad) * r
			)
			local p = PathfindingService:CreatePath(PATH_AGENT)
			local ok = pcall(function() p:ComputeAsync(hrpPos, candidate) end)
			if ok and p.Status == Enum.PathStatus.Success then
				return candidate, p
			end
		end
	end

	for _, r in ipairs({3, 6}) do
		for _, deg in ipairs(angles) do
			local rad       = math.rad(deg)
			local candidate = Vector3.new(
				hrpPos.X + math.cos(rad) * r,
				hrpPos.Y,
				hrpPos.Z + math.sin(rad) * r
			)
			local p = PathfindingService:CreatePath(PATH_AGENT)
			local ok = pcall(function() p:ComputeAsync(hrpPos, candidate) end)
			if ok and p.Status == Enum.PathStatus.Success then
				return candidate, p
			end
		end
	end

	return nil, nil
end

local function doWalk(humanoid, hrp, target)

	local path = PathfindingService:CreatePath(PATH_AGENT)
	local ok   = pcall(function() path:ComputeAsync(hrp.Position, target) end)

	if ok and path.Status == Enum.PathStatus.Success then
		if walkPath(humanoid, hrp, path) then return true end
	end

	local midPoint, midPath = findApproachPoint(hrp.Position, target)
	if midPoint then
		walkPath(humanoid, hrp, midPath)

		local finalPath = PathfindingService:CreatePath(PATH_AGENT)
		local ok2 = pcall(function() finalPath:ComputeAsync(hrp.Position, target) end)
		if ok2 and finalPath.Status == Enum.PathStatus.Success then
			if walkPath(humanoid, hrp, finalPath) then return true end
		end
	end

	if hrp.Position.Y > target.Y + 2 then
		humanoid:MoveTo(target)
		humanoid.Jump = true
		task.wait(0.3)
		humanoid.Jump = true
		return false
	end

	humanoid:MoveTo(target)
	return false
end

local function WalkToDetector(detector)
	local respawned  = false
	local respawnConn = LocalPlayer.CharacterAdded:Connect(function() respawned = true end)

	local sprintSpeed = workspace:GetAttribute("PlayerSprintspeed") or 26

	local detPos    = detector.Position
	local lookFlat  = Vector3.new(detector.CFrame.LookVector.X, 0, detector.CFrame.LookVector.Z).Unit
	local target    = detPos + lookFlat * 2

	while true do
		local char     = LocalPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local hrp      = char and char:FindFirstChild("HumanoidRootPart")

		if not humanoid or not hrp then
			task.wait(2)
			continue
		end

		if (hrp.Position - target).Magnitude < 5 then
			break
		end

		respawned = false
		local savedSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = sprintSpeed

		doWalk(humanoid, hrp, target)

		humanoid.WalkSpeed = savedSpeed

		if respawned then
			print("[Walk] Respawned, retrying...")
			task.wait(2)
		else
			break
		end
	end

	respawnConn:Disconnect()
end

if game.PlaceId == 9503261072 then

	if isHost then
		local jobId = game.JobId

		print("[Host] Cleaning old session")
		fbDelete(sessionPath)
		task.wait(2)

		print("[Host] Creating new session | JobId:", jobId)
		fbSet(sessionPath, {
			host   = LocalPlayer.Name,
			vip    = isVIP,
			status = "waiting",
			jobId  = jobId,
			joins  = {},
		})

		if isVIP then
			for _, joinName in ipairs(partyJoins) do
				fbSet(fbJoinPath(joinName), {
					onServer = false, invited = false,
					accepted = false, ready   = false,
				})
			end

			print("[Host VIP] Waiting for all joins on server")
			waitForAllJoins("onServer")
			print("[Host VIP] All joins on server, starting party")

			local net = ReplicatedStorage:WaitForChild("Network")
			net:WaitForChild("ClientChangePartyTypeRequest"):FireServer("Party")
			task.wait(0.5)

			task.spawn(function()
				while game.PlaceId == 9503261072 do
					for _, joinName in ipairs(partyJoins) do
						local joinPlayer = Players:FindFirstChild(joinName)
						if joinPlayer then
							local joinData = fbGet(fbJoinPath(joinName))
							if joinData and joinData.onServer and not joinData.accepted then
								print("[Host VIP] Sending invite to:", joinName)
								pcall(function()
									net:WaitForChild("ClientInviteToPartyRequest"):FireServer(joinPlayer)
								end)
								fbUpdate(fbJoinPath(joinName), function(d) d.invited = true end)
							end
						end
					end
					task.wait(3)
				end
			end)

			print("[Host VIP] Waiting for all joins to accept")
			waitForAllJoins("accepted")
			print("[Host VIP] Waiting for all joins to be ready")
			waitForAllJoins("ready")
			print("[Host VIP] All joins ready")

			local difficulty = config["Auto Difficulty"] or "Elite"
			print("[Host VIP] Setting difficulty:", difficulty)
			net:WaitForChild("ClientChangePartyMapRequest"):FireServer(difficulty)
			task.wait(1)

			print("[Host VIP] Cleaning session before start")
			fbDelete(sessionPath)
			task.wait(2)

			print("[Host VIP] Starting game")
			net:WaitForChild("ClientStartGameRequest"):FireServer()

		else
			for _, joinName in ipairs(partyJoins) do
				fbSet(fbJoinPath(joinName), {onServer = false})
			end

			print("[Host Non-VIP] Waiting for all joins on server")
			waitForAllJoins("onServer")
			print("[Host Non-VIP] All joins on server, starting APC walk")

			runAPCLoop(function(cur, max, detector, LeaveQueue)
				if cur == 0 and max == 4 then
					print("[Host Non-VIP] Walking to APC (0/4)")
					WalkToDetector(detector)
				elseif cur > expectedPlayers and max == 4 and LeaveQueue then
					print("[Host Non-VIP] Too many players, leaving")
					pcall(LeaveQueue.FireServer, LeaveQueue)
				end
			end)
		end

	elseif isJoin then
		print("[Join] Waiting for host session")
		local session = waitForData(sessionPath, function(data)
			return data.vip ~= nil and data.jobId and data.jobId ~= ""
		end)

		local hostJobId = session.jobId
		local hostVIP   = session.vip
		local myJobId   = game.JobId

		print("[Join] Host VIP:", hostVIP, "| Host JobId:", hostJobId, "| My JobId:", myJobId)

		if hostJobId ~= myJobId then
			print("[Join] Teleporting to host server")
			local CoreGui = game:GetService("CoreGui")
			if CoreGui.RobloxPromptGui:FindFirstChild("promptOverlay") then
				CoreGui.RobloxPromptGui.promptOverlay.Visible = false
			end
			TeleportService:TeleportToPlaceInstance(9503261072, hostJobId, LocalPlayer)
			task.wait(5)
			return
		end

		print("[Join] Already on host server")

		local myPath      = fbJoinPath(LocalPlayer.Name)
		local currentData = fbGet(myPath)
		if currentData then
			currentData.onServer = true
			fbSet(myPath, currentData)
		else
			fbSet(myPath, {onServer = true})
		end

		if hostVIP then
			print("[Join VIP] Hooking invite event")
			local Network = require(ReplicatedFirst:WaitForChild("Client"):WaitForChild("Network"))
			local net     = ReplicatedStorage:WaitForChild("Network")
			local inviteHandled = false

			Network.HookEvent("PartyInvitePrompt", function(inviter, partyId)
				if inviter and inviter.Name == partyHost and not inviteHandled then
					inviteHandled = true
					print("[Join VIP] Got invite - PartyId:", partyId)
					task.wait(0.2)

					print("[Join VIP] Accepting invite")
					pcall(function()
						net:WaitForChild("ClientAcceptInviteRequest"):FireServer(inviter, partyId)
					end)
					fbUpdate(myPath, function(d) d.accepted = true end)

					task.wait(0.5)
					print("[Join VIP] Setting ready")
					pcall(function()
						net:WaitForChild("ClientSetPartyReadyStateRequest"):FireServer(true)
					end)
					fbUpdate(myPath, function(d) d.ready = true end)
				end
			end)

			print("[Join VIP] Waiting for session cleanup")
			while true do
				if not fbGet(sessionPath) then
					print("[Join VIP] Session deleted, game starting")
					break
				end
				task.wait(2)
			end

		else
			print("[Join Non-VIP] Starting APC walk")
			runAPCLoop(function(cur, max, detector, LeaveQueue)
				if cur == 0 and max == 4 then
					print("[Join Non-VIP] Walking to APC (0/4)")
					WalkToDetector(detector)
				elseif cur == expectedPlayers and max == 4 then

				elseif cur > expectedPlayers and max == 4 and LeaveQueue then
					print("[Join Non-VIP] Too many players, leaving")
					pcall(LeaveQueue.FireServer, LeaveQueue)
				end
			end)
		end

	else
		if specialMaps[targetMapName] then
			ReplicatedStorage:WaitForChild("Network")
				:WaitForChild("ClientRequestSoloGame")
				:InvokeServer(targetMapName)
			return
		end

		runAPCLoop(function(cur, max, detector, LeaveQueue)
			if cur == 0 and max == 4 then
				local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if hrp then WalkToDetector(detector) end
			elseif cur >= 2 and max == 4 and LeaveQueue then
				pcall(LeaveQueue.FireServer, LeaveQueue)
			end
		end)
	end
end

if config.mapvoting then
	local function normalize(t)
		return string.upper((t:gsub("%s+", " ")):gsub("^%s*(.-)%s*$", "%1"))
	end
	local function titleCase(t)
		return t:gsub("(%w)(%w*)", function(a, b) return a:upper() .. b:lower() end)
	end

	local targetMap = normalize(config.mapvoting)
	local voteName  = titleCase(config.mapvoting)

	if isVIP and (isHost or isSolo) then
		if isHost then print("[Host] VIP map override:", voteName) end

		local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
		if not Remotes then return end

		pcall(function() Remotes:WaitForChild("MapOverride"):FireServer(voteName) end)
		task.wait(1)
		pcall(function() Remotes:WaitForChild("MapVoteCast"):FireServer(voteName) end)
		task.wait(1)
		pcall(function() Remotes:WaitForChild("MapVoteReady"):FireServer() end)

		if isHost then
			task.wait(2)
			print("[Host] Cleaning session after map vote")
			fbDelete(sessionPath)
		end
		return
	end

	if isJoin then
		print("[Join] Waiting for host map selection")
		local Remotes = ReplicatedStorage:WaitForChild("Remotes")
		task.wait(3)
		pcall(function() Remotes:WaitForChild("MapVoteCast"):FireServer(voteName) end)
		task.wait(0.5)
		pcall(function() Remotes:WaitForChild("MapVoteReady"):FireServer() end)
		return
	end

	local playerGui       = LocalPlayer:WaitForChild("PlayerGui")
	local mapVotingScreen = playerGui:WaitForChild("Interface"):WaitForChild("MapVotingScreen")
	local Remotes         = ReplicatedStorage:WaitForChild("Remotes")

	repeat task.wait() until mapVotingScreen.Visible

	local mapFound = false
	for i = 1, 4 do
		local screen = workspace
			:WaitForChild("Game")
			:WaitForChild("MapVoting")
			:WaitForChild("VotingScreens")
			:FindFirstChild("VotingScreen" .. i)
		if screen then
			local nameLabel = screen
				:WaitForChild("ScreenPart")
				:WaitForChild("SurfaceGui")
				:WaitForChild("MapName")
			if normalize(nameLabel.Text) == targetMap then
				mapFound = true
				break
			end
		end
	end

	if not mapFound then
		local changeRemote = Remotes:WaitForChild("MapChangeVoteCast")
		local changeBtn    = mapVotingScreen.Bottom:WaitForChild("ChangeMap")
		while not changeBtn.Disabled.Visible do
			changeRemote:FireServer(true)
			task.wait(0.5)
		end
		TeleportService:Teleport(9503261072)
		return
	end

	Remotes:WaitForChild("MapVoteCast"):FireServer(voteName)
	task.wait(0.1)
	Remotes:WaitForChild("MapVoteReady"):FireServer()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local config = getgenv().TDX_Config or {}

local FIREBASE_URL = "https://apirobloxuser-default-rtdb.firebaseio.com/"
local LOBBY_PLACE_ID = 9503261072

local isVIP = false
for i = 1, 30 do
    local attr = LocalPlayer:GetAttribute("VIP")
    if attr ~= nil then
        isVIP = (attr == true)
        break
    end
    task.wait(0.5)
end

local mapAliases = {
    ["nm"] = "NightmareWithMapVoting", ["NM"] = "NightmareWithMapVoting", ["Nightmare"] = "NightmareWithMapVoting",
    ["Inter"] = "Intermediate",
    ["HW24Part1"] = "Halloween24Part1", ["HW24Part2"] = "Halloween24Part2",
    ["HW24Part3"] = "Halloween24Part3", ["HW24Part4"] = "Halloween24Part4",
    ["xmas24Part1"] = "Christmas24Part1", ["xmas24Part2"] = "Christmas24Part2",
    ["xmas25part1"] = "Christmas25Part1",
    ["tb"] = "Tower Battles",
}

local specialMaps = {
    ["Halloween Part 1"]=true,["Halloween Part 2"]=true,["Halloween Part 3"]=true,["Halloween Part 4"]=true,
    ["Halloween24Part1"]=true,["Halloween24Part2"]=true,["Halloween24Part3"]=true,["Halloween24Part4"]=true,
    ["Halloween2025"]=true,["Tower Battles"]=true,
    ["Christmas24Part1"]=true,["Christmas24Part2"]=true,["Christmas25Part1"]=true,["Christmas25Part2"]=true,
    ["Easy"]=true,["Intermediate"]=true,["Elite"]=true,["Expert"]=true,["Endless"]=true,
    ["NightmareWithMapVoting"]=true,
}

getgenv().PartySystemBlocked = getgenv().PartySystemBlocked or {
    Ready = false,
    Party = false,
    Active = false
}

local HOST_USERNAME = config["Party Host"]
local JOIN_USERNAMES = config["Party Join"] or {}

local isPartyMode = (HOST_USERNAME and HOST_USERNAME ~= "")
local isHost = isPartyMode and (LocalPlayer.Name:lower() == HOST_USERNAME:lower())
local isJoin = false

if isPartyMode then
    if type(JOIN_USERNAMES) == "string" then
        JOIN_USERNAMES = {JOIN_USERNAMES}
    end
    
    for _, username in ipairs(JOIN_USERNAMES) do
        if LocalPlayer.Name:lower() == username:lower() then
            isJoin = true
            break
        end
    end
end

local function getPlayerFromUsername(username)
    for _, player in pairs(Players:GetPlayers()) do
        if player.Name:lower() == username:lower() then
            return player
        end
    end
    return nil
end

local function generatePartyId()
    return HttpService:GenerateGUID(false):lower()
end

local function httpRequest(method, url, body)
    local requestData = {
        Url = url,
        Method = method,
        Headers = {["Content-Type"] = "application/json"}
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
    
    if success and result and result.StatusCode and result.StatusCode >= 200 and result.StatusCode < 300 then
        if result.Body and result.Body ~= "null" and result.Body ~= "" then
            local decodeSuccess, decoded = pcall(function()
                return HttpService:JSONDecode(result.Body)
            end)
            if decodeSuccess then
                return decoded
            end
        end
        return true
    end
    
    return nil
end

local function firebaseSet(path, data)
    local url = FIREBASE_URL .. path .. ".json"
    return httpRequest("PUT", url, data)
end

local function firebaseGet(path)
    local url = FIREBASE_URL .. path .. ".json"
    return httpRequest("GET", url)
end

local function getJobId()
    return game.JobId
end

if game.PlaceId == LOBBY_PLACE_ID and isPartyMode and (isHost or isJoin) then
    getgenv().PartySystemBlocked.Active = true
    getgenv().PartySystemBlocked.Ready = true
    getgenv().PartySystemBlocked.Party = true
    
    task.wait(3)
    
    if isHost then
        local jobId = getJobId()
        local sessionId = HttpService:GenerateGUID(false)
        
        firebaseSet("party_sessions/" .. HOST_USERNAME, {
            jobId = jobId,
            sessionId = sessionId,
            timestamp = os.time(),
            readyJoins = {},
            acceptedJoins = {}
        })
        
        pcall(function()
            ReplicatedStorage.Network.ClientChangePartyTypeRequest:FireServer("Party")
        end)
        
        task.wait(1)
        
        local currentPartyId = generatePartyId()
        local expectedJoins = {}
        
        for _, username in ipairs(JOIN_USERNAMES) do
            if username ~= "" then
                table.insert(expectedJoins, username)
            end
        end
        
        local maxWaitTime = 120
        local startTime = tick()
        local allJoinsReady = false
        
        task.spawn(function()
            while tick() - startTime < maxWaitTime and not allJoinsReady do
                local sessionData = firebaseGet("party_sessions/" .. HOST_USERNAME)
                
                if sessionData and sessionData.readyJoins then
                    local readyCount = 0
                    
                    for _, username in ipairs(expectedJoins) do
                        if sessionData.readyJoins[username] == true then
                            readyCount = readyCount + 1
                        end
                    end
                    
                    if readyCount == #expectedJoins then
                        allJoinsReady = true
                        break
                    end
                end
                
                task.wait(2)
            end
        end)
        
        while not allJoinsReady and tick() - startTime < maxWaitTime do
            task.wait(0.5)
        end
        
        if allJoinsReady then
            for _, joinUsername in ipairs(JOIN_USERNAMES) do
                if joinUsername ~= "" then
                    local joinPlayer = getPlayerFromUsername(joinUsername)
                    
                    if joinPlayer then
                        pcall(function()
                            ReplicatedStorage.Network.ClientInviteToPartyRequest:FireServer(joinPlayer)
                        end)
                        
                        task.wait(1)
                    end
                end
            end
            
            local allAccepted = false
            local acceptStartTime = tick()
            local maxAcceptWait = 60
            
            task.spawn(function()
                while tick() - acceptStartTime < maxAcceptWait and not allAccepted do
                    local sessionData = firebaseGet("party_sessions/" .. HOST_USERNAME)
                    
                    if sessionData and sessionData.acceptedJoins then
                        local acceptCount = 0
                        
                        for _, username in ipairs(expectedJoins) do
                            if sessionData.acceptedJoins[username] == true then
                                acceptCount = acceptCount + 1
                            end
                        end
                        
                        if acceptCount == #expectedJoins then
                            allAccepted = true
                            break
                        end
                    end
                    
                    task.wait(2)
                end
            end)
            
            while not allAccepted and tick() - acceptStartTime < maxAcceptWait do
                task.wait(0.5)
            end
            
            if allAccepted then
                getgenv().PartySystemBlocked.Ready = false
                
                pcall(function()
                    ReplicatedStorage.Network.ClientSetPartyReadyStateRequest:FireServer(true)
                end)
                
                task.wait(1)
                
                pcall(function()
                    ReplicatedStorage.Network.ClientStartGameRequest:FireServer()
                end)
            end
        end
        
        Players.PlayerAdded:Connect(function(player)
            for _, joinUsername in ipairs(JOIN_USERNAMES) do
                if player.Name:lower() == joinUsername:lower() then
                    task.wait(3)
                    pcall(function()
                        ReplicatedStorage.Network.ClientInviteToPartyRequest:FireServer(player)
                    end)
                end
            end
        end)
    end
    
    if isJoin then
        local maxWaitTime = 120
        local startTime = tick()
        local hostJobId = nil
        
        while tick() - startTime < maxWaitTime do
            local sessionData = firebaseGet("party_sessions/" .. HOST_USERNAME)
            
            if sessionData and sessionData.jobId then
                hostJobId = sessionData.jobId
                break
            end
            
            task.wait(3)
        end
        
        if hostJobId and hostJobId ~= "" and hostJobId ~= getJobId() then
            local CoreGui = game:GetService("CoreGui")
            if CoreGui.RobloxPromptGui:FindFirstChild("promptOverlay") then
                CoreGui.RobloxPromptGui.promptOverlay.Visible = false
            end
            
            TeleportService:TeleportToPlaceInstance(LOBBY_PLACE_ID, hostJobId, LocalPlayer)
            return
        end
        
        if hostJobId == getJobId() then
            local hostPlayer = getPlayerFromUsername(HOST_USERNAME)
            
            if hostPlayer then
                local sessionData = firebaseGet("party_sessions/" .. HOST_USERNAME)
                
                if sessionData then
                    sessionData.readyJoins = sessionData.readyJoins or {}
                    sessionData.readyJoins[LocalPlayer.Name] = true
                    firebaseSet("party_sessions/" .. HOST_USERNAME, sessionData)
                end
            end
        end
        
        local hasAccepted = false
        local Network = nil
        
        pcall(function()
            Network = require(ReplicatedFirst:WaitForChild("Client", 5):WaitForChild("Network", 5))
        end)
        
        local function acceptInvite(inviter, partyId)
            if hasAccepted then return end
            
            if inviter and inviter.Name:lower() == HOST_USERNAME:lower() then
                task.wait(0.5)
                
                local acceptSuccess = pcall(function()
                    ReplicatedStorage.Network.ClientAcceptInviteRequest:FireServer(inviter, partyId)
                end)
                
                if acceptSuccess then
                    hasAccepted = true
                    
                    local sessionData = firebaseGet("party_sessions/" .. HOST_USERNAME)
                    
                    if sessionData then
                        sessionData.acceptedJoins = sessionData.acceptedJoins or {}
                        sessionData.acceptedJoins[LocalPlayer.Name] = true
                        firebaseSet("party_sessions/" .. HOST_USERNAME, sessionData)
                    end
                    
                    task.wait(2)
                    
                    getgenv().PartySystemBlocked.Ready = false
                    
                    pcall(function()
                        ReplicatedStorage.Network.ClientSetPartyReadyStateRequest:FireServer(true)
                    end)
                end
            end
        end
        
        if Network then
            Network.HookEvent("PartyInvitePrompt", function(inviter, partyId, lobbyType, memberCount)
                acceptInvite(inviter, partyId)
            end)
        else
            local InvitePromptEvent = ReplicatedStorage.Network:WaitForChild("PartyInvitePrompt", 10)
            
            if InvitePromptEvent then
                InvitePromptEvent.OnClientEvent:Connect(function(inviter, partyId, lobbyType, memberCount)
                    acceptInvite(inviter, partyId)
                end)
            end
        end
    end
    
    task.wait(10)
    getgenv().PartySystemBlocked.Party = false
end

local targetMapName = mapAliases[config["Map"] or "Christmas24Part1"] or config["Map"] or "Christmas24Part1"

if game.PlaceId == LOBBY_PLACE_ID then
    if specialMaps[targetMapName] and not isPartyMode then
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientChangePartyTypeRequest"):FireServer("Party")
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientChangePartyMapRequest"):FireServer(targetMapName)
        task.wait(1.5)
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientStartGameRequest"):FireServer()
    end

    local LeaveQueue = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("LeaveQueue")

    while game.PlaceId == LOBBY_PLACE_ID do
        for _, rootName in ipairs({"APCs","APCs2","BasementElevators"}) do
            local root = workspace:FindFirstChild(rootName)
            if root then
                for _, folder in ipairs(root:GetChildren()) do
                    if folder:IsA("Folder") then
                        local detector = folder:FindFirstChild("APC") and folder.APC:FindFirstChild("Detector")
                        local displayscreen = folder:FindFirstChild("mapdisplay")
                            and folder.mapdisplay:FindFirstChild("screen")
                            and folder.mapdisplay.screen:FindFirstChild("displayscreen")

                        if detector and displayscreen then
                            local mapLabel = displayscreen:FindFirstChild("map")
                            local plrLabel = displayscreen:FindFirstChild("plrcount")
                            local statusLabel = displayscreen:FindFirstChild("status")

                            if mapLabel and plrLabel and statusLabel
                                and tostring(mapLabel.Text) == tostring(targetMapName)
                                and statusLabel.Text ~= "TRANSPORTING..."
                            then
                                local cur, max = (plrLabel.Text or ""):match("(%d+)%s*/%s*(%d+)")
                                cur, max = tonumber(cur), tonumber(max)
                                if cur and max then
                                    if cur == 0 and max == 4 then
                                        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                                        if hrp then hrp.CFrame = detector.CFrame * CFrame.new(0,0,-2) end
                                    elseif cur >= 2 and max == 4 and LeaveQueue then
                                        pcall(LeaveQueue.FireServer, LeaveQueue)
                                    end
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

if config.mapvoting then
    local function normalize(t) return string.upper((t:gsub("%s+", " ")):gsub("^%s*(.-)%s*$", "%1")) end
    local function titleCase(t) return t:gsub("(%w)(%w*)", function(a,b) return a:upper()..b:lower() end) end

    local targetMap = normalize(config.mapvoting)
    local voteName = titleCase(config.mapvoting)

    if isVIP then
        local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not Remotes then return end

        pcall(function()
            Remotes:WaitForChild("MapOverride"):FireServer(voteName)
        end)

        task.wait(1)

        pcall(function()
            Remotes:WaitForChild("MapVoteCast"):FireServer(voteName)
        end)

        task.wait(1)

        if not getgenv().PartySystemBlocked.Ready then
            pcall(function()
                Remotes:WaitForChild("MapVoteReady"):FireServer()
            end)
        end

        return
    end

    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local mapVotingScreen = playerGui:WaitForChild("Interface"):WaitForChild("MapVotingScreen")
    local Remotes = ReplicatedStorage:WaitForChild("Remotes")

    repeat task.wait() until mapVotingScreen.Visible

    local mapFound = false
    for i = 1, 4 do
        local screen = workspace:WaitForChild("Game"):WaitForChild("MapVoting"):WaitForChild("VotingScreens"):FindFirstChild("VotingScreen"..i)
        if screen and normalize(screen:WaitForChild("ScreenPart"):WaitForChild("SurfaceGui"):WaitForChild("MapName").Text) == targetMap then
            mapFound = true
            break
        end
    end

    if not mapFound then
        local changeRemote = Remotes:WaitForChild("MapChangeVoteCast")
        local changeBtn = mapVotingScreen.Bottom:WaitForChild("ChangeMap")
        while not changeBtn.Disabled.Visible do
            changeRemote:FireServer(true)
            task.wait(0.5)
        end
        TeleportService:Teleport(LOBBY_PLACE_ID)
        return
    end

    Remotes:WaitForChild("MapVoteCast"):FireServer(voteName)
    task.wait(0.1)
    
    if not getgenv().PartySystemBlocked.Ready then
        Remotes:WaitForChild("MapVoteReady"):FireServer()
    end
end

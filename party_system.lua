local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}
local HOST_USERNAME = config["Party Host"]
local JOIN_USERNAMES = config["Party Join"] or {}

if not HOST_USERNAME or HOST_USERNAME == "" then
    warn("⚠ Party System: No host specified")
    return
end

if type(JOIN_USERNAMES) == "string" then
    JOIN_USERNAMES = {JOIN_USERNAMES}
end

if #JOIN_USERNAMES == 0 then
    warn("Party System: No join players specified")
    return
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

local function waitForAllJoinPlayers()
    local foundPlayers = {}
    local maxWaitTime = 60
    local startTime = tick()
    
    while tick() - startTime < maxWaitTime do
        foundPlayers = {}
        for _, username in ipairs(JOIN_USERNAMES) do
            local player = getPlayerFromUsername(username)
            if player then
                table.insert(foundPlayers, player)
            end
        end
        
        if #foundPlayers == #JOIN_USERNAMES then
            return foundPlayers
        end
        
        task.wait(1)
    end
    
    return foundPlayers
end
local isHost = LocalPlayer.Name:lower() == HOST_USERNAME:lower()
local isJoin = false

for _, username in ipairs(JOIN_USERNAMES) do
    if LocalPlayer.Name:lower() == username:lower() then
        isJoin = true
        break
    end
end

if not isHost and not isJoin then
    warn("Party System: This player is neither host nor join player!")
    return
end

print("Party System Loaded for: " .. LocalPlayer.Name)
task.wait(3)
if isHost then
    print("Running as PARTY HOST: " .. LocalPlayer.Name)
    local success, err = pcall(function()
        local ChangePartyTypeEvent = ReplicatedStorage.Network.ClientChangePartyTypeRequest
        ChangePartyTypeEvent:FireServer("Party")
    end)
    
    if success then
        print("Party type set to 'Party'")
    else
        warn("Failed to set party type: " .. tostring(err))
    end
    
    task.wait(1)
    local currentPartyId = generatePartyId()
    print("Generated Party ID: " .. currentPartyId)
    local invitedPlayers = {}
    
    for _, joinUsername in ipairs(JOIN_USERNAMES) do
        if joinUsername ~= "" then
            local joinPlayer = getPlayerFromUsername(joinUsername)
            
            if joinPlayer then
                print("Sending invite to: " .. joinPlayer.Name)
                
                local inviteSuccess, inviteErr = pcall(function()
                    local InviteEvent = ReplicatedStorage.Network.ClientInviteToPartyRequest
                    InviteEvent:FireServer(joinPlayer)
                end)
                
                if inviteSuccess then
                    print("Invite sent to " .. joinPlayer.Name)
                    table.insert(invitedPlayers, joinPlayer)
                else
                    warn("Failed to invite " .. joinPlayer.Name .. ": " .. tostring(inviteErr))
                end
                
                task.wait(1)
            else
                warn("Join player not found: " .. joinUsername)
            end
        end
    end
    print("Waiting for all players to join...")
    task.wait(5)
    print("All invites sent, setting ready state...")
    
    local readySuccess, readyErr = pcall(function()
        local ReadyEvent = ReplicatedStorage.Network.ClientSetPartyReadyStateRequest
        ReadyEvent:FireServer(true)
    end)
    
    if readySuccess then
        print("Host is now READY")
    else
        warn("Failed to set ready state: " .. tostring(readyErr))
    end
    Players.PlayerAdded:Connect(function(player)
        for _, joinUsername in ipairs(JOIN_USERNAMES) do
            if player.Name:lower() == joinUsername:lower() then
                print("Join player reconnected: " .. player.Name)
                task.wait(3)
                
                pcall(function()
                    local InviteEvent = ReplicatedStorage.Network.ClientInviteToPartyRequest
                    InviteEvent:FireServer(player)
                    print("Auto-invited " .. player.Name)
                end)
            end
        end
    end)
end
if isJoin then
    print("Running as JOIN PLAYER: " .. LocalPlayer.Name)
    
    local hasAccepted = false
    local Network = nil
    local success, err = pcall(function()
        Network = require(ReplicatedFirst:WaitForChild("Client", 5):WaitForChild("Network", 5))
    end)
    
    local function acceptInvite(inviter, partyId)
        if hasAccepted then return end
        
        if inviter and inviter.Name:lower() == HOST_USERNAME:lower() then
            print("Received invite from host: " .. inviter.Name)
            print("Party ID: " .. partyId)
            
            task.wait(0.5)
            
            local acceptSuccess, acceptErr = pcall(function()
                local AcceptEvent = ReplicatedStorage.Network.ClientAcceptInviteRequest
                AcceptEvent:FireServer(inviter, partyId)
            end)
            
            if acceptSuccess then
                print("Successfully accepted invite from " .. inviter.Name)
                hasAccepted = true
                task.wait(2)
                
                local readySuccess, readyErr = pcall(function()
                    local ReadyEvent = ReplicatedStorage.Network.ClientSetPartyReadyStateRequest
                    ReadyEvent:FireServer(true)
                end)
                
                if readySuccess then
                    print("Join player is now READY")
                else
                    warn("Failed to set ready state: " .. tostring(readyErr))
                end
            else
                warn("Failed to accept invite: " .. tostring(acceptErr))
            end
        else
            print("Ignored invite from: " .. (inviter and inviter.Name or "Unknown"))
        end
    end
    
    if not success or not Network then
        warn("Using direct hook method")
        
        local InvitePromptEvent = ReplicatedStorage.Network:WaitForChild("PartyInvitePrompt", 10)
        
        if InvitePromptEvent then
            InvitePromptEvent.OnClientEvent:Connect(function(inviter, partyId, lobbyType, memberCount)
                acceptInvite(inviter, partyId)
            end)
            
            print("Listening for invites from: " .. HOST_USERNAME .. " (Direct)")
        else
            warn("PartyInvitePrompt event not found!")
        end
    else
        Network.HookEvent("PartyInvitePrompt", function(inviter, partyId, lobbyType, memberCount)
            acceptInvite(inviter, partyId)
        end)
        
        print("Listening for invites from: " .. HOST_USERNAME .. " (Network module)")
    end
end

print("Party System initialized successfully!")

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "by dem3x3",
    Footer = "version: 2.0",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

repeat wait() until game:IsLoaded() and Players.LocalPlayer
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

local function getEmbeddedRecordScript(macroFileName)
    local outJson = "tdx/macros/" .. macroFileName .. ".json"
    
    if not isfile or not isfile(outJson) then
        if makefolder then
            pcall(makefolder, "tdx")
            pcall(makefolder, "tdx/macros")
        end
        writefile(outJson, "[]")
    end
    
    return [[
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

local outJson = "]] .. outJson .. [["

if isfile and isfile(outJson) then
    writefile(outJson, "[]")
end

local recordedActions = {}
local hash2pos = {}
local pendingQueue = {}
local timeout = 2
local lastKnownLevels = {}
local lastUpgradeTime = {}

local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local globalEnv = getGlobalEnv()

local TowerClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = require(towerModule)
end)

if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
        end
    end
end

local function GetTowerSpawnPosition(tower)
    if not tower then return nil end
    local spawnCFrame = tower.SpawnCFrame
    if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
        return spawnCFrame.Position
    end
    return nil
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, towerButton in ipairs(towersBar:GetChildren()) do
        if towerButton.Name == name then
            local costFrame = towerButton:FindFirstChild("CostFrame")
            if costFrame then
                local costText = costFrame:FindFirstChild("CostText")
                if costText and costText:IsA("TextLabel") then
                    local raw = tostring(costText.Text):gsub("%D", "")
                    return tonumber(raw) or 0
                end
            end
        end
    end
    return 0
end

local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil, nil end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil, nil end
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return nil, nil end
    local wave = gameInfoBar.Wave.WaveText.Text
    local time = gameInfoBar.TimeLeft.TimeLeftText.Text
    return wave, time
end

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

local function GetTowerNameByHash(towerHash)
    if not TowerClass or not TowerClass.GetTowers then return nil end
    local towers = TowerClass.GetTowers()
    local tower = towers[towerHash]
    if tower and tower.Type then
        return tower.Type
    end
    return nil
end

local function IsMovingSkillTower(towerName, skillIndex)
    if not towerName or not skillIndex then return false end
    if towerName == "Helicopter" and (skillIndex == 1 or skillIndex == 3) then return true end
    if towerName == "Cryo Helicopter" and (skillIndex == 1 or skillIndex == 3) then return true end
    if towerName == "Jet Trooper" and skillIndex == 1 then return true end
    return false
end

local function IsPositionRequiredSkill(towerName, skillIndex)
    if not towerName or not skillIndex then return false end
    if skillIndex == 1 then return true end
    if skillIndex == 3 then return false end
    return true
end

local function updateJsonFile()
    if not HttpService then return end
    local jsonLines = {}
    for i, entry in ipairs(recordedActions) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            if i < #recordedActions then
                jsonStr = jsonStr .. ","
            end
            table.insert(jsonLines, jsonStr)
        end
    end
    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    safeWriteFile(outJson, finalJson)
end

local function parseMacroLine(line)
    if line:match('TDX:skipWave%(%)') then
        local currentWave, currentTime = getCurrentWaveAndTime()
        
        local waveName = currentWave and string.upper(tostring(currentWave)) or "UNKNOWN"
        local timeNumber = convertTimeToNumber(currentTime)
        return {{
            SkipWave = waveName,
            skip = true,
            time = timeNumber
        }}
    end

    local hash, skillIndex, x, y, z = line:match('TDX:useMovingSkill%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%)')
    if hash and skillIndex and x and y and z then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                towermoving = pos.x,
                skillindex = tonumber(skillIndex),
                location = string.format("%s, %s, %s", x, y, z),
                wave = currentWave,
                time = convertTimeToNumber(currentTime)
            }}
        end
    end

    local hash, skillIndex = line:match('TDX:useSkill%(([^,]+),%s*([^%)]+)%)')
    if hash and skillIndex then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                towermoving = pos.x,
                skillindex = tonumber(skillIndex),
                location = "no_pos",
                wave = currentWave,
                time = convertTimeToNumber(currentTime)
            }}
        end
    end

    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
        name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
        return {{
            TowerPlaceCost = GetTowerPlaceCostByName(name),
            TowerPlaced = name,
            TowerVector = string.format("%s, %s, %s", x, y, z),
            Rotation = rot,
            TowerA1 = a1
        }}
    end

    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos = hash2pos[tostring(hash)]
        local pathNum, count = tonumber(path), tonumber(upgradeCount)
        if pos and pathNum and count and count > 0 then
            local entries = {}
            for _ = 1, count do
                table.insert(entries, {
                    UpgradeCost = 0,
                    UpgradePath = pathNum,
                    TowerUpgraded = pos.x
                })
            end
            return entries
        end
    end

    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash and targetType then
        local pos = hash2pos[tostring(hash)]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                TowerTargetChange = pos.x,
                TargetWanted = tonumber(targetType),
                TargetWave = currentWave,
                TargetChangedAt = convertTimeToNumber(currentTime)
            }}
        end
    end

    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[tostring(hash)]
        if pos then
            return {{ SellTower = pos.x }}
        end
    end

    local towerName, upgradeName = line:match('TDX:upgradeShop%(([^,]+),%s*([^%)]+)%)')
    if towerName and upgradeName then
        towerName = tostring(towerName):gsub('^%s*"(.-)"%s*$', '%1')
        upgradeName = tostring(upgradeName):gsub('^%s*"(.-)"%s*$', '%1')
        return {{
            UpgradeShopTower = towerName,
            UpgradeShopUpgrade = upgradeName
        }}
    end

    local selection = line:match('TDX:loadoutSelection%(([^%)]+)%)')
    if selection then
        local n = tonumber(selection)
        if n ~= nil then
            return {{
                LoadoutSelection = n
            }}
        end
    end

    return nil
end

local function processAndWriteAction(commandString)
    if globalEnv.TDX_REBUILDING_TOWERS then
        local axisX = nil
        local a1, towerName, vec, rot = commandString:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
        if vec then axisX = tonumber(vec) end
        if not axisX then
            local hash = commandString:match('TDX:upgradeTower%(([^,]+),')
            if hash then
                local pos = hash2pos[tostring(hash)]
                if pos then axisX = pos.x end
            end
        end
        if not axisX then
            local hash = commandString:match('TDX:changeQueryType%(([^,]+),')
            if hash then
                local pos = hash2pos[tostring(hash)]
                if pos then axisX = pos.x end
            end
        end
        if not axisX then
            local hash = commandString:match('TDX:useMovingSkill%(([^,]+),')
            if not hash then hash = commandString:match('TDX:useSkill%(([^,]+),') end
            if hash then
                local pos = hash2pos[tostring(hash)]
                if pos then axisX = pos.x end
            end
        end
        if axisX and globalEnv.TDX_REBUILDING_TOWERS[axisX] then
            return
        end
    end

    local entries = parseMacroLine(commandString)
    if entries then
        for _, entry in ipairs(entries) do
            table.insert(recordedActions, entry)
        end
        updateJsonFile()
    end
end

local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    })
end

local function tryConfirm(typeStr, specificHash)
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if item.type == typeStr then
            if not specificHash or string.find(item.code, tostring(specificHash)) then
                processAndWriteAction(item.code)
                table.remove(pendingQueue, i)
                return
            end
        end
    end
end

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data and data[1]
    if not d then return end
    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end
    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    local currentTime = tick()
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.0001 then
        return
    end
    lastUpgradeTime[hash] = currentTime
    local upgradedPath, upgradeCount = nil, 0
    if lastKnownLevels[hash] then
        for path = 1, 2 do
            local oldLevel = lastKnownLevels[hash][path] or 0
            local newLevel = newLevels[path] or 0
            if newLevel > oldLevel then
                upgradedPath = path
                upgradeCount = newLevel - oldLevel
                break
            end
        end
    end
    if upgradedPath and upgradeCount > 0 then
        local code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), upgradedPath, upgradeCount)
        processAndWriteAction(code)
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                table.remove(pendingQueue, i)
            end
        end
    else
        tryConfirm("Upgrade", hash)
    end
    lastKnownLevels[hash] = newLevels or {}
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then
        tryConfirm("Target")
    end
end)

ReplicatedStorage.Remotes.SkipWaveVoteCast.OnClientEvent:Connect(function()
    tryConfirm("SkipWave")
end)

pcall(function()
    task.spawn(function()
        while task.wait(0.2) do
            for i = #pendingQueue, 1, -1 do
                local item = pendingQueue[i]
                if item.type == "MovingSkill" and tick() - item.created > 0.1 then
                    processAndWriteAction(item.code)
                    table.remove(pendingQueue, i)
                end
            end
        end
    end)
end)

local skipWaveConnection = RunService.Heartbeat:Connect(function()
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if item.type == "SkipWave" and tick() - item.created > 0.1 then
            processAndWriteAction(item.code)
            table.remove(pendingQueue, i)
        end
    end
end)

local function handleRemote(name, args)
    if name == "SkipWaveVoteCast" then
        local shouldRecord = false
        if args and #args > 0 then
            local firstArg = args[1]
            if firstArg == true or firstArg == "true" or (type(firstArg) == "string" and firstArg:lower() == "skip") then
                shouldRecord = true
            end
        end
        
        if shouldRecord then
            local globalEnv = getGlobalEnv()
            if globalEnv.TDX_AutoSkipEnabled then
                task.spawn(function()
                    task.wait(0.1)
                    local playerGui = player:FindFirstChildOfClass("PlayerGui")
                    if playerGui then
                        local interface = playerGui:FindFirstChild("Interface")
                        if interface then
                            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
                            if gameInfoBar then
                                local waveText = gameInfoBar:FindFirstChild("Wave")
                                local timeText = gameInfoBar:FindFirstChild("TimeLeft")
                                if waveText and timeText then
                                    local waveLabel = waveText:FindFirstChild("WaveText")
                                    local timeLabel = timeText:FindFirstChild("TimeLeftText")
                                    if waveLabel and timeLabel then
                                        local waveName = string.upper(waveLabel.Text)
                                        local timeStr = timeLabel.Text
                                        if globalEnv.TDX_RecordWaveConfig then
                                            globalEnv.TDX_RecordWaveConfig(waveName, true, timeStr)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
                setPending("SkipWave", "TDX:skipWave()")
            end
        end
    end
    
    if name == "DifficultyVoteCast" then
        local globalEnv = getGlobalEnv()
        if args and #args > 0 and globalEnv.TDX_RecordDifficulty then
            local difficulty = args[1]
            if type(difficulty) == "string" then
                globalEnv.TDX_RecordDifficulty(difficulty)
            end
        end
    end
    
    if name == "DifficultyVoteReady" then
    end

    if name == "TowerUseAbilityRequest" then
        local towerHash, skillIndex, targetPos = unpack(args)
        if typeof(towerHash) == "number" and typeof(skillIndex) == "number" then
            local towerName = GetTowerNameByHash(towerHash)
            if IsMovingSkillTower(towerName, skillIndex) then
                local code
                if IsPositionRequiredSkill(towerName, skillIndex) and typeof(targetPos) == "Vector3" then
                    code = string.format("TDX:useMovingSkill(%s, %d, Vector3.new(%s, %s, %s))", 
                        tostring(towerHash), skillIndex, 
                        tostring(targetPos.X), tostring(targetPos.Y), tostring(targetPos.Z))
                elseif not IsPositionRequiredSkill(towerName, skillIndex) then
                    code = string.format("TDX:useSkill(%s, %d)", tostring(towerHash), skillIndex)
                end
                if code then
                    setPending("MovingSkill", code, towerHash)
                end
            end
        end
    end

    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" and path >= 0 and path <= 2 and count > 0 and count <= 5 then
            setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), path, count), hash)
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
            local code = string.format('TDX:placeTower(%s, "%s", Vector3.new(%s, %s, %s), %s)', tostring(a1), towerName, tostring(vec.X), tostring(vec.Y), tostring(vec.Z), tostring(rot))
            setPending("Place", code)
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..tostring(args[1])..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", string.format("TDX:changeQueryType(%s, %s)", tostring(args[1]), tostring(args[2])))
    end

    if name == "UpgradeShopOperationRequest" then
        if game.PlaceId == 11739766412 then
            local towerName, upgradeName = unpack(args)
            if typeof(towerName) == "string" and typeof(upgradeName) == "string" then
                local code = string.format('TDX:upgradeShop("%s", "%s")', towerName, upgradeName)
                processAndWriteAction(code)
            end
        end
    end

    if name == "LoadoutSelectionChanged" then
        local selection = args and args[1]
        if typeof(selection) == "number" then
            local code = string.format("TDX:loadoutSelection(%d)", selection)
            processAndWriteAction(code)
        end
    end
    
    if name == "SoloToggleSpeedControl" then
        if args and args[1] == "Speed" and args[2] == true then
            if globalEnv.TDX_RecordSpeedToggle then
                globalEnv.TDX_RecordSpeedToggle(true)
            end
        elseif args and args[1] == "Speed" and args[2] == false then
            if globalEnv.TDX_RecordSpeedToggle then
                globalEnv.TDX_RecordSpeedToggle(false)
            end
        end
    end
end

local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        return
    end

    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldFireServer(self, ...)
    end)

    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldInvokeServer(self, ...)
    end)

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local args = {...}
            local remoteName = self.Name
            if remoteName == "SkipWaveVoteCast" then
                task.spawn(function()
                    handleRemote(remoteName, args)
                end)
            else
                handleRemote(remoteName, args)
            end
        end
        return oldNamecall(self, ...)
    end)
end

task.spawn(function()
    while task.wait(0.5) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                table.remove(pendingQueue, i)
            end
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local pos = GetTowerSpawnPosition(tower)
                if pos then
                    hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
    end
end)

setupHooks()
]]
end

local function getEmbeddedRunMacroScript()
    return [[
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function setThreadIdentity(identity)
    if setthreadidentity then
        setthreadidentity(identity)
    elseif syn and syn.set_thread_identity then
        syn.set_thread_identity(identity)
    end
end

local function SafeRemoteCall(remoteType, remote, ...)
    local args = {...}
    return task.spawn(function()
        setThreadIdentity(2)
        if remoteType == "FireServer" then
            pcall(function()
                remote:FireServer(unpack(args))
            end)
        elseif remoteType == "InvokeServer" then
            local success, result = pcall(function()
                return remote:InvokeServer(unpack(args))
            end)
            return success and result or nil
        end
    end)
end

local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local function safeReadFile(path)
    if readfile and typeof(readfile) == "function" then
        local success, result = pcall(readfile, path)
        return success and result or nil
    end
    return nil
end

local function safeIsFile(path)
    if isfile and typeof(isfile) == "function" then
        local success, result = pcall(isfile, path)
        return success and result or false
    end
    return false
end

local defaultConfig = {
    ["Macro Name"] = "endless",
    ["PlaceMode"] = "Rewrite",
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster", "Combat Drone"},
    ["TargetChangeCheckDelay"] = 0.05,
    ["RebuildPriority"] = false,
    ["RebuildCheckInterval"] = 0,
    ["MacroStepDelay"] = 0.1,
    ["MaxConcurrentRebuilds"] = 120,
    ["MonitorCheckDelay"] = 0.05,
    ["AllowParallelTargets"] = false,
    ["AllowParallelSkips"] = true,
    ["UseThreadedRemotes"] = true
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

local function getMaxAttempts()
    local placeMode = globalEnv.TDX_Config.PlaceMode or "Ashed"
    if placeMode == "Ashed" then return 1 end
    if placeMode == "Rewrite" then return 10 end
    return 1
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local success, result = pcall(function() return require(path) end)
        if success and result then return result end
        RunService.RenderStepped:Wait()
    end
    return nil
end

local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    local client = ps:FindFirstChild("Client")
    if not client then return nil end
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then return nil end
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then return nil end
    return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then 
    error("Failed to load TowerClass - make sure you are in TDX game")
end

task.spawn(function()
    while task.wait(0.5) do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                if globalEnv.TDX_Config.UseThreadedRemotes then
                    SafeRemoteCall("FireServer", Remotes.SellTower, hash)
                else
                    pcall(function() Remotes.SellTower:FireServer(hash) end)
                end
                task.wait(globalEnv.TDX_Config.MacroStepDelay)
            end
        end
    end
end)

local function GetTowerByAxis(targetX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local spawnCFrame = tower.SpawnCFrame
        if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
            if spawnCFrame.Position.X == targetX then
                return hash, tower
            end
        end
    end
    return nil, nil
end

local function WaitForTowerInitialization(axisX, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local hash, tower = GetTowerByAxis(axisX)
        if hash and tower and tower.LevelHandler then
            return hash, tower
        end
        RunService.RenderStepped:Wait()
    end
    return nil, nil
end

local function getGameUI()
    local attempts = 0
    while attempts < 30 do
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface and interface.Parent then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar and gameInfoBar.Parent then
                local waveFrame = gameInfoBar:FindFirstChild("Wave")
                local timeFrame = gameInfoBar:FindFirstChild("TimeLeft")
                if waveFrame and timeFrame and waveFrame.Parent and timeFrame.Parent then
                    local waveText = waveFrame:FindFirstChild("WaveText")
                    local timeText = timeFrame:FindFirstChild("TimeLeftText")
                    if waveText and timeText and waveText.Parent and timeText.Parent then
                        return { waveText = waveText, timeText = timeText }
                    end
                end
            end
        end
        attempts = attempts + 1
        task.wait(1)
    end
    error("Failed to find Game UI")
end

local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

local function TryUpgradeShop(towerName, upgradeName)
    if game.PlaceId ~= 11739766412 then return false end
    local delay = (getGlobalEnv().TDX_Config and getGlobalEnv().TDX_Config.MacroStepDelay) or 0.35
    local notified = false
    while true do
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("UpgradeShopOperationRequest")
        if remote then
            if not notified then
                notified = true
                Library:Notify({
                    Title = "Upgrade Shop",
                    Description = tostring(towerName) .. " -> " .. tostring(upgradeName),
                    Time = 2,
                })
            end
            local ok, res = pcall(function()
                if remote:IsA("RemoteFunction") then
                    return remote:InvokeServer(towerName, upgradeName)
                else
                    remote:FireServer(towerName, upgradeName)
                    return true
                end
            end)
            local success = ok and (res == nil or res == true or res == "success")
            if success then
                Library:Notify({
                    Title = "Upgrade Sent",
                    Description = tostring(towerName) .. " -> " .. tostring(upgradeName),
                    Time = 2,
                })
                return true
            end
        end
        task.wait(delay)
    end
end

local function parseTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then return priority end
    end
    return math.huge
end

local function SellAllTowers(skipList)
    local skipMap = {}
    if skipList then for _, name in ipairs(skipList) do skipMap[name] = true end end
    for hash, tower in pairs(TowerClass.GetTowers()) do
        if not skipMap[tower.Type] then
            if globalEnv.TDX_Config.UseThreadedRemotes then
                SafeRemoteCall("FireServer", Remotes.SellTower, hash)
            else
                pcall(function() Remotes.SellTower:FireServer(hash) end)
            end
            task.wait(globalEnv.TDX_Config.MacroStepDelay)
        end
    end
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local levelHandler = tower.LevelHandler
    local maxLvl = levelHandler:GetMaxLevel()
    local curLvl = levelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return nil end
    local towerName = tower.Type
    local discount = 0
    local priceMultiplier = 1
    local dynamicPriceData = {}
    if tower.BuffHandler then
        pcall(function() 
            discount = tower.BuffHandler:GetDiscount() or 0 
        end)
    end
    if levelHandler.HasDynamicPriceScaling then
        local playerData = TowerClass.GetDynamicPriceScalingData(tower)
        dynamicPriceData = playerData or {}
    end
    local success, cost = pcall(function()
        local LevelHandlerUtilities = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("LevelHandlerUtilities"))
        return LevelHandlerUtilities.GetLevelUpgradeCost(levelHandler, towerName, path, 1, discount, priceMultiplier, dynamicPriceData)
    end)
    if not success then
        return nil
    end
    return cost
end

local function WaitForCash(amount)
    while cashStat.Value < amount do RunService.RenderStepped:Wait() end
end

local function PlaceTowerRetry(args, axisValue)
    for i = 1, getMaxAttempts() do
        if globalEnv.TDX_Config.UseThreadedRemotes then
            SafeRemoteCall("InvokeServer", Remotes.PlaceTower, unpack(args))
        else
            pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end)
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
        local _, tower = WaitForTowerInitialization(axisValue, 3)
        if tower then return true end
    end
    return false
end

local function UpgradeTowerRetry(axisValue, path)
    for i = 1, getMaxAttempts() do
        local hash, tower = WaitForTowerInitialization(axisValue)
        if not hash then task.wait(globalEnv.TDX_Config.MacroStepDelay); continue end
        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return true end
        WaitForCash(cost)
        if globalEnv.TDX_Config.UseThreadedRemotes then
            SafeRemoteCall("FireServer", Remotes.TowerUpgradeRequest, hash, path, 1)
        else
            pcall(function() Remotes.TowerUpgradeRequest:FireServer(hash, path, 1) end)
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
        local startTime = tick()
        repeat
            RunService.RenderStepped:Wait()
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler and t.LevelHandler:GetLevelOnPath(path) > before then return true end
        until tick() - startTime > 3
    end
    return false
end

local function ChangeTargetRetry(axisValue, targetType)
    for i = 1, getMaxAttempts() do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            if globalEnv.TDX_Config.UseThreadedRemotes then
                SafeRemoteCall("FireServer", Remotes.ChangeQueryType, hash, targetType)
            else
                pcall(function() Remotes.ChangeQueryType:FireServer(hash, targetType) end)
            end
            task.wait(globalEnv.TDX_Config.MacroStepDelay)
            return true
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
    end
    return false
end

local function SkipWaveRetry()
    local function setThreadIdentity(identity)
        if setthreadidentity then
            setthreadidentity(identity)
        elseif syn and syn.set_thread_identity then
            syn.set_thread_identity(identity)
        end
    end
    
    return task.spawn(function()
        setThreadIdentity(2)
        local SkipEvent = Remotes:FindFirstChild("SkipWaveVoteCast")
        if SkipEvent then
            pcall(function()
                local args = {true}
                if SkipEvent:IsA("RemoteEvent") then
                    SkipEvent:FireServer(unpack(args))
                elseif SkipEvent:IsA("RemoteFunction") then
                    SkipEvent:InvokeServer(unpack(args))
                end
            end)
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
        return true
    end)
end

local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then return false end
    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    for i = 1, getMaxAttempts() do
        local hash, tower = WaitForTowerInitialization(axisValue)
        if hash and tower and tower.AbilityHandler then
            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if ability then
                local cooldown = ability.CooldownRemaining or 0
                if cooldown > 0 then task.wait(cooldown + 0.1) end
                local success = false
                if globalEnv.TDX_Config.UseThreadedRemotes then
                    if location == "no_pos" then
                        if useFireServer then
                            SafeRemoteCall("FireServer", TowerUseAbilityRequest, hash, skillIndex)
                        else
                            SafeRemoteCall("InvokeServer", TowerUseAbilityRequest, hash, skillIndex)
                        end
                        success = true
                    else
                        local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                        if x and y and z then
                            local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                            if useFireServer then
                                SafeRemoteCall("FireServer", TowerUseAbilityRequest, hash, skillIndex, pos)
                            else
                                SafeRemoteCall("InvokeServer", TowerUseAbilityRequest, hash, skillIndex, pos)
                            end
                            success = true
                        end
                    end
                else
                    if location == "no_pos" then
                        success = pcall(function()
                            if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex) 
                            else TowerUseAbilityRequest:InvokeServer(hash, skillIndex) end
                        end)
                    else
                        local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                        if x and y and z then
                            local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                            success = pcall(function()
                                if useFireServer then TowerUseAbilityRequest:FireServer(hash, skillIndex, pos) 
                                else TowerUseAbilityRequest:InvokeServer(hash, skillIndex, pos) end
                            end)
                        end
                    end
                end
                if success then 
                    task.wait(globalEnv.TDX_Config.MacroStepDelay)
                    return true 
                end
            end
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
    end
    return false
end

local function SellTowerRetry(axisValue)
    for i = 1, getMaxAttempts() do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            if globalEnv.TDX_Config.UseThreadedRemotes then
                SafeRemoteCall("FireServer", Remotes.SellTower, hash)
            else
                pcall(function() Remotes.SellTower:FireServer(hash) end)
            end
            task.wait(globalEnv.TDX_Config.MacroStepDelay)
            if not GetTowerByAxis(axisValue) then return true end
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
    end
    return false
end

local function StartUnifiedMonitor(monitorEntries, gameUI)
    local processedEntries = {}
    local attemptedSkipWaves = {}
    local function shouldExecuteEntry(entry, currentWave, currentTime)
        if entry.SkipWave then
            local entryWave = string.upper(tostring(entry.SkipWave))
            local currentWaveUpper = string.upper(tostring(currentWave))
            if attemptedSkipWaves[entryWave] then return false end
            if entryWave ~= currentWaveUpper then return false end
            if entry.skip == true then
                local playerGui = player:FindFirstChildOfClass("PlayerGui")
                if playerGui then
                    local interface = playerGui:FindFirstChild("Interface")
                    if interface then
                        local topAreaQueueFrame = interface:FindFirstChild("TopAreaQueueFrame")
                        if topAreaQueueFrame then
                            local skipWaveVoteScreen = topAreaQueueFrame:FindFirstChild("SkipWaveVoteScreen")
                            if skipWaveVoteScreen and skipWaveVoteScreen.Visible == true then
                                return true
                            end
                        end
                    end
                end
                return false
            end
            return false
        end
        if entry.TowerTargetChange then
            if entry.TargetWave and entry.TargetWave ~= currentWave then return false end
            if entry.TargetChangedAt then
                if currentTime ~= convertToTimeFormat(entry.TargetChangedAt) then return false end
            end
            return true
        end
        if entry.towermoving then
            if entry.wave and entry.wave ~= currentWave then return false end
            if entry.time then
                if currentTime ~= convertToTimeFormat(entry.time) then return false end
            end
            return true
        end
        return false
    end
    local function executeEntry(entry)
        if entry.SkipWave then
            local entryWave = string.upper(tostring(entry.SkipWave))
            attemptedSkipWaves[entryWave] = true
            if globalEnv.TDX_Config.AllowParallelSkips then 
                task.spawn(SkipWaveRetry) 
            else 
                return SkipWaveRetry() 
            end
            return true
        end
        if entry.TowerTargetChange then
            if globalEnv.TDX_Config.AllowParallelTargets then 
                task.spawn(function() ChangeTargetRetry(entry.TowerTargetChange, entry.TargetWanted) end) 
            else 
                return ChangeTargetRetry(entry.TowerTargetChange, entry.TargetWanted) 
            end
            return true
        end
        if entry.towermoving then
            return UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end
        return false
    end
    task.spawn(function()
        setThreadIdentity(2)
        while true do
            local success, currentWave, currentTime = pcall(function() return gameUI.waveText.Text, gameUI.timeText.Text end)
            if success then
                for i, entry in ipairs(monitorEntries) do
                    if not processedEntries[i] and shouldExecuteEntry(entry, currentWave, currentTime) then
                        if executeEntry(entry) then
                            processedEntries[i] = true
                        end
                    end
                end
            end
            task.wait(globalEnv.TDX_Config.MonitorCheckDelay or 0.1)
        end
    end)
end

local function StartRebuildSystem(rebuildEntry, towerRecords, skipTypesMap)
    local config = globalEnv.TDX_Config
    local rebuildAttempts, soldPositions, jobQueue, activeJobs = {}, {}, {}, {}
    local function RebuildWorker()
        task.spawn(function()
            setThreadIdentity(2)
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    local records = job.records
                    local placeRecord, upgradeRecords, targetRecords, movingRecords = nil, {}, {}, {}
                    for _, record in ipairs(records) do
                        local action = record.entry
                        if action.TowerPlaced then placeRecord = record
                        elseif action.TowerUpgraded then table.insert(upgradeRecords, record)
                        elseif action.TowerTargetChange then table.insert(targetRecords, record)
                        elseif action.towermoving then table.insert(movingRecords, record) end
                    end
                    local rebuildSuccess = true
                    if placeRecord then
                        local action = placeRecord.entry
                        local vecTab = {}
                        for coord in action.TowerVector:gmatch("[^,%s]+") do 
                            table.insert(vecTab, tonumber(coord)) 
                        end
                        if #vecTab == 3 then
                            local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
                            local args = {tonumber(action.TowerA1), action.TowerPlaced, pos, tonumber(action.Rotation or 0)}
                            WaitForCash(action.TowerPlaceCost)
                            if not PlaceTowerRetry(args, pos.X) then 
                                rebuildSuccess = false 
                            end
                        end
                    end
                    if rebuildSuccess then
                        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
                        for _, record in ipairs(upgradeRecords) do
                            if not UpgradeTowerRetry(tonumber(record.entry.TowerUpgraded), record.entry.UpgradePath) then 
                                rebuildSuccess = false
                                break 
                            end
                        end
                    end
                    if rebuildSuccess and #movingRecords > 0 then
                        task.spawn(function()
                            local lastMovingRecord = movingRecords[#movingRecords].entry
                            UseMovingSkillRetry(lastMovingRecord.towermoving, lastMovingRecord.skillindex, lastMovingRecord.location)
                        end)
                    end
                    if rebuildSuccess then
                        for _, record in ipairs(targetRecords) do
                            ChangeTargetRetry(tonumber(record.entry.TowerTargetChange), record.entry.TargetWanted)
                        end
                    end
                    activeJobs[job.x] = nil
                else
                    RunService.RenderStepped:Wait()
                end
            end
        end)
    end
    for i = 1, config.MaxConcurrentRebuilds do RebuildWorker() end
    task.spawn(function()
        while true do
            local existingTowersCache = {}
            for hash, tower in pairs(TowerClass.GetTowers()) do
                if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
                    existingTowersCache[tower.SpawnCFrame.Position.X] = true
                end
            end
            local jobsAdded = false
            for x, records in pairs(towerRecords) do
                if not existingTowersCache[x] and not activeJobs[x] and not (config.ForceRebuildEvenIfSold == false and soldPositions[x]) then
                    local towerType, firstPlaceRecord = nil, nil
                    for _, record in ipairs(records) do
                        if record.entry.TowerPlaced then 
                            towerType, firstPlaceRecord = record.entry.TowerPlaced, record
                            break 
                        end
                    end
                    if towerType then
                        local skipRule = skipTypesMap[towerType]
                        local shouldSkip = false
                        if skipRule then
                            if skipRule.beOnly and firstPlaceRecord.line < skipRule.fromLine then 
                                shouldSkip = true
                            elseif not skipRule.beOnly then 
                                shouldSkip = true 
                            end
                        end
                        if not shouldSkip then
                            rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                            if not config.MaxRebuildRetry or rebuildAttempts[x] <= config.MaxRebuildRetry then
                                activeJobs[x] = true
                                table.insert(jobQueue, { 
                                    x = x, records = records, 
                                    priority = GetTowerPriority(towerType), 
                                    deathTime = tick() 
                                })
                                jobsAdded = true
                            end
                        end
                    end
                end
            end
            if jobsAdded and #jobQueue > 1 then
                table.sort(jobQueue, function(a, b) 
                    if a.priority == b.priority then return a.deathTime < b.deathTime end
                    return a.priority < b.priority 
                end)
            end
            task.wait(config.RebuildCheckInterval or 0)
        end
    end)
end

local function RunMacroRunner()
    local config = globalEnv.TDX_Config
    local macroName = config["Macro Name"] or "event"
    local macroPath = "tdx/macros/" .. macroName .. ".json"
    if not safeIsFile(macroPath) then 
        error("Macro file not found: " .. macroPath) 
    end
    local macroContent = safeReadFile(macroPath)
    if not macroContent then 
        error("Failed to read macro file") 
    end
    local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
    if not ok or type(macro) ~= "table" then 
        error("Error parsing macro file") 
    end
    local gameUI, towerRecords, skipTypesMap, monitorEntries, rebuildSystemActive = getGameUI(), {}, {}, {}, false
    for i, entry in ipairs(macro) do
        if entry.TowerTargetChange or entry.towermoving or entry.SkipWave then 
            table.insert(monitorEntries, entry) 
        end
    end
    if #monitorEntries > 0 then 
        StartUnifiedMonitor(monitorEntries, gameUI) 
    end
    for i, entry in ipairs(macro) do
        if entry.SuperFunction == "sell_all" then 
            SellAllTowers(entry.Skip)
        elseif entry.SuperFunction == "rebuild" then
            if not rebuildSystemActive then
                for _, skip in ipairs(entry.Skip or {}) do 
                    skipTypesMap[skip] = { beOnly = entry.Be == true, fromLine = i } 
                end
                StartRebuildSystem(entry, towerRecords, skipTypesMap)
                rebuildSystemActive = true
            end
        elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            local vecTab = {}
            for coord in entry.TowerVector:gmatch("[^,%s]+") do 
                table.insert(vecTab, tonumber(coord)) 
            end
            if #vecTab == 3 then
                local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
                local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}
                WaitForCash(entry.TowerPlaceCost)
                PlaceTowerRetry(args, pos.X)
                towerRecords[pos.X] = towerRecords[pos.X] or {}
                table.insert(towerRecords[pos.X], { line = i, entry = entry })
            end
        elseif entry.TowerUpgraded and entry.UpgradePath then
            local axis = tonumber(entry.TowerUpgraded)
            UpgradeTowerRetry(axis, entry.UpgradePath)
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        elseif entry.UpgradeShopTower and entry.UpgradeShopUpgrade then
            if game.PlaceId == 11739766412 then
                TryUpgradeShop(entry.UpgradeShopTower, entry.UpgradeShopUpgrade)
            end
        elseif entry.LoadoutSelection ~= nil then
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local remote = remotes and remotes:FindFirstChild("LoadoutSelectionChanged")
            if remote then
                if globalEnv.TDX_Config.UseThreadedRemotes then
                    SafeRemoteCall("FireServer", remote, entry.LoadoutSelection)
                else
                    pcall(function()
                        remote:FireServer(entry.LoadoutSelection)
                    end)
                end
            end
        elseif entry.TowerTargetChange and entry.TargetWanted then
            local axis = tonumber(entry.TowerTargetChange)
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        elseif entry.SellTower then
            local axis = tonumber(entry.SellTower)
            SellTowerRetry(axis)
            towerRecords[axis] = nil
        elseif entry.towermoving and entry.skillindex and entry.location then
            local axis = entry.towermoving
            towerRecords[axis] = towerRecords[axis] or {}
            table.insert(towerRecords[axis], { line = i, entry = entry })
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
    end
end

pcall(RunMacroRunner)
]]
end

local function getEmbeddedAutoSkipScript()
    return [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

if not _G.WaveConfig or type(_G.WaveConfig) ~= "table" then
    error("Please set _G.WaveConfig table before running the script!")
end

local SkipEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast")
local TDX_Shared = ReplicatedStorage:WaitForChild("TDX_Shared")
local Common = TDX_Shared:WaitForChild("Common")
local NetworkingHandler = require(Common:WaitForChild("NetworkingHandler"))

local function safeSkipWave()
    local function setThreadIdentity(identity)
        if setthreadidentity then
            setthreadidentity(identity)
        elseif syn and syn.set_thread_identity then
            syn.set_thread_identity(identity)
        end
    end
    
    return task.spawn(function()
        setThreadIdentity(2)
        pcall(function()
            local SkipEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast")
            local args = {true}
            if SkipEvent:IsA("RemoteEvent") then
                SkipEvent:FireServer(unpack(args))
            elseif SkipEvent:IsA("RemoteFunction") then
                SkipEvent:InvokeServer(unpack(args))
            end
        end)
    end)
end

local skippedWaves = {}
local function checkSkipWaveScreen()
    while true do
        task.wait(0.1)
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local topAreaQueueFrame = interface:FindFirstChild("TopAreaQueueFrame")
            if topAreaQueueFrame then
                local skipWaveVoteScreen = topAreaQueueFrame:FindFirstChild("SkipWaveVoteScreen")
                if skipWaveVoteScreen and skipWaveVoteScreen.Visible == true then
                    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
                    if gameInfoBar then
                        local waveText = gameInfoBar:FindFirstChild("Wave")
                        if waveText then
                            local waveLabel = waveText:FindFirstChild("WaveText")
                            if waveLabel then
                                local waveName = string.upper(waveLabel.Text)
                                
                                if not skippedWaves[waveName] then
                                    if _G.WaveConfig and _G.WaveConfig[waveName] then
                                        local waveConfig = _G.WaveConfig[waveName]
                                        if waveConfig == true then
                                            skippedWaves[waveName] = true
                                        elseif type(waveConfig) == "table" and waveConfig.skip == true then
                                            skippedWaves[waveName] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                    safeSkipWave()
                else
                    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
                    if gameInfoBar then
                        local waveText = gameInfoBar:FindFirstChild("Wave")
                        if waveText then
                            local waveLabel = waveText:FindFirstChild("WaveText")
                            if waveLabel then
                                local currentWaveName = string.upper(waveLabel.Text)
                                for waveName, _ in pairs(skippedWaves) do
                                    if waveName ~= currentWaveName then
                                        skippedWaves[waveName] = nil
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

task.spawn(checkSkipWaveScreen)
]]
end

local function getEmbeddedSimpleAutoSkipScript()
    return [[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local globalEnv = getGlobalEnv()

local function safeSkipWave()
    local function setThreadIdentity(identity)
        if setthreadidentity then
            setthreadidentity(identity)
        elseif syn and syn.set_thread_identity then
            syn.set_thread_identity(identity)
        end
    end
    
    return task.spawn(function()
        setThreadIdentity(2)
        pcall(function()
            local SkipEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast")
            local args = {true}
            if SkipEvent:IsA("RemoteEvent") then
                SkipEvent:FireServer(unpack(args))
            elseif SkipEvent:IsA("RemoteFunction") then
                SkipEvent:InvokeServer(unpack(args))
            end
        end)
    end)
end

local lastSkipTime = 0
local skipInterval = 0.5

RunService.Heartbeat:Connect(function()
    if not globalEnv.TDX_AutoSkipEnabled then return end
    
    local currentTime = tick()
    if currentTime - lastSkipTime < skipInterval then return end
    lastSkipTime = currentTime
    
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return end
    
    local topAreaQueueFrame = interface:FindFirstChild("TopAreaQueueFrame")
    if not topAreaQueueFrame then return end
    
    local skipWaveVoteScreen = topAreaQueueFrame:FindFirstChild("SkipWaveVoteScreen")
    if skipWaveVoteScreen and skipWaveVoteScreen.Visible == true then
        safeSkipWave()
    end
end)
]]
end

local function getEmbeddedSpeedScript()
    return [[
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then return end

local Remote = Remotes:FindFirstChild("SoloToggleSpeedControl")
if not Remote then return end

local function getUIElements()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil end
    local speedChangeScreen = interface:FindFirstChild("SpeedChangeScreen")
    if not speedChangeScreen then return nil end
    local owned = speedChangeScreen:FindFirstChild("Owned")
    if not owned then return nil end
    local active = owned:FindFirstChild("Active")
    local default = owned:FindFirstChild("Default")
    return { active = active, default = default, owned = owned }
end

local function isSpeedControlDisabled()
    local ui = getUIElements()
    if not ui or not ui.default then return true end
    local speedButton = ui.default:FindFirstChild("Speed")
    if speedButton then
        local activateButton = speedButton:FindFirstChild("Activate")
        if activateButton and not activateButton.Interactable then
            return true
        end
    end
    local slowButton = ui.default:FindFirstChild("Slow")
    if slowButton then
        local activateButton = slowButton:FindFirstChild("Activate")
        if activateButton and not activateButton.Interactable then
            return true
        end
    end
    if workspace:GetAttribute("IsTutorial") then return true end
    if workspace:GetAttribute("SpeedBoostLocked") then return true end
    return false
end

local isWaiting = false
local monitoring = true
local lastCheckTime = 0

local function safeCallSpeedRemote()
    local function setThreadIdentity(identity)
        if setthreadidentity then
            setthreadidentity(identity)
        elseif syn and syn.set_thread_identity then
            syn.set_thread_identity(identity)
        end
    end
    
    return task.spawn(function()
        setThreadIdentity(2)
        pcall(function()
            if Remote:IsA("RemoteEvent") then
                Remote:FireServer(true, true)
            elseif Remote:IsA("RemoteFunction") then
                Remote:InvokeServer(true, true)
            end
        end)
    end)
end

    task.spawn(function()
        task.wait(3)
    for i = 1, 30 do
        if not isSpeedControlDisabled() then
            local ui = getUIElements()
            if ui and ui.active then
                if not ui.active.Visible then
                    safeCallSpeedRemote()
                    task.wait(1)
                    local ui2 = getUIElements()
                    if ui2 and ui2.active and ui2.active.Visible then
                        break
                    end
                else
                    break
                end
            end
        end
        task.wait(0.5)
    end
end)

RunService.Heartbeat:Connect(function()
    if not monitoring then return end
    local currentTime = tick()
    if currentTime - lastCheckTime < 0.5 then return end
    lastCheckTime = currentTime
    local ui = getUIElements()
    if not ui or not ui.active then
        task.wait(5)
        return
    end
    if not ui.active.Visible and not isWaiting and not isSpeedControlDisabled() then
        isWaiting = true
        task.wait(3)
        if not isSpeedControlDisabled() then
            safeCallSpeedRemote()
            task.wait(0.5)
        end
        isWaiting = false
    end
end)

_G.StopSpeedMonitoring = function()
    monitoring = false
end

_G.StartSpeedMonitoring = function()
    monitoring = true
end
]]
end

local function getEmbeddedReturnLobbyScript()
    return [[
local v1 = game:GetService("ReplicatedStorage")
local v2 = game:GetService("Players")
local v3 = v2.LocalPlayer
if not v3 then return end
local v4 = v3:WaitForChild("PlayerGui")
local v5 = v4:WaitForChild("Interface")
local v6 = v5:WaitForChild("GameOverScreen")
local v7 = v1:WaitForChild("Remotes")
local v8 = v7:FindFirstChild("RequestTeleportToLobby")
if not v8 or not (v8:IsA("RemoteEvent") or v8:IsA("RemoteFunction")) then
    return
end
local function v9()
    local v10 = 5
    for _ = 1, v10 do
        local v11 = pcall(function()
            task.wait(1)
            if v8:IsA("RemoteEvent") then
                v8:FireServer()
            else
                v8:InvokeServer()
            end
        end)
        if v11 then return true else task.wait(1) end
    end
    return false
end
local function v12()
    while true do
        if v6 and v6.Visible then v9() end
        task.wait(4)
    end
end
if v6 and v6.Visible then v9() end
if v6 then
    v6:GetPropertyChangedSignal("Visible"):Connect(function()
        if v6.Visible then coroutine.wrap(v12)() end
    end)
end
local v13 = v5:WaitForChild("CutsceneScreen")
local function v14()
    task.wait(1)
    v1:WaitForChild("Remotes"):WaitForChild("CutsceneVoteCast"):FireServer(true)
end
if v13.Visible then
    v14()
else
    local v15
    v15 = v13:GetPropertyChangedSignal("Visible"):Connect(function()
        if v13.Visible then
            v14()
            v15:Disconnect()
        end
    end)
end
]]
end

local function getEmbeddedAutoJoinScript()
    return readfile("auto_join.lua") or ""
end

local function getEmbeddedDifficultyScript()
    return [[
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local voteRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DifficultyVoteCast", true)
local readyRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DifficultyVoteReady", true)
if not voteRemote then return end
local mode = getgenv().TDX_Config and getgenv().TDX_Config["Auto Difficulty"]
if not mode then return end
local difficultyVoteScreen
repeat
    task.wait(0.25)
    local interface = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Interface")
    difficultyVoteScreen = interface and interface:FindFirstChild("DifficultyVoteScreen")
until difficultyVoteScreen and difficultyVoteScreen.Visible
voteRemote:FireServer(mode)
if readyRemote then
    task.wait(0.25)
    readyRemote:FireServer()
end
]]
end

local function getEmbeddedAutoSkillScript()
    return readfile("auto_skill.lua") or ""
end

local function getEmbeddedVoterScript()
    return readfile("voter.lua") or ""
end

local function getEmbeddedHealScript()
    return [[
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")
local promptPart = workspace:FindFirstChild("Game")
if promptPart then promptPart = promptPart:FindFirstChild("Map") end
if promptPart then promptPart = promptPart:FindFirstChild("ProximityPrompts") end
if promptPart then promptPart = promptPart:FindFirstChild("Prompt") end
if not promptPart then
    return
end
local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
if not prompt then
    return
end
prompt.RequiresLineOfSight = false
prompt.MaxActivationDistance = 999999
prompt.HoldDuration = 999999
prompt.Enabled = true
local ghostPart = Instance.new("Part")
ghostPart.Name = "PromptCamPart"
ghostPart.Size = Vector3.new(0.0001, 0.0001, 0.0001)
ghostPart.Transparency = 1
ghostPart.Anchored = true
ghostPart.CanCollide = false
ghostPart.CanQuery = false
ghostPart.CanTouch = false
ghostPart.Parent = workspace
prompt.Parent = ghostPart
RunService.RenderStepped:Connect(function()
    if camera and ghostPart then
        local camCF = camera.CFrame
        ghostPart.CFrame = camCF * CFrame.new(0, 0, -3)
    end
end)
task.spawn(function()
    while true do
        if prompt and prompt.Enabled then
            pcall(function()
                prompt:InputHoldBegin()
            end)
        end
        task.wait(0.5)
    end
end)
local function xoaGuiPrompt()
    local existed = playerGui:FindFirstChild("ProximityPrompts")
    if existed then existed:Destroy() end
    playerGui.ChildAdded:Connect(function(child)
        if child.Name == "ProximityPrompts" then
            task.wait()
            child:Destroy()
        end
    end)
end
xoaGuiPrompt()
]]
end

local function getEmbeddedBlackScreenScript()
    return [=[
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local Terrain = workspace:WaitForChild("Terrain")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local scriptEnabled = true
local isRemoving = false
function _G.blackoff()
    scriptEnabled = false
    isRemoving = true
    for _, v in pairs(CoreGui:GetChildren()) do
        if v:IsA("ScreenGui") and v.DisplayOrder == 2147483647 then
            pcall(function()
                v:Destroy()
            end)
        end
    end
end
function _G.blackon()
    scriptEnabled = true
end
pcall(function()
    LocalPlayer.CameraMaxZoomDistance = 1000
    Lighting.Technology = Enum.Technology.Compatibility
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 100000
    Terrain.WaterWaveSize = 0
    Terrain.WaterWaveSpeed = 0
    Terrain.WaterReflectance = 0
end)
local enemyModule = nil
pcall(function()
    enemyModule = require(LocalPlayer.PlayerScripts:WaitForChild("Client"):WaitForChild("GameClass"):WaitForChild("EnemyClass"))
end)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = tostring(math.random(1e9, 2e9))
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 2147483647
screenGui.Parent = CoreGui

local blackFrame = Instance.new("Frame")
blackFrame.Name = "Cover"
blackFrame.Size = UDim2.new(1, 0, 1, 0)
blackFrame.Position = UDim2.new(0, 0, 0, 0)
blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
blackFrame.BorderSizePixel = 0
blackFrame.ZIndex = 1
blackFrame.Active = true
blackFrame.Parent = screenGui

local headerLabel = Instance.new("TextLabel")
headerLabel.Name = "Header"
headerLabel.Size = UDim2.new(1, -20, 0, 30)
headerLabel.Position = UDim2.new(0, 10, 0, 10)
headerLabel.BackgroundTransparency = 1
headerLabel.TextColor3 = Color3.new(1, 1, 1)
headerLabel.TextStrokeTransparency = 0
headerLabel.Font = Enum.Font.SourceSansBold
headerLabel.TextSize = 24
headerLabel.TextYAlignment = Enum.TextYAlignment.Top
headerLabel.TextXAlignment = Enum.TextXAlignment.Left
headerLabel.ZIndex = 2
headerLabel.Parent = screenGui

local enemyListFrame = Instance.new("ScrollingFrame")
enemyListFrame.Name = "EnemyList"
enemyListFrame.Size = UDim2.new(1, -20, 1, -50)
enemyListFrame.Position = UDim2.new(0, 10, 0, 40)
enemyListFrame.BackgroundTransparency = 1
enemyListFrame.BorderSizePixel = 0
enemyListFrame.ScrollBarThickness = 6
enemyListFrame.ScrollingDirection = Enum.ScrollingDirection.XY
enemyListFrame.ZIndex = 2
enemyListFrame.Parent = screenGui

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.Padding = UDim.new(0, 2)
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Parent = enemyListFrame
local function kick(englishReason)
    pcall(function() LocalPlayer:Kick(englishReason or "GUI tampering was detected.") end)
end
local function protect(instance, propertiesToProtect)
local originalProperties = { Parent = instance.Parent }
for _, propName in ipairs(propertiesToProtect) do originalProperties[propName] = instance[propName] end
instance.AncestryChanged:Connect(function(_, parent)
if isRemoving then return end
if parent ~= originalProperties.Parent then kick("Reason: Attempted to delete or move a protected GUI element.") end
end)
for propName, originalValue in pairs(originalProperties) do
if propName ~= "Parent" then
instance:GetPropertyChangedSignal(propName):Connect(function()
if isRemoving then return end
if instance[propName] ~= originalValue then kick("Reason: Attempted to modify protected GUI property: " .. propName) end
end)
end
end
end

protect(screenGui, {"Name", "DisplayOrder", "IgnoreGuiInset", "Enabled"})
protect(blackFrame, {"Name", "Size", "Position", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex", "Active"})
protect(headerLabel, {"Name", "Size", "Position", "TextColor3", "Visible", "ZIndex"})
protect(enemyListFrame, {"Name", "Size", "Position", "Visible", "ZIndex"})
local function formatPercent(value)
    if value < 0 then value = 0 end
    return math.floor(value * 100 + 0.5) .. "%"
end
local waveTextLabel, timeTextLabel
pcall(function()
    local interface = PlayerGui:WaitForChild("Interface", 15)
    local gameInfoBar = interface and interface:WaitForChild("GameInfoBar", 15)
    if gameInfoBar then
        waveTextLabel = gameInfoBar:WaitForChild("Wave", 5) and gameInfoBar.Wave:WaitForChild("WaveText", 5)
        timeTextLabel = gameInfoBar:WaitForChild("TimeLeft", 5) and gameInfoBar.TimeLeft:WaitForChild("TimeLeftText", 5)
    end
end)
local SHIELD_COLOR_STRING = "rgb(0,170,255)"
local NORMAL_COLOR = Color3.new(1, 1, 1)
RunService.RenderStepped:Connect(function()
if not scriptEnabled then return end

local waveStr = (waveTextLabel and waveTextLabel.Text) or "?"
local timeStr = (timeTextLabel and timeTextLabel.Text) or "??:??"
headerLabel.Text = string.format("Wave: %s | Time: %s", waveStr, timeStr)
    local enemyGroups = {}
    if enemyModule and enemyModule.GetEnemies then
        for _, enemy in pairs(enemyModule.GetEnemies()) do
            pcall(function()
                if not (enemy and enemy.IsAlive and not enemy.IsFakeEnemy) then return end
                local hh = enemy.HealthHandler
                if not (hh and hh.GetMaxHealth and hh.GetHealth) then return end
                local maxHealth = hh:GetMaxHealth()
                if not (typeof(maxHealth) == "number" and maxHealth > 0) then return end
                local currentHealth = hh:GetHealth() or 0
                local currentShield = 0
                if hh.GetShield then currentShield = hh:GetShield() or 0 end
                local hasShield = currentShield > 0
                local percentValue = (currentHealth + currentShield) / maxHealth
                local hp = formatPercent(percentValue)
                local name = enemy.DisplayName or "Unknown"
                if not enemyGroups[name] then enemyGroups[name] = { count = 0, hpData = {} } end
                local group = enemyGroups[name]
                group.count += 1
                table.insert(group.hpData, {hp = hp, shield = hasShield})
            end)
        end
    end
for _, child in ipairs(enemyListFrame:GetChildren()) do  
    if child:IsA("TextLabel") then child:Destroy() end  
end
    local sortedNames = {}
    for name in pairs(enemyGroups) do table.insert(sortedNames, name) end
    table.sort(sortedNames)
    local maxCanvasWidth = 0
    for i, name in ipairs(sortedNames) do
        local data = enemyGroups[name]
        local newLine = Instance.new("TextLabel")
        newLine.Name = name
        newLine.LayoutOrder = i
        newLine.AutomaticSize = Enum.AutomaticSize.X
        newLine.Size = UDim2.new(0, 0, 0, 22)
        newLine.TextWrapped = false
        newLine.BackgroundTransparency = 1
        newLine.Font = Enum.Font.SourceSansBold
        newLine.TextSize = 22
        newLine.TextXAlignment = Enum.TextXAlignment.Left
        newLine.RichText = true
        newLine.TextColor3 = NORMAL_COLOR
        local hpStrings = {}
        for _, hpInfo in ipairs(data.hpData) do
            if hpInfo.shield then
                table.insert(hpStrings, string.format('<font color="%s">%s</font>', SHIELD_COLOR_STRING, hpInfo.hp))
            else
                table.insert(hpStrings, hpInfo.hp)
            end
        end
        local hpString = table.concat(hpStrings, ", ")
    newLine.Text = string.format("%s (x%d): %s", name, data.count, hpString)  
    newLine.Parent = enemyListFrame  

    maxCanvasWidth = math.max(maxCanvasWidth, newLine.AbsoluteSize.X)  
end  

    enemyListFrame.CanvasSize = UDim2.new(0, maxCanvasWidth, 0, uiListLayout.AbsoluteContentSize.Y)
end)
RunService.RenderStepped:Connect(function()
if not scriptEnabled then return end

screenGui.DisplayOrder = 2147483647
if screenGui.Parent ~= CoreGui then screenGui.Parent = CoreGui end

for _, child in ipairs(CoreGui:GetChildren()) do  
    if child:IsA("ScreenGui") and child ~= screenGui then  
        pcall(function()  
            child.DisplayOrder = -1  
        end)  
    end  
end

end)
]=]
end


local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local globalEnv = getGlobalEnv()

if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
    pcall(makefolder, "tdx/configs")
end

local function getMacroList()
    local macros = {}
    local macroPath = "tdx/macros"
    
    if not isfolder(macroPath) then
        if makefolder then
            pcall(makefolder, macroPath)
        end
    end
    
    if listfiles then
        local success, files = pcall(listfiles, macroPath)
        if success then
            files = files or {}
            for _, file in ipairs(files) do
                local fileName = file:match("([^/\\]+)$")
                if fileName and fileName:match("%.json$") then
                    local macroName = fileName:gsub("%.json$", "")
                    table.insert(macros, macroName)
                end
            end
        end
    end
    
    table.sort(macros)
    return macros
end


local isRecording = false
local currentRecordingMacro = nil
local recordedWaveConfig = {}
local recordedSpeedToggles = {}
local recordedDifficulty = nil

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

local function createNewMacro(macroName)
    if not macroName or macroName == "" then
        return false, "Enter macro name!"
    end
    
    local macroPath = "tdx/macros/" .. macroName .. ".json"
    
    if isfile and isfile(macroPath) then
        return false, "Macro with this name already exists!"
    end
    
    writefile(macroPath, "[]")
    
    return true, "Macro '" .. macroName .. "' created!"
end

local function saveConfigToMacro(macroPath, config)
    if not isfile or not isfile(macroPath) then return end
    
    local content = readfile(macroPath)
    local jsonData = HttpService:JSONDecode(content)
    
    table.insert(jsonData, 1, {
        SuperFunction = "config",
        Map = config.Map,
        Difficulty = config["Auto Difficulty"],
        MapVoting = config.mapvoting,
        WaveConfig = config.WaveConfig,
        SpeedToggles = config.SpeedToggles,
        ReturnLobby = config["Return Lobby"],
        AutoSkill = config["Auto Skill"],
        Loadout = config.loadout
    })
    
    local newContent = HttpService:JSONEncode(jsonData)
    writefile(macroPath, newContent)
end

local function startRecording(macroName)
    if isRecording then
        return false, "Recording is already in progress!"
    end
    
    if not macroName or macroName == "" then
        return false, "Select a macro to record!"
    end
    
    local macroPath = "tdx/macros/" .. macroName .. ".json"
    
    if not isfile or not isfile(macroPath) then
        return false, "Macro not found: " .. macroName
    end
    
    currentRecordingMacro = macroName
    recordedWaveConfig = {}
    recordedSpeedToggles = {}
    recordedDifficulty = nil
    
    local globalEnv = getGlobalEnv()
    globalEnv.TDX_Config = globalEnv.TDX_Config or {}
    
    globalEnv.TDX_AutoSkipEnabled = true
    
    globalEnv.TDX_RecordDifficulty = function(difficulty)
        recordedDifficulty = difficulty
    end
    
    globalEnv.TDX_RecordWaveConfig = function(waveName, skip, timeStr)
        if not isRecording then return end
        local timeNumber = nil
        if timeStr then
            timeNumber = convertTimeToNumber(timeStr)
        end
        if not recordedWaveConfig[waveName] then
            recordedWaveConfig[waveName] = {}
        end
        recordedWaveConfig[waveName].skip = skip
        recordedWaveConfig[waveName].time = timeNumber
    end
    
    globalEnv.TDX_RecordSpeedToggle = function(enabled)
        if not isRecording then return end
        local currentWave, currentTime = nil, nil
        local playerGui = player:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            local interface = playerGui:FindFirstChild("Interface")
            if interface then
                local gameInfoBar = interface:FindFirstChild("GameInfoBar")
                if gameInfoBar then
                    local waveText = gameInfoBar:FindFirstChild("Wave")
                    local timeText = gameInfoBar:FindFirstChild("TimeLeft")
                    if waveText and timeText then
                        currentWave = waveText:FindFirstChild("WaveText").Text
                        currentTime = timeText:FindFirstChild("TimeLeftText").Text
                    end
                end
            end
        end
        table.insert(recordedSpeedToggles, {
            enabled = enabled,
            wave = currentWave,
            time = currentTime
        })
    end
    
    globalEnv.TDX_Config["Macros"] = "record"
    
    local recordScript = getEmbeddedRecordScript(macroName)
    if not recordScript or recordScript == "" then
        return false, "Error: recording script is empty!"
    end
    
    local loadstringFunc = loadstring
    
    local success, err = pcall(function()
        if not loadstringFunc or type(loadstringFunc) ~= "function" then
            local genv = getGlobalEnv()
            loadstringFunc = genv.loadstring or _G.loadstring
            
            if (not loadstringFunc or type(loadstringFunc) ~= "function") and syn and syn.loadstring then
                loadstringFunc = syn.loadstring
            end
            
            if (not loadstringFunc or type(loadstringFunc) ~= "function") and getgenv then
                local genv = getgenv()
                if genv and genv.loadstring then
                    loadstringFunc = genv.loadstring
                end
            end
        end
        
        if not loadstringFunc or type(loadstringFunc) ~= "function" then
            error("loadstring is not available. Make sure you are using a supported executor (Synapse, Script-Ware, etc.)")
        end
        
        local func, parseError = loadstringFunc(recordScript)
        if not func then
            error("Error parsing recording script: " .. tostring(parseError))
        end
        
        task.spawn(function()
            func()
        end)
        
        task.wait(0.1)
        isRecording = true
    end)
    
    if not success then
        globalEnv.TDX_Config["Macros"] = nil
        globalEnv.TDX_AutoSkipEnabled = nil
        globalEnv.TDX_RecordSpeedToggle = nil
        currentRecordingMacro = nil
        return false, "Error loading recording script: " .. tostring(err)
    end
    
    return true, "Recording started! Macro: " .. macroName
end

local function stopRecording()
    if not isRecording then
        return false, "Recording is not active!"
    end
    
    local globalEnv = getGlobalEnv()
    if globalEnv.TDX_Config then
        globalEnv.TDX_Config["Macros"] = nil
    end
    
    local macroPath = "tdx/macros/" .. currentRecordingMacro .. ".json"
    if isfile and isfile(macroPath) then
        local content = readfile(macroPath)
        local jsonData = HttpService:JSONDecode(content)
        
        local waveConfig = {}
        for _, entry in ipairs(jsonData) do
            if entry.SkipWave and entry.skip == true then
                local waveName = string.upper(tostring(entry.SkipWave))
                waveConfig[waveName] = {
                    skip = true,
                    time = entry.time
                }
            end
        end
        local difficulty = recordedDifficulty or (globalEnv.TDX_Config and globalEnv.TDX_Config["Auto Difficulty"])
        
        local configToSave = {
            Map = globalEnv.TDX_Config and globalEnv.TDX_Config["Map"] or nil,
            ["Auto Difficulty"] = difficulty,
            mapvoting = globalEnv.TDX_Config and globalEnv.TDX_Config.mapvoting or nil,
            WaveConfig = waveConfig,
            SpeedToggles = recordedSpeedToggles,
            ["Return Lobby"] = globalEnv.TDX_Config and globalEnv.TDX_Config["Return Lobby"] or nil,
            ["Auto Skill"] = globalEnv.TDX_Config and globalEnv.TDX_Config["Auto Skill"] or nil,
            loadout = globalEnv.TDX_Config and globalEnv.TDX_Config.loadout or nil
        }
        saveConfigToMacro(macroPath, configToSave)
    end
    
    isRecording = false
    currentRecordingMacro = nil
    recordedWaveConfig = {}
    recordedSpeedToggles = {}
    recordedDifficulty = nil
    
    if globalEnv.TDX_AutoSkipEnabled ~= nil then
        globalEnv.TDX_AutoSkipEnabled = nil
    end
    if globalEnv.TDX_RecordSpeedToggle then
        globalEnv.TDX_RecordSpeedToggle = nil
    end
    if globalEnv.TDX_RecordDifficulty then
        globalEnv.TDX_RecordDifficulty = nil
    end
    if globalEnv.TDX_RecordWaveConfig then
        globalEnv.TDX_RecordWaveConfig = nil
    end
    
    return true, "Recording stopped! Macro saved."
end

local function playMacro(macroName)
    if isRecording then
        return false, "Stop recording first!"
    end
    
    if not macroName or macroName == "" then
        return false, "Select a macro!"
    end
    
    local macroPath = "tdx/macros/" .. macroName .. ".json"
    
    if not isfile or not isfile(macroPath) then
        return false, "Macro not found: " .. macroName
    end
    
    local content = readfile(macroPath)
    local jsonData = HttpService:JSONDecode(content)
    
    local config = nil
    if jsonData[1] and jsonData[1].SuperFunction == "config" then
        config = jsonData[1]
    end
    
    local globalEnv = getGlobalEnv()
    globalEnv.TDX_Config = globalEnv.TDX_Config or {}
    
    if config then
        globalEnv.TDX_Config["Map"] = config.Map
        globalEnv.TDX_Config["Auto Difficulty"] = config.Difficulty
        globalEnv.TDX_Config.mapvoting = config.MapVoting
        globalEnv.TDX_Config["Return Lobby"] = config.ReturnLobby
        globalEnv.TDX_Config["Auto Skill"] = config.AutoSkill
        globalEnv.TDX_Config.loadout = config.Loadout
        
        if config.WaveConfig then
            _G.WaveConfig = config.WaveConfig
        end
        
        if config.SpeedToggles then
            task.spawn(function()
                for _, speedToggle in ipairs(config.SpeedToggles) do
                    while true do
                        local playerGui = player:FindFirstChildOfClass("PlayerGui")
                        if playerGui then
                            local interface = playerGui:FindFirstChild("Interface")
                            if interface then
                                local gameInfoBar = interface:FindFirstChild("GameInfoBar")
                                if gameInfoBar then
                                    local waveText = gameInfoBar:FindFirstChild("Wave")
                                    local timeText = gameInfoBar:FindFirstChild("TimeLeft")
                                    if waveText and timeText then
                                        local currentWave = waveText:FindFirstChild("WaveText").Text
                                        local currentTime = timeText:FindFirstChild("TimeLeftText").Text
                                        
                                        if currentWave == speedToggle.wave and currentTime == speedToggle.time then
                                            local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
                                            if Remotes then
                                                local Remote = Remotes:FindFirstChild("SoloToggleSpeedControl")
                                                if Remote then
                                                    if Remote:IsA("RemoteEvent") then
                                                        Remote:FireServer(speedToggle.enabled, true)
                                                    elseif Remote:IsA("RemoteFunction") then
                                                        Remote:InvokeServer(speedToggle.enabled, true)
                                                    end
                                                end
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        task.wait(0.1)
                    end
                end
            end)
        end
    end
    
    globalEnv.TDX_Config["Macros"] = "run"
    globalEnv.TDX_Config["Macro Name"] = macroName
    
    local autoSkipToggleOn = Toggles.AutoSkipToggle and Toggles.AutoSkipToggle.Value

    if config then
        pcall(function() loadstring(getEmbeddedSpeedScript())() end)
        
        if config.Map then
            pcall(function() loadstring(getEmbeddedAutoJoinScript())() end)
        end
        if config.Difficulty then
            pcall(function() loadstring(getEmbeddedDifficultyScript())() end)
        end
        if config.WaveConfig and autoSkipToggleOn then
            pcall(function() loadstring(getEmbeddedAutoSkipScript())() end)
        end
        if config.mapvoting and game.PlaceId == 11739766412 then
            pcall(function() loadstring(getEmbeddedVoterScript())() end)
        end
        if config.ReturnLobby then
            pcall(function() loadstring(getEmbeddedReturnLobbyScript())() end)
        end
        if config.AutoSkill then
            pcall(function() loadstring(getEmbeddedAutoSkillScript())() end)
        end
    else
        pcall(function() loadstring(getEmbeddedSpeedScript())() end)
    end
    
    local runScript = getEmbeddedRunMacroScript()
    local success, err = pcall(function()
        loadstring(runScript)()
    end)
    
    if not success then
        return false, "Error loading playback script: " .. tostring(err)
    end
    
    return true, "Macro '" .. macroName .. "' started!"
end



local Tabs = {
    Main = Window:AddTab("Macros", "play"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

local placeId = game.PlaceId
local isLobby = (placeId == 9503261072)
local isLoadingConfig = true
local deferredPlayMacro = false

local function playSelectedMacro()
    local selected = Options.MacroDropdown.Value
    local macros = getMacroList()
    local found = false
    for _, m in ipairs(macros) do
        if m == selected then
            found = true
            break
        end
    end
    if not selected or selected == "" or selected == "No macros found" or not found then
        Library:Notify({
            Title = "Error",
            Description = "Select a macro from the list!",
            Time = 3,
        })
        if Toggles.PlayMacroToggle then
            Toggles.PlayMacroToggle:SetValue(false)
        end
        return
    end
    local success, message = playMacro(selected)
    if success then
        Library:Notify({
            Title = "Macro Started",
            Description = message,
            Time = 5,
        })
    else
        Library:Notify({
            Title = "Error",
            Description = message,
            Time = 5,
        })
        if Toggles.PlayMacroToggle then
            Toggles.PlayMacroToggle:SetValue(false)
        end
    end
end

local MainLeftGroup, MainRightGroup

if not isLobby then
    MainLeftGroup = Tabs.Main:AddLeftGroupbox("Record Macro", "record")
    MainRightGroup = Tabs.Main:AddRightGroupbox("Play Macro", "play")
end

if not isLobby then
MainLeftGroup:AddInput("NewMacroNameInput", {
    Default = "",
    Numeric = false,
    Finished = false,
    Text = "New Macro Name",
    Placeholder = "Enter name",
    Tooltip = "Enter a name for the new macro",
})

MainLeftGroup:AddButton({
    Text = "Create New Macro",
    Func = function()
        local macroName = Options.NewMacroNameInput.Value
        local success, message = createNewMacro(macroName)
        if success then
            Library:Notify({
                Title = "Macro Created",
                Description = message,
                Time = 3,
            })
            Options.NewMacroNameInput:SetValue("")
            task.wait(0.5)
            local macros = getMacroList()
            if #macros > 0 then
                Options.MacroDropdown:SetValues(macros)
                Options.MacroDropdown:SetValue(macroName)
            end
        else
            Library:Notify({
                Title = "Error",
                Description = message,
                Time = 3,
            })
        end
    end,
})

local macroList = getMacroList()
MainLeftGroup:AddDropdown("RecordMacroDropdown", {
    Values = #macroList > 0 and macroList or { "Create a macro first" },
    Default = 1,
    Multi = false,
    Text = "Select Macro to Record",
    Tooltip = "Select the macro to be recorded",
    Callback = function(Value) end,
})

MainLeftGroup:AddToggle("RecordMacroToggle", {
    Text = "Record Macro",
    Default = false,
    Tooltip = "Enable to start recording the selected macro",
    Callback = function(Value)
        if Value then
            local selected = Options.RecordMacroDropdown.Value
            if not selected or selected == "" or selected == "Create a macro first" then
                Library:Notify({
                    Title = "Error",
                    Description = "Select a macro to record!",
                    Time = 3,
                })
                Toggles.RecordMacroToggle:SetValue(false)
                return
            end
            
            local success, message = startRecording(selected)
            if success then
                Library:Notify({
                    Title = "Recording Started",
                    Description = message,
                    Time = 5,
                })
            else
                Library:Notify({
                    Title = "Error",
                    Description = message,
                    Time = 5,
                })
                Toggles.RecordMacroToggle:SetValue(false)
            end
        else
            local success, message = stopRecording()
            if success then
                Library:Notify({
                    Title = "Recording Stopped",
                    Description = message,
                    Time = 5,
                })
            else
                Library:Notify({
                    Title = "Error",
                    Description = message,
                    Time = 5,
                })
            end
        end
    end,
})

MainRightGroup:AddDropdown("MacroDropdown", {
    Values = #macroList > 0 and macroList or { "No macros found" },
    Default = 1,
    Multi = false,
    Text = "Select Macro",
    Tooltip = "Select a macro to play",
    Callback = function(Value) end,
})

MainRightGroup:AddToggle("PlayMacroToggle", {
    Text = "Play Macro",
    Default = false,
    Tooltip = "Enable to play the selected macro",
    Callback = function(Value)
        if Value then
            if isLoadingConfig then
                deferredPlayMacro = true
                return
            end
            playSelectedMacro()
        else
            Library:Notify({
                Title = "Info",
                Description = "To stop playback, restart the game",
                Time = 3,
            })
        end
    end,
})

MainRightGroup:AddButton({
    Text = "Refresh Macro List",
    Func = function()
        local macros = getMacroList()
        if #macros > 0 then
            Options.MacroDropdown:SetValues(macros)
            Options.MacroDropdown:SetValue(macros[1])
            Options.RecordMacroDropdown:SetValues(macros)
            Options.RecordMacroDropdown:SetValue(macros[1])
            Library:Notify({
                Title = "List Updated",
                Description = "Found macros: " .. #macros,
                Time = 3,
            })
        else
            Library:Notify({
                Title = "No Macros Found",
                Description = "Create a macro first",
                Time = 3,
            })
        end
    end,
})
end

local MiscGroup

if isLobby then
    MiscGroup = Tabs.Main:AddRightGroupbox("Misc Func", "settings")
else
    MiscGroup = Tabs.Main:AddRightGroupbox("Misc Func", "settings")
end

if isLobby then
MiscGroup:AddButton({
    Text = "Quick Join Game",
    Func = function()
        local TeleportService = game:GetService("TeleportService")
        pcall(function()
            TeleportService:Teleport(11739766412, game.Players.LocalPlayer)
        end)
    end,
})
end

local function startSimpleAutoSkip()
    local globalEnv = getGlobalEnv()
    if globalEnv.TDX_SimpleAutoSkipRunning then return end
    globalEnv.TDX_SimpleAutoSkipRunning = true
    pcall(function() 
        loadstring(getEmbeddedSimpleAutoSkipScript())()
    end)
end

if not isLobby then
MiscGroup:AddToggle("AutoSkipToggle", {
    Text = "Auto Skip",
    Default = false,
    Tooltip = "Automatically skips waves when SkipWaveVoteScreen becomes visible",
    Callback = function(Value)
        local globalEnv = getGlobalEnv()
        globalEnv.TDX_AutoSkipEnabled = Value
        if Value then
            startSimpleAutoSkip()
        end
    end,
})

MiscGroup:AddToggle("Speed15Toggle", {
    Text = "1.5x Speed",
    Default = false,
    Tooltip = "Enable/disable 1.5x game speed",
    Callback = function(Value)
        task.spawn(function()
            local Remotes = ReplicatedStorage:WaitForChild("Remotes")
            local SoloToggleSpeedControl = Remotes:WaitForChild("SoloToggleSpeedControl")
            
            local args = Value and {true, true} or {false}
            local success, err = pcall(function()
                SoloToggleSpeedControl:FireServer(unpack(args))
            end)
            
            if success then
                Library:Notify({
                    Title = Value and "Speed Enabled" or "Speed Disabled",
                    Description = Value and "1.5x speed activated" or "1.5x speed deactivated",
                    Time = 3,
                })
            else
                Library:Notify({
                    Title = "Error",
                    Description = "Failed to toggle speed: " .. tostring(err),
                    Time = 5,
                })
                Toggles.Speed15Toggle:SetValue(not Value)
            end
        end)
    end,
})

MiscGroup:AddToggle("ReturnLobbyToggle", {
    Text = "Return Lobby",
    Default = false,
    Tooltip = "Automatically return to lobby when game ends",
    Callback = function(Value)
        if Value then
            local globalEnv = getGlobalEnv()
            if not globalEnv.TDX_ReturnLobbyRunning then
                globalEnv.TDX_ReturnLobbyRunning = true
                pcall(function()
                    loadstring(getEmbeddedReturnLobbyScript())()
                end)
            end
        else
            local globalEnv = getGlobalEnv()
            globalEnv.TDX_ReturnLobbyEnabled = nil
            globalEnv.TDX_ReturnLobbyRunning = nil
        end
    end,
})

MiscGroup:AddToggle("HealToggle", {
    Text = "Heal",
    Default = false,
    Tooltip = "Auto heal using proximity prompt",
    Callback = function(Value)
        if Value then
            if not globalEnv.TDX_HealRunning then
                globalEnv.TDX_HealRunning = true
                pcall(function()
                    loadstring(getEmbeddedHealScript())()
                end)
            end
        end
    end,
})

local collectCreditThread
local function collectUpgradeShopCredits()
    if game.PlaceId ~= 11739766412 then return end
    local gameFolder = workspace:FindFirstChild("Game")
    if not gameFolder then return end
    local ri = gameFolder:FindFirstChild("RaycastIgnore")
    if not ri then return end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end
    local event = remotes:FindFirstChild("ClientsideCoinCollectedStartedEvent")
    if not event then return end
    for _, child in ipairs(ri:GetChildren()) do
        local num = tostring(child.Name):match("^UpgradeShopCredit(%d+)$")
        if num then
            local n = tonumber(num)
            if n then
                pcall(function()
                    if event:IsA("RemoteEvent") then
                        event:FireServer(n)
                    elseif event:IsA("RemoteFunction") then
                        event:InvokeServer(n)
                    end
                end)
            end
        end
    end
end

local function startCollectUpgradeCredit()
    if game.PlaceId ~= 11739766412 then return end
    if collectCreditThread then return end
    collectCreditThread = task.spawn(function()
        while true do
            if not getGlobalEnv().TDX_CollectUpgradeCredit then
                break
            end
            collectUpgradeShopCredits()
            task.wait(0.2)
        end
        collectCreditThread = nil
    end)
end

if game.PlaceId == 11739766412 then
MiscGroup:AddToggle("CollectUpgradeCreditToggle", {
    Text = "Collect Upgrade Credit",
    Default = false,
    Tooltip = "Auto-collect upgrade credit coins",
    Callback = function(Value)
        if Value then
            getGlobalEnv().TDX_CollectUpgradeCredit = true
            startCollectUpgradeCredit()
        else
            getGlobalEnv().TDX_CollectUpgradeCredit = nil
        end
    end,
})
end
end

if not isLobby then
MiscGroup:AddToggle("BlackScreenToggle", {
    Text = "Black Screen",
    Default = false,
    Tooltip = "Show black screen with enemy info",
    Callback = function(Value)
        if Value then
            if not globalEnv.TDX_BlackScreenRunning then
                globalEnv.TDX_BlackScreenRunning = true
                pcall(function()
                    loadstring(getEmbeddedBlackScreenScript())()
                end)
            else
                if _G.blackon then
                    _G.blackon()
                end
            end
        else
            if _G.blackoff then
                _G.blackoff()
            end
            globalEnv.TDX_BlackScreenRunning = false
        end
    end,
}):AddKeyPicker("BlackScreenKeybind", { Default = "None", NoUI = false, Text = "Black Screen Key" })

Options.BlackScreenKeybind:OnClick(function()
    Toggles.BlackScreenToggle:SetValue(not Toggles.BlackScreenToggle.Value)
end)
end

local function normalizeString(str)
    if not str then return "" end
    return string.upper(str):gsub("%s+", "")
end

local function getMapsList()
    local maps = {}
    local success, mapData = pcall(function()
        return require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("MapData"))
    end)
    
    if success and mapData then
        for mapKey, _ in pairs(mapData) do
            if type(mapKey) == "string" then
                local mapName = mapKey:match("v3%.(.+)") or mapKey:match("^(.+)$")
                if mapName then
                    table.insert(maps, mapName)
                end
            end
        end
    end
    
    table.sort(maps)
    return maps
end

local function findMapAPC(mapName)
    local normalizedTarget = normalizeString(mapName)
    local apcTypes = {"APCs", "APCs2", "Helis", "BasementElevators"}
    
    for _, apcType in ipairs(apcTypes) do
        local apcContainer = workspace:FindFirstChild(apcType)
        if apcContainer then
            for _, apc in ipairs(apcContainer:GetChildren()) do
                if apc:IsA("Model") or apc:IsA("Folder") then
                    local mapDisplay = apc:FindFirstChild("mapdisplay")
                    if mapDisplay then
                        local screen = mapDisplay:FindFirstChild("screen")
                        if screen then
                            local displayScreen = screen:FindFirstChild("displayscreen")
                            if displayScreen then
                                local map = displayScreen:FindFirstChild("map")
                                if map and map:IsA("TextLabel") then
                                    local mapText = normalizeString(map.Text)
                                    if mapText == normalizedTarget then
                                        local detector = apc:FindFirstChild("APC")
                                        if detector then
                                            detector = detector:FindFirstChild("Detector")
                                            if detector then
                                                return detector
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

local function getAvailableTowers()
    local towers = {}
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local gui = playerGui:FindFirstChild("GUI")
        if gui then
            local shop = gui:FindFirstChild("Shop")
            if shop then
                local items = shop:FindFirstChild("Items")
                if items then
                    local towersFolder = items:FindFirstChild("Towers")
                    if towersFolder then
                        for _, towerItem in ipairs(towersFolder:GetChildren()) do
                            if towerItem:IsA("Frame") or towerItem:IsA("GuiObject") then
                                local checkmark = towerItem:FindFirstChild("Checkmark")
                                if checkmark and checkmark.Visible == true then
                                    table.insert(towers, towerItem.Name)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return towers
end

local function getPlayerLoadout(playerName)
    local Network = ReplicatedStorage:WaitForChild("Network")
    local ClientGetLoadoutForPlayerRequest = Network:WaitForChild("ClientGetLoadoutForPlayerRequest")
    local targetPlayer = Players:FindFirstChild(playerName)
    if not targetPlayer then return nil end
    
    local success, result = pcall(function()
        local args = {targetPlayer}
        return ClientGetLoadoutForPlayerRequest:InvokeServer(unpack(args))
    end)
    
    if success and result and result.Towers then
        return result.Towers
    end
    return nil
end

local function updateTowerDropdown()
    local availableTowers = getAvailableTowers()
    
    if #availableTowers == 0 then
        availableTowers = {"No towers available"}
    end
    
    if Options.TowerDropdown then
        Options.TowerDropdown:SetValues(availableTowers)
    end
end

local function clearAutoloadConfigs()
    local base = "TDXMacroManager"
    local function wipeAutoload(path)
        if listfiles then
            local ok, files = pcall(listfiles, path)
            if ok and files then
                for _, f in ipairs(files) do
                    local name = tostring(f):lower()
                    if name:find("autoload") and isfile and isfile(f) then
                        pcall(delfile, f)
                    end
                end
            end
        end
    end
    wipeAutoload(base)
    wipeAutoload(base .. "/settings")
    pcall(function()
        if SaveManager and SaveManager.ClearAutoloadConfig then
            SaveManager:ClearAutoloadConfig()
        elseif SaveManager and SaveManager.SetAutoloadConfig then
            SaveManager:SetAutoloadConfig(nil)
        end
    end)
end

local function clearSavedConfigs()
    local base = "TDXMacroManager"
    local targets = {
        base .. "/" .. tostring(game.PlaceId),
        base .. "/settings",
        base .. "/11739766412",
        base
    }
    local function wipe(path)
        if listfiles then
            local ok, files = pcall(listfiles, path)
            if ok and files then
                for _, f in ipairs(files) do
                    if isfile and isfile(f) then
                        pcall(delfile, f)
                    end
                end
            end
        end
    end
    for _, folder in ipairs(targets) do
        if isfolder and isfolder(folder) then
            wipe(folder)
        end
    end
    clearAutoloadConfigs()
    local genv = getGlobalEnv()
    genv.TDX_Config = {}
    _G.WaveConfig = nil
    genv.TDX_CollectUpgradeCredit = nil
    genv.TDX_ReturnLobbyEnabled = nil
    genv.TDX_HealEnabled = nil
    genv.TDX_AutoSkipEnabled = nil
end

local returnLobbyThread
local function startReturnLobby()
    local genv = getGlobalEnv()
    genv.TDX_ReturnLobbyEnabled = true
    if returnLobbyThread then return end
    returnLobbyThread = task.spawn(function()
        local v1 = ReplicatedStorage
        local v2 = Players
        local v3 = v2.LocalPlayer
        if not v3 then return end
        local v4 = v3:WaitForChild("PlayerGui")
        local v5 = v4:WaitForChild("Interface")
        local v6 = v5:WaitForChild("GameOverScreen")
        local v7 = v1:WaitForChild("Remotes")
        local v8 = v7:FindFirstChild("RequestTeleportToLobby")
        if not v8 or not (v8:IsA("RemoteEvent") or v8:IsA("RemoteFunction")) then
            returnLobbyThread = nil
            return
        end
        local function v9()
            for _ = 1, 5 do
                if not genv.TDX_ReturnLobbyEnabled then break end
                pcall(function()
                    task.wait(1)
                    if v8:IsA("RemoteEvent") then
                        v8:FireServer()
                    else
                        v8:InvokeServer()
                    end
                end)
                if not genv.TDX_ReturnLobbyEnabled then break end
                task.wait(1)
            end
        end
        local function v12()
            while genv.TDX_ReturnLobbyEnabled do
                if v6 and v6.Visible then
                    v9()
                end
                task.wait(4)
            end
        end
        if v6 and v6.Visible then
            v9()
        end
        if v6 then
            v6:GetPropertyChangedSignal("Visible"):Connect(function()
                if not genv.TDX_ReturnLobbyEnabled then return end
                if v6.Visible then
                    coroutine.wrap(v12)()
                end
            end)
        end
        local v13 = v5:WaitForChild("CutsceneScreen")
        local function v14()
            task.wait(1)
            v1:WaitForChild("Remotes"):WaitForChild("CutsceneVoteCast"):FireServer(true)
        end
        if v13.Visible then
            v14()
        else
            local v15
            v15 = v13:GetPropertyChangedSignal("Visible"):Connect(function()
                if v13.Visible then
                    v14()
                    v15:Disconnect()
                end
            end)
        end
        v12()
        returnLobbyThread = nil
    end)
end

local function stopReturnLobby()
    local genv = getGlobalEnv()
    genv.TDX_ReturnLobbyEnabled = nil
end


if isLobby then
    local mapsList = getMapsList()
    table.insert(mapsList, 1, "None")
    MiscGroup:AddDropdown("MapDropdown", {
        Values = #mapsList > 0 and mapsList or {"None", "Loading maps..."},
        Default = 1,
        Multi = false,
        Text = "Select Map",
        Tooltip = "Select a map to teleport to (auto teleport in loop)",
        Callback = function(Value) end,
    })
    
    task.spawn(function()
        task.wait(2)
        local maps = getMapsList()
        table.insert(maps, 1, "None")
        if #maps > 0 and Options.MapDropdown then
            local currentValue = Options.MapDropdown.Value
            Options.MapDropdown:SetValues(maps)
            if currentValue and currentValue ~= "" and currentValue ~= "Loading maps..." and currentValue ~= "None" then
                local found = false
                for _, map in ipairs(maps) do
                    if map == currentValue then
                        found = true
                        break
                    end
                end
                if found then
                    Options.MapDropdown:SetValue(currentValue)
                end
            end
        end
    end)
    
    task.spawn(function()
        while task.wait(1) do
            if Options.MapDropdown and Options.MapDropdown.Value and Options.MapDropdown.Value ~= "None" and Options.MapDropdown.Value ~= "" and Options.MapDropdown.Value ~= "Loading maps..." then
                local selectedMap = Options.MapDropdown.Value
                local detector = findMapAPC(selectedMap)
                if detector then
                    local apcTypes = {"APCs", "APCs2", "Helis", "BasementElevators"}
                    local foundAPC = nil
                    for _, apcType in ipairs(apcTypes) do
                        local apcContainer = workspace:FindFirstChild(apcType)
                        if apcContainer then
                            for _, apc in ipairs(apcContainer:GetChildren()) do
                                if apc:IsA("Model") or apc:IsA("Folder") then
                                    local mapDisplay = apc:FindFirstChild("mapdisplay")
                                    if mapDisplay then
                                        local screen = mapDisplay:FindFirstChild("screen")
                                        if screen then
                                            local displayScreen = screen:FindFirstChild("displayscreen")
                                            if displayScreen then
                                                local map = displayScreen:FindFirstChild("map")
                                                if map and map:IsA("TextLabel") then
                                                    local mapText = normalizeString(map.Text)
                                                    local normalizedTarget = normalizeString(selectedMap)
                                                    if mapText == normalizedTarget then
                                                        foundAPC = apc
                                                        break
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if foundAPC then break end
                    end
                    
                    if foundAPC then
                        local plrcount = foundAPC:FindFirstChild("mapdisplay")
                        if plrcount then
                            plrcount = plrcount:FindFirstChild("screen")
                            if plrcount then
                                plrcount = plrcount:FindFirstChild("displayscreen")
                                if plrcount then
                                    plrcount = plrcount:FindFirstChild("plrcount")
                                    if plrcount and plrcount:IsA("TextLabel") then
                                        local countText = plrcount.Text or ""
                                        local current, max = countText:match("(%d+)/(%d+)")
                                        current = tonumber(current) or 0
                                        max = tonumber(max) or 4
                                        
                                        if current > 1 then
                                            local Network = ReplicatedStorage:WaitForChild("Network")
                                            local LeaveQueue = Network:WaitForChild("LeaveQueue")
                                            pcall(function()
                                                LeaveQueue:FireServer()
                                            end)
                                            
                                            while current > 0 do
                                                task.wait(0.5)
                                                countText = plrcount.Text or ""
                                                current, max = countText:match("(%d+)/(%d+)")
                                                current = tonumber(current) or 0
                                                max = tonumber(max) or 4
                                            end
                                        end
                                        
                                        if current == 0 then
                                            local character = player.Character
                                            if character and character:FindFirstChild("HumanoidRootPart") then
                                                character:FindFirstChild("HumanoidRootPart").CFrame = detector.CFrame
                                                task.wait(0.5)
                                                
                                                countText = plrcount.Text or ""
                                                current, max = countText:match("(%d+)/(%d+)")
                                                current = tonumber(current) or 0
                                                
                                                if current > 1 then
                                                    local Network = ReplicatedStorage:WaitForChild("Network")
                                                    local LeaveQueue = Network:WaitForChild("LeaveQueue")
                                                    pcall(function()
                                                        LeaveQueue:FireServer()
                                                    end)
                                                    
                                                    while current > 0 do
                                                        task.wait(0.5)
                                                        countText = plrcount.Text or ""
                                                        current, max = countText:match("(%d+)/(%d+)")
                                                        current = tonumber(current) or 0
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    
    MiscGroup:AddDropdown("TowerDropdown", {
        Values = {"Loading..."},
        Default = 1,
        Multi = true,
        Text = "Select Towers for Loadout",
        Tooltip = "Select up to 6 towers for your loadout",
        Callback = function(Value) end,
    })

    MiscGroup:AddButton({
        Text = "Apply Loadout",
    Func = function()
        local selectedTowers = Options.TowerDropdown.Value
        
        local loadout = {}
        local count = 0
        
        if selectedTowers and type(selectedTowers) == "table" then
            for towerName, isSelected in pairs(selectedTowers) do
                if isSelected == true and count < 6 and towerName and towerName ~= "" and towerName ~= "No towers available" and towerName ~= "Loading..." then
                    table.insert(loadout, towerName)
                    count = count + 1
                end
            end
        end
        
        if count == 0 then
            Library:Notify({
                Title = "Error",
                Description = "No towers selected!",
                Time = 3,
            })
            return
        end
        
        while #loadout < 6 do
            table.insert(loadout, "")
        end
        
        task.spawn(function()
            local Network = ReplicatedStorage:WaitForChild("Network")
            local UpdateLoadout = Network:WaitForChild("UpdateLoadout")
            
            local args = {loadout}
            local success, err = pcall(function()
                UpdateLoadout:FireServer(unpack(args))
            end)
            
            if success then
                Library:Notify({
                    Title = "Loadout Updated",
                    Description = "Applied " .. count .. " tower(s) to loadout",
                    Time = 3,
                })
            else
                Library:Notify({
                    Title = "Error",
                    Description = "Failed to update loadout: " .. tostring(err),
                    Time = 5,
                })
            end
        end)
    end,
    })
    
    MiscGroup:AddButton({
        Text = "Reset Macro Config",
        Func = function()
            clearSavedConfigs()
            Library:Notify({
                Title = "Config Reset",
                Description = "Macro config cleared for this place and game",
                Time = 3,
            })
        end,
    })
    
    MiscGroup:AddToggle("OldShopUIToggle", {
        Text = "Old Shop UI",
        Default = false,
        Tooltip = "Show/hide old shop UI",
        Callback = function(Value)
            local playerGui = player:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                local gui = playerGui:FindFirstChild("GUI")
                if gui then
                    local shop = gui:FindFirstChild("Shop")
                    if shop then
                        shop.Visible = Value
                    end
                end
            end
        end,
    })
end

if isLobby then
    task.spawn(function()
        while task.wait(2) do
            updateTowerDropdown()
        end
    end)
end

if isLobby then
    task.spawn(function()
        task.wait(1)
        updateTowerDropdown()
    end)
end


task.spawn(function()
    while task.wait(5) do
        local macros = getMacroList()
        if #macros > 0 then
            local currentRecordValue = Options.RecordMacroDropdown and Options.RecordMacroDropdown.Value or nil
            local currentPlayValue = Options.MacroDropdown and Options.MacroDropdown.Value or nil
            
            if Options.MacroDropdown then
                Options.MacroDropdown:SetValues(macros)
            end
            if Options.RecordMacroDropdown then
                Options.RecordMacroDropdown:SetValues(macros)
            end
            
            local foundRecord = false
            local foundPlay = false
            for _, macro in ipairs(macros) do
                if macro == currentRecordValue then foundRecord = true end
                if macro == currentPlayValue then foundPlay = true end
            end
            
            if not foundRecord and Options.RecordMacroDropdown then
                Options.RecordMacroDropdown:SetValue(macros[1])
            end
            if not foundPlay and Options.MacroDropdown then
                if not (Toggles.PlayMacroToggle and Toggles.PlayMacroToggle.Value) then
                    Options.MacroDropdown:SetValue(macros[1])
                end
            end
        end
    end
end)

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu", "wrench")

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = true,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu Key")
    :AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu Key" })

MenuGroup:AddButton("Unload", function()
    Library:Unload()
end)

MenuGroup:AddButton("Reset Autoload Config", function()
    clearAutoloadConfigs()
    Library:Notify({
        Title = "Autoload Reset",
        Description = "Autoload configs cleared",
        Time = 3,
    })
end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
local ignoreIndexes = { "MenuKeybind", "BlackScreenKeybind" }
if isLobby then
    table.insert(ignoreIndexes, "RecordMacroDropdown")
    table.insert(ignoreIndexes, "MacroDropdown")
    table.insert(ignoreIndexes, "Speed15Toggle")
    table.insert(ignoreIndexes, "AutoSkipToggle")
    table.insert(ignoreIndexes, "BlackScreenToggle")
    table.insert(ignoreIndexes, "ReturnLobbyToggle")
    table.insert(ignoreIndexes, "HealToggle")
else
    table.insert(ignoreIndexes, "MapDropdown")
    table.insert(ignoreIndexes, "TowerDropdown")
    table.insert(ignoreIndexes, "OldShopUIToggle")
end
SaveManager:SetIgnoreIndexes(ignoreIndexes)

ThemeManager:SetFolder("TDXMacroManager")
SaveManager:SetFolder("TDXMacroManager")
SaveManager:SetSubFolder(tostring(game.PlaceId))

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()
isLoadingConfig = false
local globalEnv = getGlobalEnv()
globalEnv.TDX_AutoSkipEnabled = (Toggles.AutoSkipToggle and Toggles.AutoSkipToggle.Value) or false
if deferredPlayMacro and Toggles.PlayMacroToggle and Toggles.PlayMacroToggle.Value then
    deferredPlayMacro = false
    playSelectedMacro()
end

task.spawn(function()
    task.wait(0.5)
    if Toggles.ReturnLobbyToggle and Toggles.ReturnLobbyToggle.Value then
        startReturnLobby()
    end
    if Toggles.HealToggle and Toggles.HealToggle.Value then
        if not globalEnv.TDX_HealRunning then
            globalEnv.TDX_HealRunning = true
            pcall(function()
                loadstring(getEmbeddedHealScript())()
            end)
        end
    end
    if not isLobby and Toggles.BlackScreenToggle and Toggles.BlackScreenToggle.Value then
        if not globalEnv.TDX_BlackScreenRunning then
            globalEnv.TDX_BlackScreenRunning = true
            pcall(function()
                loadstring(getEmbeddedBlackScreenScript())()
            end)
        end
    end
    if Toggles.Speed15Toggle and Toggles.Speed15Toggle.Value then
        task.spawn(function()
            local Remotes = ReplicatedStorage:WaitForChild("Remotes")
            local SoloToggleSpeedControl = Remotes:WaitForChild("SoloToggleSpeedControl")
            local args = {true, true}
            pcall(function()
                SoloToggleSpeedControl:FireServer(unpack(args))
            end)
        end)
    end
    if Toggles.AutoSkipToggle and Toggles.AutoSkipToggle.Value then
        local globalEnv = getGlobalEnv()
        globalEnv.TDX_AutoSkipEnabled = true
    end
    if isLobby and Options.TowerDropdown then
        local selectedTowers = Options.TowerDropdown.Value
        if selectedTowers and type(selectedTowers) == "table" then
            local loadout = {}
            local count = 0
            for towerName, isSelected in pairs(selectedTowers) do
                if isSelected == true and count < 6 and towerName and towerName ~= "" and towerName ~= "No towers available" and towerName ~= "Loading..." then
                    table.insert(loadout, towerName)
                    count = count + 1
                end
            end
            if count > 0 then
                while #loadout < 6 do
                    table.insert(loadout, "")
                end
                task.spawn(function()
                    task.wait(1)
                    local Network = ReplicatedStorage:WaitForChild("Network")
                    local UpdateLoadout = Network:WaitForChild("UpdateLoadout")
                    local args = {loadout}
                    pcall(function()
                        UpdateLoadout:FireServer(unpack(args))
                    end)
                end)
            end
        end
    end
    if isLobby and Toggles.OldShopUIToggle and Toggles.OldShopUIToggle.Value then
        local playerGui = player:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            local gui = playerGui:FindFirstChild("GUI")
            if gui then
                local shop = gui:FindFirstChild("Shop")
                if shop then
                    shop.Visible = true
                end
            end
        end
    end
end)


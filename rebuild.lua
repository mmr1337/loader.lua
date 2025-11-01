local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local macroPath = "tdx/macros/recorder_output.json"

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

local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 120,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
    ["UseThreadedRemotes"] = true,
}

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
globalEnv.TDX_REBUILDING_TOWERS = globalEnv.TDX_REBUILDING_TOWERS or {}

for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

local function getMaxAttempts()
    local placeMode = globalEnv.TDX_Config.PlaceMode or "Rewrite"
    if placeMode == "Ashed" then return 1 end
    if placeMode == "Rewrite" then return 10 end
    return 1
end

local function safeReadFile(path)
    if readfile and isfile and isfile(path) then
        local ok, res = pcall(readfile, path)
        if ok then return res end
    end
    return nil
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = tick()
    while tick() - t0 < timeout do
        local ok, mod = pcall(require, path)
        if ok and mod then return mod end
        RunService.Heartbeat:Wait()
    end
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
if not TowerClass then error("Không thể load TowerClass!") end

local function AddToRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = true end
local function RemoveFromRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil end

task.spawn(function()
    while task.wait(0.5) do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                if globalEnv.TDX_Config.UseThreadedRemotes then
                    SafeRemoteCall("FireServer", Remotes.SellTower, hash)
                else
                    pcall(function() Remotes.SellTower:FireServer(hash) end)
                end
                task.wait(globalEnv.TDX_Config.AutoSellConvertDelay or 0.1)
            end
        end
    end
end)

local function GetTowerHashBySpawnX(targetX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local spawnCFrame = tower.SpawnCFrame
        if spawnCFrame and typeof(spawnCFrame) == "CFrame" then
            if spawnCFrame.Position.X == targetX then
                return hash, tower, spawnCFrame.Position
            end
        end
    end
    return nil, nil, nil
end

local function GetTowerByAxis(axisX)
    return GetTowerHashBySpawnX(axisX)
end

local function WaitForTowerInitialization(axisX, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local hash, tower = GetTowerByAxis(axisX)
        if hash and tower and tower.LevelHandler then
            return hash, tower
        end
        task.wait()
    end
    return nil, nil
end

local function WaitForCash(amount)
    while cash.Value < amount do
        RunService.RenderStepped:Wait()
    end
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
end

local function ShouldSkipTower(axisX, towerName, firstPlaceLine)
    local config = globalEnv.TDX_Config
    if config.SkipTowersAtAxis and table.find(config.SkipTowersAtAxis, axisX) then return true end
    if config.SkipTowersByName and table.find(config.SkipTowersByName, towerName) then return true end
    if config.SkipTowersByLine and firstPlaceLine and table.find(config.SkipTowersByLine, firstPlaceLine) then return true end
    return false
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

local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        if globalEnv.TDX_Config.UseThreadedRemotes then
            SafeRemoteCall("InvokeServer", Remotes.PlaceTower, unpack(args))
        else
            pcall(function()
                Remotes.PlaceTower:InvokeServer(unpack(args))
            end)
        end

        local _, tower = WaitForTowerInitialization(axisValue, 3)
        if tower then
            RemoveFromRebuildCache(axisValue)
            return true
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        local hash, tower = WaitForTowerInitialization(axisValue)
        if not hash then
            task.wait(0.2)
            attempts = attempts + 1
            continue
        end

        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then
            RemoveFromRebuildCache(axisValue)
            return true
        end

        WaitForCash(cost)

        if globalEnv.TDX_Config.UseThreadedRemotes then
            SafeRemoteCall("FireServer", Remotes.TowerUpgradeRequest, hash, path, 1)
        else
            pcall(function()
                Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
            end)
        end

        local startTime = tick()
        repeat
            task.wait(0.1)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler and t.LevelHandler:GetLevelOnPath(path) > before then
                RemoveFromRebuildCache(axisValue)
                return true
            end
        until tick() - startTime > 3

        attempts = attempts + 1
        task.wait()
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            if globalEnv.TDX_Config.UseThreadedRemotes then
                SafeRemoteCall("FireServer", Remotes.ChangeQueryType, hash, targetType)
            else
                pcall(function()
                    Remotes.ChangeQueryType:FireServer(hash, targetType)
                end)
            end
            RemoveFromRebuildCache(axisValue)
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    RemoveFromRebuildCache(axisValue)
end

local function HasSkill(axisValue, skillIndex)
    local hash, tower = WaitForTowerInitialization(axisValue)
    if not hash or not tower or not tower.AbilityHandler then
        return false
    end
    local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
    return ability ~= nil
end

local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local maxAttempts = getMaxAttempts()
    local attempts = 0
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then return false end

    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    AddToRebuildCache(axisValue)

    while attempts < maxAttempts do
        local hash, tower = WaitForTowerInitialization(axisValue)
        if hash and tower then
            if not tower.AbilityHandler then
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                RemoveFromRebuildCache(axisValue)
                return false
            end

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
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

local function RebuildTowerSequence(records)
    local placeRecord, upgradeRecords, targetRecords, movingRecords = nil, {}, {}, {}
    for _, record in ipairs(records) do
        local entry = record.entry
        if entry.TowerPlaced then placeRecord = record
        elseif entry.TowerUpgraded then table.insert(upgradeRecords, record)
        elseif entry.TowerTargetChange then table.insert(targetRecords, record)
        elseif entry.towermoving then table.insert(movingRecords, record) end
    end

    local rebuildSuccess = true

    if placeRecord then
        local entry = placeRecord.entry
        local vecTab = {}
        for coord in entry.TowerVector:gmatch("[^,%s]+") do 
            table.insert(vecTab, tonumber(coord)) 
        end
        if #vecTab == 3 then
            local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
            local args = {tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)}
            WaitForCash(entry.TowerPlaceCost)
            if not PlaceTowerRetry(args, pos.X, entry.TowerPlaced) then
                rebuildSuccess = false
            end
        end
    end

    if rebuildSuccess and #movingRecords > 0 then
        task.spawn(function()
            local lastMovingRecord = movingRecords[#movingRecords]
            local entry = lastMovingRecord.entry
            while not HasSkill(entry.towermoving, entry.skillindex) do
                RunService.Heartbeat:Wait()
            end
            UseMovingSkillRetry(entry.towermoving, entry.skillindex, entry.location)
        end)
    end

    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            local entry = record.entry
            if not UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) then
                rebuildSuccess = false
                break
            end
            task.wait(0.1)
        end
    end

    if rebuildSuccess then
        for _, record in ipairs(targetRecords) do
            local entry = record.entry
            ChangeTargetRetry(tonumber(entry.TowerTargetChange), entry.TargetWanted)
            task.wait(0.05)
        end
    end

    return rebuildSuccess
end

task.spawn(function()
    local lastMacroHash = ""
    local towersByAxis, soldAxis, rebuildAttempts = {}, {}, {}
    local deadTowerTracker = { deadTowers = {}, nextDeathId = 1 }

    local function recordTowerDeath(x)
        if not deadTowerTracker.deadTowers[x] then
            deadTowerTracker.deadTowers[x] = { deathTime = tick(), deathId = deadTowerTracker.nextDeathId }
            deadTowerTracker.nextDeathId = deadTowerTracker.nextDeathId + 1
        end
    end

    local function clearTowerDeath(x) 
        deadTowerTracker.deadTowers[x] = nil 
    end

    local jobQueue, activeJobs = {}, {}

    local function RebuildWorker()
        task.spawn(function()
            setThreadIdentity(2)
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)
                    if not ShouldSkipTower(job.x, job.towerName, job.firstPlaceLine) then
                        if RebuildTowerSequence(job.records) then
                            rebuildAttempts[job.x] = 0
                            clearTowerDeath(job.x)
                        end
                    else
                        rebuildAttempts[job.x] = 0
                        clearTowerDeath(job.x)
                    end
                    activeJobs[job.x] = nil
                else
                    RunService.Heartbeat:Wait()
                end
            end
        end)
    end

    for i = 1, globalEnv.TDX_Config.MaxConcurrentRebuilds do 
        RebuildWorker() 
    end

    while true do
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = #macroContent .. "|" .. macroContent:sub(1, 50)
            if macroHash ~= lastMacroHash then
                lastMacroHash = macroHash
                local ok, macro = pcall(HttpService.JSONDecode, HttpService, macroContent)
                if ok and type(macro) == "table" then
                    towersByAxis, soldAxis = {}, {}
                    for i, entry in ipairs(macro) do
                        local x = nil
                        if entry.SellTower then 
                            x = tonumber(entry.SellTower)
                            if x then soldAxis[x] = true end
                        elseif entry.TowerPlaced and entry.TowerVector then 
                            x = tonumber(entry.TowerVector:match("^([%d%-%.]+),"))
                        elseif entry.TowerUpgraded then 
                            x = tonumber(entry.TowerUpgraded)
                        elseif entry.TowerTargetChange then 
                            x = tonumber(entry.TowerTargetChange)
                        elseif entry.towermoving then 
                            x = entry.towermoving 
                        end

                        if x then
                            towersByAxis[x] = towersByAxis[x] or {}
                            table.insert(towersByAxis[x], {line = i, entry = entry})
                        end
                    end
                end
            end
        end

        local existingTowersCache = {}
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
                existingTowersCache[tower.SpawnCFrame.Position.X] = true
            end
        end

        local jobsAdded = false
        for x, records in pairs(towersByAxis) do
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
            elseif not existingTowersCache[x] then
                if not activeJobs[x] then
                    recordTowerDeath(x)
                    local towerType, firstPlaceLine = nil, nil
                    for _, record in ipairs(records) do
                        if record.entry.TowerPlaced then
                            towerType = record.entry.TowerPlaced
                            firstPlaceLine = record.line
                            break
                        end
                    end

                    if towerType then
                        rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                        local maxRetry = globalEnv.TDX_Config.MaxRebuildRetry
                        if not maxRetry or rebuildAttempts[x] <= maxRetry then
                            activeJobs[x] = true
                            table.insert(jobQueue, {
                                x = x, records = records, priority = GetTowerPriority(towerType),
                                deathTime = deadTowerTracker.deadTowers[x].deathTime,
                                towerName = towerType, firstPlaceLine = firstPlaceLine
                            })
                            jobsAdded = true
                        end
                    end
                end
            else
                clearTowerDeath(x)
                if activeJobs[x] then
                    activeJobs[x] = nil
                    for i = #jobQueue, 1, -1 do
                        if jobQueue[i].x == x then 
                            table.remove(jobQueue, i)
                            break 
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

        RunService.RenderStepped:Wait()
    end
end)
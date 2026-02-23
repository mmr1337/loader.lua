local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function setThreadIdentity(identity)
    if setthreadidentity then
        setthreadidentity(identity)
    elseif syn and syn.set_thread_identity then
        syn.set_thread_identity(identity)
    end
end

local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
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
        task.wait(0.1)
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
if not TowerClass then error("Cannot load TowerClass") end

local LHU_Cache = nil
local function GetLHU()
    if LHU_Cache then return LHU_Cache end
    pcall(function()
        LHU_Cache = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("LevelHandlerUtilities"))
    end)
    return LHU_Cache
end
GetLHU()

local defaultConfig = {
    ["MaxConcurrentRebuilds"] = 8,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["ForceRebuildEvenIfSold"] = false,
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
    ["UseThreadedRemotes"] = true,
    ["RebuildCashCooldown"] = 3,
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

local function AddToRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = true end
local function RemoveFromRebuildCache(axisX) globalEnv.TDX_REBUILDING_TOWERS[axisX] = nil end

task.spawn(function()
    while task.wait(0.5) do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                setThreadIdentity(2)
                pcall(function() Remotes.SellTower:FireServer(hash) end)
                task.wait(globalEnv.TDX_Config.AutoSellConvertDelay or 0.1)
            end
        end
    end
end)

local towerAxisCache = {}
local lastCacheTime = 0

local function RefreshTowerCache()
    local now = tick()
    if now - lastCacheTime < 0.2 then return end
    towerAxisCache = {}
    for hash, tower in pairs(TowerClass.GetTowers()) do
        if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
            towerAxisCache[tower.SpawnCFrame.Position.X] = hash
        end
    end
    lastCacheTime = now
end

local function ForceRefreshCache()
    lastCacheTime = 0
    RefreshTowerCache()
end

local function GetTowerByAxis(axisX)
    RefreshTowerCache()
    local hash = towerAxisCache[axisX]
    if hash then
        local towers = TowerClass.GetTowers()
        local tower = towers[hash]
        if tower then return hash, tower end
    end
    ForceRefreshCache()
    hash = towerAxisCache[axisX]
    if hash then
        local towers = TowerClass.GetTowers()
        return hash, towers[hash]
    end
    return nil, nil
end

local function WaitForTowerInitialization(axisX, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        ForceRefreshCache()
        local hash, tower = GetTowerByAxis(axisX)
        if hash and tower and tower.LevelHandler then
            return hash, tower
        end
        task.wait(0.15)
    end
    return nil, nil
end

local function WaitForCash(amount)
    while cash.Value < amount do task.wait(0.2) end
end

local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then return priority end
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
    if levelHandler:GetLevelOnPath(path) >= levelHandler:GetMaxLevel() then return nil end

    local towerName = tower.Type
    local discount = 0
    local dynamicPriceData = {}

    if tower.BuffHandler then
        pcall(function() discount = tower.BuffHandler:GetDiscount() or 0 end)
    end
    if levelHandler.HasDynamicPriceScaling then
        pcall(function() dynamicPriceData = TowerClass.GetDynamicPriceScalingData(tower) or {} end)
    end

    local lhu = GetLHU()
    if not lhu then return nil end

    local success, cost = pcall(function()
        return lhu.GetLevelUpgradeCost(levelHandler, towerName, path, 1, discount, 1, dynamicPriceData)
    end)
    return success and cost or nil
end

local function PlaceTowerRetry(args, axisValue, towerName)
    AddToRebuildCache(axisValue)
    for i = 1, 3 do
        setThreadIdentity(2)
        pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end)
        task.wait(0.2)
        ForceRefreshCache()
        local _, tower = GetTowerByAxis(axisValue)
        if tower then
            RemoveFromRebuildCache(axisValue)
            return true
        end
    end
    RemoveFromRebuildCache(axisValue)
    return false
end

local function UpgradeTowerRetry(axisValue, path)
    AddToRebuildCache(axisValue)
    for i = 1, 3 do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then
            task.wait(0.3)
            ForceRefreshCache()
            hash, tower = GetTowerByAxis(axisValue)
        end
        if not hash or not tower then
            RemoveFromRebuildCache(axisValue)
            return false
        end

        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then
            RemoveFromRebuildCache(axisValue)
            return true
        end

        local before = tower.LevelHandler:GetLevelOnPath(path)
        WaitForCash(cost)

        setThreadIdentity(2)
        pcall(function() Remotes.TowerUpgradeRequest:FireServer(hash, path, 1) end)
        task.wait(0.12)

        ForceRefreshCache()
        local _, t2 = GetTowerByAxis(axisValue)
        if t2 and t2.LevelHandler and t2.LevelHandler:GetLevelOnPath(path) > before then
            RemoveFromRebuildCache(axisValue)
            return true
        end
        task.wait(0.2)
    end
    RemoveFromRebuildCache(axisValue)
    return true
end

local function ChangeTargetRetry(axisValue, targetType)
    AddToRebuildCache(axisValue)
    for i = 1, 3 do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            setThreadIdentity(2)
            pcall(function() Remotes.ChangeQueryType:FireServer(hash, targetType) end)
            task.wait(0.1)
            RemoveFromRebuildCache(axisValue)
            return
        end
        task.wait(0.2)
    end
    RemoveFromRebuildCache(axisValue)
end

local function HasSkill(axisValue, skillIndex)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower or not tower.AbilityHandler then return false end
    return tower.AbilityHandler:GetAbilityFromIndex(skillIndex) ~= nil
end

local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local TowerUseAbilityRequest = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not TowerUseAbilityRequest then return false end
    local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
    AddToRebuildCache(axisValue)

    for i = 1, 3 do
        local hash, tower = GetTowerByAxis(axisValue)
        if hash and tower and tower.AbilityHandler then
            local ability = tower.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if not ability then
                RemoveFromRebuildCache(axisValue)
                return false
            end

            local cooldown = ability.CooldownRemaining or 0
            if cooldown > 0 then task.wait(cooldown + 0.1) end

            setThreadIdentity(2)
            local success = false

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

            if success then
                RemoveFromRebuildCache(axisValue)
                return true
            end
        end
        task.wait(0.2)
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
            local lastEntry = movingRecords[#movingRecords].entry
            local timeout = tick() + 30
            while not HasSkill(lastEntry.towermoving, lastEntry.skillindex) do
                if tick() > timeout then return end
                task.wait(0.5)
            end
            UseMovingSkillRetry(lastEntry.towermoving, lastEntry.skillindex, lastEntry.location)
        end)
    end

    if rebuildSuccess then
        table.sort(upgradeRecords, function(a, b) return a.line < b.line end)
        for _, record in ipairs(upgradeRecords) do
            if not UpgradeTowerRetry(tonumber(record.entry.TowerUpgraded), record.entry.UpgradePath) then
                rebuildSuccess = false
                break
            end
            task.wait(0.05)
        end
    end

    if rebuildSuccess then
        for _, record in ipairs(targetRecords) do
            ChangeTargetRetry(tonumber(record.entry.TowerTargetChange), record.entry.TargetWanted)
            task.wait(0.05)
        end
    end

    return rebuildSuccess
end

local function ParseMacroForRebuild(macro)
    local towersByAxis = {}
    local soldAxis = {}

    for i, entry in ipairs(macro) do
        if entry.SuperFunction or entry.SkipWave then
            continue
        end

        if entry.SellTower then
            local x = tonumber(entry.SellTower)
            if x then
                soldAxis[x] = true
                towersByAxis[x] = nil
            end

        elseif entry.TowerPlaced and entry.TowerVector then
            local x = tonumber(entry.TowerVector:match("^([%d%-%.]+),"))
            if x then
                soldAxis[x] = nil
                towersByAxis[x] = {}
                table.insert(towersByAxis[x], {line = i, entry = entry})
            end

        elseif entry.TowerUpgraded then
            local x = tonumber(entry.TowerUpgraded)
            if x and towersByAxis[x] then
                table.insert(towersByAxis[x], {line = i, entry = entry})
            end

        elseif entry.TowerTargetChange then
            local x = tonumber(entry.TowerTargetChange)
            if x and towersByAxis[x] then
                table.insert(towersByAxis[x], {line = i, entry = entry})
            end

        elseif entry.towermoving then
            local x = entry.towermoving
            if x and towersByAxis[x] then
                table.insert(towersByAxis[x], {line = i, entry = entry})
            end
        end
    end

    return towersByAxis, soldAxis
end

task.spawn(function()
    local macroName = globalEnv.TDX_Config["Macro Name"]
    local macroPath
    if macroName then
        macroPath = "tdx/macros/" .. macroName .. ".json"
    else
        macroPath = "tdx/macros/recorder_output.json"
    end

    local waitStart = tick()
    while tick() - waitStart < 30 do
        if safeReadFile(macroPath) then break end
        task.wait(1)
    end

    local lastMacroHash = ""
    local towersByAxis = {}
    local soldAxis = {}
    local rebuildAttempts = {}
    local everAlive = {}
    local lastCashValue = cash.Value
    local lastCashDecreaseTime = 0
    local REBUILD_CASH_COOLDOWN = globalEnv.TDX_Config.RebuildCashCooldown or 3

    local jobQueue = {}
    local activeJobs = {}
    local maxWorkers = globalEnv.TDX_Config.MaxConcurrentRebuilds or 8
    if maxWorkers > 20 then maxWorkers = 20 end

    for w = 1, maxWorkers do
        task.spawn(function()
            setThreadIdentity(2)
            while true do
                if #jobQueue > 0 then
                    local job = table.remove(jobQueue, 1)

                    if soldAxis[job.x] and not globalEnv.TDX_Config.ForceRebuildEvenIfSold then
                        activeJobs[job.x] = nil
                        continue
                    end

                    ForceRefreshCache()
                    if GetTowerByAxis(job.x) then
                        activeJobs[job.x] = nil
                        continue
                    end

                    if not ShouldSkipTower(job.x, job.towerName, job.firstPlaceLine) then
                        if RebuildTowerSequence(job.records) then
                            rebuildAttempts[job.x] = 0
                        end
                    else
                        rebuildAttempts[job.x] = 0
                    end

                    activeJobs[job.x] = nil
                else
                    task.wait(0.5)
                end
            end
        end)
    end

    while true do
        local macroContent = safeReadFile(macroPath)
        if macroContent and #macroContent > 10 then
            local macroHash = #macroContent .. "|" .. macroContent:sub(1, 80)
            if macroHash ~= lastMacroHash then
                lastMacroHash = macroHash
                local ok, macro = pcall(HttpService.JSONDecode, HttpService, macroContent)
                if ok and type(macro) == "table" then
                    towersByAxis, soldAxis = ParseMacroForRebuild(macro)
                end
            end
        end

        local currentCash = cash.Value
        if currentCash < lastCashValue then
            lastCashDecreaseTime = tick()
        end
        lastCashValue = currentCash

        local macroBusy = (tick() - lastCashDecreaseTime) < REBUILD_CASH_COOLDOWN

        ForceRefreshCache()
        local existingNow = {}
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" then
                local x = tower.SpawnCFrame.Position.X
                existingNow[x] = true
                everAlive[x] = true
            end
        end

        if not macroBusy then
            local jobsAdded = false

            for x, records in pairs(towersByAxis) do
                if not globalEnv.TDX_Config.ForceRebuildEvenIfSold and soldAxis[x] then
                    continue
                end

                if existingNow[x] then
                    continue
                end

                if activeJobs[x] then
                    continue
                end

                if not everAlive[x] then
                    continue
                end

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
                            x = x,
                            records = records,
                            priority = GetTowerPriority(towerType),
                            deathTime = tick(),
                            towerName = towerType,
                            firstPlaceLine = firstPlaceLine
                        })
                        jobsAdded = true
                    end
                end
            end

            if jobsAdded and #jobQueue > 1 then
                table.sort(jobQueue, function(a, b)
                    if a.priority == b.priority then return a.deathTime < b.deathTime end
                    return a.priority < b.priority
                end)
            end
        end

        for x in pairs(soldAxis) do
            if not globalEnv.TDX_Config.ForceRebuildEvenIfSold then
                everAlive[x] = nil
            end
        end

        task.wait(0.5)
    end
end)

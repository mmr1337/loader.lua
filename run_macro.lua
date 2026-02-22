local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local LevelHandlerUtilitiesCache = nil
local function GetLevelHandlerUtilities()
    if LevelHandlerUtilitiesCache then return LevelHandlerUtilitiesCache end
    local success, result = pcall(function()
        return require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("LevelHandlerUtilities"))
    end)
    if success and result then
        LevelHandlerUtilitiesCache = result
    end
    return LevelHandlerUtilitiesCache
end

local function setThreadIdentity(identity)
    if setthreadidentity then
        setthreadidentity(identity)
    elseif syn and syn.set_thread_identity then
        syn.set_thread_identity(identity)
    end
end

local function SafeRemoteCall(remoteType, remote, ...)
    local args = {...}
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
        task.wait(0.1)
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
    error("Cannot load TowerClass")
end

task.spawn(function()
    while task.wait(0.5) do
        for hash, tower in pairs(TowerClass.GetTowers()) do
            if tower.Converted == true then
                setThreadIdentity(2)
                pcall(function() Remotes.SellTower:FireServer(hash) end)
                task.wait(0.05)
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

-- [FIX] task.wait(0.05) вместо RenderStepped:Wait() — снижает нагрузку
local function WaitForTowerInitialization(axisX, timeout)
    timeout = timeout or 5
    local startTime = tick()
    while tick() - startTime < timeout do
        local hash, tower = GetTowerByAxis(axisX)
        if hash and tower and tower.LevelHandler then
            return hash, tower
        end
        task.wait(0.05)
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
                local default = gameInfoBar:FindFirstChild("Default")
                if default and default.Parent then
                    local waveFrame = default:FindFirstChild("Wave")
                    local timeFrame = default:FindFirstChild("TimeLeft")
                    if waveFrame and timeFrame and waveFrame.Parent and timeFrame.Parent then
                        local waveText = waveFrame:FindFirstChild("WaveText")
                        local timeText = timeFrame:FindFirstChild("TimeLeftText")
                        if waveText and timeText and waveText.Parent and timeText.Parent then
                            return { waveText = waveText, timeText = timeText }
                        end
                    end
                end
            end
        end
        attempts = attempts + 1
        task.wait(1)
    end
    error("Cannot find Game UI")
end

local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
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
            setThreadIdentity(2)
            pcall(function() Remotes.SellTower:FireServer(hash) end)
            task.wait(globalEnv.TDX_Config.MacroStepDelay)
        end
    end
end

-- [FIX] Используем кэшированный модуль вместо require каждый раз
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
    
    local LHU = GetLevelHandlerUtilities()
    if not LHU then return nil end
    
    local success, cost = pcall(function()
        return LHU.GetLevelUpgradeCost(levelHandler, towerName, path, 1, discount, priceMultiplier, dynamicPriceData)
    end)
    
    if not success then return nil end
    return cost
end

-- [FIX] task.wait(0.1) вместо RenderStepped — нет смысла проверять баланс 60 раз/сек
local function WaitForCash(amount)
    while cashStat.Value < amount do task.wait(0.1) end
end

-- [FIX] SafeRemoteCall теперь блокирующий — InvokeServer ждёт ответа сервера
-- Это главный фикс: раньше спавнился поток, InvokeServer уходил в фон,
-- код шёл дальше, не находил башню, спавнил ещё один InvokeServer и т.д.
-- Результат: десятки одновременных запросов на сервер → замедление
local function PlaceTowerRetry(args, axisValue)
    for i = 1, getMaxAttempts() do
        if globalEnv.TDX_Config.UseThreadedRemotes then
            SafeRemoteCall("InvokeServer", Remotes.PlaceTower, unpack(args))
        else
            setThreadIdentity(2)
            pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end)
        end
        task.wait(globalEnv.TDX_Config.MacroStepDelay)
        local _, tower = WaitForTowerInitialization(axisValue, 3)
        if tower then return true end
    end
    return false
end

-- [FIX] Верификация апгрейда: task.wait(0.05) вместо RenderStepped, таймаут 2с вместо 3
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
            setThreadIdentity(2)
            pcall(function() Remotes.TowerUpgradeRequest:FireServer(hash, path, 1) end)
        end

        task.wait(globalEnv.TDX_Config.MacroStepDelay)
        local startTime = tick()
        repeat
            task.wait(0.05)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler and t.LevelHandler:GetLevelOnPath(path) > before then return true end
        until tick() - startTime > 2
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
                setThreadIdentity(2)
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
    if globalEnv.TDX_Config.UseThreadedRemotes then
        SafeRemoteCall("FireServer", Remotes.SkipWaveVoteCast, true)
    else
        setThreadIdentity(2)
        pcall(function() Remotes.SkipWaveVoteCast:FireServer(true) end)
    end
    task.wait(globalEnv.TDX_Config.MacroStepDelay)
    return true
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
                setThreadIdentity(2)

                if location == "no_pos" then
                    success = pcall(function()
                        if useFireServer then
                            TowerUseAbilityRequest:FireServer(hash, skillIndex)
                        else
                            TowerUseAbilityRequest:InvokeServer(hash, skillIndex)
                        end
                    end)
                else
                    local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                    if x and y and z then
                        local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                        success = pcall(function()
                            if useFireServer then
                                TowerUseAbilityRequest:FireServer(hash, skillIndex, pos)
                            else
                                TowerUseAbilityRequest:InvokeServer(hash, skillIndex, pos)
                            end
                        end)
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
                setThreadIdentity(2)
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
            if attemptedSkipWaves[entry.SkipWave] then return false end
            if entry.SkipWave ~= currentWave then return false end
            if entry.SkipWhen then
                local currentTimeNumber = parseTimeToNumber(currentTime)
                if not currentTimeNumber or currentTimeNumber > entry.SkipWhen then return false end
            end
            return true
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
            attemptedSkipWaves[entry.SkipWave] = true
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
                    -- [FIX] task.wait(0.1) вместо RenderStepped для idle воркеров
                    task.wait(0.1)
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

            task.wait(config.RebuildCheckInterval or 0.1)
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
        error("Cannot read macro file") 
    end

    local ok, macro = pcall(function() return HttpService:JSONDecode(macroContent) end)
    if not ok or type(macro) ~= "table" then 
        error("Macro parse error") 
    end

    -- [FIX] Прогреваем кэш LevelHandlerUtilities до начала макро
    GetLevelHandlerUtilities()

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

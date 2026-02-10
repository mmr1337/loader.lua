local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

local outJson = "tdx/macros/recorder_output.json"

if isfile and isfile(outJson) and delfile then
    local ok, err = pcall(delfile, outJson)
    if not ok then
        warn("karamba: " .. tostring(err))
    end
end

local recordedActions = {}
local hash2pos = {}

local pendingQueue = {}
local timeout = 5
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

--==============================================================================
--=                           HÀM TIỆN ÍCH (HELPERS)                           =
--==============================================================================

local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Lỗi khi ghi file: " .. tostring(err))
        else
            print("✅ Đã ghi file: " .. path)
        end
    end
end

local function safeReadFile(path)
    if isfile and isfile(path) and readfile then
        local success, content = pcall(readfile, path)
        if success then
            return content
        end
    end
    return ""
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
    
    local defaultFrame = gameInfoBar:FindFirstChild("Default")
    if not defaultFrame then return nil, nil end

    local wave, time
    
    local waveFrame = defaultFrame:FindFirstChild("Wave")
    if waveFrame then
        local waveText = waveFrame:FindFirstChild("WaveText")
        if waveText and waveText:IsA("TextLabel") then
            wave = waveText.Text
        end
    end
    
    local timeFrame = defaultFrame:FindFirstChild("TimeLeft")
    if timeFrame then
        local timeText = timeFrame:FindFirstChild("TimeLeftText")
        if timeText and timeText:IsA("TextLabel") then
            time = timeText.Text
        end
    end

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
            table.insert(jsonLines, jsonStr)
        else
            warn("⚠️ Không thể encode entry #" .. i)
        end
    end
    local finalJson = "[\n" .. table.concat(jsonLines, ",\n") .. "\n]"
    safeWriteFile(outJson, finalJson)
end

local function preserveSuperFunctions()
    local content = safeReadFile(outJson)
    if content == "" then return end

    content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub(",$", "")
        if line:match("%S") then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
            if ok and decoded and decoded.SuperFunction then
                table.insert(recordedActions, decoded)
            end
        end
    end
    if #recordedActions > 0 then
        updateJsonFile()
    end
end

local function parseMacroLine(line)
    if line:match('TDX:skipWave%(%)') then
        local currentWave, currentTime = getCurrentWaveAndTime()
        return {{
            SkipWave = currentWave,
            SkipWhen = convertTimeToNumber(currentTime)
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

    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*"([^"]+)",%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%),%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
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
                TargetType = tonumber(targetType),
                TargetWave = currentWave,
                TargetTime = convertTimeToNumber(currentTime)
            }}
        end
    end

    local hash, wave, time = line:match('TDX:sellTower%(([^,]+),%s*"([^"]+)",%s*([^%)]+)%)')
    if hash and wave and time then
        local pos = hash2pos[tostring(hash)]
        if pos then
            return {{ 
                SellTower = pos.x,
                SellWave = wave,
                SellTime = tonumber(time)
            }}
        end
    end

    return nil
end

local function processAndWriteAction(commandString)
    if globalEnv.TDX_REBUILDING_TOWERS then
        local axisX = nil

        local vecMatch = commandString:match('Vector3%.new%(([^,]+),')
        if vecMatch then
            axisX = tonumber(vecMatch)
        end

        if not axisX then
            local hash = commandString:match('TDX:upgradeTower%(([^,]+),')
            if not hash then
                hash = commandString:match('TDX:changeQueryType%(([^,]+),')
            end
            if not hash then
                hash = commandString:match('TDX:useMovingSkill%(([^,]+),')
            end
            if not hash then
                hash = commandString:match('TDX:useSkill%(([^,]+),')
            end
            if not hash then
                hash = commandString:match('TDX:sellTower%(([^,]+),')
            end
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
            print("📝 Записано: " .. commandString:sub(1, 50))
        end
        updateJsonFile()
    end
end

--==============================================================================
--=                      XỬ LÝ SỰ KIỆN & HOOKS                                 =
--==============================================================================

local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    })
    print("⏳ Pending: " .. typeStr .. " | " .. code:sub(1, 50))
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

local lastTowerCount = 0
local soldTowerData = {}

task.spawn(function()
    while task.wait(0.05) do
        if TowerClass and TowerClass.GetTowers then
            local currentTowers = TowerClass.GetTowers()
            local currentCount = 0
            local currentHashes = {}
            
            for hash, tower in pairs(currentTowers) do
                currentCount = currentCount + 1
                currentHashes[tostring(hash)] = true
            end
            
            if currentCount < lastTowerCount then
                for hashStr, posData in pairs(hash2pos) do
                    if not currentHashes[hashStr] and not soldTowerData[hashStr] then
                        local currentWave, currentTime = getCurrentWaveAndTime()
                        local code = string.format('TDX:sellTower(%s, "%s", %s)', 
                            hashStr,
                            tostring(currentWave or "Unknown"),
                            tostring(convertTimeToNumber(currentTime) or 0))
                        
                        soldTowerData[hashStr] = true
                        processAndWriteAction(code)
                        hash2pos[hashStr] = nil
                        break
                    end
                end
            end
            
            lastTowerCount = currentCount
        end
    end
end)

ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data and data[1]
    if not d then return end
    if d.Creation then
        tryConfirm("Place")
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
        if args and args[1] == true then
            setPending("SkipWave", "TDX:skipWave()")
        end
    end

    if name == "TowerUseAbilityRequest" then
        local towerHash, skillIndex, targetPos = unpack(args)
        if typeof(towerHash) == "number" and typeof(skillIndex) == "number" then
            local towerName = GetTowerNameByHash(towerHash)
            if IsMovingSkillTower(towerName, skillIndex) then
                local code

                if IsPositionRequiredSkill(towerName, skillIndex) and typeof(targetPos) == "Vector3" then
                    code = string.format("TDX:useMovingSkill(%s, %d, Vector3.new(%s, %s, %s))", 
                        tostring(towerHash), 
                        skillIndex, 
                        tostring(targetPos.X), 
                        tostring(targetPos.Y), 
                        tostring(targetPos.Z))
                elseif not IsPositionRequiredSkill(towerName, skillIndex) then
                    code = string.format("TDX:useSkill(%s, %d)", 
                        tostring(towerHash), 
                        skillIndex)
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
    elseif name == "ChangeQueryType" then
        local towerHash, targetType = unpack(args)
        if typeof(towerHash) == "number" and typeof(targetType) == "number" then
            setPending("Target", string.format("TDX:changeQueryType(%s, %s)", tostring(towerHash), tostring(targetType)))
        end
    end
end

local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("⚠️ Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end

    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        if not checkcaller() then
            handleRemote(self.Name, {...})
        end
        return oldFireServer(self, ...)
    end)

    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        if not checkcaller() then
            handleRemote(self.Name, {...})
        end
        return oldInvokeServer(self, ...)
    end)

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            handleRemote(self.Name, {...})
        end
        return oldNamecall(self, ...)
    end)
    
    print("✅ Hooks установлены успешно")
end

--==============================================================================
--=                         VÒNG LẶP & KHỞI TẠO                               =
--==============================================================================

task.spawn(function()
    while task.wait(0.5) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                warn("❌ Timeout: " .. pendingQueue[i].type .. " | Code: " .. pendingQueue[i].code:sub(1, 50))
                table.remove(pendingQueue, i)
            end
        end
    end
end)

task.spawn(function()
    while task.wait(0.1) do
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

local function cleanupSkipWaveConnection()
    if skipWaveConnection then
        skipWaveConnection:Disconnect()
        skipWaveConnection = nil
    end
end

getGlobalEnv().TDX_CLEANUP_SKIP_WAVE = cleanupSkipWaveConnection

preserveSuperFunctions()
setupHooks()

print("🎬 Macro Recorder запущен! Файл: " .. outJson)
print("📊 Всего записей: " .. #recordedActions)

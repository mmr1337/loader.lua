local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function setThreadIdentity(identity)
    if setthreadidentity then setthreadidentity(identity)
    elseif syn and syn.set_thread_identity then syn.set_thread_identity(identity) end
end

local function SmartWait(seconds)
    if not seconds or seconds <= 0 then RunService.RenderStepped:Wait(); return end
    local start = tick()
    while tick() - start < seconds do RunService.RenderStepped:Wait() end
end

local function getGlobalEnv() return (getgenv and getgenv()) or _G end
local globalEnv = getGlobalEnv()

local defaultConfig = {
    ["MacroPath"] = "tdx/macros/recorder_output.json",
    ["MaxConcurrentRebuilds"] = 120,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["MaxRebuildRetry"] = nil,
    ["AutoSellConvertDelay"] = 0.2,
    ["PlaceMode"] = "Rewrite",
    ["UseThreadedRemotes"] = true,
    ["UpgradeDelay"] = 0.5, 
    ["SkipTowersAtAxis"] = {},
    ["SkipTowersByName"] = {},
    ["SkipTowersByLine"] = {},
    ["ReliveTowers"] = {}, 
    ["AutoReshield"] = true,
    ["ShieldTowerName"] = "Shield Tower",
    ["ReshieldThreshold"] = 0,
}

if makefolder then pcall(makefolder, "tdx"); pcall(makefolder, "tdx/macros") end

if not globalEnv.TDX_Recorder_Context then
    globalEnv.TDX_Recorder_Context = {
        Config = defaultConfig,
        RebuildingCache = {}, 
        HashToPosCache = {}   
    }
    if writefile then pcall(writefile, defaultConfig.MacroPath, "[]") end
else
    for k, v in pairs(defaultConfig) do globalEnv.TDX_Recorder_Context.Config[k] = v end
end

local CurrentConfig = globalEnv.TDX_Recorder_Context.Config
local RebuildingCache = globalEnv.TDX_Recorder_Context.RebuildingCache
local HashToPosCache = globalEnv.TDX_Recorder_Context.HashToPosCache

local function safeWriteFile(path, content) if writefile then pcall(writefile, path, content) end end
local function safeReadFile(path) 
    if isfile and isfile(path) and readfile then
        local s, c = pcall(readfile, path)
        return s and c or ""
    end
    return ""
end

local GameModules = { Networking = nil, LevelUtils = nil, TowerClass = nil, GameClass = nil }
local function InitializeModules()
    local Common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
    local function RequireSafe(mod)
        local t0 = tick()
        while tick() - t0 < 5 do
            local ok, m = pcall(require, mod)
            if ok and m then return m end
            RunService.RenderStepped:Wait()
        end
        return nil
    end
    GameModules.Networking = RequireSafe(Common:WaitForChild("NetworkingHandler"))
    GameModules.LevelUtils = RequireSafe(Common:WaitForChild("LevelHandlerUtilities"))
    local Client = PlayerScripts:WaitForChild("Client")
    local GameClassMod = Client:FindFirstChild("GameClass")
    if GameClassMod then
        GameModules.GameClass = RequireSafe(GameClassMod)
        local TowerMod = GameClassMod:FindFirstChild("TowerClass")
        if TowerMod then GameModules.TowerClass = RequireSafe(TowerMod) end
    end
end
InitializeModules()
if not GameModules.TowerClass then return end

local NetEvents = {}
local RequiredEvents = { "NewCoinDropEvent", "ClientsideCoinCollectedStartedEvent", "ClientsideCoinCollectedEvent" }
for _, name in ipairs(RequiredEvents) do NetEvents[name] = GameModules.Networking.GetEvent(name) end

NetEvents.NewCoinDropEvent:AttachCallback(function(args)
    local serverHash = args[1]
    local walkNear = args[10]
    if serverHash then
        task.spawn(function()
          task.wait(0.5)
            if walkNear then NetEvents.ClientsideCoinCollectedStartedEvent:FireServer(serverHash) end
            NetEvents.ClientsideCoinCollectedEvent:FireServer(serverHash)
        end)
    end
end)

local pendingQueue = {}
local lastKnownLevels = {}

local function appendToJsonFile(entry)
    if not HttpService then return end
    local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
    if not ok then return end
    local path = CurrentConfig.MacroPath
    local content = safeReadFile(path)
    if content == "" or content == "[]" then safeWriteFile(path, "[" .. jsonStr .. "]")
    else content = content:gsub("%s*%]%s*$", ""); safeWriteFile(path, content .. "," .. jsonStr .. "]") end
end

local function GetTowerSpawnPosition(tower)
    if not tower then return nil end
    local spawnCFrame = tower.SpawnCFrame
    if spawnCFrame and typeof(spawnCFrame) == "CFrame" then return spawnCFrame.Position end
    return nil
end

local function GetTowerNameByHash(towerHash)
    local towers = GameModules.TowerClass.GetTowers()
    local tower = towers[towerHash]
    return (tower and tower.Type) or nil
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface") or playerGui:WaitForChild("Interface", 1)
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
    
    local default = gameInfoBar:FindFirstChild("Default")
    if not default then return nil, nil end
    
    local waveFrame = default:FindFirstChild("Wave")
    local timerFrame = default:FindFirstChild("Timer")
    local waveText = waveFrame and waveFrame:FindFirstChild("WaveText")
    local timerText = timerFrame and timerFrame:FindFirstChild("TimerText")
    local waveNum = nil
    local timeStr = nil
    if waveText and waveText:IsA("TextLabel") then
        local raw = tostring(waveText.Text)
        local num = raw:match("Wave (%d+)")
        waveNum = tonumber(num)
    end
    if timerText and timerText:IsA("TextLabel") then
        timeStr = tostring(timerText.Text)
    end
    return waveNum, timeStr
end

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then return tonumber(mins) * 100 + tonumber(secs) end
    return nil
end

local function IsMovingSkillTower(towerName, skillIndex)
    if not towerName or not skillIndex then return false end
    if towerName == "Helicopter" and (skillIndex == 1 or skillIndex == 3) then return true end
    if towerName == "Cryo Helicopter" and (skillIndex == 1 or skillIndex == 3) then return true end
    if towerName == "Jet Trooper" and skillIndex == 1 then return true end
    if towerName == "Psycho Slayer" then return true end
    return false
end

local function parseMacroLine(line)
    if line:match('TDX:skipWave%(%)') then
        local w, t = getCurrentWaveAndTime()
        return {{ SkipWave = w, SkipWhen = convertTimeToNumber(t) }}
    end
    local sName, sStat, sBool = line:match('TDX:shopUpgrade%("([^"]+)",%s*"([^"]+)",%s*([^%)]+)%)')
    if not sName then sName, sStat = line:match('TDX:shopUpgrade%("([^"]+)",%s*"([^"]+)"%)') end
    if sName and sStat then
        local w, t = getCurrentWaveAndTime()
        return {{ ShopUpgrade = sName, Stat = sStat, Extra = (sBool == "true"), Wave = w, Time = convertTimeToNumber(t) }}
    end
    local rName = line:match('TDX:shopRefund%("([^"]+)"%)')
    if rName then
        local w, t = getCurrentWaveAndTime()
        return {{ ShopRefund = rName, Wave = w, Time = convertTimeToNumber(t) }}
    end
    local hash, skillIndex, x, y, z = line:match('TDX:useMovingSkill%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%)')
    if hash and skillIndex and x and y and z then
        local pos = HashToPosCache[tostring(hash)]
        if pos then
            local w, t = getCurrentWaveAndTime()
            return {{ towermoving = pos.x, skillindex = tonumber(skillIndex), location = string.format("%s, %s, %s", x, y, z), wave = w, time = convertTimeToNumber(t) }}
        end
    end
    local hash, skillIndex = line:match('TDX:useSkill%(([^,]+),%s*([^%)]+)%)')
    if hash and skillIndex then
        local pos = HashToPosCache[tostring(hash)]
        if pos then
            local w, t = getCurrentWaveAndTime()
            return {{ towermoving = pos.x, skillindex = tonumber(skillIndex), location = "no_pos", wave = w, time = convertTimeToNumber(t) }}
        end
    end
    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
        name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
        return {{ TowerPlaceCost = GetTowerPlaceCostByName(name), TowerPlaced = name, TowerVector = string.format("%s, %s, %s", x, y, z), Rotation = rot, TowerA1 = a1 }}
    end
    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos = HashToPosCache[tostring(hash)]
        local pathNum, count = tonumber(path), tonumber(upgradeCount)
        if pos and pathNum and count and count > 0 then
            local entries = {}
            for _ = 1, count do table.insert(entries, { UpgradeCost = 0, UpgradePath = pathNum, TowerUpgraded = pos.x }) end
            return entries
        end
    end
    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash and targetType then
        local pos = HashToPosCache[tostring(hash)]
        if pos then
            local w, t = getCurrentWaveAndTime()
            return {{ TowerTargetChange = pos.x, TargetWanted = tonumber(targetType), TargetWave = w, TargetChangedAt = convertTimeToNumber(t) }}
        end
    end
    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local hashStr = tostring(hash)
        local pos = HashToPosCache[hashStr]
        if pos then
            local entry = { SellTower = pos.x }
            HashToPosCache[hashStr] = nil
            return {entry}
        end
    end
    return nil
end

local function processAndWriteAction(commandString)
    local axisX = nil
    local _, _, vec = commandString:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+)')
    if vec then axisX = tonumber(vec) end
    if not axisX then
        local hash = commandString:match('TDX:upgradeTower%(([^,]+),') 
                  or commandString:match('TDX:changeQueryType%(([^,]+),')
                  or commandString:match('TDX:sellTower%(([^%)]+)%)')
                  or commandString:match('TDX:useMovingSkill%(([^,]+),')
                  or commandString:match('TDX:useSkill%(([^,]+),')
        if hash then
            local pos = HashToPosCache[tostring(hash)]
            if pos then axisX = pos.x end
        end
    end
    if axisX and RebuildingCache[axisX] then return end
    local entries = parseMacroLine(commandString)
    if entries then for _, entry in ipairs(entries) do appendToJsonFile(entry) end end
end

local function setPending(typeStr, code, hash, extra)
    table.insert(pendingQueue, { type = typeStr, code = code, created = tick(), hash = hash, extra = extra })
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
    if d.Creation then tryConfirm("Place") else tryConfirm("Sell") end
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or #data == 0 then return end
    local towerData = data[#data]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    if not lastKnownLevels[hash] then lastKnownLevels[hash] = {0, 0} end
    local pos = HashToPosCache[tostring(hash)]
    if not pos then lastKnownLevels[hash] = {newLevels[1] or 0, newLevels[2] or 0}; return end
    local old1, new1 = lastKnownLevels[hash][1] or 0, newLevels[1] or 0
    local old2, new2 = lastKnownLevels[hash][2] or 0, newLevels[2] or 0
    local count1 = (new1 > old1) and (new1 - old1) or 0
    local count2 = (new2 > old2) and (new2 - old2) or 0
    local paths = {}
    if count1 >= count2 then
        if count1 > 0 then table.insert(paths, {p=1, c=count1}) end
        if count2 > 0 then table.insert(paths, {p=2, c=count2}) end
    else
        if count2 > 0 then table.insert(paths, {p=2, c=count2}) end
        if count1 > 0 then table.insert(paths, {p=1, c=count1}) end
    end
    for _, pd in ipairs(paths) do
        for i=1, pd.c do
            if not RebuildingCache[pos.x] then appendToJsonFile({UpgradeCost=0, UpgradePath=pd.p, TowerUpgraded=pos.x}) end
        end
    end
    lastKnownLevels[hash] = {new1, new2}
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then tryConfirm("Target") end
end)

local UpgradeShopDataUpdate = ReplicatedStorage.Remotes:FindFirstChild("UpgradeShopDataUpdate")
if UpgradeShopDataUpdate then UpgradeShopDataUpdate.OnClientEvent:Connect(function() tryConfirm("ShopUpgrade") end) end

local UpgradeShopTowerReset = ReplicatedStorage.Remotes:FindFirstChild("UpgradeShopTowerReset")
if UpgradeShopTowerReset then UpgradeShopTowerReset.OnClientEvent:Connect(function(uid) if tostring(uid) == tostring(player.UserId) then tryConfirm("ShopRefund") end end) end

local function handleRemote(name, args)
    if name == "SkipWaveVoteCast" then
        if args and args[1] == true then setPending("SkipWave", "TDX:skipWave()") end
    elseif name == "UpgradeShopOperationRequest" then
        local tName, stat, isTrue = args[1], args[2], args[3]
        local code
        if isTrue ~= nil then code = string.format('TDX:shopUpgrade("%s", "%s", %s)', tostring(tName), tostring(stat), tostring(isTrue))
        else code = string.format('TDX:shopUpgrade("%s", "%s")', tostring(tName), tostring(stat)) end
        setPending("ShopUpgrade", code)
    elseif name == "UpgradeShopRefundAllRequest" then
        local tName = args[1]
        local code = string.format('TDX:shopRefund("%s")', tostring(tName))
        setPending("ShopRefund", code, nil, tName)
    elseif name == "TowerUseAbilityRequest" then
        local h, idx, vec = args[1], args[2], args[3]
        if type(h) == "number" and type(idx) == "number" then
            local tName = GetTowerNameByHash(h)
            if IsMovingSkillTower(tName, idx) then
                local code
                if (idx == 1) and typeof(vec) == "Vector3" then
                    code = string.format("TDX:useMovingSkill(%s, %d, Vector3.new(%s, %s, %s))", tostring(h), idx, tostring(vec.X), tostring(vec.Y), tostring(vec.Z))
                elseif idx == 3 then
                    code = string.format("TDX:useSkill(%s, %d)", tostring(h), idx)
                end
                if code then setPending("MovingSkill", code, h) end
            end
        end
    elseif name == "PlaceTower" then
        local a1, n, v, r = args[1], args[2], args[3], args[4]
        if type(a1)=="number" and type(n)=="string" and typeof(v)=="Vector3" and type(r)=="number" then
            setPending("Place", string.format('TDX:placeTower(%s, "%s", Vector3.new(%s, %s, %s), %s)', tostring(a1), n, tostring(v.X), tostring(v.Y), tostring(v.Z), tostring(r)))
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..tostring(args[1])..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", string.format("TDX:changeQueryType(%s, %s)", tostring(args[1]), tostring(args[2])))
    end
end

local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then return end
    local oldFireServer, oldInvokeServer
    oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldFireServer(self, ...)
    end)
    oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        handleRemote(self.Name, {...})
        return oldInvokeServer(self, ...)
    end)
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then handleRemote(self.Name, {...}) end
        return oldNamecall(self, ...)
    end)
end
setupHooks()

local function SafeRemoteCall(remoteType, remote, ...)
    local args = {...}
    task.spawn(function()
        setThreadIdentity(2)
        if remoteType == "FireServer" then pcall(function() remote:FireServer(unpack(args)) end)
        elseif remoteType == "InvokeServer" then pcall(function() remote:InvokeServer(unpack(args)) end) end
    end)
end

local function ForceSellTower(hash)
    if CurrentConfig.UseThreadedRemotes then SafeRemoteCall("FireServer", Remotes.SellTower, hash)
    else pcall(function() Remotes.SellTower:FireServer(hash) end) end
end

local function FindTower(mode, value)
    local towers = GameModules.TowerClass.GetTowers()
    if mode == "Axis" then
        for hash, tower in pairs(towers) do
            if tower.SpawnCFrame and typeof(tower.SpawnCFrame) == "CFrame" and tower.SpawnCFrame.Position.X == value then
                return hash, tower
            end
        end
    end
    return nil, nil
end

local function CreateTowerContext(axisX) return { axisX = axisX, hash = nil, tower = nil, levelHandler = nil } end
local function UpdateContext(ctx)
    local h, t = FindTower("Axis", ctx.axisX)
    if h and t and t.LevelHandler then ctx.hash = h; ctx.tower = t; ctx.levelHandler = t.LevelHandler; return true end
    return false
end

local function WaitForCash(amount) while cash.Value < amount do RunService.RenderStepped:Wait() end end

local function CalculateUpgradeCost(tower, path, count)
    if not tower or not tower.LevelHandler or count <= 0 then return nil end
    local lh = tower.LevelHandler
    local discount = 0; if tower.BuffHandler then pcall(function() discount = tower.BuffHandler:GetDiscount() or 0 end) end
    local dynamic = {}; if lh.HasDynamicPriceScaling then dynamic = GameModules.TowerClass.GetDynamicPriceScalingData(tower) or {} end
    local s, r = pcall(function() return GameModules.LevelUtils.GetLevelUpgradeCost(lh, tower.Type, path, count, discount, 1, dynamic) end)
    return s and math.ceil(r) or nil
end

local function PlaceTowerRetry(args, axisValue, towerName)
    local attempts = 0
    while attempts < 10 do
        if CurrentConfig.UseThreadedRemotes then SafeRemoteCall("InvokeServer", Remotes.PlaceTower, unpack(args))
        else pcall(function() Remotes.PlaceTower:InvokeServer(unpack(args)) end) end
        local t0 = tick()
        while tick() - t0 < 3 do if FindTower("Axis", axisValue) then return true end; RunService.RenderStepped:Wait() end
        attempts = attempts + 1
    end
    return false
end

local function UpgradeTowerToLevel(axisValue, targetPath1, targetPath2)
    local ctx = CreateTowerContext(axisValue)
    if not UpdateContext(ctx) then return false end
    local curP1 = ctx.levelHandler:GetLevelOnPath(1) or 0
    local curP2 = ctx.levelHandler:GetLevelOnPath(2) or 0
    local maxP1 = ctx.levelHandler:GetMaxPossibleLevel(1)
    local maxP2 = ctx.levelHandler:GetMaxPossibleLevel(2)
    local actualTarget1 = math.min(targetPath1, maxP1)
    local actualTarget2 = math.min(targetPath2, maxP2)
    if curP1 > actualTarget1 or curP2 > actualTarget2 then ForceSellTower(ctx.hash); return false end
    local function HandlePathSmart(pathIndex, targetLevel)
        while true do
            if not UpdateContext(ctx) then return false end
            local currentLevel = ctx.levelHandler:GetLevelOnPath(pathIndex) or 0
            if currentLevel >= targetLevel then 
                if currentLevel > targetLevel then ForceSellTower(ctx.hash); return false end
                return true 
            end
            local upgradesNeeded = targetLevel - currentLevel
            local currentCash = cash.Value
            local amountToBuy = 0
            for k = upgradesNeeded, 1, -1 do
                local costK = CalculateUpgradeCost(ctx.tower, pathIndex, k)
                if costK and currentCash >= costK then amountToBuy = k; break end
            end
            if amountToBuy == 0 then
                local costOne = CalculateUpgradeCost(ctx.tower, pathIndex, 1)
                if costOne then WaitForCash(costOne); amountToBuy = 1 else return false end
            end
            if amountToBuy > 0 then
                if CurrentConfig.UseThreadedRemotes then SafeRemoteCall("FireServer", Remotes.TowerUpgradeRequest, ctx.hash, pathIndex, amountToBuy)
                else pcall(function() Remotes.TowerUpgradeRequest:FireServer(ctx.hash, pathIndex, amountToBuy) end) end
                local start = tick()
                local expected = currentLevel + amountToBuy
                while tick() - start < 2 do
                    local lvl = ctx.levelHandler:GetLevelOnPath(pathIndex) or 0
                    if lvl >= expected then break end
                    RunService.RenderStepped:Wait()
                end
            else
                RunService.RenderStepped:Wait()
            end
        end
    end
    if not HandlePathSmart(1, actualTarget1) then return false end
    if not HandlePathSmart(2, actualTarget2) then return false end
    return true
end

local function ChangeTargetRetry(axisValue, targetType)
    local attempts = 0
    while attempts < 3 do
        local hash = FindTower("Axis", axisValue)
        if hash then
            if CurrentConfig.UseThreadedRemotes then SafeRemoteCall("FireServer", Remotes.ChangeQueryType, hash, targetType)
            else pcall(function() Remotes.ChangeQueryType:FireServer(hash, targetType) end) end
            return true
        end
        attempts = attempts + 1
        SmartWait(0.2)
    end
    return false
end

local function UseMovingSkillRetry(axisValue, skillIndex, location)
    local Remote = Remotes:FindFirstChild("TowerUseAbilityRequest")
    if not Remote then return false end
    local isEvent = Remote:IsA("RemoteEvent")
    local attempts = 0
    while attempts < 5 do
        local h, t = FindTower("Axis", axisValue)
        if h and t and t.AbilityHandler then
            local ability = t.AbilityHandler:GetAbilityFromIndex(skillIndex)
            if ability then
                if ability.CooldownRemaining > 0 then SmartWait(ability.CooldownRemaining + 0.1) end
                local args = {h, skillIndex}
                if location ~= "no_pos" then
                    local x, y, z = location:match("([^,%s]+),%s*([^,%s]+),%s*([^,%s]+)")
                    if x then table.insert(args, Vector3.new(tonumber(x), tonumber(y), tonumber(z))) end
                end
                if CurrentConfig.UseThreadedRemotes then SafeRemoteCall(isEvent and "FireServer" or "InvokeServer", Remote, unpack(args))
                else pcall(function() if isEvent then Remote:FireServer(unpack(args)) else Remote:InvokeServer(unpack(args)) end end) end
                return true
            end
        end
        attempts = attempts + 1
        SmartWait(0.2)
    end
    return false
end

local function RebuildTowerSequence(records)
    local placeRecord, upgradesByPath, targetRecords, movingRecords = nil, {[1]={}, [2]={}}, {}, {}
    for _, r in ipairs(records) do
        local e = r.entry
        if e.TowerPlaced then placeRecord = r
        elseif e.TowerUpgraded then table.insert(upgradesByPath[e.UpgradePath] or {}, r)
        elseif e.TowerTargetChange then table.insert(targetRecords, r)
        elseif e.towermoving then table.insert(movingRecords, r) end
    end
    local success = true
    if placeRecord then
        local e = placeRecord.entry
        local v = {}; for c in e.TowerVector:gmatch("[^,%s]+") do table.insert(v, tonumber(c)) end
        local pos = Vector3.new(v[1], v[2], v[3])
        local args = {tonumber(e.TowerA1), e.TowerPlaced, pos, tonumber(e.Rotation or 0)}
        WaitForCash(e.TowerPlaceCost)
        if not PlaceTowerRetry(args, pos.X, e.TowerPlaced) then success = false end
    end
    if success and placeRecord then
        local v = {}; for c in placeRecord.entry.TowerVector:gmatch("[^,%s]+") do table.insert(v, tonumber(c)) end
        local posX = v[1]
        local max1, max2 = #upgradesByPath[1], #upgradesByPath[2]
        if max1 > 0 or max2 > 0 then
            if not UpgradeTowerToLevel(posX, max1, max2) then success = false end
        end
    end
    if success then
        for _, r in ipairs(targetRecords) do ChangeTargetRetry(tonumber(r.entry.TowerTargetChange), r.entry.TargetWanted) end
        if #movingRecords > 0 then
            task.spawn(function()
                local last = movingRecords[#movingRecords].entry
                while not IsMovingSkillTower(last.towermoving, last.skillindex) do SmartWait(0.5) end
                UseMovingSkillRetry(last.towermoving, last.skillindex, last.location)
            end)
        end
    end
    return success
end

local lastMacroHash = ""
local towersByAxis, soldAxis, rebuildAttempts = {}, {}, {}
local deadTowers, nextDeathId, jobQueue, activeJobs = {}, 1, {}, {}
local loopTimers = { pending = 0, logic = 0 }

local function GetTowerPriority(towerName)
    for priority, name in ipairs(CurrentConfig.PriorityRebuildOrder or {}) do
        if towerName == name then return priority end
    end
    return 999
end

local function ShouldSkipTower(axisX, towerName, lineIndex)
    if CurrentConfig.SkipTowersAtAxis[axisX] then return true end
    if CurrentConfig.SkipTowersByName[towerName] then return true end
    if lineIndex and CurrentConfig.SkipTowersByLine[lineIndex] then return true end
    return false
end

RunService.RenderStepped:Connect(function(dt)
    if GameModules.TowerClass.GetTowers then
        local currentTowers = GameModules.TowerClass.GetTowers()
        local existingHashes = {}
        
        for hash, tower in pairs(currentTowers) do
            local pos = GetTowerSpawnPosition(tower)
            if pos then
                local hashStr = tostring(hash)
                existingHashes[hashStr] = true
                HashToPosCache[hashStr] = {x = pos.X, y = pos.Y, z = pos.Z}
            end
        end
        
        for hashStr, _ in pairs(HashToPosCache) do
            if not existingHashes[hashStr] then
                HashToPosCache[hashStr] = nil
            end
        end
    end

    loopTimers.pending = loopTimers.pending + dt
    if loopTimers.pending >= 0.05 then
        loopTimers.pending = 0
        for i = #pendingQueue, 1, -1 do
            local item = pendingQueue[i]
            local age = tick() - item.created
            local timeout = (item.type == "ShopUpgrade" or item.type == "ShopRefund") and 15 or 2
            if (item.type == "MovingSkill" or item.type == "SkipWave") and age > 0.1 then
                processAndWriteAction(item.code)
                table.remove(pendingQueue, i)
            elseif age > timeout then table.remove(pendingQueue, i) end
        end
    end

    loopTimers.logic = loopTimers.logic + dt
    if loopTimers.logic >= 0.2 then
        loopTimers.logic = 0
        pcall(function()
            for hash, tower in pairs(GameModules.TowerClass.GetTowers()) do
                local tName = tower.Type
                local shouldSell = tower.Converted
                if not shouldSell and CurrentConfig.ReliveTowers[tName] then
                    local val = CurrentConfig.ReliveTowers[tName]
                    if val == -1 and tower.IsRebuilding and tower:IsRebuilding() then shouldSell = true
                    elseif val ~= -1 and (tower.RebuildsLeft or 0) <= val then shouldSell = true end
                end
                if not shouldSell and CurrentConfig.AutoReshield and tName == CurrentConfig.ShieldTowerName then
                    if tower.LevelHandler and tower.LevelHandler.Path1Level >= 5 then
                        if (tower.HealthHandler:GetShield() or 0) <= (CurrentConfig.ReshieldThreshold or 0) then shouldSell = true end
                    end
                end
                if shouldSell then ForceSellTower(hash) end
            end
        end)
    end

    local path = CurrentConfig.MacroPath
    local content = safeReadFile(path)
    if content and #content > 10 then
        local mh = #content.."|"..content:sub(1,50)
        if mh ~= lastMacroHash then
            lastMacroHash = mh
            local ok, m = pcall(HttpService.JSONDecode, HttpService, content)
            if ok and type(m)=="table" then
                towersByAxis, soldAxis = {}, {}
                for i, e in ipairs(m) do
                    local x
                    if e.SellTower then x=tonumber(e.SellTower); soldAxis[x]=true
                    elseif e.TowerPlaced then x=tonumber(e.TowerVector:match("^([%d%-%.]+),"))
                    elseif e.TowerUpgraded then x=tonumber(e.TowerUpgraded)
                    elseif e.TowerTargetChange then x=tonumber(e.TowerTargetChange)
                    elseif e.towermoving then x=e.towermoving end
                    if x then towersByAxis[x] = towersByAxis[x] or {}; table.insert(towersByAxis[x], {line=i, entry=e}) end
                end
            end
        end
    end

    local existCache = {}
    for _, t in pairs(GameModules.TowerClass.GetTowers()) do if t.SpawnCFrame then existCache[t.SpawnCFrame.Position.X] = true end end

    local added = false
    for x, recs in pairs(towersByAxis) do
        if not soldAxis[x] and not existCache[x] then
            if not activeJobs[x] then
                if not deadTowers[x] then deadTowers[x] = {time=tick(), id=nextDeathId}; nextDeathId=nextDeathId+1 end
                local tType, line
                for _, r in ipairs(recs) do if r.entry.TowerPlaced then tType=r.entry.TowerPlaced; line=r.line; break end end
                if tType then
                    rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                    if not CurrentConfig.MaxRebuildRetry or rebuildAttempts[x] <= CurrentConfig.MaxRebuildRetry then
                        activeJobs[x] = true
                        table.insert(jobQueue, { x=x, records=recs, priority=GetTowerPriority(tType), deathTime=deadTowers[x].time, towerName=tType, firstPlaceLine=line })
                        added = true
                    end
                end
            end
        else
            deadTowers[x] = nil
            if activeJobs[x] then
                activeJobs[x] = nil
                for i=#jobQueue, 1, -1 do if jobQueue[i].x == x then table.remove(jobQueue, i); break end end
            end
        end
    end
    if added and #jobQueue > 1 then table.sort(jobQueue, function(a,b) return (a.priority==b.priority) and (a.deathTime<b.deathTime) or (a.priority<b.priority) end) end
end)

task.spawn(function()
    while true do
        RunService.RenderStepped:Wait()
        if #jobQueue > 0 then
            local job = table.remove(jobQueue, 1)
            task.spawn(function()
                setThreadIdentity(2)
                RebuildingCache[job.x] = true
                local s = pcall(function()
                    if not ShouldSkipTower(job.x, job.towerName, job.firstPlaceLine) then
                        if RebuildTowerSequence(job.records) then rebuildAttempts[job.x] = 0; deadTowers[job.x] = nil end
                    else rebuildAttempts[job.x] = 0; deadTowers[job.x] = nil end
                end)
                RebuildingCache[job.x] = nil
                if not s then rebuildAttempts[job.x] = (rebuildAttempts[job.x] or 0) + 1 end
                activeJobs[job.x] = nil
            end)
        end
    end
end)

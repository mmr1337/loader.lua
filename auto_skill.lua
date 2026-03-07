
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local dtc = getgenv and getgenv().dtc or nil
newcclosure = newcclosure or function(f) return f end
setreadonly  = setreadonly  or function() end
getrawmetatable = getrawmetatable or getmetatable

local LocalPlayer   = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local GameClass     = PlayerScripts.Client.GameClass

local TowerClass = require(GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(GameClass:WaitForChild("EnemyClass"))

local Remotes                = ReplicatedStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = Remotes:WaitForChild("TowerUseAbilityRequest")
local TowerAttack            = Remotes:WaitForChild("TowerAttack")
local TowerChainAttack       = Remotes:WaitForChild("TowerChainAttack")

local Common         = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local TowerUtilities = require(Common:WaitForChild("TowerUtilities"))
local PathHandler    = require(Common:WaitForChild("PathHandler"))
local MapHandler     = require(Common:WaitForChild("MapHandler"))

local CONFIG = {
    CheckInterval        = 0.25,
    SpecialCheckInterval = 0.25,
    MobsterDelay         = 0.5,
    QueueMaxSize         = 5,

    CacheInterval        = 0.05,
}

local SETTINGS = {
    Directional = {
        ["Toxicnator"]        = true, ["Ghost"]             = true,
        ["Ice Breaker"]       = true, ["Artillery"]         = true,
        ["Golden Mine Layer"] = true, ["Flame Trooper"]     = true,
        ["John"]              = true, ["Slammer"]           = true,
    },
    SeparateLogic = {
        ["Commander"]      = true, ["EDJ"]            = true,
        ["Medic"]          = true, ["Mobster"]         = true,
        ["Golden Mobster"] = true, ["Relic"]           = true,
        ["Shield Tower"]   = true, ["Combat Medic"]    = true,
    },
    SkipGeneralLogic = {
        ["Helicopter"]       = true, ["Cryo Helicopter"] = true,
        ["Combat Drone"]     = true, ["Machine Gunner"]  = true,
        ["Refractor"]        = true, ["Psycho Slayer"]   = true,
    },
    SkipAirTargeting = {
        ["Ice Breaker"]    = true, ["John"]           = true,
        ["Slammer"]        = true, ["Mobster"]        = true,
        ["Golden Mobster"] = true, ["Toxicnator"]     = true,
    },
    SkipMedicBuff = {
        ["Refractor"]        = true,
        ["Mine Layer"]       = true,
        ["Golden Mine Layer"]= true,
    },
}

local Initialized = false

local FilteredEnemies    = {}
local EnemyProgressCache = {}
local FilteredTowers     = {}
local TowerPositionCache = {}
local TowerBuffCache     = {}
local TowerRangeCache    = {}
local AbilityListCache   = {}
local AbilityUsableCache = {}

local ActiveEnemies  = {}

local NextGeneralCheck      = 0
local NextSpecialCheck      = 0
local PathEnds              = {}
local MedicPendingTargets   = {}
local MEDIC_TIMEOUT         = 0.5
local MobsterLastUsed       = {}
local MobsterPendingEnemies = {}
local MOBSTER_TIMEOUT       = 0.4

local SkillQueue     = {}
local SkillQueueHead = 1
local SkillQueueTail = 0

local SpecialRunning = false
local ShieldRunning  = false

local function setThreadIdentity(n)
    if setthreadidentity then setthreadidentity(n)
    elseif syn then syn.set_thread_identity(n) end
end

local function getDistanceSq(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return dx*dx + dz*dz
end

local function getTowerPos(tower)
    local c = tower.Character
    if not c then return nil end
    local p = c.PrimaryPart
    return p and p.Position or nil
end

local function getRange(tower)
    local h = tower.Hash
    local v = TowerRangeCache[h]
    if v then return v end
    v = tower:GetCurrentRange()
    TowerRangeCache[h] = v
    return v
end

local function getLevels(tower)
    local lh = tower.LevelHandler
    if not lh then return 0, 0 end
    return lh.Path1Level, lh.Path2Level
end

local function invalidateAbilityCache()
    table.clear(AbilityUsableCache)
end

local function buildAbilityList(hash, ah)
    local map  = ah.AbilityIndexToNameMap
    local abs  = ah.Abilities
    if not map or not abs then
        AbilityListCache[hash] = nil
        return
    end
    local t = {}
    for i = 1, 3 do
        local n = map[i]
        t[i] = n and abs[n] or nil
    end
    AbilityListCache[hash] = t
end

local function onTowerAdded(hash, tower)
    FilteredTowers[hash] = tower
    local cf = tower.CFrame
    if cf then TowerPositionCache[hash] = cf.Position end

    local ah = tower.AbilityHandler
    if ah then buildAbilityList(hash, ah) end

    local bh = tower.BuffHandler
    if bh then
        local stunned = bh:IsStunned()
        local kritz   = false
        for _, b in pairs(bh.ActiveBuffs or {}) do
            if b and b.Name and tostring(b.Name):match("^MedicKritz") then
                kritz = true; break
            end
        end
        TowerBuffCache[hash] = { Stunned = stunned, MedicKritz = kritz }
    end
end

local function onTowerRemoved(hash)
    FilteredTowers[hash]     = nil
    AbilityListCache[hash]   = nil
    TowerBuffCache[hash]     = nil
    TowerRangeCache[hash]    = nil
    TowerPositionCache[hash] = nil
end

local function onEnemyAdded(hash, enemy)
    if enemy.IsFakeEnemy then return end
    FilteredEnemies[hash] = enemy
    local mh = enemy.MovementHandler
    if mh then
        local pi = mh.PathIndex or 0
        EnemyProgressCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
    end
end

local function onEnemyRemoved(hash)
    FilteredEnemies[hash]    = nil
    EnemyProgressCache[hash] = nil
end

local function hookFunc(tbl, key, wrapper)
    local orig = rawget(tbl, key) or tbl[key]
    if not orig then return end

    if clonefunction and detour_function then
        local ok, cloned = pcall(clonefunction, orig)
        if ok and cloned then
            pcall(detour_function, orig, newcclosure(function(...)
                return wrapper(cloned, ...)
            end))
            return
        end
    end

    local mt = getrawmetatable and getrawmetatable(tbl)
    if mt and setreadonly then pcall(setreadonly, mt, false) end
    tbl[key] = newcclosure and newcclosure(function(...) return wrapper(orig, ...) end)
              or function(...) return wrapper(orig, ...) end
end

local function hookAbilityHandlerClass()

    local ahcPath = GameClass:FindFirstChild("TowerClass")
                    and GameClass.TowerClass:FindFirstChild("AbilityHandlerClass")

    local ahc = nil
    if ahcPath then
        local ok, m = pcall(require, ahcPath)
        if ok then ahc = m end
    end

    if not ahc then
        local ok, upvals = pcall(debug.getupvalues, TowerClass.New)
        if ok and upvals then
            for _, v in pairs(upvals) do
                if type(v) == "table" and rawget(v, "_GenerateAbilities") then
                    ahc = v; break
                end
            end
        end
    end

    if not ahc then

        return false
    end

    hookFunc(ahc, "_GenerateAbilities", function(orig, self, ...)
        orig(self, ...)
        local tower = self.Tower
        if tower and tower.Hash then
            buildAbilityList(tower.Hash, self)
            table.clear(AbilityUsableCache)
        end
    end)

    local ahcPath2 = GameClass:FindFirstChild("TowerClass")
                     and GameClass.TowerClass:FindFirstChild("AbilityHandlerClass")
                     and GameClass.TowerClass.AbilityHandlerClass:FindFirstChild("AbilityClass")
    local ac = nil
    if ahcPath2 then
        local ok, m = pcall(require, ahcPath2)
        if ok then ac = m end
    end
    if not ac then
        local ok, upvals = pcall(debug.getupvalues, ahc._GenerateAbilities)
        if ok and upvals then
            for _, v in pairs(upvals) do
                if type(v) == "table" and rawget(v, "BeginCooldown") and rawget(v, "CanUse") then
                    ac = v; break
                end
            end
        end
    end
    if ac then
        hookFunc(ac, "BeginCooldown", function(orig, ab, ...)
            orig(ab, ...)
            AbilityUsableCache[ab] = false
        end)
    end

    return true
end

local function hookTowerClass()

    hookFunc(TowerClass, "New", function(orig, ...)
        local tower = orig(...)
        if tower and tower.Hash then
            onTowerAdded(tower.Hash, tower)
        end
        return tower
    end)

    hookFunc(TowerClass, "Destroy", function(orig, tower, ...)
        local hash = tower and tower.Hash
        orig(tower, ...)
        if hash then onTowerRemoved(hash) end
    end)

    hookFunc(TowerClass, "ApplyBuffData", function(orig, tower, ...)
        orig(tower, ...)
        local hash = tower and tower.Hash
        if not hash then return end
        local bh = tower.BuffHandler
        if not bh then return end
        local stunned = bh:IsStunned()
        local kritz   = false
        for _, b in pairs(bh.ActiveBuffs) do
            if b and b.Name and tostring(b.Name):match("^MedicKritz") then
                kritz = true; break
            end
        end
        TowerBuffCache[hash]  = { Stunned = stunned, MedicKritz = kritz }
        TowerRangeCache[hash] = nil
    end)

    hookFunc(TowerClass, "RemoveBuffData", function(orig, tower, ...)
        orig(tower, ...)
        local hash = tower and tower.Hash
        if not hash then return end
        local bh = tower.BuffHandler
        if not bh then return end
        local stunned = bh:IsStunned()
        local kritz   = false
        for _, b in pairs(bh.ActiveBuffs) do
            if b and b.Name and tostring(b.Name):match("^MedicKritz") then
                kritz = true; break
            end
        end
        TowerBuffCache[hash]  = { Stunned = stunned, MedicKritz = kritz }
        TowerRangeCache[hash] = nil
    end)

    hookFunc(TowerClass, "SetPosition", function(orig, tower, pos, ...)
        orig(tower, pos, ...)
        local hash = tower and tower.Hash
        if hash and pos then
            TowerPositionCache[hash] = typeof(pos) == "Vector3" and pos or Vector3.new(pos.X, pos.Y, pos.Z)
        end
    end)

    hookFunc(TowerClass, "SetPositionForAirUnit", function(orig, tower, ...)
        orig(tower, ...)
        local hash = tower and tower.Hash
        if hash then
            local gp = tower.GoalPosition
            if gp then TowerPositionCache[hash] = gp end
        end
    end)

    hookFunc(TowerClass, "Upgrade", function(orig, tower, ...)
        local hash = tower and tower.Hash
        orig(tower, ...)
        if hash then
            TowerRangeCache[hash] = nil

            local ah = tower.AbilityHandler
            if ah then buildAbilityList(hash, ah) end
        end
    end)
end

local function hookEnemyClass()
    hookFunc(EnemyClass, "New", function(orig, ...)
        local enemy = orig(...)
        if enemy and enemy.Hash then
            onEnemyAdded(enemy.Hash, enemy)
        end
        return enemy
    end)

    hookFunc(EnemyClass, "Destroy", function(orig, enemy, ...)
        local hash = enemy and enemy.Hash
        orig(enemy, ...)
        if hash then onEnemyRemoved(hash) end
    end)
end

local function hookPathEnds()
    if type(PathHandler) ~= "table" then return end
    local ok, positions = pcall(function()
        return PathHandler.GetEndNodePositions and PathHandler.GetEndNodePositions()
    end)
    if ok and type(positions) == "table" then
        for i, pos in ipairs(positions) do
            PathEnds[i] = pos
        end
    end
end

local function populateExisting()

    local rawE = EnemyClass.GetEnemies()
    if rawE then
        for hash, enemy in pairs(rawE) do
            if enemy and not enemy.IsFakeEnemy and enemy.IsAlive then
                onEnemyAdded(hash, enemy)
            end
        end
    end

    local rawT = TowerClass.GetTowers()
    if rawT then
        for hash, tower in pairs(rawT) do
            if tower then
                onTowerAdded(hash, tower)
            end
        end
    end
end

local function snapshotEnemies()
    local arr, n = {}, 0
    for _, e in pairs(FilteredEnemies) do
        if e.IsAlive then n = n + 1; arr[n] = e end
    end
    return arr
end

local function isAbilityUsable(ab)
    if not ab then return false end
    local v = AbilityUsableCache[ab]
    if v ~= nil then return v end
    v = ab:CanUse()
    AbilityUsableCache[ab] = v
    return v
end

local function hasAnyUsableAbility(al)
    if not al then return false end
    for i = 1, 3 do
        if isAbilityUsable(al[i]) then return true end
    end
    return false
end

local function useAbility(ab)
    if not ab then return end
    AbilityUsableCache[ab] = false
    local ok = ab:Use()

    if not ok then
        AbilityUsableCache[ab] = nil
    end
end

local function enqueueSkill(hash, index, pos, targetHash)
    if SkillQueueTail - SkillQueueHead + 1 >= CONFIG.QueueMaxSize then return end

    local al = AbilityListCache[hash]
    local ab = al and al[index]
    if ab then
        if not ab:CanUse() then return end
        ab:BeginCooldown()
        AbilityUsableCache[ab] = false
    end
    SkillQueueTail = SkillQueueTail + 1
    SkillQueue[SkillQueueTail] = { hash = hash, index = index, pos = pos, targetHash = targetHash, ability = ab }
end

local function cacheMapPaths()
    if next(PathEnds) then return end
    hookPathEnds()
end

local EnemySnapshot     = {}
local EnemySnapshotSize = 0

local function buildEnemySnapshot(enemies)
    local n = 0
    for _, e in ipairs(enemies) do
        local ep = e:GetPosition()
        if not ep then continue end
        local ec = EnemyProgressCache[e.Hash]
        n = n + 1
        EnemySnapshot[n] = {
            pos    = ep,
            isAir  = e.IsAirUnit,
            hp     = e.HealthHandler and e.HealthHandler:GetMaxHealth() or 0,
            prg    = ec and ec.progress or 0,
            bounty = e.BountyDisplayHandler and e.BountyDisplayHandler.BountyCount or 0,
            enemy  = e,
        }
    end
    for i = n + 1, EnemySnapshotSize do EnemySnapshot[i] = nil end
    EnemySnapshotSize = n
end

local function getFarthestEnemy(pos, range, noAir)
    local rsq = range * range
    local best, bestPrg = nil, -1
    for i = 1, EnemySnapshotSize do
        local s = EnemySnapshot[i]
        if noAir and s.isAir then continue end
        if getDistanceSq(s.pos, pos) > rsq then continue end
        if s.prg > bestPrg then bestPrg = s.prg; best = s.pos end
    end
    return best
end

local function getStrongestEnemy(pos, range, noAir)
    local rsq = range * range
    local best, bestHP = nil, -1
    for i = 1, EnemySnapshotSize do
        local s = EnemySnapshot[i]
        if noAir and s.isAir then continue end
        if getDistanceSq(s.pos, pos) > rsq then continue end
        if s.hp > bestHP then bestHP = s.hp; best = s.pos end
    end
    return best
end

local function getRelicTarget()
    local best, bestPrg = nil, -1
    for i = 1, EnemySnapshotSize do
        local s = EnemySnapshot[i]
        if s.isAir then continue end
        if s.prg > bestPrg then bestPrg = s.prg; best = s.pos end
    end
    return best
end

local function getDPS(tower)
    if not tower.LevelHandler then return 0 end
    local levelStats = tower.LevelHandler:GetLevelStats()
    local buffStats  = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or nil
    local result     = TowerUtilities.CalculateDPS(levelStats, buffStats)
    return typeof(result) == "number" and result or 0
end

local function isBuffedByMedic(tower)
    local cached = TowerBuffCache[tower.Hash]
    if cached then return cached.MedicKritz end
    if not tower.BuffHandler then return false end
    for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
        if buff and buff.Name and tostring(buff.Name):match("^MedicKritz") then return true end
    end
    return false
end

local function getBestMedicTarget(medicTower, medicHash)
    local medicPos = getTowerPos(medicTower)
    if not medicPos then return nil end
    local medicRangeSq = getRange(medicTower) ^ 2
    local bestHash, bestDPS = nil, -1
    for hash, tower in pairs(FilteredTowers) do
        if hash == medicHash or not tower.IsAlive then continue end
        if SETTINGS.SkipMedicBuff[tower.Type or ""] then continue end
        if isBuffedByMedic(tower) then continue end
        local tPos = getTowerPos(tower)
        if not tPos then continue end
        if getDistanceSq(tPos, medicPos) > medicRangeSq then continue end
        local dps = getDPS(tower)
        if dps > bestDPS then bestDPS = dps; bestHash = hash end
    end
    return bestHash
end

local function anyTowerNeedsHeal(medicHash, pos, rsq)
    for h, t in pairs(FilteredTowers) do
        if h == medicHash or not t.IsAlive then continue end
        if t.v10 and t.v10.NoHeal then continue end
        if pos then
            local tp = getTowerPos(t)
            if not tp or getDistanceSq(tp, pos) > rsq then continue end
        end
        local hh = t.HealthHandler
        if not hh then continue end
        if hh:GetHealth() < hh:GetMaxHealth() then return true end
    end
    return false
end

local function getBestCombatMedicTarget(hash)
    local best, bestDPS = nil, -1
    for h, t in pairs(FilteredTowers) do
        if h == hash or not t.IsAlive then continue end
        if t.v10 and t.v10.NoHeal then continue end
        local tp = getTowerPos(t)
        if not tp then continue end
        local hh = t.HealthHandler
        if not hh then continue end
        local dps = getDPS(t)
        if dps > bestDPS then bestDPS = dps; best = tp end
    end
    return best
end

local function getMobsterTarget(tower)
    local pos = getTowerPos(tower)
    if not pos then return nil end
    local rsq = getRange(tower)^2
    local now = tick()
    for id, data in pairs(MobsterPendingEnemies) do
        local e = data.enemy
        local hb = e and e.BountyDisplayHandler and e.BountyDisplayHandler.BountyCount > 0
        if hb or now - data.time > MOBSTER_TIMEOUT or not (e and e.IsAlive) then
            MobsterPendingEnemies[id] = nil
        end
    end
    local bE, bHP, bPrg = nil, -1, -1
    for i = 1, EnemySnapshotSize do
        local s = EnemySnapshot[i]
        if s.isAir then continue end
        if s.bounty > 0 then continue end
        local id = tostring(s.enemy)
        if MobsterPendingEnemies[id] then continue end
        if getDistanceSq(s.pos, pos) > rsq then continue end
        if s.hp > bHP or (s.hp == bHP and s.prg > bPrg) then
            bHP = s.hp; bPrg = s.prg; bE = s.enemy
        end
    end
    return bE
end

local function processCombatMedic(tower, hash, now)
    local al = AbilityListCache[hash]
    if not hasAnyUsableAbility(al) then return end
    local pos = getTowerPos(tower)
    if not pos then return end
    local rsq = getRange(tower)^2
    if MedicPendingTargets[hash] then
        local pd = MedicPendingTargets[hash]
        local timedOut = now - pd.time > MEDIC_TIMEOUT
        if timedOut then
            MedicPendingTargets[hash] = nil
        else
            return
        end
    end
    if not anyTowerNeedsHeal(hash, pos, rsq) then return end
    for i = 1, 3 do
        local ab = al[i]
        if isAbilityUsable(ab) then
            local tp = getBestCombatMedicTarget(hash)
            if tp then
                enqueueSkill(hash, i, tp, nil)
                MedicPendingTargets[hash] = { time = now }
                break
            end
        end
    end
end

local function processMobster(tower, hash, now)
    local al = AbilityListCache[hash]
    if not hasAnyUsableAbility(al) then return end
    if MobsterLastUsed[hash] and now - MobsterLastUsed[hash] < CONFIG.MobsterDelay then return end
    for i = 1, 3 do
        local ab = al[i]
        if isAbilityUsable(ab) then
            local e = getMobsterTarget(tower)
            if e then
                local ep = e:GetPosition()
                if ep then
                    enqueueSkill(hash, i, ep, nil)
                    MobsterPendingEnemies[tostring(e)] = { enemy=e, time=now }
                    MobsterLastUsed[hash] = now
                    break
                end
            end
        end
    end
end

local function processRelic(tower, hash)
    local al = AbilityListCache[hash]
    if not hasAnyUsableAbility(al) then return end
    local p1 = getLevels(tower)
    if p1 < 5 then return end
    for i = 1, 3 do
        local ab = al[i]
        if isAbilityUsable(ab) then
            local tp = getRelicTarget()
            if tp then enqueueSkill(hash, i, tp, nil); break end
        end
    end
end

local function processAttack(attackHash, now)
    local atTower = FilteredTowers[attackHash]
    if not atTower then return end
    local atPos = getTowerPos(atTower)
    if not atPos then return end

    for hash, tower in pairs(FilteredTowers) do
        if hash == attackHash or not tower.IsAlive then continue end
        local tp = getTowerPos(tower)
        if not tp then continue end
        if getDistanceSq(tp, atPos) > getRange(tower)^2 then continue end
        local al = AbilityListCache[hash]
        if not al then continue end
        local tType = tower.Type

        if tType == "EDJ" or tType == "Commander" then
            if isAbilityUsable(al[1]) then useAbility(al[1]) end

        elseif tType == "Medic" then
            local _, p2 = getLevels(tower)
            if p2 < 4 then continue end
            if MedicPendingTargets[hash] then
                local pd = MedicPendingTargets[hash]
                local targetTower = pd.tower
                local timedOut = now - pd.time > MEDIC_TIMEOUT
                local buffed = targetTower and targetTower.IsAlive and isBuffedByMedic(targetTower)
                if buffed or timedOut then
                    MedicPendingTargets[hash] = nil
                else
                    continue
                end
            end
            for i = 1, 3 do
                local ab = al[i]
                if isAbilityUsable(ab) then
                    local th = getBestMedicTarget(tower, hash)
                    if th then
                        local targetTower = FilteredTowers[th]
                        enqueueSkill(hash, i, nil, th)
                        MedicPendingTargets[hash] = { tower = targetTower, time = now }
                        break
                    end
                end
            end
        end
    end
end

TowerAttack.OnClientEvent:Connect(newcclosure(function(data)
    if not Initialized or not next(FilteredTowers) then return end
    local now = tick()
    task.spawn(function()
        setThreadIdentity(2)
        for _, d in ipairs(data) do
            if d and d.X then processAttack(d.X, now) end
        end
    end)
end))

TowerChainAttack.OnClientEvent:Connect(newcclosure(function(data)
    if not Initialized or not next(FilteredTowers) then return end
    local now = tick()
    task.spawn(function()
        setThreadIdentity(2)
        for _, d in ipairs(data) do
            if d and d[1] then processAttack(d[1], now) end
        end
    end)
end))

local function makeShieldCoro()
    return coroutine.create(function()
        while true do
            setThreadIdentity(2)
            invalidateAbilityCache()
            for hash, tower in pairs(FilteredTowers) do
                if not tower.IsAlive then continue end
                if tower.Type ~= "Shield Tower" then continue end
                local p1 = getLevels(tower)
                if p1 < 4 or not tower.AbilityHandler then continue end
                local al = AbilityListCache[hash]
                if not hasAnyUsableAbility(al) then continue end
                local pos = getTowerPos(tower)
                if not pos then continue end
                local rsq  = getRange(tower)^2
                local fire = false
                for oh, other in pairs(FilteredTowers) do
                    if not other.IsAlive then continue end
                    local bc = TowerBuffCache[oh]
                    if bc and bc.Stunned then
                        local op = getTowerPos(other)
                        if op and getDistanceSq(op, pos) <= rsq then fire = true; break end
                    end
                end
                if fire then
                    for i = 1, 3 do
                        if isAbilityUsable(al[i]) then
                            enqueueSkill(hash, i, nil, nil)
                            break
                        end
                    end
                end
            end
            coroutine.yield()
        end
    end)
end

local shieldCoro = makeShieldCoro()

RunService.RenderStepped:Connect(newcclosure(function()
    if not Initialized then return end
    local now = tick()
    invalidateAbilityCache()

    if not next(FilteredTowers) then return end

    if coroutine.status(shieldCoro) == "suspended" then
        local ok, err = coroutine.resume(shieldCoro)
        if not ok then shieldCoro = makeShieldCoro() end
    end

    if now < NextSpecialCheck then return end
    NextSpecialCheck = now + CONFIG.SpecialCheckInterval
    if SpecialRunning then return end

    SpecialRunning = true
    task.spawn(function()
        setThreadIdentity(2)
        for hash, tower in pairs(FilteredTowers) do
            if not tower.IsAlive then continue end
            local tType = tower.Type
            if not SETTINGS.SeparateLogic[tType] then continue end
            if tType == "Commander" or tType == "EDJ"
            or tType == "Medic"     or tType == "Shield Tower" then
                continue
            end
            if not hasAnyUsableAbility(AbilityListCache[hash]) then continue end
            if tType == "Combat Medic" then
                processCombatMedic(tower, hash, now)
            elseif tType == "Mobster" or tType == "Golden Mobster" then
                local _, p2 = getLevels(tower)
                if p2 >= 3 and p2 <= 5 then processMobster(tower, hash, now) end
            elseif tType == "Relic" then
                processRelic(tower, hash)
            end
        end
        SpecialRunning = false
    end)
end))

RunService.Heartbeat:Connect(newcclosure(function()
    if not Initialized then return end
    local now = tick()
    invalidateAbilityCache()

    if not next(FilteredTowers) then return end
    if now < NextGeneralCheck then return end
    NextGeneralCheck = now + CONFIG.CheckInterval

    cacheMapPaths()
    buildEnemySnapshot(ActiveEnemies)

    for hash, tower in pairs(FilteredTowers) do
        if not tower.IsAlive then continue end
        local tType = tower.Type
        if SETTINGS.SeparateLogic[tType] or SETTINGS.SkipGeneralLogic[tType] then continue end

        local al = AbilityListCache[hash]
        if not hasAnyUsableAbility(al) then continue end

        local p1    = getLevels(tower)
        local pos   = getTowerPos(tower)
        if not pos then continue end
        local range  = getRange(tower)
        local noAir  = SETTINGS.SkipAirTargeting[tType]

        for idx = 1, 3 do
            local ab = al[idx]
            if not isAbilityUsable(ab) then continue end

            local tPos, allow = nil, true

            if tType == "Jet Trooper" then
                allow = (idx == 2)

            elseif tType == "Toxicnator" then
                tPos  = getStrongestEnemy(pos, range, noAir)
                allow = tPos ~= nil

            else
                local cr = range
                if tType == "Flame Trooper" then cr = 9.5 end
                if tType == "Ice Breaker" and idx == 2 then cr = 8 end
                if tType == "John" and p1 < 5 then cr = 4.5 end

                local isDirect = SETTINGS.Directional[tType]
                local needPos  = isDirect == true
                if ab.IsManualAimAtGround or ab.IsManualAimAtPath then needPos = true end

                if needPos then
                    tPos  = getFarthestEnemy(pos, cr, noAir)
                    allow = tPos ~= nil
                elseif not isDirect then
                    local rsq = cr * cr
                    local has = false
                    for i = 1, EnemySnapshotSize do
                        local s = EnemySnapshot[i]
                        if noAir and s.isAir then continue end
                        if getDistanceSq(s.pos, pos) <= rsq then has = true; break end
                    end
                    allow = has
                end
            end

            if allow then
                if tPos then enqueueSkill(hash, idx, tPos, nil)
                else useAbility(ab) end
            end
        end
    end
end))

task.spawn(function()
    setThreadIdentity(2)

    repeat task.wait(0.1) until EnemyClass.GetEnemies() and TowerClass.GetTowers()

    populateExisting()

    hookTowerClass()
    hookEnemyClass()
    hookAbilityHandlerClass()

    ActiveEnemies = snapshotEnemies()

    Initialized = true

    local progressEvent = dtc and dtc.CustomEvent and dtc.CustomEvent.new()
    if progressEvent then
        progressEvent:Connect(newcclosure(function(hash, pi, pct)
            EnemyProgressCache[hash] = { progress = pi + pct, pathIndex = pi }
        end))
    end

    local hookedMetatables = {}

    local function hookMovementHandler(hash, mh)
        if not mh then return end
        local mt = getrawmetatable(mh)
        if not mt then return end
        if hookedMetatables[mt] then
            local pi = mh.PathIndex or 0
            EnemyProgressCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
            return
        end
        hookedMetatables[mt] = true
        if setreadonly then setreadonly(mt, false) end
        local origNI = rawget(mt, "__newindex")
        mt.__newindex = newcclosure(function(t, k, v)
            if origNI then origNI(t, k, v) else rawset(t, k, v) end
            if k == "PathIndex" or k == "PathPercentage" then
                local pi  = k == "PathIndex"       and v or (rawget(t, "PathIndex")       or 0)
                local pct = k == "PathPercentage"  and v or (rawget(t, "PathPercentage")  or 0)
                if progressEvent then progressEvent:Fire(hash, pi, pct) end
            end
        end)
        local pi = mh.PathIndex or 0
        EnemyProgressCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
    end

    for hash, enemy in pairs(FilteredEnemies) do
        hookMovementHandler(hash, enemy.MovementHandler)
    end

    local _origOnEnemyAdded = onEnemyAdded
    onEnemyAdded = newcclosure(function(hash, enemy)
        _origOnEnemyAdded(hash, enemy)
        hookMovementHandler(hash, enemy.MovementHandler)
    end)

    while true do
        task.wait(CONFIG.CacheInterval)
        for k, e in pairs(FilteredEnemies) do
            if not e.IsAlive then onEnemyRemoved(k) end
        end
        ActiveEnemies = snapshotEnemies()
    end
end)

task.spawn(function()
    setThreadIdentity(2)
    while true do
        if SkillQueueHead <= SkillQueueTail then
            local job = SkillQueue[SkillQueueHead]
            SkillQueue[SkillQueueHead] = nil
            SkillQueueHead = SkillQueueHead + 1

            local ok, serverCooldown = TowerUseAbilityRequest:InvokeServer(job.hash, job.index, job.pos, job.targetHash)

            local ab = job.ability
            if ab then
                if ok and serverCooldown then
                    ab.CooldownRemaining = serverCooldown
                elseif not ok then

                    ab.CooldownRemaining = 0
                    AbilityUsableCache[ab] = nil
                end
            end
        end
        task.wait(0.03)
    end
end)

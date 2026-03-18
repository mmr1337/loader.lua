local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local Client = PlayerScripts:WaitForChild("Client")
local GameClass = Client:WaitForChild("GameClass")

local TowerClass = require(GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(GameClass:WaitForChild("EnemyClass"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = Remotes:WaitForChild("TowerUseAbilityRequest")
local TowerAttack = Remotes:WaitForChild("TowerAttack")
local TowerChainAttack = Remotes:WaitForChild("TowerChainAttack")

local Common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local TowerUtilities = require(Common:WaitForChild("TowerUtilities"))
local PathHandler = require(Common:WaitForChild("PathHandler"))

local function setThreadIdentity(identity)
    if setthreadidentity then
        setthreadidentity(identity)
    elseif syn and syn.set_thread_identity then
        syn.set_thread_identity(identity)
    end
end

local function safeInvokeAbility(hash, index, pos, targetHash)
    local ok, result = pcall(function()
        return TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
    end)
    return ok, result
end

local function safeThreadInvoke(hash, index, pos, targetHash)
    task.spawn(function()
        setThreadIdentity(2)
        safeInvokeAbility(hash, index, pos, targetHash)
    end)
end

local directionalTowerTypes = {
    ["Commander"] = { onlyAbilityIndex = 3 },
    ["Toxicnator"] = true,
    ["Ghost"] = true,
    ["Ice Breaker"] = true,
    ["Mobster"] = true,
    ["Golden Mobster"] = true,
    ["Artillery"] = true,
    ["Golden Mine Layer"] = true,
    ["Flame Trooper"] = true,
    ["Slammer"] = true,
}

local skipTowerTypes = {
    ["Helicopter"] = true,
    ["Cryo Helicopter"] = true,
    ["Combat Drone"] = true,
    ["Machine Gunner"] = true,
}

local skipAirTowers = {
    ["Ice Breaker"] = true,
    ["John"] = true,
    ["Slammer"] = true,
    ["Mobster"] = true,
    ["Golden Mobster"] = true
}

local skipMedicBuffTowers = {
    ["Refractor"] = true
}

local towerCooldownState = {}
local mobsterUsedEnemies = {}
local mobsterLastUsedTime = {}
local mobsterDelay = 0.15
local medicLastUsedTime = {}
local medicDelay = 0.5

local function getDistance2D(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function getTowerPos(tower)
    if not tower then
        return nil
    end
    local ok, result = pcall(function()
        return tower:GetPosition()
    end)
    return ok and result or nil
end

local function getRange(tower)
    if not tower then
        return 0
    end
    local ok, result = pcall(function()
        return tower:GetCurrentRange()
    end)
    return ok and typeof(result) == "number" and result or 0
end

local function getUpgradeLevels(tower)
    local p1, p2 = 0, 0
    if not tower or not tower.LevelHandler then
        return p1, p2
    end
    pcall(function()
        p1 = tower.LevelHandler:GetLevelOnPath(1) or 0
    end)
    pcall(function()
        p2 = tower.LevelHandler:GetLevelOnPath(2) or 0
    end)
    return p1, p2
end

local function getTowerAbilities(tower)
    if not tower or not tower.AbilityHandler then
        return nil, nil
    end

    local ah = tower.AbilityHandler
    local map = ah.AbilityIndexToNameMap
    local abs = ah.Abilities

    if not map or not abs then
        return nil, nil
    end

    local abilities = table.create(3)
    local configs = table.create(3)
    local hasAny = false

    for i = 1, 3 do
        local n = map[i]
        local ab = n and abs[n] or nil
        abilities[i] = ab
        configs[i] = ab and ab.Config or nil
        if ab then
            hasAny = true
        end
    end

    if not hasAny then
        return nil, nil
    end

    return abilities, configs
end

local function getAbilityByIndex(tower, index)
    local abilities = getTowerAbilities(tower)
    if type(abilities) == "table" then
        return abilities[index]
    end
    return nil
end

local function canUseAbility(tower, index)
    local ab = getAbilityByIndex(tower, index)
    if not ab then
        return false, nil
    end

    local ok, usable = pcall(function()
        return ab:CanUse()
    end)

    if not ok then
        return false, ab
    end

    return usable == true, ab
end

local function updateCooldownState(hash, index, ab)
    towerCooldownState[hash] = towerCooldownState[hash] or {}
    local prev = towerCooldownState[hash][index]

    local cd = 0
    pcall(function()
        cd = ab and (ab.CooldownRemaining or 0) or 0
    end)

    towerCooldownState[hash][index] = {
        cooldown = cd,
        stamp = tick()
    }

    return prev, cd
end

local function isReadyNow(tower, hash, index)
    local usable, ab = canUseAbility(tower, index)
    if not ab then
        return false, nil
    end

    updateCooldownState(hash, index, ab)
    if not usable then
        return false, ab
    end

    local cd = 0
    pcall(function()
        cd = ab.CooldownRemaining or 0
    end)

    if cd > 0.05 then
        return false, ab
    end

    return true, ab
end

local function getDPS(tower)
    if not tower or not tower.LevelHandler then
        return 0
    end

    local ok, result = pcall(function()
        local levelStats = tower.LevelHandler:GetLevelStats()
        local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or nil
        return TowerUtilities.CalculateDPS(levelStats, buffStats)
    end)

    return ok and typeof(result) == "number" and result or 0
end

local function isBuffedByMedic(tower)
    if not tower or not tower.BuffHandler or not tower.BuffHandler.ActiveBuffs then
        return false
    end
    for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
        local buffName = tostring(buff.Name or "")
        if buffName:match("^MedicKritz") then
            return true
        end
    end
    return false
end

local function canReceiveBuff(tower)
    if not tower or tower.NoBuffs then
        return false
    end
    if skipMedicBuffTowers[tower.Type] then
        return false
    end
    return true
end

local function getEnemies()
    local result = {}
    for _, e in pairs(EnemyClass.GetEnemies()) do
        if e and e.IsAlive and not e.IsFakeEnemy then
            table.insert(result, e)
        end
    end
    return result
end

local function getEnemyPathPercentage(enemy)
    if not enemy or not enemy.MovementHandler then
        return 0
    end

    local mh = enemy.MovementHandler
    local pathPercent = mh.PathPercentage or 0

    if mh.ReverseDirection then
        pathPercent = 1 - pathPercent
    end

    return (mh.PathIndex or 0) + pathPercent
end

local function getFarthestEnemyNoRange(options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then
            continue
        end
        if excludeAir and enemy.IsAirUnit then
            continue
        end

        table.insert(candidates, {
            enemy = enemy,
            pathPercent = getEnemyPathPercentage(enemy)
        })
    end

    if #candidates == 0 then
        return nil
    end

    table.sort(candidates, function(a, b)
        return a.pathPercent > b.pathPercent
    end)

    return candidates[1].enemy:GetPosition()
end

local function getFarthestEnemyInRangeByPath(pos, range, options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then
            continue
        end
        if excludeAir and enemy.IsAirUnit then
            continue
        end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) <= range then
            table.insert(candidates, {
                enemy = enemy,
                position = ePos,
                pathPercent = getEnemyPathPercentage(enemy)
            })
        end
    end

    if #candidates == 0 then
        return nil
    end

    table.sort(candidates, function(a, b)
        return a.pathPercent > b.pathPercent
    end)

    return candidates[1].position
end

local function tacticalTarget(pos, range, options)
    options = options or {}
    local mode = options.mode or "nearest"
    local excludeAir = options.excludeAir or false
    local usedEnemies = options.usedEnemies
    local markUsed = options.markUsed or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then
            continue
        end
        if excludeAir and enemy.IsAirUnit then
            continue
        end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) > range then
            continue
        end

        if usedEnemies then
            local id = tostring(enemy)
            if usedEnemies[id] then
                continue
            end
        end

        table.insert(candidates, enemy)
    end

    if #candidates == 0 then
        return nil
    end

    local chosen = nil
    if mode == "maxhp" then
        local maxHP = -1
        for _, enemy in ipairs(candidates) do
            if enemy.HealthHandler then
                local hp = enemy.HealthHandler:GetMaxHealth()
                if hp > maxHP then
                    maxHP = hp
                    chosen = enemy
                end
            end
        end
    elseif mode == "currenthp" then
        local maxCurrentHP = -1
        for _, enemy in ipairs(candidates) do
            if enemy.HealthHandler then
                local currentHP = enemy.HealthHandler:GetHealth()
                if currentHP > maxCurrentHP then
                    maxCurrentHP = currentHP
                    chosen = enemy
                end
            end
        end
    elseif mode == "random_weighted" then
        table.sort(candidates, function(a, b)
            local hpA = a.HealthHandler and a.HealthHandler:GetMaxHealth() or 0
            local hpB = b.HealthHandler and b.HealthHandler:GetMaxHealth() or 0
            return hpA > hpB
        end)
        if math.random(1, 10) <= 3 then
            chosen = candidates[1]
        else
            chosen = candidates[math.random(1, #candidates)]
        end
    else
        chosen = candidates[1]
    end

    if chosen and markUsed and usedEnemies then
        usedEnemies[tostring(chosen)] = true
    end

    return chosen and chosen:GetPosition() or nil
end

local function hasSplashDamage(cfg)
    if not cfg then
        return false, 0
    end
    if cfg.ProjectileHitData then
        local hitData = cfg.ProjectileHitData
        if hitData.IsSplash and hitData.SplashRadius and hitData.SplashRadius > 0 then
            return true, hitData.SplashRadius
        end
    end
    if cfg.HasRadiusEffect and cfg.EffectRadius and cfg.EffectRadius > 0 then
        return true, cfg.EffectRadius
    end
    return false, 0
end

local function getAbilityRange(ab, cfg, defaultRange)
    if cfg then
        if cfg.ManualAimInfiniteRange == true then
            return math.huge
        end
        if cfg.ManualAimCustomRange and cfg.ManualAimCustomRange > 0 then
            return cfg.ManualAimCustomRange
        end
        if cfg.Range and cfg.Range > 0 then
            return cfg.Range
        end
        if cfg.CustomQueryData and cfg.CustomQueryData.Range then
            return cfg.CustomQueryData.Range
        end
    end
    if ab then
        if ab.ManualAimInfiniteRange == true then
            return math.huge
        end
        if ab.ManualAimCustomRange and ab.ManualAimCustomRange > 0 then
            return ab.ManualAimCustomRange
        end
    end
    return defaultRange
end

local function requiresManualAiming(ab, cfg)
    if cfg then
        if cfg.IsManualAimAtGround == true or cfg.IsManualAimAtPath == true then
            return true
        end
    end
    if ab then
        return ab.IsManualAimAtGround == true or ab.IsManualAimAtPath == true
    end
    return false
end

local function getEnhancedTarget(pos, towerRange, towerType, ab, cfg)
    local options = { excludeAir = skipAirTowers[towerType] or false }
    local effectiveRange = getAbilityRange(ab, cfg, towerRange)

    local isSplash = false
    if cfg then
        isSplash = hasSplashDamage(cfg)
    end
    local isManualAim = requiresManualAiming(ab, cfg)

    if isSplash or isManualAim then
        return getFarthestEnemyInRangeByPath(pos, effectiveRange, options)
    end

    return getFarthestEnemyInRangeByPath(pos, effectiveRange, options)
end

local function getMobsterTarget(tower, hash, path)
    local pos = getTowerPos(tower)
    local range = getRange(tower)
    if not pos then
        return nil
    end

    mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}

    if path == 2 then
        local candidates = {}
        local maxHP = -1

        for _, enemy in ipairs(getEnemies()) do
            if not enemy.GetPosition then
                continue
            end
            if enemy.IsAirUnit then
                continue
            end

            local ePos = enemy:GetPosition()
            if getDistance2D(ePos, pos) > range then
                continue
            end

            local id = tostring(enemy)
            if mobsterUsedEnemies[hash][id] then
                continue
            end

            local hp = enemy.HealthHandler and enemy.HealthHandler:GetMaxHealth() or 0

            if hp > maxHP then
                maxHP = hp
                candidates = {{enemy = enemy, hp = hp, pathPercent = getEnemyPathPercentage(enemy)}}
            elseif hp == maxHP then
                table.insert(candidates, {enemy = enemy, hp = hp, pathPercent = getEnemyPathPercentage(enemy)})
            end
        end

        if #candidates == 0 then
            return nil
        end

        if #candidates > 1 then
            table.sort(candidates, function(a, b)
                return a.pathPercent > b.pathPercent
            end)
        end

        local chosen = candidates[1].enemy
        mobsterUsedEnemies[hash][tostring(chosen)] = true
        return chosen:GetPosition()
    else
        for _, enemy in ipairs(getEnemies()) do
            if not enemy.GetPosition then
                continue
            end
            if enemy.IsAirUnit then
                continue
            end

            local ePos = enemy:GetPosition()
            if getDistance2D(ePos, pos) <= range then
                return ePos
            end
        end
        return nil
    end
end

local function getCommanderTarget()
    local candidates = {}
    for _, e in ipairs(getEnemies()) do
        if not e.IsAirUnit then
            table.insert(candidates, e)
        end
    end

    if #candidates == 0 then
        return nil
    end

    table.sort(candidates, function(a, b)
        local hpA = a.HealthHandler and a.HealthHandler:GetMaxHealth() or 0
        local hpB = b.HealthHandler and b.HealthHandler:GetMaxHealth() or 0
        return hpA > hpB
    end)

    local chosen
    if math.random(1, 10) <= 3 then
        chosen = candidates[1]
    else
        chosen = candidates[math.random(1, #candidates)]
    end

    return chosen and chosen:GetPosition() or nil
end

local function getBestMedicTarget(medicTower, ownedTowers)
    local medicPos = getTowerPos(medicTower)
    local medicRange = getRange(medicTower)
    if not medicPos then
        return nil
    end

    local bestHash, bestDPS = nil, -1

    for hash, tower in pairs(ownedTowers) do
        if tower == medicTower then
            continue
        end
        if canReceiveBuff(tower) and not isBuffedByMedic(tower) then
            local towerPos = getTowerPos(tower)
            if towerPos and getDistance2D(towerPos, medicPos) <= medicRange then
                local dps = getDPS(tower)
                if dps > bestDPS then
                    bestDPS = dps
                    bestHash = hash
                end
            end
        end
    end
    return bestHash
end

local function cleanupDeadEnemiesFromCache()
    for hash, enemies in pairs(mobsterUsedEnemies) do
        for enemyId, _ in pairs(enemies) do
            for _, e in pairs(EnemyClass.GetEnemies()) do
                if tostring(e) == enemyId and not e:Alive() then
                    enemies[enemyId] = nil
                    break
                end
            end
        end
    end
end

local function processReactiveTowerSkills(attackData)
    local ownedTowers = TowerClass.GetTowers() or {}

    for _, data in ipairs(attackData) do
        local attackingTowerHash = data.X
        local attackingTower = ownedTowers[attackingTowerHash]
        if not attackingTower then
            continue
        end

        task.spawn(function()
            setThreadIdentity(2)

            for hash, tower in pairs(ownedTowers) do
                if hash == attackingTowerHash then
                    continue
                end
                if not tower or not tower.AbilityHandler then
                    continue
                end

                local towerPos = getTowerPos(tower)
                local attackingPos = getTowerPos(attackingTower)
                if not towerPos or not attackingPos then
                    continue
                end

                local distance = getDistance2D(towerPos, attackingPos)
                local towerRange = getRange(tower)

                if distance <= towerRange then
                    if tower.Type == "EDJ" then
                        local ready = isReadyNow(tower, hash, 1)
                        if ready then
                            safeThreadInvoke(hash, 1, nil, nil)
                        end
                    elseif tower.Type == "Commander" then
                        local only = 3
                        local ready = isReadyNow(tower, hash, only)
                        if ready then
                            local pos = getCommanderTarget()
                            if pos then
                                safeThreadInvoke(hash, only, pos, nil)
                            end
                        end
                    elseif tower.Type == "Medic" then
                        local _, p2 = getUpgradeLevels(tower)
                        if p2 >= 4 then
                            local now = tick()
                            if not medicLastUsedTime[hash] or now - medicLastUsedTime[hash] >= medicDelay then
                                local targetHash = getBestMedicTarget(tower, ownedTowers)
                                if targetHash then
                                    for index = 1, 3 do
                                        local ready = isReadyNow(tower, hash, index)
                                        if ready then
                                            safeThreadInvoke(hash, index, nil, targetHash)
                                            medicLastUsedTime[hash] = now
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end

TowerAttack.OnClientEvent:Connect(processReactiveTowerSkills)

if TowerChainAttack then
    TowerChainAttack.OnClientEvent:Connect(function(data)
        local converted = {}
        for _, v in ipairs(data) do
            if v and v[1] then
                table.insert(converted, { X = v[1] })
            end
        end
        processReactiveTowerSkills(converted)
    end)
end

local skillsThisFrame = 0
local MAX_SKILLS_PER_FRAME = 8

RunService.Heartbeat:Connect(function()
    if not Initialized then
        return
    end

    skillsThisFrame = 0
    cleanupDeadEnemiesFromCache()

    local ownedTowers = TowerClass.GetTowers() or {}
    local now = tick()

    for hash, tower in pairs(ownedTowers) do
        if skillsThisFrame >= MAX_SKILLS_PER_FRAME then
            break
        end

        if not tower or not tower.AbilityHandler or not tower.IsAlive then
            continue
        end

        if skipTowerTypes[tower.Type] then
            continue
        end

        local p1, p2 = getUpgradeLevels(tower)
        local pos = getTowerPos(tower)
        local range = getRange(tower)
        if not pos then
            continue
        end

        local abilities, configs = getTowerAbilities(tower)
        if not abilities then
            continue
        end

        for index = 1, 3 do
            if skillsThisFrame >= MAX_SKILLS_PER_FRAME then
                break
            end

            local ab = abilities[index]
            local cfg = configs and configs[index] or nil
            if not ab then
                continue
            end

            local ready = isReadyNow(tower, hash, index)
            if not ready then
                continue
            end

            local targetPos = nil
            local targetHash = nil
            local allowUse = true

            if tower.Type == "Jet Trooper" then
                if index ~= 2 then
                    allowUse = false
                end
            end

            if tower.Type == "Ghost" then
                if p2 > 2 then
                    allowUse = false
                else
                    targetPos = getFarthestEnemyNoRange({ excludeAir = false })
                end
            elseif tower.Type == "Toxicnator" then
                targetPos = tacticalTarget(pos, range, {
                    mode = "maxhp",
                    excludeAir = false
                })
                allowUse = targetPos ~= nil
            elseif tower.Type == "Flame Trooper" then
                targetPos = getEnhancedTarget(pos, 9.5, tower.Type, ab, cfg)
                allowUse = targetPos ~= nil
            elseif tower.Type == "Ice Breaker" then
                local customRange = index == 2 and 8 or range
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ab, cfg)
                allowUse = targetPos ~= nil
            elseif tower.Type == "Slammer" then
                targetPos = getEnhancedTarget(pos, range, tower.Type, ab, cfg)
                allowUse = targetPos ~= nil
            elseif tower.Type == "John" then
                local customRange = p1 >= 5 and range or 4.5
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ab, cfg)
                allowUse = targetPos ~= nil
            elseif tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                if p2 >= 3 and p2 <= 5 then
                    if mobsterLastUsedTime[hash] and now - mobsterLastUsedTime[hash] < mobsterDelay then
                        allowUse = false
                    else
                        targetPos = getMobsterTarget(tower, hash, 2)
                        allowUse = targetPos ~= nil
                    end
                elseif p1 >= 4 and p1 <= 5 then
                    targetPos = getMobsterTarget(tower, hash, 1)
                    allowUse = targetPos ~= nil
                else
                    allowUse = false
                end
            elseif tower.Type == "Commander" then
                local directionalInfo = directionalTowerTypes[tower.Type]
                if type(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex ~= index then
                    allowUse = false
                else
                    targetPos = getCommanderTarget()
                    allowUse = targetPos ~= nil
                end
            else
                local directional = directionalTowerTypes[tower.Type]
                local sendWithPos = (type(directional) == "table" and directional.onlyAbilityIndex == index) or directional == true

                if requiresManualAiming(ab, cfg) then
                    sendWithPos = true
                end

                if sendWithPos and allowUse then
                    targetPos = getEnhancedTarget(pos, range, tower.Type, ab, cfg)
                    if not targetPos then
                        allowUse = false
                    end
                elseif not sendWithPos and not directional and allowUse then
                    local hasEnemies = getFarthestEnemyInRangeByPath(pos, range, {
                        excludeAir = skipAirTowers[tower.Type] or false
                    })
                    if not hasEnemies then
                        allowUse = false
                    end
                end
            end

            if tower.Type == "Medic" then
                local _, medicP2 = getUpgradeLevels(tower)
                if medicP2 >= 4 then
                    local target = getBestMedicTarget(tower, ownedTowers)
                    if target then
                        targetHash = target
                    else
                        allowUse = false
                    end
                else
                    allowUse = false
                end
            end

            if allowUse then
                if globalEnv and globalEnv.TDX_Config and globalEnv.TDX_Config.UseThreadedRemotes == false then
                    safeInvokeAbility(hash, index, targetPos, targetHash)
                else
                    safeThreadInvoke(hash, index, targetPos, targetHash)
                end
                skillsThisFrame = skillsThisFrame + 1

                if tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                    if p2 >= 3 and p2 <= 5 then
                        mobsterLastUsedTime[hash] = now
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    setThreadIdentity(2)

    repeat
        task.wait(0.1)
    until EnemyClass.GetEnemies() and TowerClass.GetTowers()

    populate()
    hookTC()
    hookEC()
    hookAHC()

    Initialized = true

    local progressEvent = dtc and dtc.CustomEvent and dtc.CustomEvent.new()
    if progressEvent then
        progressEvent:Connect(newcclosure(function(hash, pi, pct)
            EProgCache[hash] = { progress = pi + pct, pathIndex = pi }
        end))
    end

    local hookedMetatables = {}

    local function hookMovementHandler(hash, mh)
        if not mh then
            return
        end
        local mt = getrawmetatable(mh)
        if not mt then
            return
        end
        if hookedMetatables[mt] then
            local pi = mh.PathIndex or 0
            EProgCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
            return
        end
        hookedMetatables[mt] = true
        if setreadonly then
            setreadonly(mt, false)
        end
        local origNI = rawget(mt, "__newindex")
        mt.__newindex = newcclosure(function(t, k, v)
            if origNI then
                origNI(t, k, v)
            else
                rawset(t, k, v)
            end
            if k == "PathIndex" or k == "PathPercentage" then
                local pi = k == "PathIndex" and v or (rawget(t, "PathIndex") or 0)
                local pct = k == "PathPercentage" and v or (rawget(t, "PathPercentage") or 0)
                if progressEvent then
                    progressEvent:Fire(hash, pi, pct)
                end
            end
        end)
        local pi = mh.PathIndex or 0
        EProgCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
    end

    for hash, enemy in _pairs(FEnemies) do
        hookMovementHandler(hash, enemy.MovementHandler)
    end

    local _origOnEnemyAdded = onEAdd
    onEAdd = newcclosure(function(hash, enemy)
        _origOnEnemyAdded(hash, enemy)
        hookMovementHandler(hash, enemy.MovementHandler)
    end)

    while true do
        task.wait(0.05)

        for k, e in _pairs(FEnemies) do
            if not e.IsAlive then
                onERemove(k)
            end
        end

        local rawTowers = TowerClass.GetTowers()
        if rawTowers then
            for hash, tower in _pairs(rawTowers) do
                if tower then
                    FTowers[hash] = tower
                end
            end
        end
    end
end)

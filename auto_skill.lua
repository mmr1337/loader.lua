local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local TowerAttack = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerAttack")

local Common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local TowerUtilities = require(Common:WaitForChild("TowerUtilities"))

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

local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}
if globalEnv.TDX_Config.UseThreadedRemotes == nil then
    globalEnv.TDX_Config.UseThreadedRemotes = true
end

local frameCounter = 0
local PROCESS_EVERY_N_FRAMES = 3

local cachedEnemies = {}
local cachedEnemyTime = 0

local function refreshEnemyCache()
    local now = tick()
    if now - cachedEnemyTime < 0.04 then return end
    cachedEnemyTime = now
    cachedEnemies = {}
    for _, e in pairs(EnemyClass.GetEnemies()) do
        if e and e.IsAlive and not e.IsFakeEnemy then
            table.insert(cachedEnemies, e)
        end
    end
end

-- Tower configurations
local directionalTowerTypes = {
    ["Commander"] = { onlyAbilityIndex = 3 },
    ["Toxicnator"] = true,
    ["Ghost"] = true,
    ["Ice Breaker"] = true,
    ["Mobster"] = true,
    ["Golden Mobster"] = true,
    ["Artillery"] = true,
    ["Golden Mine Layer"] = true,
    ["Flame Trooper"] = true
}

local skipTowerTypes = {
    ["Helicopter"] = true,
    ["Cryo Helicopter"] = true,
    ["Medic"] = true,
    ["Combat Drone"] = true,
    ["Machine Gunner"] = true
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

local mobsterUsedEnemies = {}
local prevCooldown = {}
local mobsterLastUsedTime = {}
local mobsterDelay = 0.15
local medicLastUsedTime = {}
local medicDelay = 0.5

-- ═══════════════════════════════════════════════════════
-- [FIX 3] Очистка мёртвых врагов каждые 2 сек
-- Было: каждый кадр, двойной перебор
-- ═══════════════════════════════════════════════════════
local lastCleanupTime = 0

local function cleanupDeadEnemiesFromCache()
    local now = tick()
    if now - lastCleanupTime < 2 then return end
    lastCleanupTime = now

    local aliveSet = {}
    for _, e in pairs(EnemyClass.GetEnemies()) do
        if e and e.IsAlive then
            aliveSet[tostring(e)] = true
        end
    end

    for hash, enemies in pairs(mobsterUsedEnemies) do
        for enemyId in pairs(enemies) do
            if not aliveSet[enemyId] then
                enemies[enemyId] = nil
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════
-- Утилиты — без изменений
-- ═══════════════════════════════════════════════════════
local function getDistance2D(pos1, pos2)
    local dx = pos1.X - pos2.X
    local dz = pos1.Z - pos2.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function getTowerPos(tower)
    if not tower then return nil end
    local success, result = pcall(function() return tower:GetPosition() end)
    return success and result or nil
end

local function getRange(tower)
    if not tower then return 0 end
    local success, result = pcall(function() return tower:GetCurrentRange() end)
    return success and typeof(result) == "number" and result or 0
end

local function GetCurrentUpgradeLevels(tower)
    local p1, p2 = 0, 0
    pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
    pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
    return p1, p2
end

local function isCooldownReady(hash, index, ability)
    if not ability then return false end
    local lastCD = (prevCooldown[hash] and prevCooldown[hash][index]) or 0
    local currentCD = ability.CooldownRemaining or 0
    if currentCD > lastCD + 0.1 or currentCD > 0 then
        prevCooldown[hash] = prevCooldown[hash] or {}
        prevCooldown[hash][index] = currentCD
        return false
    end
    prevCooldown[hash] = prevCooldown[hash] or {}
    prevCooldown[hash][index] = currentCD
    return true
end

-- ═══════════════════════════════════════════════════════
-- [FIX 4] DPS кэш — пересчёт раз в 5 секунд
-- Было: CalculateDPS при каждом TowerAttack event
-- ═══════════════════════════════════════════════════════
local dpsCache = {}
local dpsCacheTime = {}

local function getDPS(tower, hash)
    if not tower or not tower.LevelHandler then return 0 end
    local key = hash or tostring(tower)
    local now = tick()
    if dpsCache[key] and dpsCacheTime[key] and now - dpsCacheTime[key] < 5 then
        return dpsCache[key]
    end

    local success, result = pcall(function()
        local levelStats = tower.LevelHandler:GetLevelStats()
        local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or nil
        return TowerUtilities.CalculateDPS(levelStats, buffStats)
    end)
    local dps = success and typeof(result) == "number" and result or 0
    dpsCache[key] = dps
    dpsCacheTime[key] = now
    return dps
end

local function isBuffedByMedic(tower)
    if not tower or not tower.BuffHandler or not tower.BuffHandler.ActiveBuffs then return false end
    for _, buff in pairs(tower.BuffHandler.ActiveBuffs) do
        local buffName = tostring(buff.Name or "")
        if buffName:match("^MedicKritz") then return true end
    end
    return false
end

local function canReceiveBuff(tower)
    if not tower or tower.NoBuffs then return false end
    if skipMedicBuffTowers[tower.Type] then return false end
    return true
end

-- ═══════════════════════════════════════════════════════
-- [FIX 5] Поиск врагов: single-pass max вместо sort
-- Было: собрать в таблицу → table.sort → взять [1]
-- Стало: один проход, запоминаем лучшего
-- ═══════════════════════════════════════════════════════
local function getEnemyPathPercentage(enemy)
    if not enemy or not enemy.MovementHandler then return 0 end
    local mh = enemy.MovementHandler
    local pathPercent = mh.PathPercentage or 0
    if mh.ReverseDirection then
        pathPercent = 1 - pathPercent
    end
    return (mh.PathIndex or 0) + pathPercent
end

local function getFarthestEnemyNoRange(options)
    local excludeAir = options and options.excludeAir or false
    local bestPos = nil
    local bestPath = -1

    for _, enemy in ipairs(cachedEnemies) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        local pp = getEnemyPathPercentage(enemy)
        if pp > bestPath then
            bestPath = pp
            bestPos = enemy:GetPosition()
        end
    end

    return bestPos
end

-- Единая функция поиска: возвращает позицию лучшего врага в радиусе
local function getFarthestEnemyInRange(pos, range, options)
    local excludeAir = options and options.excludeAir or false
    local bestPos = nil
    local bestPath = -1

    for _, enemy in ipairs(cachedEnemies) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) <= range then
            local pp = getEnemyPathPercentage(enemy)
            if pp > bestPath then
                bestPath = pp
                bestPos = ePos
            end
        end
    end

    return bestPos
end

local function hasSplashDamage(ability)
    if not ability or not ability.Config then return false end
    if ability.Config.ProjectileHitData then
        local hitData = ability.Config.ProjectileHitData
        if hitData.IsSplash and hitData.SplashRadius and hitData.SplashRadius > 0 then
            return true, hitData.SplashRadius
        end
    end
    if ability.Config.HasRadiusEffect and ability.Config.EffectRadius and ability.Config.EffectRadius > 0 then
        return true, ability.Config.EffectRadius
    end
    return false, 0
end

local function getAbilityRange(ability, defaultRange)
    if not ability or not ability.Config then return defaultRange end
    local config = ability.Config
    if config.ManualAimInfiniteRange == true then return math.huge end
    if config.ManualAimCustomRange and config.ManualAimCustomRange > 0 then return config.ManualAimCustomRange end
    if config.Range and config.Range > 0 then return config.Range end
    if config.CustomQueryData and config.CustomQueryData.Range then return config.CustomQueryData.Range end
    return defaultRange
end

local function requiresManualAiming(ability)
    if not ability or not ability.Config then return false end
    return ability.Config.IsManualAimAtGround == true or ability.Config.IsManualAimAtPath == true
end

local function getEnhancedTarget(pos, towerRange, towerType, ability)
    local excludeAir = skipAirTowers[towerType] or false
    local effectiveRange = getAbilityRange(ability, towerRange)
    return getFarthestEnemyInRange(pos, effectiveRange, { excludeAir = excludeAir })
end

-- ═══════════════════════════════════════════════════════
-- [FIX 6] tacticalTarget: single-pass вместо sort
-- ═══════════════════════════════════════════════════════
local function tacticalTarget(pos, range, options)
    options = options or {}
    local mode = options.mode or "nearest"
    local excludeAir = options.excludeAir or false
    local usedEnemies = options.usedEnemies
    local markUsed = options.markUsed or false

    local chosen = nil
    local bestVal = -1
    local allCandidates = nil -- только для random

    for _, enemy in ipairs(cachedEnemies) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) > range then continue end

        if usedEnemies then
            if usedEnemies[tostring(enemy)] then continue end
        end

        if mode == "maxhp" then
            local hp = enemy.HealthHandler and enemy.HealthHandler:GetMaxHealth() or 0
            if hp > bestVal then
                bestVal = hp
                chosen = enemy
            end
        elseif mode == "currenthp" then
            local hp = enemy.HealthHandler and enemy.HealthHandler:GetHealth() or 0
            if hp > bestVal then
                bestVal = hp
                chosen = enemy
            end
        elseif mode == "random_weighted" then
            if not allCandidates then allCandidates = {} end
            table.insert(allCandidates, enemy)
            local hp = enemy.HealthHandler and enemy.HealthHandler:GetMaxHealth() or 0
            if hp > bestVal then
                bestVal = hp
                chosen = enemy
            end
        else
            if not chosen then chosen = enemy end
        end
    end

    -- random_weighted: 30% strongest, 70% random
    if mode == "random_weighted" and allCandidates and #allCandidates > 0 then
        if math.random(1, 10) > 3 then
            chosen = allCandidates[math.random(1, #allCandidates)]
        end
    end

    if chosen and markUsed and usedEnemies then
        usedEnemies[tostring(chosen)] = true
    end

    return chosen and chosen:GetPosition() or nil
end

-- ═══════════════════════════════════════════════════════
-- [FIX 7] getMobsterTarget: single-pass max
-- ═══════════════════════════════════════════════════════
local function getMobsterTarget(tower, hash, path)
    local pos = getTowerPos(tower)
    local range = getRange(tower)
    if not pos then return nil end

    mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}

    if path == 2 then
        local bestEnemy = nil
        local bestHP = -1
        local bestPath = -1

        for _, enemy in ipairs(cachedEnemies) do
            if not enemy.GetPosition then continue end
            if enemy.IsAirUnit then continue end

            local ePos = enemy:GetPosition()
            if getDistance2D(ePos, pos) > range then continue end

            local id = tostring(enemy)
            if mobsterUsedEnemies[hash][id] then continue end

            local hp = enemy.HealthHandler and enemy.HealthHandler:GetMaxHealth() or 0
            local pp = getEnemyPathPercentage(enemy)

            if hp > bestHP or (hp == bestHP and pp > bestPath) then
                bestHP = hp
                bestPath = pp
                bestEnemy = enemy
            end
        end

        if not bestEnemy then return nil end
        mobsterUsedEnemies[hash][tostring(bestEnemy)] = true
        return bestEnemy:GetPosition()
    else
        for _, enemy in ipairs(cachedEnemies) do
            if not enemy.GetPosition then continue end
            if enemy.IsAirUnit then continue end

            local ePos = enemy:GetPosition()
            if getDistance2D(ePos, pos) <= range then
                return ePos
            end
        end
        return nil
    end
end

-- ═══════════════════════════════════════════════════════
-- [FIX 8] getCommanderTarget: single-pass
-- ═══════════════════════════════════════════════════════
local function getCommanderTarget()
    local bestEnemy = nil
    local bestHP = -1
    local groundCount = 0
    local groundEnemies = nil

    for _, e in ipairs(cachedEnemies) do
        if e.IsAirUnit then continue end
        groundCount = groundCount + 1

        local hp = e.HealthHandler and e.HealthHandler:GetMaxHealth() or 0
        if hp > bestHP then
            bestHP = hp
            bestEnemy = e
        end
    end

    if not bestEnemy then return nil end

    if math.random(1, 10) <= 3 then
        return bestEnemy:GetPosition()
    else
        groundEnemies = {}
        for _, e in ipairs(cachedEnemies) do
            if not e.IsAirUnit then
                table.insert(groundEnemies, e)
            end
        end
        if #groundEnemies == 0 then return nil end
        local chosen = groundEnemies[math.random(1, #groundEnemies)]
        return chosen and chosen:GetPosition() or nil
    end
end

local function getBestMedicTarget(medicTower, ownedTowers)
    local medicPos = getTowerPos(medicTower)
    if not medicPos then return nil end
    local medicRange = getRange(medicTower)
    local bestHash, bestDPS = nil, -1

    for hash, tower in pairs(ownedTowers) do
        if tower == medicTower then continue end
        if canReceiveBuff(tower) and not isBuffedByMedic(tower) then
            local towerPos = getTowerPos(tower)
            if towerPos and getDistance2D(towerPos, medicPos) <= medicRange then
                local dps = getDPS(tower, hash)
                if dps > bestDPS then
                    bestDPS = dps
                    bestHash = hash
                end
            end
        end
    end
    return bestHash
end

local function SendSkill(hash, index, pos, targetHash)
    task.spawn(function()
        setThreadIdentity(2)
        pcall(function()
            TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
        end)
    end)
end

local lastAttackProcessTime = 0

TowerAttack.OnClientEvent:Connect(function(attackData)
    local now = tick()
    if now - lastAttackProcessTime < 0.1 then return end
    lastAttackProcessTime = now

    local ownedTowers = TowerClass.GetTowers() or {}

    -- Собираем позиции атакующих башен (без дублей)
    local attackPositions = {}
    for _, data in ipairs(attackData) do
        local attackingTower = ownedTowers[data.X]
        if attackingTower then
            local pos = getTowerPos(attackingTower)
            if pos then
                table.insert(attackPositions, pos)
            end
        end
    end

    if #attackPositions == 0 then return end

    task.spawn(function()
        setThreadIdentity(2)
        local now2 = tick()

        for hash, tower in pairs(ownedTowers) do
            if not tower or not tower.AbilityHandler then continue end

            local towerType = tower.Type
            if towerType ~= "EDJ" and towerType ~= "Commander" and towerType ~= "Medic" then
                continue
            end

            local towerPos = getTowerPos(tower)
            if not towerPos then continue end
            local towerRange = getRange(tower)

            local inRange = false
            for _, attackPos in ipairs(attackPositions) do
                if getDistance2D(towerPos, attackPos) <= towerRange then
                    inRange = true
                    break
                end
            end
            if not inRange then continue end

            if towerType == "EDJ" or towerType == "Commander" then
                local ability = tower.AbilityHandler:GetAbilityFromIndex(1)
                if isCooldownReady(hash, 1, ability) then
                    SendSkill(hash, 1)
                end
            elseif towerType == "Medic" then
                local _, p2 = GetCurrentUpgradeLevels(tower)
                if p2 >= 4 then
                    if not medicLastUsedTime[hash] or now2 - medicLastUsedTime[hash] >= medicDelay then
                        for index = 1, 3 do
                            local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                            if isCooldownReady(hash, index, ability) then
                                local tgtHash = getBestMedicTarget(tower, ownedTowers)
                                if tgtHash then
                                    SendSkill(hash, index, nil, tgtHash)
                                    medicLastUsedTime[hash] = now2
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end)

-- ═══════════════════════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════════════════════
local MAX_SKILLS_PER_FRAME = 5

RunService.Heartbeat:Connect(function()
    frameCounter = frameCounter + 1
    if frameCounter % PROCESS_EVERY_N_FRAMES ~= 0 then return end

    refreshEnemyCache()
    if #cachedEnemies == 0 then return end

    cleanupDeadEnemiesFromCache()

    local ownedTowers = TowerClass.GetTowers() or {}
    local skillsThisFrame = 0
    local now = tick()

    -- Pre-calculate mobster targets
    local towerSkills = {}
    for hash, tower in pairs(ownedTowers) do
        if not tower or not tower.AbilityHandler then continue end
        if tower.Type ~= "Mobster" and tower.Type ~= "Golden Mobster" then continue end

        local p1, p2 = GetCurrentUpgradeLevels(tower)

        if p2 >= 3 and p2 <= 5 then
            if mobsterLastUsedTime[hash] and now - mobsterLastUsedTime[hash] < mobsterDelay then
                continue
            end
        end

        if (p2 >= 3 and p2 <= 5) or (p1 >= 4 and p1 <= 5) then
            for index = 1, 3 do
                local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                if isCooldownReady(hash, index, ability) then
                    local targetPos = getMobsterTarget(tower, hash, p2 >= 3 and 2 or 1)
                    if targetPos then
                        towerSkills[hash] = towerSkills[hash] or {}
                        towerSkills[hash][index] = targetPos
                    end
                    break
                end
            end
        end
    end

    -- Execute skills
    for hash, tower in pairs(ownedTowers) do
        if skillsThisFrame >= MAX_SKILLS_PER_FRAME then break end
        if not tower or not tower.AbilityHandler then continue end
        if skipTowerTypes[tower.Type] then continue end

        local p1, p2 = GetCurrentUpgradeLevels(tower)
        local pos = getTowerPos(tower)
        if not pos then continue end
        local range = getRange(tower)

        for index = 1, 3 do
            if skillsThisFrame >= MAX_SKILLS_PER_FRAME then break end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
            if not isCooldownReady(hash, index, ability) then continue end

            local targetPos = nil
            local allowUse = true

            if tower.Type == "Jet Trooper" then
                if index ~= 2 then allowUse = false end
            end

            -- Ghost
            if tower.Type == "Ghost" then
                if p2 > 2 then
                    break
                else
                    targetPos = getFarthestEnemyNoRange({ excludeAir = false })
                    if targetPos then
                        SendSkill(hash, index, targetPos)
                        skillsThisFrame = skillsThisFrame + 1
                    end
                    break
                end
            end

            -- Toxicnator
            if tower.Type == "Toxicnator" then
                targetPos = tacticalTarget(pos, range, {
                    mode = "maxhp",
                    excludeAir = false
                })
                if targetPos then
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            -- Flame Trooper
            if tower.Type == "Flame Trooper" then
                targetPos = getEnhancedTarget(pos, 9.5, tower.Type, ability)
                if targetPos then
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            -- Ice Breaker
            if tower.Type == "Ice Breaker" then
                local customRange = index == 2 and 8 or range
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ability)
                if targetPos then
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            if tower.Type == "Slammer" then
                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                if targetPos then
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            if tower.Type == "John" then
                local customRange = p1 >= 5 and range or 4.5
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ability)
                if targetPos then
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            if tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                if towerSkills[hash] and towerSkills[hash][index] then
                    SendSkill(hash, index, towerSkills[hash][index])
                    skillsThisFrame = skillsThisFrame + 1
                    if p2 >= 3 and p2 <= 5 then
                        mobsterLastUsedTime[hash] = now
                    end
                end
                break
            end

            if tower.Type == "Commander" then
                if index == 3 then
                    targetPos = getCommanderTarget()
                    if targetPos then
                        SendSkill(hash, index, targetPos)
                        skillsThisFrame = skillsThisFrame + 1
                    end
                end
                break
            end

            local directional = directionalTowerTypes[tower.Type]
            local sendWithPos = typeof(directional) == "table" and directional.onlyAbilityIndex == index or directional == true

            if ability and requiresManualAiming(ability) then
                sendWithPos = true
            end

            if not targetPos and sendWithPos and allowUse then
                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                if not targetPos then allowUse = false end
            end

            if not sendWithPos and not directional and allowUse then
                local hasEnemies = getFarthestEnemyInRange(pos, range, {
                    excludeAir = skipAirTowers[tower.Type] or false
                })
                if not hasEnemies then allowUse = false end
            end

            if allowUse then
                if sendWithPos and targetPos then
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                elseif not sendWithPos then
                    SendSkill(hash, index)
                    skillsThisFrame = skillsThisFrame + 1
                end
            end
        end
    end
end)

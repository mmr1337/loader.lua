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

-- Thread identity management
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

-- Enhanced tower configurations
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

-- Tracking variables
local mobsterUsedEnemies = {}
local frameUsedEnemies = {}  -- Cache chung cho mỗi frame
local prevCooldown = {}

-- Cleanup dead enemies từ cache
local function cleanupDeadEnemiesFromCache()
    for hash, enemies in pairs(mobsterUsedEnemies) do
        for enemyId, _ in pairs(enemies) do
            -- Parse enemy hash từ string
            local testEnemy = nil
            for _, e in pairs(EnemyClass.GetEnemies()) do
                if tostring(e) == enemyId and not e:Alive() then
                    enemies[enemyId] = nil
                    break
                end
            end
        end
    end
end
local medicLastUsedTime = {}
local medicDelay = 0.5

-- ======== Core utility functions ========
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

local function getDPS(tower)
    if not tower or not tower.LevelHandler then return 0 end
    local success, result = pcall(function()
        local levelStats = tower.LevelHandler:GetLevelStats()
        local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or nil
        return TowerUtilities.CalculateDPS(levelStats, buffStats)
    end)
    return success and typeof(result) == "number" and result or 0
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

-- ======== Enhanced enemy management ========
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
    if not enemy or not enemy.MovementHandler then return 0 end
    
    local mh = enemy.MovementHandler
    local pathPercent = mh.PathPercentage or 0
    
    -- Nếu đi reverse direction, phải invert percentage
    if mh.ReverseDirection then
        pathPercent = 1 - pathPercent
    end
    
    -- Combine PathIndex và PathPercentage để so sánh chính xác
    -- Kẻ ở PathIndex cao hơn hoặc PathPercentage cao hơn = đi xa hơn
    return (mh.PathIndex or 0) + pathPercent
end

local function getFarthestEnemyNoRange(options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        table.insert(candidates, {
            enemy = enemy,
            pathPercent = getEnemyPathPercentage(enemy)
        })
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        return a.pathPercent > b.pathPercent
    end)

    return candidates[1].enemy:GetPosition()
end

local function getFarthestEnemyInRange(pos, range, options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) <= range then
            table.insert(candidates, {
                enemy = enemy,
                pathPercent = getEnemyPathPercentage(enemy)
            })
        end
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        return a.pathPercent > b.pathPercent
    end)

    return candidates[1].enemy:GetPosition()
end

local function getNearestEnemyInRange(pos, range, options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) <= range then
            table.insert(candidates, {
                enemy = enemy,
                position = ePos,
                pathPercent = getEnemyPathPercentage(enemy)
            })
        end
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        return a.pathPercent > b.pathPercent
    end)

    return candidates[1].position
end

local function getFarthestEnemyInRangeByPath(pos, range, options)
    options = options or {}
    local excludeAir = options.excludeAir or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) <= range then
            table.insert(candidates, {
                enemy = enemy,
                position = ePos,
                pathPercent = getEnemyPathPercentage(enemy)
            })
        end
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        return a.pathPercent > b.pathPercent
    end)

    return candidates[1].position
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
    local options = { excludeAir = skipAirTowers[towerType] or false }
    local effectiveRange = getAbilityRange(ability, towerRange)

    if ability then
        local isSplash, splashRadius = hasSplashDamage(ability)
        local isManualAim = requiresManualAiming(ability)
        if isSplash or isManualAim then
            return getFarthestEnemyInRangeByPath(pos, effectiveRange, options)
        end
    end

    if not directionalTowerTypes[towerType] then
        return getFarthestEnemyInRangeByPath(pos, effectiveRange, options)
    else
        return getFarthestEnemyInRangeByPath(pos, effectiveRange, options)
    end
end

local function tacticalTarget(pos, range, options)
    options = options or {}
    local mode = options.mode or "nearest"
    local excludeAir = options.excludeAir or false
    local usedEnemies = options.usedEnemies
    local markUsed = options.markUsed or false

    local candidates = {}
    for _, enemy in ipairs(getEnemies()) do
        if not enemy.GetPosition then continue end
        if excludeAir and enemy.IsAirUnit then continue end

        local ePos = enemy:GetPosition()
        if getDistance2D(ePos, pos) > range then continue end

        if usedEnemies then
            local id = tostring(enemy)
            if usedEnemies[id] then continue end
        end

        table.insert(candidates, enemy)
    end

    if #candidates == 0 then return nil end

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

local function getMobsterTarget(tower, hash, path)
    local pos = getTowerPos(tower)
    local range = getRange(tower)

    mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}

    if path == 2 then
        -- Path 2: Complex logic with tracking
        local candidates = {}
        local maxHP = -1

        for _, enemy in ipairs(getEnemies()) do
            if not enemy.GetPosition then continue end
            if enemy.IsAirUnit then continue end

            local ePos = enemy:GetPosition()
            if getDistance2D(ePos, pos) > range then continue end

            local id = tostring(enemy)
            if mobsterUsedEnemies[hash][id] then continue end

            local hp = enemy.HealthHandler and enemy.HealthHandler:GetMaxHealth() or 0

            if hp > maxHP then
                maxHP = hp
                candidates = {{enemy = enemy, hp = hp, pathPercent = getEnemyPathPercentage(enemy)}}
            elseif hp == maxHP then
                table.insert(candidates, {enemy = enemy, hp = hp, pathPercent = getEnemyPathPercentage(enemy)})
            end
        end

        if #candidates == 0 then return nil end

        -- Sort by path percentage (farthest first) when same HP
        if #candidates > 1 then
            table.sort(candidates, function(a, b)
                return a.pathPercent > b.pathPercent
            end)
        end

        local chosen = candidates[1].enemy
        mobsterUsedEnemies[hash][tostring(chosen)] = true
        return chosen:GetPosition()
    else
        -- Path 1: Just check if enemy exists in range, then cast
        for _, enemy in ipairs(getEnemies()) do
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

local function getCommanderTarget()
    local candidates = {}
    for _, e in ipairs(getEnemies()) do
        if not e.IsAirUnit then 
            table.insert(candidates, e) 
        end
    end

    if #candidates == 0 then return nil end

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
    local bestHash, bestDPS = nil, -1

    for hash, tower in pairs(ownedTowers) do
        if tower == medicTower then continue end
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

local function SendSkill(hash, index, pos, targetHash)
    if globalEnv.TDX_Config.UseThreadedRemotes then
        task.spawn(function()
            setThreadIdentity(2)
            pcall(function()
                TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
            end)
        end)
    else
        pcall(function()
            TowerUseAbilityRequest:InvokeServer(hash, index, pos, targetHash)
        end)
    end
end

-- ======== Tower Attack Event Handler ========
local function handleTowerAttack(attackData)
    local ownedTowers = TowerClass.GetTowers() or {}

    for _, data in ipairs(attackData) do
        local attackingTowerHash = data.X
        local targetHash = data.Y

        local attackingTower = ownedTowers[attackingTowerHash]
        if not attackingTower then continue end

        task.spawn(function()
            setThreadIdentity(2)

            for hash, tower in pairs(ownedTowers) do
                if hash == attackingTowerHash then continue end

                local towerPos = getTowerPos(tower)
                local attackingPos = getTowerPos(attackingTower)
                if not towerPos or not attackingPos then continue end

                local distance = getDistance2D(towerPos, attackingPos)
                local towerRange = getRange(tower)

                if distance <= towerRange then
                    if tower.Type == "EDJ" or tower.Type == "Commander" then
                        local ability = tower.AbilityHandler:GetAbilityFromIndex(1)
                        if isCooldownReady(hash, 1, ability) then
                            SendSkill(hash, 1)
                        end
                    elseif tower.Type == "Medic" then
                        local _, p2 = GetCurrentUpgradeLevels(tower)
                        if p2 >= 4 then
                            local now = tick()
                            if not medicLastUsedTime[hash] or now - medicLastUsedTime[hash] >= medicDelay then
                                for index = 1, 3 do
                                    local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
                                    if isCooldownReady(hash, index, ability) then
                                        local targetHash = getBestMedicTarget(tower, ownedTowers)
                                        if targetHash then
                                            SendSkill(hash, index, nil, targetHash)
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

TowerAttack.OnClientEvent:Connect(handleTowerAttack)

-- ======== MAIN LOOP ========
local skillsThisFrame = 0
local MAX_SKILLS_PER_FRAME = 5
local mobsterProcessedThisFrame = false

RunService.Heartbeat:Connect(function()
    skillsThisFrame = 0
    frameUsedEnemies = {}  -- Reset cache chung mỗi frame
    cleanupDeadEnemiesFromCache()  -- Clear enemy chết ra khỏi cache
    local ownedTowers = TowerClass.GetTowers() or {}
    local towerSkills = {}

    -- First pass: calculate targets for towers with complex logic
    for hash, tower in pairs(ownedTowers) do
        if not tower or not tower.AbilityHandler then continue end
        if skipTowerTypes[tower.Type] then continue end

        local p1, p2 = GetCurrentUpgradeLevels(tower)
        local pos = getTowerPos(tower)
        local range = getRange(tower)

        -- Pre-calculate for Mobster/Golden Mobster and similar towers
        if tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
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
    end

    -- Second pass: execute skills with frame limit
    for hash, tower in pairs(ownedTowers) do
        if skillsThisFrame >= MAX_SKILLS_PER_FRAME then break end
        if not tower or not tower.AbilityHandler then continue end
        if skipTowerTypes[tower.Type] then continue end

        local p1, p2 = GetCurrentUpgradeLevels(tower)
        local pos = getTowerPos(tower)
        local range = getRange(tower)

        for index = 1, 3 do
            if skillsThisFrame >= MAX_SKILLS_PER_FRAME then break end

            local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
            if not isCooldownReady(hash, index, ability) then continue end

            local targetPos = nil
            local allowUse = true

            -- Jet Trooper: chỉ dùng skill 2
            if tower.Type == "Jet Trooper" then
                if index ~= 2 then allowUse = false end
            end

            -- Ghost: lấy kẻ địch xa nhất không giới hạn range
            if tower.Type == "Ghost" then
                if p2 > 2 then
                    allowUse = false
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

            -- Toxicnator: dùng range của tower
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

            -- Flame Trooper: dùng range tùy chỉnh 9.5
            if tower.Type == "Flame Trooper" then
                targetPos = getEnhancedTarget(pos, 9.5, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            -- Ice Breaker: skill 1 dùng range, skill 2 dùng 8
            if tower.Type == "Ice Breaker" then
                local customRange = index == 2 and 8 or range
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            -- Slammer: dùng range của tower
            if tower.Type == "Slammer" then
                targetPos = getEnhancedTarget(pos, range, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            -- John: dùng range của tower, hoặc 4.5 nếu p1 < 5
            if tower.Type == "John" then
                local customRange = p1 >= 5 and range or 4.5
                targetPos = getEnhancedTarget(pos, customRange, tower.Type, ability)
                if targetPos then 
                    SendSkill(hash, index, targetPos)
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            -- Mobster & Golden Mobster (use pre-calculated target, share frame cache)
            if tower.Type == "Mobster" or tower.Type == "Golden Mobster" then
                if towerSkills[hash] and towerSkills[hash][index] then
                    SendSkill(hash, index, towerSkills[hash][index])
                    skillsThisFrame = skillsThisFrame + 1
                end
                break
            end

            -- Commander: chỉ skill 3
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

            -- General targeting cho directional towers
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
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))

-- === CÀI ĐẶT ===
local NEW_SPLASH_RADIUS = 9999 -- Thay đổi bán kính sát thương lan ở đây
local ENABLED = true
-- =================

print("Executor: Combat Drone Splash Damage script loaded.")
print("Target Splash Radius: " .. tostring(NEW_SPLASH_RADIUS))

RunService.Heartbeat:Connect(function()
    if not ENABLED then return end

    local allTowers = TowerClass.GetTowers()
    if not allTowers then return end

    for hash, tower in pairs(allTowers) do
        -- Thêm điều kiện: Chỉ áp dụng nếu trụ là "Combat Drone"
        if tower and tower.Type == "Combat Drone" then
            if tower.LevelHandler then
                local success, levelStats = pcall(function()
                    return tower.LevelHandler:GetLevelStats()
                end)

                if success and levelStats then
                    -- Ghi đè các thuộc tính sát thương lan
                    levelStats.IsSplash = true
                    levelStats.SplashRadius = NEW_SPLASH_RADIUS
                end
            end
        end
    end
end)


local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local ClientFolder = PlayerScripts:WaitForChild("Client")
local UserInputHandlerFolder = ClientFolder:WaitForChild("UserInputHandler")
local FirstPersonHandlerFolder = UserInputHandlerFolder:WaitForChild("FirstPersonHandler")
local FirstPersonAttackManagerFolder = FirstPersonHandlerFolder:WaitForChild("FirstPersonAttackManager")

local FirstPersonHandler = require(FirstPersonHandlerFolder)
local FirstPersonAttackManager = require(FirstPersonAttackManagerFolder)
local FirstPersonAttackHandlerClass = require(FirstPersonAttackManagerFolder:WaitForChild("FirstPersonAttackHandlerClass"))
local EnemyClass = require(ClientFolder:WaitForChild("GameClass"):WaitForChild("EnemyClass"))

local original_FirstPersonHandler_Begin = FirstPersonHandler.Begin
local original_FirstPersonHandler_Stop = FirstPersonHandler.Stop
local original_AttackHandler_Attack = FirstPersonAttackHandlerClass._Attack

_G.CurrentFPSControlledTower = nil
_G.AutoAttackRunning = false
local hasNoEnemySet = false -- track đã tắt attack khi không có enemy

-- Begin / Stop Tower Control
FirstPersonHandler.Begin = function(towerInstance)
    _G.CurrentFPSControlledTower = towerInstance
    _G.AutoAttackRunning = true
    hasNoEnemySet = false
    return original_FirstPersonHandler_Begin(towerInstance)
end

FirstPersonHandler.Stop = function()
    _G.CurrentFPSControlledTower = nil
    _G.AutoAttackRunning = false
    FirstPersonAttackManager.ToggleTryAttacking(false)
    hasNoEnemySet = false
    return original_FirstPersonHandler_Stop()
end

-- Helper: tính tiến độ của enemy
local function getEnemyPathProgress(enemy)
    if not enemy or not enemy.MovementHandler then return 0 end

    if enemy.MovementHandler.GetPathPercentage then
        return enemy.MovementHandler:GetPathPercentage() or 0
    end

    if enemy.MovementHandler.PathPercentage then
        return enemy.MovementHandler.PathPercentage or 0
    end

    if enemy.MovementHandler.GetCurrentNode then
        local currentNode = enemy.MovementHandler:GetCurrentNode()
        if currentNode and currentNode.GetPercentageAlongPath then
            return currentNode:GetPercentageAlongPath(1) or 0
        end
    end

    return 0
end

-- Heartbeat: bật/tắt attack dựa vào enemy targetable, chỉ set false 1 lần khi không có enemy
RunService.Heartbeat:Connect(function()
    if not _G.AutoAttackRunning or not _G.CurrentFPSControlledTower then
        return
    end

    local foundEnemy = false
    for _, enemy in pairs(EnemyClass.GetEnemies()) do
        if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
            foundEnemy = true
            break
        end
    end

    if foundEnemy then
        FirstPersonAttackManager.ToggleTryAttacking(true)
        hasNoEnemySet = false
    elseif not hasNoEnemySet then
        -- chỉ set false 1 lần
        FirstPersonAttackManager.ToggleTryAttacking(false)
        hasNoEnemySet = true
    end
end)

-- Override _Attack: chọn enemy đi xa nhất + headshot 95%
FirstPersonAttackHandlerClass._Attack = function(self)
    local currentTower = _G.CurrentFPSControlledTower
    if not (currentTower and currentTower.DirectControlHandler and currentTower.DirectControlHandler:IsActive()) then
        return original_AttackHandler_Attack(self)
    end

    local towerPosition = currentTower:GetTorsoPosition() or currentTower:GetPosition()
    local furthestEnemy = nil
    local maxProgress = -1

    for _, enemy in pairs(EnemyClass.GetEnemies()) do
        if enemy and enemy.IsAlive and not enemy.IsFakeEnemy and enemy:FirstPersonTargetable() then
            local enemyPosition = enemy:GetTorsoPosition() or enemy:GetPosition()
            if enemyPosition and towerPosition then
                local pathProgress = getEnemyPathProgress(enemy)
                if pathProgress > maxProgress then
                    maxProgress = pathProgress
                    furthestEnemy = enemy
                end
            end
        end
    end

    if furthestEnemy then
        local targetChance = math.random(1, 100)
        local targetPosition, hitPart

        if targetChance <= 95 then -- headshot 95%
            local headPart = furthestEnemy.Character and furthestEnemy.Character.GetHead and furthestEnemy.Character:GetHead()
            if headPart then
                targetPosition = headPart.Position
                hitPart = headPart
            else
                targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
                hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso() 
                          or (furthestEnemy.Character and furthestEnemy.Character.PrimaryPart) 
                          or (furthestEnemy.Model and furthestEnemy.Model.PrimaryPart)
            end
        else
            targetPosition = furthestEnemy:GetTorsoPosition() or furthestEnemy:GetPosition()
            hitPart = furthestEnemy.Character and furthestEnemy.Character:GetTorso() 
                      or (furthestEnemy.Character and furthestEnemy.Character.PrimaryPart) 
                      or (furthestEnemy.Model and furthestEnemy.Model.PrimaryPart)
        end

        if hitPart and targetPosition then
            local hitNormal = (targetPosition - towerPosition).Unit
            if self.IsProjectile then
                self:_AttackProjectile(hitPart, targetPosition, hitNormal)
            else
                self:_AttackHitscan(hitPart, targetPosition, hitNormal)
            end

            self:_BurstAttackHandling()
            FirstPersonHandler.Attacked(self.Index, self.UseAbilityName, self.AttackConfig.NoTriggerClientTowerAttacked)
            return
        end
    end

    return original_AttackHandler_Attack(self)
end







for _, mod in ipairs(getloadedmodules()) do
    if mod.Name == "FirstPersonAttackHandlerClass" then
        local ModuleTable = require(mod)
        if ModuleTable and ModuleTable.New then
            local oldNew = ModuleTable.New
            ModuleTable.New = function(...)
                local obj = oldNew(...)
                obj.DefaultShotInterval = 0.001
                obj.ReloadTime = 0.001
                obj.CurrentFirerateMultiplier = 0.001
                obj.DefaultSpreadDegrees = 0 -- No recoil/spread
                return obj
            end
        end
    elseif mod.Name == "FirstPersonCameraHandler" then
        local cameraMod = require(mod)
        if cameraMod and cameraMod.CameraShake then
            cameraMod.CameraShake = function() end
        end
        if cameraMod and cameraMod.ApplyRecoil then
            cameraMod.ApplyRecoil = function() end
        end
    end
end

print("Đã loại bỏ cooldown, tăng tốc bắn và loại bỏ độ giật!")
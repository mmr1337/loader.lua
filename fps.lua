local REMOVAL_LEVEL = 2

task.wait(1)

pcall(function()
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
    local GameClass = PlayerScripts.Client:WaitForChild("GameClass")

    local TowerClass = require(GameClass:WaitForChild("TowerClass"))
    local EnemyClass = require(GameClass:WaitForChild("EnemyClass"))
    local PathEntityClass = require(GameClass:WaitForChild("PathEntityClass"))
    local ProjectileHandler = require(GameClass:WaitForChild("ProjectileHandler"))
    local DropCoinsHandler = require(GameClass:WaitForChild("DropCoinsHandler"))
    local VisualEffectHandler = require(GameClass:WaitForChild("VisualEffectHandler"))
    local VisualSequenceHandler = require(GameClass:WaitForChild("VisualSequenceHandler"))
    local NetworkingHandler = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("NetworkingHandler"))

    VisualEffectHandler.NewVisualEffect = function() return end
    VisualSequenceHandler.StartNewSequence = function() return end
    if DropCoinsHandler then DropCoinsHandler.DropCoins = function() return end end

    local originalNewProjectile = ProjectileHandler.NewProjectile
    ProjectileHandler.NewProjectile = function(...)
        local realProjectiles = originalNewProjectile(...)
        if realProjectiles then
            for _, proj in ipairs(realProjectiles) do
                task.spawn(function()
                    if not proj or not proj.Model then return end
                    local function stripFX(instance)
                        if instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") or instance:IsA("Light") then
                            instance.Enabled = false
                        end
                    end
                    for _, d in ipairs(proj.Model:GetDescendants()) do stripFX(d) end
                    proj.Model.DescendantAdded:Connect(stripFX)
                end)
            end
        end
        return realProjectiles
    end

    local function disableModelFX(instance)
        if not instance or not instance.Parent then return end
        local cn = instance.ClassName
        if cn == "ParticleEmitter" or cn == "Beam" or cn == "Trail" or cn == "PointLight" or cn == "SpotLight" then
            instance.Enabled = false
            if instance:IsA("Light") then instance.Brightness = 0 end
        end
    end

    local function disableTowerFX(instance)
        if not instance or not instance.Parent then return end
        if string.find(instance.Name, "Ring", 1, true) or (instance.Parent and string.find(instance.Parent.Name, "Ring", 1, true)) then return end
        disableModelFX(instance)
    end

    local function processTower(tower)
        if tower and tower.Character and tower.Character.CharacterModel then
            local charModel = tower.Character.CharacterModel
            tower.Character.Attacked = function() return end
            tower.Character.RunDefaultBeamEffects = function() return end
            for _, v in ipairs(charModel:GetDescendants()) do disableTowerFX(v) end
            charModel.DescendantAdded:Connect(disableTowerFX)
            if REMOVAL_LEVEL >= 2 then
                if tower.SetAnimationState then
                    local oldSetAnim = tower.SetAnimationState
                    tower.SetAnimationState = function(self, state, force)
                        if string.find(tostring(state), "Attack", 1, true) then return end
                        pcall(oldSetAnim, self, state, force)
                    end
                end
            end
        end
    end

    local function processGenericEntity(entity)
        if entity and entity.Character and entity.Character.CharacterModel then
            local charModel = entity.Character.CharacterModel
            for _, v in ipairs(charModel:GetDescendants()) do disableModelFX(v) end
            charModel.DescendantAdded:Connect(disableModelFX)
            if REMOVAL_LEVEL >= 2 then
                if entity.SetAnimationState then
                    local oldSetAnim = entity.SetAnimationState
                    entity.SetAnimationState = function(self, state, force)
                        if state == "Attack" or state == "Spawn" then return end
                        pcall(oldSetAnim, self, state, force)
                    end
                end
                if entity._Attacked then
                    entity._Attacked = function() return end
                end
            end
        end
    end

    if TowerClass and TowerClass.GetTowers then
        for _, t in pairs(TowerClass.GetTowers()) do task.spawn(processTower, t) end
    end
    local oldTowerNew = TowerClass.New
    TowerClass.New = function(...)
        local t = oldTowerNew(...)
        if t then task.spawn(processTower, t) end
        return t
    end

    if EnemyClass and EnemyClass.GetEnemies then
        for _, e in pairs(EnemyClass.GetEnemies()) do task.spawn(processGenericEntity, e) end
    end
    local oldEnemyNew = EnemyClass.New
    EnemyClass.New = function(...)
        local e = oldEnemyNew(...)
        if e then task.spawn(processGenericEntity, e) end
        return e
    end

    if PathEntityClass and PathEntityClass.GetPathEntities then
        for _, p in pairs(PathEntityClass.GetPathEntities()) do task.spawn(processGenericEntity, p) end
    end
    local oldPathEntityNew = PathEntityClass.New
    PathEntityClass.New = function(...)
        local p = oldPathEntityNew(...)
        if p then task.spawn(processGenericEntity, p) end
        return p
    end

    local function disableEvent(eventName)
        local event = NetworkingHandler:GetEvent(eventName)
        if event and event.AttachCallback then
            event:AttachCallback(function() end)
        end
    end

    disableEvent("RemoveBurnEffect")
    disableEvent("EnemiesBurningUpdate")
end)
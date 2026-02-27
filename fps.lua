task.wait(1)

local CONFIG_LEVEL = 1

pcall(function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local PlayerScripts = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")
    local Client = PlayerScripts:WaitForChild("Client")
    local GameClass = Client:WaitForChild("GameClass")
    local UserInterfaceHandler = Client:WaitForChild("UserInterfaceHandler")
    local TDX_Shared = ReplicatedStorage:WaitForChild("TDX_Shared")
    local Common = TDX_Shared:WaitForChild("Common")
    local Wrappers = Common:WaitForChild("Wrappers")
    local BaseClasses = GameClass:WaitForChild("BaseClasses")
    local CharacterClass = require(BaseClasses:WaitForChild("CharacterClass"))

    local ProjectileHandler = require(GameClass:WaitForChild("ProjectileHandler"))
    local TowerClass = require(GameClass:WaitForChild("TowerClass"))

    pcall(function()
        local originalNewProjectile = ProjectileHandler.NewProjectile
        ProjectileHandler.NewProjectile = function(packet)
            local shouldRender = false
            if packet and packet.OriginEntityClass == "Tower" then
                local tower = TowerClass.GetTower(packet.OriginHash)
                if tower then
                    if tostring(tower.Type) == "Combat Drone" or tostring(tower.Name) == "Combat Drone" then
                        shouldRender = true
                    end
                end
            end
            if shouldRender then
                return originalNewProjectile(packet)
            end
            return {}
        end
    end)

    pcall(function()
        if UserInterfaceHandler and UserInterfaceHandler.TowerUIHandler then
            local UpgradeHoverHandler = require(
                UserInterfaceHandler.TowerUIHandler:WaitForChild("UpgradeHoverHandler")
            )
            if UpgradeHoverHandler and UpgradeHoverHandler.UpgradeHovered then
                local originalUpgradeHovered = UpgradeHoverHandler.UpgradeHovered
                UpgradeHoverHandler.UpgradeHovered = function(...)
                    pcall(originalUpgradeHovered, ...)
                end
            end
        end
    end)

    pcall(function()
        CharacterClass.ExplodeParts = function() end

        local DeathEffectHandler = require(CharacterClass:WaitForChild("DeathEffectHandler"))
        DeathEffectHandler.NewDeathEffect = function() end

        local EnemyClass = require(GameClass:WaitForChild("EnemyClass"))
        local originalEnemyNew = EnemyClass.New

        EnemyClass.New = function(...)
            local newEnemy = originalEnemyNew(...)
            if newEnemy and newEnemy.CustomCode and newEnemy.CustomCode.Initialize then
                local originalInitialize = newEnemy.CustomCode.Initialize
                newEnemy.CustomCode.Initialize = function(self, ...)
                    originalInitialize(self, ...)
                    if self._TimingHelpers then
                        for name, helper in pairs(self._TimingHelpers) do
                            if string.find(name, "Death") then
                                if helper and helper.Config then
                                    helper.Config.Callback = function() end
                                end
                            end
                        end
                    end
                    if self._DeathTimingHelpers then
                        for _, helper in pairs(self._DeathTimingHelpers) do
                            if helper and helper.Config then
                                helper.Config.Callback = function() end
                            end
                        end
                    end
                end
            end
            return newEnemy
        end
    end)

    if CONFIG_LEVEL >= 1 then
        pcall(function()
            local VisualEffectHandler = require(GameClass:WaitForChild("VisualEffectHandler"))
            local VisualSequenceHandler = require(GameClass:WaitForChild("VisualSequenceHandler"))
            local DropCoinsHandler = require(GameClass:WaitForChild("DropCoinsHandler"))

            VisualEffectHandler.NewVisualEffect = function() end
            VisualSequenceHandler.StartNewSequence = function() end
            if DropCoinsHandler then
                DropCoinsHandler.DropCoins = function() end
            end
        end)

        pcall(function()
            local EmitterWrapper = require(Wrappers:WaitForChild("EmitterWrapperClass"))
            EmitterWrapper.PlayTriggered = function() end
            EmitterWrapper.PlayContinuous = function() end
            EmitterWrapper.PlayAll = function() end
            EmitterWrapper.PlayKeyframeTriggered = function() end
        end)

        pcall(function()
            local NetworkingHandler = require(Common:WaitForChild("NetworkingHandler"))
            local function disableEvent(eventName)
                local event = NetworkingHandler:GetEvent(eventName)
                if event and event.AttachCallback then
                    event:AttachCallback(function() end)
                end
            end
            disableEvent("NewBurnEffect")
            disableEvent("RemoveBurnEffect")
            disableEvent("EnemiesBurningUpdate")
            disableEvent("NewVisualEffect")
        end)
    end

    if CONFIG_LEVEL >= 2 then
        pcall(function()
            local SoundWrapper = require(Wrappers:WaitForChild("SoundWrapperClass"))
            SoundWrapper.PlayTriggered = function() end
            SoundWrapper.PlayContinuous = function() end
            SoundWrapper.PlayAll = function() end
            SoundWrapper.PlayKeyframeTriggered = function() end
        end)

        pcall(function()
            local originalSetAnimationState = CharacterClass.SetAnimationState
            CharacterClass.SetAnimationState = function(self, state, ...)
                if state and (string.find(tostring(state), "Attack") or tostring(state) == "Spawn") then
                    return
                end
                pcall(originalSetAnimationState, self, state, ...)
            end
        end)
    end
end)

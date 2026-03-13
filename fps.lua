task.wait(1)

local CONFIG_LEVEL = (getgenv().TDX_Config and getgenv().TDX_Config["FpsLevel"] or 1)

local function makeEmptyModel(modelName, headOffset)
    local emptyModel = Instance.new("Model")
    emptyModel.Name = modelName
    local primaryPart = Instance.new("Part")
    primaryPart.Name = "HumanoidRootPart"
    primaryPart.Size = Vector3.new(0.05, 0.05, 0.05)
    primaryPart.Transparency = 1
    primaryPart.CanCollide = false
    primaryPart.CanQuery = false
    primaryPart.CanTouch = false
    primaryPart.Anchored = false
    primaryPart.CastShadow = false
    primaryPart.Parent = emptyModel
    emptyModel.PrimaryPart = primaryPart
    if headOffset then

        local fakeHead = Instance.new("Part")
        fakeHead.Name = "Head"
        fakeHead.Size = Vector3.new(0.05, 0.05, 0.05)
        fakeHead.Transparency = 1
        fakeHead.CanCollide = false
        fakeHead.CanQuery = true
        fakeHead.CanTouch = false
        fakeHead.Anchored = false
        fakeHead.CastShadow = false
        fakeHead:SetAttribute("IsHead", true)
        fakeHead.Parent = emptyModel
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = primaryPart
        weld.Part1 = fakeHead
        weld.Parent = primaryPart
        fakeHead.CFrame = primaryPart.CFrame * CFrame.new(0, headOffset, 0)
    end
    return emptyModel
end

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
            if packet and packet.OriginEntityClass == "Tower" then
                local tower = TowerClass.GetTower(packet.OriginHash)
                if tower then
                    if tostring(tower.Type) == "Combat Drone" or tostring(tower.Name) == "Combat Drone" then
                        return originalNewProjectile(packet)
                    end
                end
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
        local BeamEffectHelper = require(Common:WaitForChild("BeamEffectHelper"))
        BeamEffectHelper.NewBeamEffects   = function() return {} end
        BeamEffectHelper.StartBeamEffects = function() end
        BeamEffectHelper.StopBeamEffects  = function() end
        BeamEffectHelper.RunBeamEffects   = function() end
    end)

    pcall(function()
        CharacterClass.RunDefaultBeamEffects = function() end
    end)

    pcall(function()
        local NetworkingHandler = require(Common:WaitForChild("NetworkingHandler"))
        local function disableEvent(eventName)
            local event = NetworkingHandler:GetEvent(eventName)
            if event and event.AttachCallback then
                event:AttachCallback(function() end)
            end
        end
        disableEvent("TowerChainAttack")
        disableEvent("TowerConvertedChainAttack")
        disableEvent("NewBurnEffect")
        disableEvent("RemoveBurnEffect")
        disableEvent("EnemiesBurningUpdate")
        disableEvent("NewVisualEffect")
    end)

    pcall(function()
        local DeathEffectHandler = require(CharacterClass:WaitForChild("DeathEffectHandler"))
        local originalNewDeathEffect = DeathEffectHandler.NewDeathEffect
        DeathEffectHandler.NewDeathEffect = function(trackInstance, deathEffectName, deathSound, speedMultiplier)

            return originalNewDeathEffect(trackInstance, nil, deathSound, speedMultiplier)
        end
    end)

    pcall(function()

        CharacterClass._PlayDeathEffects = function() end
        CharacterClass.ExplodeParts      = function() end

        CharacterClass.RunDeathLogic = function(self, dt, dtReal)
            if self.DeathAnimationFinished then
                local delayLeft = self.DeathFadeOutDelayTimeLeft
                if delayLeft and delayLeft > 0 then
                    self.DeathFadeOutDelayTimeLeft = delayLeft - dt
                    return
                end
                local fadeLeft = self.DeathFadeOutTimeLeft
                if fadeLeft and fadeLeft > 0 then
                    local delta = self.EntityClass == "Tower" and dtReal or dt
                    fadeLeft = fadeLeft - delta
                    self.DeathFadeOutTimeLeft = fadeLeft
                    local alpha = math.max(0, 1 - fadeLeft / self.FadeOutTime)
                    for _, part in pairs(self.DeathFadeOutParts) do
                        part.Transparency = math.max(part.Transparency, alpha)
                    end
                    if fadeLeft <= 0 then
                        local removeDelay = self.DeathFadeOutRemoveDelayTimeLeft
                        if removeDelay and removeDelay > 0 then
                            self.DeathFadeOutRemoveDelayTimeLeft = removeDelay - dt
                            return
                        end
                        self.FadeOutOnDeath = false
                        self:_Cleanup()
                    end
                end
            end
            if self.GeneralWrapperDeathStopTimeLeft and self.GeneralWrapperDeathStopTimeLeft > 0 then
                self.GeneralWrapperDeathStopTimeLeft = self.GeneralWrapperDeathStopTimeLeft - dt
                if self.GeneralWrapperDeathStopTimeLeft <= 0 then
                    self:StopGeneralWrappers()
                    self.GeneralWrapperDeathStopTimeLeft = nil
                end
            end
        end
    end)

    pcall(function()
        TowerClass._PlayDeathEffects = function() end
    end)

    pcall(function()
        local EnemyClass = require(GameClass:WaitForChild("EnemyClass"))
        local AbilityHandlerClass = require(
            GameClass:WaitForChild("EnemyClass"):WaitForChild("AbilityHandlerClass")
        )

        AbilityHandlerClass.AbilityUsed = function(self, data)
            local name = data[1]
            local ability = self.Abilities[name] or self.DeathAbilities[name]
            if ability then
                ability:AbilityUsedOnServer(data)
            end
        end

        EnemyClass.AbilityUsed = function(self, data)
            if self.AbilityHandler then
                self.AbilityHandler:AbilityUsed(data)
            end
        end
    end)

    pcall(function()
        local VisualEffectHandler = require(GameClass:WaitForChild("VisualEffectHandler"))
        local PartFadingHelper = require(VisualEffectHandler:WaitForChild("PartFadingHelper"))
        PartFadingHelper.Fade = function() end
        PartFadingHelper.Run  = function() end
    end)

    pcall(function()
        local EmitterWrapper = require(Wrappers:WaitForChild("EmitterWrapperClass"))
        EmitterWrapper.PlayTriggered         = function() end
        EmitterWrapper.PlayContinuous        = function() end
        EmitterWrapper.PlayAll               = function() end
        EmitterWrapper.PlayKeyframeTriggered = function() end
    end)

    pcall(function()
        local EmitterAndSoundWrapper = require(Wrappers:WaitForChild("EmitterAndSoundWrapperClass"))
        EmitterAndSoundWrapper.PlayTriggered         = function() end
        EmitterAndSoundWrapper.PlayContinuous        = function() end
        EmitterAndSoundWrapper.PlayAll               = function() end
        EmitterAndSoundWrapper.PlayKeyframeTriggered = function() end
    end)

    pcall(function()
        local VisualEffectHandler   = require(GameClass:WaitForChild("VisualEffectHandler"))
        local VisualSequenceHandler = require(GameClass:WaitForChild("VisualSequenceHandler"))
        local DropCoinsHandler      = require(GameClass:WaitForChild("DropCoinsHandler"))

        VisualEffectHandler.NewVisualEffect    = function() end
        VisualSequenceHandler.StartNewSequence = function() end
        if DropCoinsHandler then
            DropCoinsHandler.DropCoins = function() end
        end
    end)

    pcall(function()
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
                            if helper and helper.Config then
                                local n = tostring(name)
                                local isVisual = string.find(n, "Death")  or string.find(n, "Visual")
                                             or string.find(n, "Effect") or string.find(n, "Beam")
                                             or string.find(n, "Chain")  or string.find(n, "Fade")
                                local isAnim = string.find(n, "Anim")
                                if isVisual and not isAnim then
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

                    if self._VisualHelpers then
                        for _, helper in pairs(self._VisualHelpers) do
                            if helper and helper.Config then
                                helper.Config.Callback = function() end
                            end
                        end
                    end

                    if self._EffectHelpers then
                        for _, helper in pairs(self._EffectHelpers) do
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

    if CONFIG_LEVEL >= 2 then

        pcall(function()
            local ResourceManager = require(Common:WaitForChild("ResourceManager"))

            ResourceManager.GetEnemyModel = function(modelName, _)

                return makeEmptyModel(modelName, 2)
            end

            ResourceManager.GetPathEntityModel = function(modelName, _)

                return makeEmptyModel(modelName, nil)
            end
        end)

        pcall(function()
            local originalCharNew = CharacterClass.New
            CharacterClass.New = function(initData, ...)
                if initData and initData.Config then
                    if initData.EntityClass == "Enemy" then
                        initData.Config.NoAnimations  = true
                        initData.Config.NoTorso       = true
                        initData.Config.GunModelName  = nil

                    elseif initData.EntityClass == "PathEntity" then
                        initData.Config.NoAnimations  = true
                        initData.Config.NoHead        = true
                        initData.Config.NoTorso       = true
                        initData.Config.GunModelName  = nil
                    end
                end
                return originalCharNew(initData, ...)
            end
        end)

        pcall(function()
            local FirstPersonHitHandler = require(CharacterClass:WaitForChild("FirstPersonHitHandlerClass"))
            local dummyHandler = { Hit = function() end, Destroy = function() end, Run = function() end }
            FirstPersonHitHandler.New = function() return dummyHandler end
        end)

        pcall(function()
            local SoundWrapper = require(Wrappers:WaitForChild("SoundWrapperClass"))
            SoundWrapper.PlayTriggered         = function() end
            SoundWrapper.PlayContinuous        = function() end
            SoundWrapper.PlayAll               = function() end
            SoundWrapper.PlayKeyframeTriggered = function() end
        end)

    end
end)

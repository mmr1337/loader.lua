-- highlight enemy đi xa nhất trong tầm bắn của tower
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
repeat task.wait() until LocalPlayer:FindFirstChild("PlayerScripts")

local TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)
local EnemyClass = require(LocalPlayer.PlayerScripts.Client.GameClass.EnemyClass)

-- lấy tower của local player
local function getLocalTower()
    for _, tower in pairs(TowerClass.GetTowers()) do
        if tower.OwnedByLocalPlayer and tower:Alive() then
            return tower
        end
    end
end

-- tìm enemy xa nhất trong tầm bắn
local function getFarthestEnemyInRange(tower)
    local enemies = EnemyClass.GetEnemies()
    local towerPos = tower:GetPosition()
    local range = tower:GetCurrentRange()
    local farthest, maxProgress = nil, -math.huge

    for _, enemy in pairs(enemies) do
        if enemy and enemy:Alive() and enemy.MovementHandler then
            local enemyPos = enemy:GetPosition()
            local distance = (enemyPos - towerPos).Magnitude
            if distance <= range then
                local progress = enemy.MovementHandler.PathPercentage or 0
                if progress > maxProgress then
                    maxProgress = progress
                    farthest = enemy
                end
            end
        end
    end
    return farthest
end

local function clearHighlights()
    for _, e in pairs(workspace.Game.Enemies:GetChildren()) do
        local h = e:FindFirstChildOfClass("Highlight")
        if h then h:Destroy() end
    end
    for _, t in pairs(workspace.Game.Towers:GetChildren()) do
        local h = t:FindFirstChildOfClass("Highlight")
        if h then h:Destroy() end
    end
end

local function highlightEnemyAndTower(enemy, tower)
    clearHighlights()

    -- highlight enemy (màu cam)
    if enemy and enemy.Character then
        local model = enemy.Character:GetCharacterModel()
        if model then
            local hl = Instance.new("Highlight")
            hl.FillColor = Color3.fromRGB(255, 140, 0)
            hl.OutlineColor = Color3.fromRGB(255, 255, 180)
            hl.FillTransparency = 0.25
            hl.OutlineTransparency = 0
            hl.Parent = model
        end
    end

    -- highlight tower (xanh dương nhạt + phát sáng)
    if tower and tower.Character then
        local model = tower.Character:GetCharacterModel()
        if model then
            local hl = Instance.new("Highlight")
            hl.FillColor = Color3.fromRGB(0, 170, 255)
            hl.OutlineColor = Color3.fromRGB(220, 240, 255)
            hl.FillTransparency = 0.2
            hl.OutlineTransparency = 0
            hl.Parent = model

            -- hiệu ứng phát sáng
            local light = Instance.new("PointLight")
            light.Color = Color3.fromRGB(100, 180, 255)
            light.Range = 12
            light.Brightness = 2
            light.Parent = model
        end
    end
end

-- cập nhật mỗi 0.5 giây
task.spawn(function()
    while task.wait(0.5) do
        local tower = getLocalTower()
        if tower then
            local target = getFarthestEnemyInRange(tower)
            highlightEnemyAndTower(target, tower)
        else
            clearHighlights()
        end
    end
end)
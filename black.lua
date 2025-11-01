local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local Terrain = workspace:WaitForChild("Terrain")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Script Control
local scriptEnabled = true
local isRemoving = false

function _G.blackoff()
    scriptEnabled = false
    isRemoving = true
    for _, v in pairs(CoreGui:GetChildren()) do
        if v:IsA("ScreenGui") and v.DisplayOrder == 2147483647 then
            pcall(function()
                v:Destroy()
            end)
        end
    end
end

function _G.blackon()
    scriptEnabled = true
end

pcall(function()
LocalPlayer.CameraMaxZoomDistance = 1000
Lighting.Technology = Enum.Technology.Compatibility
Lighting.GlobalShadows = false
Lighting.FogEnd = 100000
Terrain.WaterWaveSize = 0
Terrain.WaterWaveSpeed = 0
Terrain.WaterReflectance = 0
end)

local enemyModule = nil
pcall(function()
enemyModule = require(LocalPlayer.PlayerScripts:WaitForChild("Client")
:WaitForChild("GameClass")
:WaitForChild("EnemyClass"))
end)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = tostring(math.random(1e9, 2e9))
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 2147483647
screenGui.Parent = CoreGui

local blackFrame = Instance.new("Frame")
blackFrame.Name = "Cover"
blackFrame.Size = UDim2.new(1, 0, 1, 0)
blackFrame.Position = UDim2.new(0, 0, 0, 0)
blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
blackFrame.BorderSizePixel = 0
blackFrame.ZIndex = 1
blackFrame.Active = true
blackFrame.Parent = screenGui

local headerLabel = Instance.new("TextLabel")
headerLabel.Name = "Header"
headerLabel.Size = UDim2.new(1, -20, 0, 30)
headerLabel.Position = UDim2.new(0, 10, 0, 10)
headerLabel.BackgroundTransparency = 1
headerLabel.TextColor3 = Color3.new(1, 1, 1)
headerLabel.TextStrokeTransparency = 0
headerLabel.Font = Enum.Font.SourceSansBold
headerLabel.TextSize = 24
headerLabel.TextYAlignment = Enum.TextYAlignment.Top
headerLabel.TextXAlignment = Enum.TextXAlignment.Left
headerLabel.ZIndex = 2
headerLabel.Parent = screenGui

local enemyListFrame = Instance.new("ScrollingFrame")
enemyListFrame.Name = "EnemyList"
enemyListFrame.Size = UDim2.new(1, -20, 1, -50)
enemyListFrame.Position = UDim2.new(0, 10, 0, 40)
enemyListFrame.BackgroundTransparency = 1
enemyListFrame.BorderSizePixel = 0
enemyListFrame.ScrollBarThickness = 6
enemyListFrame.ScrollingDirection = Enum.ScrollingDirection.XY
enemyListFrame.ZIndex = 2
enemyListFrame.Parent = screenGui

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.Padding = UDim.new(0, 2)
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Parent = enemyListFrame

local function kick(englishReason)
pcall(function() LocalPlayer:Kick(englishReason or "GUI tampering was detected.") end)
end

local function protect(instance, propertiesToProtect)
local originalProperties = { Parent = instance.Parent }
for _, propName in ipairs(propertiesToProtect) do originalProperties[propName] = instance[propName] end
instance.AncestryChanged:Connect(function(_, parent)
if isRemoving then return end
if parent ~= originalProperties.Parent then kick("Reason: Attempted to delete or move a protected GUI element.") end
end)
for propName, originalValue in pairs(originalProperties) do
if propName ~= "Parent" then
instance:GetPropertyChangedSignal(propName):Connect(function()
if isRemoving then return end
if instance[propName] ~= originalValue then kick("Reason: Attempted to modify protected GUI property: " .. propName) end
end)
end
end
end

protect(screenGui, {"Name", "DisplayOrder", "IgnoreGuiInset", "Enabled"})
protect(blackFrame, {"Name", "Size", "Position", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex", "Active"})
protect(headerLabel, {"Name", "Size", "Position", "TextColor3", "Visible", "ZIndex"})
protect(enemyListFrame, {"Name", "Size", "Position", "Visible", "ZIndex"})

local function formatPercent(value)
if value < 0 then value = 0 end
return math.floor(value * 100 + 0.5) .. "%"
end

local waveTextLabel, timeTextLabel
pcall(function()
local interface = PlayerGui:WaitForChild("Interface", 15)
local gameInfoBar = interface and interface:WaitForChild("GameInfoBar", 15)
if gameInfoBar then
waveTextLabel = gameInfoBar:WaitForChild("Wave", 5) and gameInfoBar.Wave:WaitForChild("WaveText", 5)
timeTextLabel = gameInfoBar:WaitForChild("TimeLeft", 5) and gameInfoBar.TimeLeft:WaitForChild("TimeLeftText", 5)
end
end)

local SHIELD_COLOR_STRING = "rgb(0,170,255)"
local NORMAL_COLOR = Color3.new(1, 1, 1)

RunService.RenderStepped:Connect(function()
if not scriptEnabled then return end

local waveStr = (waveTextLabel and waveTextLabel.Text) or "?"
local timeStr = (timeTextLabel and timeTextLabel.Text) or "??:??"
headerLabel.Text = string.format("Wave: %s | Time: %s", waveStr, timeStr)

local enemyGroups = {}  
if enemyModule and enemyModule.GetEnemies then  
    for _, enemy in pairs(enemyModule.GetEnemies()) do  
        pcall(function()  
            if not (enemy and enemy.IsAlive and not enemy.IsFakeEnemy) then return end  
            local hh = enemy.HealthHandler  
            if not (hh and hh.GetMaxHealth and hh.GetHealth) then return end  
            local maxHealth = hh:GetMaxHealth()  
            if not (typeof(maxHealth) == "number" and maxHealth > 0) then return end  

            local currentHealth = hh:GetHealth() or 0  
            local currentShield = 0  
            if hh.GetShield then currentShield = hh:GetShield() or 0 end  

            local hasShield = currentShield > 0  
            local percentValue = (currentHealth + currentShield) / maxHealth  
            local hp = formatPercent(percentValue)  
            local name = enemy.DisplayName or "Unknown"  

            if not enemyGroups[name] then enemyGroups[name] = { count = 0, hpData = {} } end  

            local group = enemyGroups[name]  
            group.count += 1  
            table.insert(group.hpData, {hp = hp, shield = hasShield})  
        end)  
    end  
end  

for _, child in ipairs(enemyListFrame:GetChildren()) do  
    if child:IsA("TextLabel") then child:Destroy() end  
end  

local sortedNames = {}  
for name in pairs(enemyGroups) do table.insert(sortedNames, name) end  
table.sort(sortedNames)  

local maxCanvasWidth = 0  
for i, name in ipairs(sortedNames) do  
    local data = enemyGroups[name]  
    local newLine = Instance.new("TextLabel")  
    newLine.Name = name  
    newLine.LayoutOrder = i  
    newLine.AutomaticSize = Enum.AutomaticSize.X  
    newLine.Size = UDim2.new(0, 0, 0, 22)  
    newLine.TextWrapped = false  
    newLine.BackgroundTransparency = 1  
    newLine.Font = Enum.Font.SourceSansBold  
    newLine.TextSize = 22  
    newLine.TextXAlignment = Enum.TextXAlignment.Left  
    newLine.RichText = true  
    newLine.TextColor3 = NORMAL_COLOR  

    local hpStrings = {}  
    for _, hpInfo in ipairs(data.hpData) do  
        if hpInfo.shield then  
            table.insert(hpStrings, string.format('<font color="%s">%s</font>', SHIELD_COLOR_STRING, hpInfo.hp))  
        else  
            table.insert(hpStrings, hpInfo.hp)  
        end  
    end  

    local hpString = table.concat(hpStrings, ", ")  
    newLine.Text = string.format("%s (x%d): %s", name, data.count, hpString)  
    newLine.Parent = enemyListFrame  

    maxCanvasWidth = math.max(maxCanvasWidth, newLine.AbsoluteSize.X)  
end  

enemyListFrame.CanvasSize = UDim2.new(0, maxCanvasWidth, 0, uiListLayout.AbsoluteContentSize.Y)

end)

RunService.RenderStepped:Connect(function()
if not scriptEnabled then return end

screenGui.DisplayOrder = 2147483647
if screenGui.Parent ~= CoreGui then screenGui.Parent = CoreGui end

for _, child in ipairs(CoreGui:GetChildren()) do  
    if child:IsA("ScreenGui") and child ~= screenGui then  
        pcall(function()  
            child.DisplayOrder = -1  
        end)  
    end  
end

end)
-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- DATA + UTIL
local Data = require(ReplicatedStorage.TDX_Shared.Client.Services.Data)
local Util = require(ReplicatedStorage.TDX_Shared.Modules.Util)

-- CHỜ DATA LOAD XONG
do
    local attempts = 0
    repeat task.wait(1); attempts += 1
    until Data.Get("Gold") ~= nil or attempts > 30
end

-- FORMAT (KHÔNG LÀM TRÒN)
local function formatShort(n)
    n = tonumber(n) or 0

    if n >= 1e9 then
        local v = math.floor(n / 1e8) / 10
        return v .. "B"
    elseif n >= 1e6 then
        local v = math.floor(n / 1e5) / 10
        return v .. "M"
    elseif n >= 1e3 then
        local v = math.floor(n / 1e2) / 10
        return v .. "k"
    else
        return tostring(math.floor(n))
    end
end

-- ENEMY MODULE
local enemyModule
pcall(function()
    enemyModule = require(LocalPlayer.PlayerScripts.Client.GameClass.EnemyClass)
end)

local scriptEnabled = true

-- GUI
local gui = Instance.new("ScreenGui")
gui.DisplayOrder = 2147483647
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = CoreGui

local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1,1)
black.BackgroundColor3 = Color3.new(0,0,0)
black.BorderSizePixel = 0
black.Parent = gui

-- WAVE + TIME
local info = Instance.new("TextLabel")
info.BackgroundTransparency = 1
info.Position = UDim2.new(0,10,0,10)
info.Size = UDim2.new(1,-20,0,28)
info.TextColor3 = Color3.new(1,1,1)
info.Font = Enum.Font.SourceSansBold
info.TextSize = 22
info.TextXAlignment = Enum.TextXAlignment.Left
info.Parent = gui

-- STATS
local stats = Instance.new("TextLabel")
stats.BackgroundTransparency = 1
stats.Position = UDim2.new(0,10,0,40)
stats.Size = UDim2.new(1,-20,0,25)
stats.TextColor3 = Color3.new(1,1,1)
stats.Font = Enum.Font.SourceSansBold
stats.TextSize = 20
stats.TextXAlignment = Enum.TextXAlignment.Left
stats.Parent = gui

-- HEADER
local header = Instance.new("TextLabel")
header.BackgroundTransparency = 1
header.Size = UDim2.new(1,-20,0,30)
header.Position = UDim2.new(0,10,0,70)
header.TextColor3 = Color3.new(1,1,1)
header.Font = Enum.Font.SourceSansBold
header.TextSize = 24
header.Text = "Enemies"
header.Parent = gui

-- LIST
local list = Instance.new("ScrollingFrame")
list.BackgroundTransparency = 1
list.Size = UDim2.new(1,-20,1,-110)
list.Position = UDim2.new(0,10,0,100)
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.Parent = gui

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0,2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

-- LABEL POOL
local pool = {}
local active = {}

local function getLabel()
    local label = table.remove(pool)

    if not label then
        label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.SourceSansBold
        label.TextSize = 22
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.RichText = true
        label.AutomaticSize = Enum.AutomaticSize.X
        label.Size = UDim2.new(0,0,0,22)
        label.Parent = list
    end

    label.Visible = true
    table.insert(active,label)
    return label
end

local function releaseLabels()
    for _,l in ipairs(active) do
        l.Visible = false
        table.insert(pool,l)
    end
    table.clear(active)
end

local function percent(v)
    if v < 0 then v = 0 end
    return math.floor(v*100+0.5).."%"
end

local SHIELD = "rgb(0,170,255)"

-- LOOP
local UPDATE_RATE = 0.1
local timer = 0

RunService.Heartbeat:Connect(function(dt)

    if not scriptEnabled then return end

    timer += dt
    if timer < UPDATE_RATE then return end
    timer = 0

    -- WAVE + TIME
    local waveText, timeText = "?", "?"
    pcall(function()
        waveText = PlayerGui.Interface.GameInfoBar.Default.Wave.WaveText.Text
        timeText = PlayerGui.Interface.GameInfoBar.Default.TimeLeft.TimeLeftText.Text
    end)

    info.Text = "Wave: "..waveText.." | Time: "..timeText

    -- DATA (dùng Data.Get thay vì Data:Get)
    local goldValue = Data.Get("Gold") or 0
    local crystalValue = Data.Get("Crystals") or 0
    local xp = Data.Get("XP") or 0

    local gold = formatShort(math.floor(goldValue))
    local crystals = formatShort(math.floor(crystalValue))

    local lvl, needed, progress = 1, 0, 0
    pcall(function()
        lvl, needed, progress = Util.XPToLevelAndProgress(xp)
    end)

    stats.Text = string.format(
        "Gold: %s | Crystals: %s | Level: %d (%d/%d XP)",
        gold, crystals, lvl, progress, needed
    )

    -- ENEMIES
    if not enemyModule or not enemyModule.GetEnemies then return end

    releaseLabels()

    local groups = {}

    for _,enemy in pairs(enemyModule.GetEnemies()) do
        if enemy and enemy.IsAlive and not enemy.IsFakeEnemy then

            local hh = enemy.HealthHandler
            if not hh then continue end

            local max = hh:GetMaxHealth()
            if not max or max <= 0 then continue end

            local hp = hh:GetHealth() or 0
            local shield = hh.GetShield and hh:GetShield() or 0

            local name = enemy.DisplayName or "Unknown"

            groups[name] = groups[name] or {count=0,data={}}

            table.insert(groups[name].data,{
                hp = percent((hp+shield)/max),
                shield = shield > 0
            })

            groups[name].count += 1
        end
    end

    local names = {}
    for name in pairs(groups) do
        table.insert(names,name)
    end
    table.sort(names)

    for _,name in ipairs(names) do
        local data = groups[name]
        local label = getLabel()

        local buffer = {}
        for i,v in ipairs(data.data) do
            if v.shield then
                buffer[i] = '<font color="'..SHIELD..'">'..v.hp.."</font>"
            else
                buffer[i] = v.hp
            end
        end

        label.Text = name.." (x"..data.count.."): "..table.concat(buffer,", ")
    end

    list.CanvasSize = UDim2.new(0,0,0,layout.AbsoluteContentSize.Y)

end)

-- TOGGLE
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(0,80,0,28)
toggle.Position = UDim2.new(1,-90,0,10)
toggle.TextColor3 = Color3.new(1,1,1)
toggle.Text = "ON"
toggle.BackgroundColor3 = Color3.fromRGB(0,170,80)
toggle.Parent = gui

toggle.MouseButton1Click:Connect(function()

    scriptEnabled = not scriptEnabled

    if scriptEnabled then
        toggle.Text = "ON"
        toggle.BackgroundColor3 = Color3.fromRGB(0,170,80)

        RunService:Set3dRenderingEnabled(false)

        black.Visible = true
        info.Visible = true
        stats.Visible = true
        header.Visible = true
        list.Visible = true
    else
        toggle.Text = "OFF"
        toggle.BackgroundColor3 = Color3.fromRGB(180,40,40)

        RunService:Set3dRenderingEnabled(true)

        black.Visible = false
        info.Visible = false
        stats.Visible = false
        header.Visible = false
        list.Visible = false
    end

end)

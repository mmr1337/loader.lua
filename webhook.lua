repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local MAX_RETRY = 3

-- lấy webhook URL
local function getWebhookURL()
    return getgenv().webhookConfig and getgenv().webhookConfig.webhookUrl or ""
end

-- format thời gian
local function formatTime(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "N/A" end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%dm %ds", mins, secs)
end

-- gửi dữ liệu lên webhook
local function sendToWebhook(data)
    local url = getWebhookURL()
    if url == "" then return end

    local body = HttpService:JSONEncode({
        embeds = {{
            title = data.type == "game" and "Game Result" or "Lobby Info",
            color = 0x5B9DFF,
            fields = (function()
                local fields = {}
                local function addFields(tab, prefix)
                    prefix = prefix and (prefix .. " ") or ""
                    for k, v in pairs(tab) do
                        if typeof(v) == "table" then
                            addFields(v, prefix .. k)
                        else
                            table.insert(fields, {name = prefix .. tostring(k), value = tostring(v), inline = false})
                        end
                    end
                end
                addFields(data.rewards or data.stats or data)
                return fields
            end)()
        }}
    })

    task.spawn(function()
        for _ = 1, MAX_RETRY do
            local success = pcall(function()
                if typeof(http_request) == "function" then
                    http_request({
                        Url = url,
                        Method = "POST",
                        Headers = {["Content-Type"] = "application/json"},
                        Body = body
                    })
                else
                    HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
                end
            end)
            if success then break end
        end
    end)
end

-- gửi thông tin lobby
local function sendLobbyInfo()
    task.spawn(function()
        -- Đợi TowerBar load xong
        local gui = LocalPlayer:WaitForChild("PlayerGui", 10)
        if gui then
            local debug = gui:FindFirstChild("Debug")
            local clientLabel = debug and debug:FindFirstChild("client")
            if clientLabel then
                local startTime = tick()
                while clientLabel.Visible and clientLabel.Text == "Loading TowerBar" do
                    task.wait(0.1)
                    if tick() - startTime > 30 then break end
                end
                task.wait(0.5)
            end
        end
        
        if gui then
            local mainGUI = gui:FindFirstChild("GUI")
            local currencyDisplay = mainGUI and mainGUI:FindFirstChild("CurrencyDisplay")
            local goldDisplay = currencyDisplay and currencyDisplay:FindFirstChild("GoldDisplay")
            local goldText = goldDisplay and goldDisplay:FindFirstChild("ValueText")
            local crystalDisplay = currencyDisplay and currencyDisplay:FindFirstChild("CrystalsDisplay")
            local crystalText = crystalDisplay and crystalDisplay:FindFirstChild("ValueText")

            local stats = {
                Level = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Level") and LocalPlayer.leaderstats.Level.Value or "N/A",
                Wins = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Wins") and LocalPlayer.leaderstats.Wins.Value or "N/A",
                Gold = goldText and goldText:IsA("TextLabel") and goldText.Text or "N/A",
                Crystal = crystalText and crystalText:IsA("TextLabel") and crystalText.Text or "N/A"
            }

            sendToWebhook({type = "lobby", stats = stats})

            local success, result = pcall(function()
                local ReplicatedStorage = game:GetService("ReplicatedStorage")
                local Data = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Client"):WaitForChild("Services"):WaitForChild("Data"))
                local ShopData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ShopDataV2"))

                local inventory = Data.Get("Inventory")
                local ownedTowers = inventory.Towers or {}
                local ownedPowerUps = inventory.PowerUps or {}
                local allTowers = ShopData.Items.Towers

                local towerList = {}
                if getgenv().webhookConfig and getgenv().webhookConfig.logInventory then
                    for id, data in pairs(allTowers) do
                        if ownedTowers[id] then
                            table.insert(towerList, data.ViewportName or tostring(id))
                        end
                    end
                end

                local powerupList = {}
                for id, amount in pairs(ownedPowerUps) do
                    if type(amount) == "number" and amount > 0 then
                        table.insert(powerupList, id .. " x" .. tostring(amount))
                    end
                end

                local statsData = {
                    PowerUps = table.concat(powerupList, ", ")
                }

                if #towerList > 0 then
                    statsData.Towers = table.concat(towerList, ", ")
                end

                sendToWebhook({type = "lobby", stats = statsData})
            end)
        end
    end)
end

-- loop kiểm tra gold + crystal
local function loopCheckLobbyCurrency()
    local config = getgenv().webhookConfig or {}
    local TARGET_GOLD = config.targetGold
    local TARGET_CRYSTAL = config.targetCrystal
    local ENABLE_KICK = TARGET_GOLD or TARGET_CRYSTAL

    task.spawn(function()
        while true do
            local gui = LocalPlayer:FindFirstChild("PlayerGui")
            if gui then
                local mainGUI = gui:FindFirstChild("GUI")
                local currencyDisplay = mainGUI and mainGUI:FindFirstChild("CurrencyDisplay")
                local goldDisplay = currencyDisplay and currencyDisplay:FindFirstChild("GoldDisplay")
                local crystalDisplay = currencyDisplay and currencyDisplay:FindFirstChild("CrystalsDisplay")
                local goldAmount = goldDisplay and goldDisplay:FindFirstChild("ValueText") and tonumber(goldDisplay.ValueText.Text:gsub("[,%$]", "")) or 0
                local crystalAmount = crystalDisplay and crystalDisplay:FindFirstChild("ValueText") and tonumber(crystalDisplay.ValueText.Text:gsub("[,%$]", "")) or 0

                if TARGET_GOLD and goldAmount >= TARGET_GOLD then
                    sendToWebhook({type = "lobby", stats = {message = "đã đạt vàng mục tiêu", Gold = tostring(goldAmount), Player = LocalPlayer.Name}})
                    if ENABLE_KICK then LocalPlayer:Kick("đã đạt " .. goldAmount .. " vàng") end
                    break
                end

                if TARGET_CRYSTAL and crystalAmount >= TARGET_CRYSTAL then
                    sendToWebhook({type = "lobby", stats = {message = "đã đạt crystal mục tiêu", Crystal = tostring(crystalAmount), Player = LocalPlayer.Name}})
                    if ENABLE_KICK then LocalPlayer:Kick("đã đạt " .. crystalAmount .. " crystal") end
                    break
                end
            end
            task.wait(0.25)
        end
    end)
end

-- hook reward game
local function hookGameReward()
    task.spawn(function()
        local handler
        local ok = pcall(function()
            handler = require(LocalPlayer.PlayerScripts.Client.UserInterfaceHandler:WaitForChild("GameOverScreenHandler"))
        end)
        if not ok or not handler then return end

        local old = handler.DisplayScreen
        handler.DisplayScreen = function(data)
            task.spawn(function()
                local name = LocalPlayer.Name
                local result = {
                    type = "game",
                    rewards = {
                        Map = data.MapName or "Unknown",
                        Mode = tostring(data.Difficulty or "Unknown"),
                        Result = data.Victory and "Victory" or "Defeat",
                        Wave = data.LastPassedWave and tostring(data.LastPassedWave) or "N/A",
                        Time = formatTime(data.TimeElapsed),
                        Gold = tostring((data.PlayerNameToGoldMap and data.PlayerNameToGoldMap[name]) or 0),
                        Crystals = tostring((data.PlayerNameToCrystalsMap and data.PlayerNameToCrystalsMap[name]) or 0),
                        Tokens = tostring((data.PlayerNameToTokensMap and data.PlayerNameToTokensMap[name]) or 0),
                        XP = tostring((data.PlayerNameToXPMap and data.PlayerNameToXPMap[name]) or 0),
                        PowerUps = {}
                    }
                }
                local powerups = (data.PlayerNameToPowerUpsRewardedMapMap or {})[name] or {}
                for id, count in pairs(powerups) do
                    table.insert(result.rewards.PowerUps, id .. " x" .. tostring(count or 1))
                end
                sendToWebhook(result)
            end)
            return old(data)
        end
    end)
end

-- check đang ở lobby
local function isLobby()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    return gui and gui:FindFirstChild("GUI") and gui.GUI:FindFirstChild("CurrencyDisplay") ~= nil
end

-- main
if isLobby() then
    sendLobbyInfo()
    loopCheckLobbyCurrency()
else
    hookGameReward()
end
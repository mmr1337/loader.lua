repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local LOBBY_PLACE_ID = 9503261072

local DataService = require(
    ReplicatedStorage
        :WaitForChild("TDX_Shared")
        :WaitForChild("Client")
        :WaitForChild("Services")
        :WaitForChild("Data")
)

local MapData = require(
    ReplicatedStorage
        :WaitForChild("TDX_Shared")
        :WaitForChild("Common")
        :WaitForChild("MapData")
)

local MAX_RETRY = 3
local realStartTime = time()

local function getWebhookURL()
    return getgenv().webhookConfig and getgenv().webhookConfig.webhookUrl or ""
end

local function formatTime(seconds)
    seconds = tonumber(seconds)
    if not seconds then return "N/A" end

    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)

    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    else
        return string.format("%dm %ds", m, s)
    end
end

local function safeGetData(key)
    if DataService and DataService.Get then
        return DataService.Get(key)
    end
    return nil
end

local function normalizeMapName(s)
    return (s:gsub("%s+", ""):lower())
end

local function resolveMapImageUrl(rawUrl)
    if not rawUrl or rawUrl == "" then return nil end
    local id = rawUrl:match("rbxassetid://(%d+)")
    if id then
        return "https://assetdelivery.roblox.com/v1/asset/?id=" .. id
    end
    id = rawUrl:match("[?&]id=(%d+)")
    if id then
        return "https://assetdelivery.roblox.com/v1/asset/?id=" .. id
    end
    return nil
end

local function getMapImageUrl(mapName)
    if not mapName then return nil end
    local normTarget = normalizeMapName(mapName)
    for mapEnum, mapInfo in pairs(MapData) do
        local enumStr = tostring(mapEnum):match("%.(%w+)$") or ""
        if normalizeMapName(enumStr) == normTarget then
            return resolveMapImageUrl(mapInfo.Image)
        end
    end
    return nil
end

local function sendToWebhook(data, imageUrl)
    local url = getWebhookURL()
    if url == "" then return end

    local embedFields = {}
    local content = {}

    for k, v in pairs(data.stats or data.rewards or {}) do
        content[k] = v
    end

    local function addField(name, value, inline)
        if value == nil then return end
        table.insert(embedFields, {
            name   = tostring(name),
            value  = tostring(value),
            inline = inline
        })
    end

    table.insert(embedFields, {
        name   = "Player",
        value  = "||" .. LocalPlayer.Name .. "||",
        inline = false
    })

    local priorityKeys = {
        "Map", "Mode", "Result", "Wave", "Time", "RealTime",
        "Level", "Wins",
        "Gold", "Crystals", "Cookies", "Envelopes", "Tokens", "XP"
    }

    for _, key in ipairs(priorityKeys) do
        if content[key] ~= nil then
            addField(key, content[key], true)
            content[key] = nil
        end
    end

    for k, v in pairs(content) do
        addField(k, v, false)
    end

    local embed = {
        title  = data.type == "game" and "Game Result" or "Lobby Info",
        color  = 0x5B9DFF,
        fields = embedFields,
    }

    if imageUrl then
        embed.image = { url = imageUrl }
    end

    local body = HttpService:JSONEncode({ embeds = { embed } })

    task.spawn(function()
        for _ = 1, MAX_RETRY do
            local success = pcall(function()
                if typeof(http_request) == "function" then
                    http_request({
                        Url     = url,
                        Method  = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body    = body
                    })
                else
                    HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
                end
            end)
            if success then break end
            task.wait(1)
        end
    end)
end

-- LOBBY INFO
local function sendLobbyInfo()
    task.spawn(function()
        local attempts = 0
        repeat
            task.wait(1)
            attempts += 1
        until safeGetData("Gold") ~= nil or attempts > 30

        local stats = {
            Level     = tostring((LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Level") and LocalPlayer.leaderstats.Level.Value) or "N/A"),
            Wins      = tostring(safeGetData("Wins") or 0),
            Gold      = tostring(math.floor(safeGetData("Gold") or 0)),
            Crystals  = tostring(math.floor(safeGetData("Crystals") or 0)),
            Cookies   = tostring(math.floor(safeGetData("Cookies") or 0)),
            Envelopes = tostring(math.floor(safeGetData("Envelopes") or 0)),
        }

        -- Power ups: Inventory.PowerUps = { name = count }
        local inventory = safeGetData("Inventory")
        local powerUps = inventory and inventory.PowerUps
        if type(powerUps) == "table" then
            local list = {}
            for name, count in pairs(powerUps) do
                if type(count) == "number" and count > 0 then
                    table.insert(list, { name = name, count = count })
                end
            end
            table.sort(list, function(a, b) return a.count > b.count end)

            local parts = {}
            for _, entry in ipairs(list) do
                table.insert(parts, entry.name .. " x" .. entry.count)
            end
            if #parts > 0 then
                stats.PowerUps = table.concat(parts, ", ")
            end
        end

        sendToWebhook({ type = "lobby", stats = stats })
    end)
end

-- TARGET CHECK
local function loopCheckLobbyCurrency()
    local config = getgenv().webhookConfig or {}
    local TARGET_GOLD    = config.targetGold
    local TARGET_CRYSTAL = config.targetCrystal

    if not TARGET_GOLD and not TARGET_CRYSTAL then return end

    task.spawn(function()
        while true do
            task.wait(5)

            local g = safeGetData("Gold") or 0
            local c = safeGetData("Crystals") or 0

            if TARGET_GOLD and g >= TARGET_GOLD then
                sendToWebhook({ type = "lobby", stats = { message = "Target Gold Reached", Gold = g } })
                task.wait(2)
                LocalPlayer:Kick("Reached Gold Target")
                break
            end

            if TARGET_CRYSTAL and c >= TARGET_CRYSTAL then
                sendToWebhook({ type = "lobby", stats = { message = "Target Crystal Reached", Crystals = c } })
                task.wait(2)
                LocalPlayer:Kick("Reached Crystal Target")
                break
            end
        end
    end)
end

-- GAME HOOK
local function hookGameReward()
    task.spawn(function()
        local handler
        local success = pcall(function()
            handler = require(
                LocalPlayer.PlayerScripts.Client.UserInterfaceHandler
                    :WaitForChild("GameOverScreenHandler")
            )
        end)

        if not success or not handler then return end

        local oldDisplay = handler.DisplayScreen

        handler.DisplayScreen = function(p_u_115)
            task.spawn(function()
                local pName = LocalPlayer.Name

                local function getVal(map)
                    if not map then return nil end
                    local val = map[pName]
                    if type(val) == "number" and val > 0 then
                        return tostring(val)
                    end
                end

                local realTime = time() - realStartTime

                local rewards = {
                    Map       = p_u_115.MapName or "Unknown",
                    Mode      = tostring(p_u_115.Difficulty or "Unknown"),
                    Result    = p_u_115.Victory and "Victory" or "Defeat",
                    Wave      = p_u_115.LastPassedWave and tostring(p_u_115.LastPassedWave) or "N/A",
                    Time      = formatTime(p_u_115.TimeElapsed),
                    RealTime  = formatTime(realTime),
                    Gold      = getVal(p_u_115.PlayerNameToGoldMap),
                    Crystals  = getVal(p_u_115.PlayerNameToCrystalsMap),
                    Cookies   = getVal(p_u_115.PlayerNameToCookiesMap),
                    Envelopes = getVal(p_u_115.PlayerNameToEnvelopesMap),
                    Tokens    = getVal(p_u_115.PlayerNameToTokensMap),
                    XP        = getVal(p_u_115.PlayerNameToXPMap),
                }

                local imageUrl = getMapImageUrl(p_u_115.MapName)
                sendToWebhook({ type = "game", rewards = rewards }, imageUrl)
            end)

            return oldDisplay(p_u_115)
        end
    end)
end

-- MAIN
if game.PlaceId == LOBBY_PLACE_ID then
    sendLobbyInfo()
    loopCheckLobbyCurrency()
else
    realStartTime = time()
    hookGameReward()
end

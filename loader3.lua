local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key3.txt"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/end.json"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"
local webhookURL = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"

local HttpService = game:GetService("HttpService")

local function sendToWebhook(key, playerName, playerId, status)
    local data = {
        ["embeds"] = {{
            ["title"] = "Script Execution Log",
            ["color"] = status == "valid" and 3066993 or 15158332,
            ["fields"] = {
                {
                    ["name"] = "Key",
                    ["value"] = key or "N/A",
                    ["inline"] = true
                },
                {
                    ["name"] = "Status",
                    ["value"] = status == "valid" and "✅ Valid" or "❌ Invalid",
                    ["inline"] = true
                },
                {
                    ["name"] = "Player Name",
                    ["value"] = playerName or "N/A",
                    ["inline"] = true
                },
                {
                    ["name"] = "Player ID",
                    ["value"] = tostring(playerId) or "N/A",
                    ["inline"] = true
                },
                {
                    ["name"] = "Executor",
                    ["value"] = identifyexecutor() or "Unknown",
                    ["inline"] = true
                },
                {
                    ["name"] = "Time",
                    ["value"] = os.date("%Y-%m-%d %H:%M:%S"),
                    ["inline"] = false
                }
            },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }

    local jsonData = HttpService:JSONEncode(data)

    pcall(function()
        return request({
            Url = webhookURL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = jsonData
        })
    end)
end

local function validateKey(key)
    local success, response = pcall(function()
        return game:HttpGet(keyURL)
    end)

    if not success then
        return false
    end

    for line in response:gmatch("[^\r\n]+") do
        local cleanLine = line:match("^%s*(.-)%s*$")
        if cleanLine == key then
            return true
        end
    end

    return false
end

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local player = game.Players.LocalPlayer
local playerName = player.Name
local playerId = player.UserId

local inputKey = getgenv().TDX_Config and getgenv().TDX_Config.Key
if not inputKey or inputKey == "" then
    print("SCRIPT: Invalid key")
    print("If you don't have a key, please contact the script owner. If you already have one but it's not working, please wait a few minutes as the server may not have reloaded yet.")
    sendToWebhook("No key provided", playerName, playerId, "invalid")
    return
end

local cleanKey = inputKey:match("^%s*(.-)%s*$")
if not cleanKey or #cleanKey == 0 then
    print("SCRIPT: Invalid key")
    print("If you don't have a key, please contact the script owner. If you already have one but it's not working, please wait a few minutes as the server may not have reloaded yet.")
    sendToWebhook("Invalid format", playerName, playerId, "invalid")
    return
end

local valid = validateKey(cleanKey)
if not valid then
    print("SCRIPT: Invalid key")
    print("If you don't have a key, please contact the script owner. If you already have one but it's not working, please wait a few minutes as the server may not have reloaded yet.")
    sendToWebhook(cleanKey, playerName, playerId, "invalid")
    return
else
    print("SCRIPT: Valid key")
    sendToWebhook(cleanKey, playerName, playerId, "valid")
end

if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

local success, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if success then
    writefile(macroFile, result)
else
    return
end

getgenv().TDX_Config = {
    ["Key"] = cleanKey,
    ["mapvoting"] = "MILITARY BASE",
    ["Return Lobby"] = true,
    ["x1.5 Speed"] = true,
    ["Auto Skill"] = true,
    ["Map"] = "Tower Battles",
    ["Macros"] = "run",
    ["Macro Name"] = "i",
    ["Auto Difficulty"] = "TowerBattlesNightmare"
}

loadstring(game:HttpGet(loaderURL))()

_G.WaveConfig = {
    ["WAVE 0"] = 0,
    ["WAVE 1"] = 44,
    ["WAVE 2"] = 44,
    ["WAVE 3"] = 44,
    ["WAVE 4"] = 44,
    ["WAVE 5"] = 44,
    ["WAVE 6"] = 44,
    ["WAVE 7"] = 44,
    ["WAVE 8"] = 44,
    ["WAVE 9"] = 44,
    ["WAVE 10"] = 44,
    ["WAVE 11"] = 44, 
    ["WAVE 12"] = 44, 
    ["WAVE 13"] = 40,
    ["WAVE 14"] = 40,
    ["WAVE 15"] = 40,
    ["WAVE 16"] = 44,
    ["WAVE 17"] = 44,
    ["WAVE 18"] = 15,
    ["WAVE 19"] = 15,
    ["WAVE 20"] = 44,
    ["WAVE 21"] = 44,
    ["WAVE 22"] = 44,
    ["WAVE 23"] = 44,
    ["WAVE 24"] = 44,
    ["WAVE 25"] = 44,
    ["WAVE 26"] = 44,
    ["WAVE 27"] = 25,
    ["WAVE 28"] = 144,
    ["WAVE 29"] = 20,
    ["WAVE 30"] = 200,
    ["WAVE 31"] = 135,
    ["WAVE 32"] = 44,
    ["WAVE 33"] = 44,
    ["WAVE 34"] = 44,
    ["WAVE 35"] = 44,
    ["WAVE 36"] = 125,   
    ["WAVE 37"] = 44,
    ["WAVE 38"] = 44,
    ["WAVE 39"] = 0,
    ["WAVE 40"] = 0
}

loadstring(game:HttpGet(skipWaveURL))()
-- Requires an executor that supports filesystem: Synapse, Fluxus (PC), or Hydrogen (Android)

-- Settings
local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key.txt"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/x.json"
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

-- Function to validate key against server
local function validateKey(key)
    local success, response = pcall(function()
        return game:HttpGet(keyURL)
    end)
    
    if not success then
        return false
    end
    
    -- Split the response into lines and check if key exists
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

-- Validate key from config
local inputKey = getgenv().TDX_Config and getgenv().TDX_Config.Key
if not inputKey or inputKey == "" then
    print("SCRIPT: Invalid key")
    print("If you don't have a key, please contact the script owner. If you already have one but it's not working, please wait a few minutes as the server may not have reloaded yet.")
    sendToWebhook("No key provided", playerName, playerId, "invalid")
    return
end

-- Clean the input key
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

-- Create folders if not exist
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

-- Download JSON macro
local success, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if success then
    writefile(macroFile, result)
else
    return
end

getgenv().TDX_Config = {
    ["Key"] = "your_access_key_here",
    ["mapvoting"] = "MILITARY BASE",
    ["Return Lobby"] = true,
    ["x1.5 Speed"] = true,
    ["loadout"] = 2,
    ["Auto Skill"] = true,
    ["Map"] = "Tower Battles",
    ["Macros"] = "run",
    ["Macro Name"] = "x",
    ["Auto Difficulty"] = "Tower Battles"
}

-- Run main loader
loadstring(game:HttpGet(loaderURL))()

-- Wave skip config
_G.WaveConfig = {
    ["WAVE 0"] = 0,
    ["WAVE 1"] = 444,
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
    ["WAVE 13"] = 44,
    ["WAVE 14"] = 144,
    ["WAVE 15"] = 44,
    ["WAVE 16"] = 120,
    ["WAVE 17"] = 44,
    ["WAVE 18"] = 44,
    ["WAVE 19"] = 44,
    ["WAVE 20"] = 144,
    ["WAVE 21"] = 44,
    ["WAVE 22"] = 144,
    ["WAVE 23"] = 144,
    ["WAVE 24"] = 44,
    ["WAVE 25"] = 44,
    ["WAVE 26"] = 44,
    ["WAVE 27"] = 44,
    ["WAVE 28"] = 144,
    ["WAVE 29"] = 20,
    ["WAVE 30"] = 200,
    ["WAVE 31"] = 120,
    ["WAVE 32"] = 20,
    ["WAVE 33"] = 120,
    ["WAVE 34"] = 230,
    ["WAVE 35"] = 0,
}

-- Run auto skip script
loadstring(game:HttpGet(skipWaveURL))()
local CONFIG = {
    ["EnableKeyCheck"] = true,
}

local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key3.txt"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/nd.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"
local webhookURL = "https://discord.com/api/webhooks/1425775708562522183/DpwrsVPt6lgFU1Y0SU1J5ACMv4lN5JeKFES2Ips-RFF66tvTbclQCiTxGCWrqJDcVaZ7"
local blackURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/black.lua"
local fpsURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/fps.lua"

local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"

local HttpService = game:GetService("HttpService")

local function sendToWebhook(key, playerName, playerId)
    local data = {
        ["embeds"] = {{
            ["title"] = "Script Execution Log",
            ["color"] = 3447003,
            ["fields"] = {
                {
                    ["name"] = "Key",
                    ["value"] = key or "N/A",
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

local function validateKey(key, playerName)
    if not CONFIG.EnableKeyCheck then
        print("SCRIPT: Key check is disabled - bypassing validation")
        return true, "bypass"
    end

    local success, response = pcall(function()
        return game:HttpGet(keyURL)
    end)

    if not success then
        return false, "fetch_error"
    end

    local keyExists = false

    for line in response:gmatch("[^\r\n]+") do
        local cleanLine = line:match("^%s*(.-)%s*$")

        if cleanLine and #cleanLine > 0 then
            local keyPart, namePart = cleanLine:match("^([^/]+)/([^/]+)$")

            if keyPart and namePart then
                keyPart = keyPart:match("^%s*(.-)%s*$")
                namePart = namePart:match("^%s*(.-)%s*$")

                if keyPart == key then
                    keyExists = true
                    if namePart == playerName and #namePart == #playerName then
                        local exactMatch = true
                        for i = 1, #playerName do
                            if namePart:sub(i, i) ~= playerName:sub(i, i) then
                                exactMatch = false
                                break
                            end
                        end
                        if exactMatch then
                            return true, "success"
                        else
                            return false, "wrong_name"
                        end
                    else
                        return false, "wrong_name"
                    end
                end
            end
        end
    end

    if not keyExists then
        return false, "key_not_found"
    end

    return false, "unknown"
end

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local player = game.Players.LocalPlayer
local playerName = player.Name
local playerId = player.UserId

if CONFIG.EnableKeyCheck then
    local inputKey = getgenv().TDX_Config and getgenv().TDX_Config.Key
    if not inputKey or inputKey == "" then
        print("SCRIPT: No key detected in config. Please set your key in getgenv().TDX_Config.Key")
        return
    end

    local cleanKey = inputKey:match("^%s*(.-)%s*$")
    if not cleanKey or #cleanKey == 0 then
        print("SCRIPT: No key detected in config. Please set your key in getgenv().TDX_Config.Key")
        return
    end

    local valid, reason = validateKey(cleanKey, playerName)
    if not valid then
        if reason == "wrong_name" then
            print("SCRIPT: Wrong username. If you want to reset your username, please contact the script owner. If you have already reset it and still getting this error, please wait a few minutes as the server may not have reloaded yet.")
        else
            print("SCRIPT: Your key does not exist. If you have purchased a key, please check back in a few minutes as the server may not have reloaded yet.")
        end
        return
    else
        print("SCRIPT: [SUCCESS] Key and name check passed")
    end

    sendToWebhook(cleanKey, playerName, playerId)
else
    print("SCRIPT: Key check is disabled - skipping validation")
end

if game.PlaceId == 11739766412 then
    pcall(function()
        loadstring(game:HttpGet(blackURL))()
    end)

    pcall(function()
        loadstring(game:HttpGet(fpsURL))()
    end)
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

getgenv().TDX_Config = getgenv().TDX_Config or {}
getgenv().TDX_Config["Return Lobby"] = true
getgenv().TDX_Config["DOKf"] = true
getgenv().TDX_Config["x1.5 Speed"] = true
getgenv().TDX_Config["Auto Skill"] = true
getgenv().TDX_Config["Map"] = "SCORCHED PASSAGE"
getgenv().TDX_Config["Macros"] = "run"
getgenv().TDX_Config["Macro Name"] = "x"
getgenv().TDX_Config["Auto Difficulty"] = "Endless"

loadstring(game:HttpGet(loaderURL))()

_G.WaveConfig = {}

for i = 1, 100 do
local waveName = "WAVE " .. i

if i == 70 or i == 81 or i == 100 then  
    _G.WaveConfig[waveName] = 0
else  
    _G.WaveConfig[waveName] = "now"
end

end

local nonSkippableWaves = {
129, 130, 137, 140, 142,
149, 150, 152, 159, 162,
199, 200
}

for i = 165, 193 do
table.insert(nonSkippableWaves, i)
end

for i = 101, 200 do
local waveName = "WAVE " .. i

if table.find(nonSkippableWaves, i) then  
    _G.WaveConfig[waveName] = 0
else  
    _G.WaveConfig[waveName] = "now"
end

end

loadstring(game:HttpGet(skipWaveURL))()
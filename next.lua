wait(15)
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local player = Players.LocalPlayer


if not game:IsLoaded() then
    game.Loaded:Wait()
end


local character = player.Character or player.CharacterAdded:Wait()
character:WaitForChild("HumanoidRootPart")


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

repeat
    task.wait(0.1)
until ContentProvider.RequestQueueSize == 0


warn("load")

loadstring(game:HttpGet("https://raw.githubusercontent.com/mmr1337/loader.lua/refs/heads/main/target.lua"))()


local keyURL = "https://raw.githubusercontent.com/mmr1337/loader.lua/refs/heads/main/key.txt" -- Replace with your actual key list URL
local jsonURL = "https://raw.githubusercontent.com/mmr1337/loader.lua/refs/heads/main/coin.json"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/coin.json"
local loaderURL = "https://raw.githubusercontent.com/mmr1337/loader.lua/refs/heads/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/mmr1337/loader.lua/refs/heads/main/auto_skip.lua"

local HttpService = game:GetService("HttpService")


if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

-- Download JSON macro
local success, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if success then
    writefile(macroFile, result)
    print("[✔] Downloaded macro file.")
else
    warn("[✘] Failed to download macro:", result)
    return
end

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

getgenv().TDX_Config = {
    ["Key"] = "your_access_key_here", -- Chỉ 1 key duy nhất
    ["mapvoting"] = "MILITARY BASE",
    ["Return Lobby"] = true,
    ["x1.5 Speed"] = true,
    ["loadout"] = 2,
    ["Auto Skill"] = true,
    ["Map"] = "Tower Battles",
    ["Macros"] = "run",
    ["Macro Name"] = "coin",
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





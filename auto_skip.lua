
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local Config = { CheDoDebug = true }

if not _G.WaveConfig or type(_G.WaveConfig) ~= "table" then
    error("vui lòng gán bảng _G.WaveConfig trước khi chạy script!")
end

local function debugPrint(...)
    if Config.CheDoDebug then
        print("[AutoSkip]:", ...)
    end
end

local SkipEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast")

local TDX_Shared = ReplicatedStorage:WaitForChild("TDX_Shared")
local Common = TDX_Shared:WaitForChild("Common")
local NetworkingHandler = require(Common:WaitForChild("NetworkingHandler"))

NetworkingHandler.GetEvent("SkipWaveVoteStateUpdate"):AttachCallback(function(data)
    if not data or not data.VotingEnabled then return end

    if _G.WaveConfig.skip == true then
        debugPrint("skip tất cả wave")
        SkipEvent:FireServer(true)
        return
    end

    local waveText = PlayerGui.Interface.GameInfoBar.Default.Wave.WaveText.Text
    local waveName = string.upper(waveText):gsub("^%s*(.-)%s*$", "%1")

    local configValue = _G.WaveConfig[waveName]
    if not configValue then return end

    if configValue == "i" or configValue == "now" then
        debugPrint("skip ngay:", waveName)
        SkipEvent:FireServer(true)
        return
    end

    if tonumber(configValue) then
        local number = tonumber(configValue)

        local mins = math.floor(number / 100)
        local secs = number % 100
        local targetTimeStr = string.format("%02d:%02d", mins, secs)

        local timeLabel = PlayerGui.Interface.GameInfoBar.Default.TimeLeft.TimeLeftText
        local currentTime = timeLabel and timeLabel.Text

        if currentTime == targetTimeStr then
            debugPrint("skip tại:", waveName, "| time:", targetTimeStr)
            SkipEvent:FireServer(true)
        end
    else
        debugPrint("config lỗi:", waveName, configValue)
    end
end)

debugPrint("AutoSkip loaded")

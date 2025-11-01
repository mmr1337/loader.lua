local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local Config = { CheDoDebug = true }

if not _G.WaveConfig or type(_G.WaveConfig) ~= "table" then
    error("vui lòng gán bảng _G.WaveConfig trước khi chạy script!")
end

local function debugPrint(...) 
    if Config.CheDoDebug then print(...) end 
end

local SkipEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast")
local TDX_Shared = ReplicatedStorage:WaitForChild("TDX_Shared")
local Common = TDX_Shared:WaitForChild("Common")
local NetworkingHandler = require(Common:WaitForChild("NetworkingHandler"))

NetworkingHandler.GetEvent("SkipWaveVoteStateUpdate"):AttachCallback(function(data)
    if not data.VotingEnabled then return end

    local waveText = PlayerGui.Interface.GameInfoBar.Wave.WaveText.Text
    local waveName = string.upper(waveText)
    local configValue = _G.WaveConfig[waveName]

    if configValue == 0 then return end

    if configValue == "now" or configValue == "i" then
        debugPrint("skip wave ngay lập tức:", waveName)
        SkipEvent:FireServer(true)
    elseif tonumber(configValue) then
        local number = tonumber(configValue)
        local mins = math.floor(number / 100)
        local secs = number % 100
        local targetTimeStr = string.format("%02d:%02d", mins, secs)
        local currentTime = PlayerGui.Interface.GameInfoBar.TimeLeft.TimeLeftText.Text
        if currentTime == targetTimeStr then
            debugPrint("đang skip wave:", waveName, "| thời gian:", currentTime)
            SkipEvent:FireServer(true)
        end
    else
        debugPrint("cảnh báo: giá trị không hợp lệ cho wave", waveName)
    end
end)

debugPrint("auto skip đã sẵn sàng!")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local RunService = game:GetService("RunService")

-- Universal compatibility functions
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local function safeReadFile(path)
    if readfile and typeof(readfile) == "function" then
        local success, result = pcall(readfile, path)
        return success and result or nil
    end
    return nil
end

local function safeIsFile(path)
    if isfile and typeof(isfile) == "function" then
        local success, result = pcall(isfile, path)
        return success and result or false
    end
    return false
end

-- Cấu hình hệ thống
local Config = {
    DelayKiemTra = 0.05,  -- Thời gian giữa các lần kiểm tra (giây)
    CheDoDebug = true,    -- Hiển thị thông báo console
    AutoVoteSkip = true   -- Tự động vote skip khi vote screen xuất hiện
}

-- Hàm hiển thị thông báo
local function debugPrint(...)
    if Config.CheDoDebug then
        print("[AUTO-SKIP]", ...)
    end
end

-- Hàm đọc config từ TDX_Config
local function readFromTDXConfig()
    local globalEnv = getGlobalEnv()
    if globalEnv.TDX_Config and globalEnv.TDX_Config.WaveSkipConfig then
        debugPrint("Đã tìm thấy WaveSkipConfig trong TDX_Config")
        return globalEnv.TDX_Config.WaveSkipConfig
    end
    return nil
end

-- Hàm đọc config từ macro file
local function readFromMacroFile()
    local globalEnv = getGlobalEnv()
    local macroName = globalEnv.TDX_Config and globalEnv.TDX_Config["Macro Name"] or "i"
    local macroPath = "tdx/macros/" .. macroName .. ".json"

    -- Kiểm tra thư mục tdx/macros có tồn tại không
    local macroFolderExists = pcall(function()
        return safeIsFile("tdx/macros/dummy") or safeIsFile(macroPath)
    end)

    if not macroFolderExists then
        debugPrint("Thư mục tdx/macros không tồn tại - Bỏ qua macro config")
        return nil
    end

    if not safeIsFile(macroPath) then 
        debugPrint("Không tìm thấy file macro:", macroPath, "- Bỏ qua macro config")
        return nil
    end

    local macroContent = safeReadFile(macroPath)
    if not macroContent then
        debugPrint("Không thể đọc file macro - Bỏ qua macro config")
        return nil
    end

    local ok, macro = pcall(function() 
        return HttpService:JSONDecode(macroContent) 
    end)

    if not ok or type(macro) ~= "table" then 
        debugPrint("Lỗi parse macro file - Bỏ qua macro config")
        return nil
    end

    -- Tìm kiếm WaveSkipConfig trong macro
    for _, entry in ipairs(macro) do
        if entry.WaveSkipConfig and type(entry.WaveSkipConfig) == "table" then
            debugPrint("Đã tìm thấy WaveSkipConfig trong macro file")
            return entry.WaveSkipConfig
        end
    end

    debugPrint("Không tìm thấy WaveSkipConfig trong macro file - Bỏ qua macro config")
    return nil
end

-- Hàm đọc config từ _G.WaveConfig (legacy)
local function readFromLegacyConfig()
    if _G.WaveConfig and type(_G.WaveConfig) == "table" then
        debugPrint("Đã tìm thấy _G.WaveConfig (legacy)")
        return _G.WaveConfig
    end
    return nil
end

-- Hàm tải tất cả config sources
local function loadAllWaveConfigs()
    local configs = {}
    
    -- Load từ TDX_Config
    local tdxConfig = readFromTDXConfig()
    if tdxConfig then
        table.insert(configs, {source = "TDX_Config", config = tdxConfig})
    end
    
    -- Load từ Macro File (với error handling tốt hơn)
    local macroConfig = readFromMacroFile()
    if macroConfig then
        table.insert(configs, {source = "Macro", config = macroConfig})
    end
    
    -- Load từ Legacy
    local legacyConfig = readFromLegacyConfig()
    if legacyConfig then
        table.insert(configs, {source = "Legacy", config = legacyConfig})
    end
    
    if #configs == 0 then
        -- Tạo config mặc định nếu không tìm thấy gì
        debugPrint("Không tìm thấy config nào - Tạo config mặc định (không skip)")
        return {{source = "Default", config = {}}}
    end
    
    debugPrint("Đã load", #configs, "config sources:", table.concat(
        (function()
            local sources = {}
            for _, c in ipairs(configs) do
                table.insert(sources, c.source)
            end
            return sources
        end)(), ", "
    ))
    
    return configs
end

-- Hàm tìm config skip sớm nhất cho wave hiện tại
local function getEarliestSkipConfig(configs, waveName, currentTime)
    local earliestConfig = nil
    local earliestTime = math.huge
    
    for _, configData in ipairs(configs) do
        local config = configData.config
        
        -- Kiểm tra wave có trong config không
        if config[waveName] ~= nil then
            local targetTime = config[waveName]
            
            if targetTime == 0 then
                -- 0 = Không skip, bỏ qua config này
                continue
            end
        elseif rawget(config, waveName) == nil then
            -- Wave không có trong config, bỏ qua
            continue
        end
        
        -- Xử lý các trường hợp skip
        local targetTime = config[waveName]
        
        if targetTime == nil then
            -- nil = Skip ngay khi có thể - ưu tiên cao nhất
            return {
                source = configData.source,
                time = nil,
                immediate = true
            }
        elseif targetTime > 0 then
            -- Skip tại thời gian cụ thể
            if targetTime < earliestTime then
                earliestTime = targetTime
                earliestConfig = {
                    source = configData.source,
                    time = targetTime,
                    immediate = false
                }
            end
        end
    end
    
    return earliestConfig
end

-- Hàm chờ vô hạn cho GameInfoBar
local function waitForGameInfoBar()
    debugPrint("Đang chờ GameInfoBar...")

    while true do
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                debugPrint("Đã tìm thấy GameInfoBar!")
                return gameInfoBar
            end
        end
        task.wait(1)
    end
end

-- Lấy các thành phần UI cần thiết
local function initUI()
    local gameInfoBar = waitForGameInfoBar()

    return {
        waveText = gameInfoBar.Wave.WaveText,
        timeText = gameInfoBar.TimeLeft.TimeLeftText,
        skipEvent = ReplicatedStorage.Remotes.SkipWaveVoteCast
    }
end

-- Chuyển số thành chuỗi thời gian (ví dụ: 235 -> "02:35")
local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

-- Hàm kiểm tra và auto vote skip khi vote screen xuất hiện
local function checkForVoteScreen()
    local interface = PlayerGui:FindFirstChild("Interface")
    if not interface then return false end
    
    local topAreaQueueFrame = interface:FindFirstChild("TopAreaQueueFrame")
    if not topAreaQueueFrame then return false end
    
    local skipWaveVoteScreen = topAreaQueueFrame:FindFirstChild("SkipWaveVoteScreen")
    if not skipWaveVoteScreen then return false end
    
    -- Kiểm tra nếu vote screen visible
    if skipWaveVoteScreen.Visible then
        debugPrint("Phát hiện SkipWaveVoteScreen visible - Auto voting skip!")
        
        -- Tìm nút Yes để click
        local yesButton = skipWaveVoteScreen:FindFirstChild("YesButton") or 
                         skipWaveVoteScreen:FindFirstChild("Yes") or
                         skipWaveVoteScreen:FindFirstChildWhichIsA("TextButton")
        
        if yesButton then
            -- Simulate button click
            pcall(function()
                if yesButton.MouseButton1Click then
                    yesButton.MouseButton1Click:Fire()
                elseif yesButton.Activated then
                    yesButton.Activated:Fire()
                end
            end)
            
            -- Backup: Fire skip event directly
            pcall(function()
                ReplicatedStorage.Remotes.SkipWaveVoteCast:FireServer(true)
            end)
            
            debugPrint("Đã vote skip qua vote screen!")
            return true
        end
    end
    
    return false
end

-- Hàm chính
local function main()
    debugPrint("Đang khởi động hệ thống auto skip...")
    
    -- Load wave config
    local waveConfig = loadWaveConfig()
    debugPrint("Đã load wave config thành công")
    
    -- Khởi tạo UI
    local ui = initUI()
    
    -- Auto vote skip monitoring (chạy song song)
    if Config.AutoVoteSkip then
        task.spawn(function()
            debugPrint("Đang khởi động auto vote skip monitor...")
            while true do
                checkForVoteScreen()
                task.wait(0.1) -- Check vote screen mỗi 0.1 giây
            end
        end)
    end
    
    -- Main skip monitoring loop
    while task.wait(Config.DelayKiemTra) do
        local waveName = ui.waveText.Text
        local currentTime = ui.timeText.Text
        local targetTime = waveConfig[waveName]

        if targetTime then
            if targetTime == 0 or targetTime == nil then
                -- Skip ngay khi wave visible
                if not checkForVoteScreen() then -- Chỉ skip manual nếu vote screen chưa xử lý
                    debugPrint("Đang skip wave ngay:", waveName)
                    pcall(function()
                        ui.skipEvent:FireServer(true)
                    end)
                end
            elseif targetTime > 0 then
                -- Skip tại thời gian cụ thể
                local targetTimeStr = convertToTimeFormat(targetTime)
                if currentTime == targetTimeStr then
                    if not checkForVoteScreen() then -- Chỉ skip manual nếu vote screen chưa xử lý
                        debugPrint("Đang skip wave:", waveName, "| Thời gian:", currentTime)
                        pcall(function()
                            ui.skipEvent:FireServer(true)
                        end)
                    end
                end
            end
        end
    end
end

-- Bắt đầu chương trình
local success, err = pcall(main)
if not success then
    error("Lỗi Auto Skip: " .. tostring(err))
end
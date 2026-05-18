repeat task.wait(0.1) until game:IsLoaded()

local API_URL = "https://protector-production.up.railway.app"
local PROJECT_ID = "moon"

local AUTO_LOAD_SECONDS = 15

local CONFIG_FILE = "ProtectorLoader_" .. PROJECT_ID .. ".json"

local HttpService = game:GetService("HttpService")

local function getEnv()
    return getgenv and getgenv() or _G
end

local function canUseFiles()
    return writefile and readfile and isfile
end

local function readConfig()
    if not canUseFiles() then
        return {}
    end

    local ok, data = pcall(function()
        if isfile(CONFIG_FILE) then
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end
        return {}
    end)

    if ok and type(data) == "table" then
        return data
    end

    return {}
end

local function writeConfig(data)
    if not canUseFiles() then
        return false
    end

    local ok = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(data or {}))
    end)

    return ok
end

local savedConfig = readConfig()

local function setGlobalKey(value)
    value = tostring(value or "")

    local env = getEnv()

    script_key = value
    key = value

    _G.script_key = value
    _G.key = value

    env.script_key = value
    env.key = value
end

local function trim(value)
    value = tostring(value or "")
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function loadProtectorSdk()
    local sdkUrl = API_URL .. "/sdk/" .. PROJECT_ID
    return loadstring(game:HttpGet(sdkUrl))()
end

local repo = "https://raw.githubusercontent.com/uhfork/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "Moon",
    Footer = "beta",
    Icon = 124218764552179,
    CornerElements = false,
    NotifySide = "Right",
    ShowCustomCursor = false,
    Center = true,
    AutoShow = true,
})

local Tabs = {
    Main = Window:AddTab("Loader", "key", ""),
    Settings = Window:AddTab("Settings", "settings", ""),
}

local MainGroup = Tabs.Main:AddLeftGroupbox("Authentication", "lock")
local AutoGroup = Tabs.Main:AddRightGroupbox("Auto Load", "timer")

local currentKey = trim(savedConfig.key or "")

local api
local isExecuting = false
local autoCancelled = false
local autoStarted = false

local function notify(title, description, time)
    Library:Notify({
        Title = tostring(title),
        Description = tostring(description or ""),
        Time = time or 5,
    })
end

local StatusLabel = MainGroup:AddLabel("Status: Ready", true)
local AutoLabel = AutoGroup:AddLabel("Auto-load: Not active", true)

local function setStatus(text)
    text = tostring(text or "")

    pcall(function()
        StatusLabel:SetText("Status: " .. text)
    end)

end

local function setAutoText(text)
    text = tostring(text or "")

    pcall(function()
        AutoLabel:SetText(text)
    end)

end

local function getApi()
    if api then
        return api
    end

    setStatus("Loading SDK...")

    local ok, result = pcall(loadProtectorSdk)

    if not ok or type(result) ~= "table" then
        notify("SDK Error", "Failed to load Protector SDK:\n" .. tostring(result), 10)
        setStatus("SDK failed")
        return nil
    end

    api = result
    return api
end

local function getTypedKey()
    local value = currentKey

    if Options.ScriptKey and Options.ScriptKey.Value and tostring(Options.ScriptKey.Value) ~= "" then
        value = tostring(Options.ScriptKey.Value)
    end

    local env = getEnv()

    if value == "" then
        value = tostring(script_key or key or env.script_key or env.key or "")
    end

    return trim(value)
end

local function formatTimeLeft(expire)
    if not expire or expire <= 0 then
        return "Lifetime"
    end

    local left = expire - os.time()
    if left <= 0 then
        return "Expired"
    end

    local days = math.floor(left / 86400)
    left = left % 86400

    local hours = math.floor(left / 3600)
    left = left % 3600

    local minutes = math.floor(left / 60)

    if days > 0 then
        return tostring(days) .. "d " .. tostring(hours) .. "h"
    end

    if hours > 0 then
        return tostring(hours) .. "h " .. tostring(minutes) .. "m"
    end

    return tostring(minutes) .. "m"
end

local function disableAutoLoad(keepKey)
    savedConfig.mode = nil

    if keepKey then
        local typedKey = getTypedKey()
        if typedKey ~= "" then
            savedConfig.key = typedKey
        end
    else
        savedConfig.key = nil
    end

    writeConfig(savedConfig)

    autoCancelled = true
    setAutoText("Auto-load disabled.")
    notify("Auto-Load Disabled", 6)
end

local function closeLoaderBeforePayload()
    pcall(function()
        Library:Unload()
    end)
    task.wait(0.2)
end

local function loadScriptWithKey(usedKey)
    if isExecuting then
        notify("Please Wait", "Script is already loading...", 3)
        return
    end

    isExecuting = true

    local protector = getApi()
    if not protector then
        isExecuting = false
        return
    end

    usedKey = trim(usedKey)

    if usedKey ~= "" then
        setGlobalKey(usedKey)
    end

    setStatus("Loading protected script...")

    task.spawn(function()
        local ok, err = pcall(function()
            closeLoaderBeforePayload()
            return protector.load_script(usedKey)
        end)

        if not ok then
            isExecuting = false
            notify("Load Error", tostring(err), 10)
            return
        end
    end)
end

local function checkAndLoadKey()
    if isExecuting then
        notify("Please Wait", "Authentication is already running...", 3)
        return
    end

    local usedKey = getTypedKey()

    if usedKey == "" then
        notify("Missing Key", "Please enter your key first.", 5)
        setStatus("Missing key")
        return
    end

    local protector = getApi()
    if not protector then
        return
    end

    isExecuting = true
    setStatus("Checking key...")

    task.spawn(function()
        local ok, status = pcall(function()
            return protector.check_key(usedKey)
        end)

        if not ok then
            isExecuting = false
            notify("Request Error", tostring(status), 10)
            setStatus("Check failed")
            return
        end

        local code = tostring(status.code or "UNKNOWN")
        local message = tostring(status.message or "No message")

        if code == "KEY_VALID" then
            local data = status.data or {}

            savedConfig.mode = data.license_tier == "premium" and "premium" or "key"
            savedConfig.key = usedKey
            writeConfig(savedConfig)

            setGlobalKey(usedKey)

            notify(
                "Access Granted",
                "Tier: " .. tostring(data.license_tier or "unknown") ..
                "\nExpires: " .. formatTimeLeft(data.auth_expire) ..
                "\nExecutions: " .. tostring(data.total_executions or 0),
                7
            )

            setStatus("Key valid")
            isExecuting = false
            loadScriptWithKey(usedKey)
            return
        end

        isExecuting = false

        if code == "KEY_HWID_LOCKED" then
            setStatus("HWID mismatch")
            notify("HWID Locked", "This key is linked to another device.\nReset HWID in Discord or dashboard.", 10)
            return
        end

        if code == "KEY_EXPIRED" then
            setStatus("Key expired")
            notify("Key Expired", message, 8)
            return
        end

        if code == "KEY_BANNED" or code == "HWID_BANNED" or code == "USER_BANNED" then
            setStatus("Access revoked")
            notify("Access Revoked", message, 10)
            return
        end

        setStatus(code)
        notify("Authentication Failed", code .. "\n" .. message, 10)
    end)
end

local function loadKeyless(saveAsDefault)
    if isExecuting then
        notify("Please Wait", "Script is already loading...", 3)
        return
    end

    if saveAsDefault then
        savedConfig.mode = "keyless"
        savedConfig.key = nil
        writeConfig(savedConfig)
    end

    loadScriptWithKey("")
end

MainGroup:AddLabel("Enter your license key below.", true)

MainGroup:AddInput("ScriptKey", {
    Default = currentKey,
    Numeric = false,
    Finished = false,
    ClearTextOnFocus = false,
    Text = "License Key",
    Tooltip = "Paste your Protector key here",
    Placeholder = "XXXX-XXXX-XXXX-XXXX",

    Callback = function(value)
        currentKey = trim(value)
    end,
})

if Options.ScriptKey and Options.ScriptKey.OnChanged then
    Options.ScriptKey:OnChanged(function()
        currentKey = trim(Options.ScriptKey.Value or "")
    end)
end

MainGroup:AddButton({
    Text = "Execute",
    Func = checkAndLoadKey,
    DoubleClick = false,
    Tooltip = "Check key and load protected script",
    Disabled = false,
    Visible = true,
    Risky = false,
})

MainGroup:AddDivider()

MainGroup:AddLabel("Keyless project?", true)

MainGroup:AddButton({
    Text = "Execute Keyless",
    Func = function()
        loadKeyless(true)
    end,
    DoubleClick = false,
})


AutoGroup:AddButton({
    Text = "Load Now",
    Func = function()
        if not savedConfig.mode then
            notify("No Auto-Load", "No saved keyless/premium mode found.", 5)
            return
        end

        autoCancelled = false
        autoStarted = true

        if savedConfig.mode == "keyless" then
            loadKeyless(false)
        else
            loadScriptWithKey(savedConfig.key or "")
        end
    end,
    DoubleClick = false,
})

AutoGroup:AddButton({
    Text = "Off Auto-Load",
    Func = function()
        disableAutoLoad(true)
    end,
    DoubleClick = false,
})

AutoGroup:AddButton({
    Text = "Clear Saved Key",
    Func = function()
        disableAutoLoad(false)
        currentKey = ""
        notify("Saved Key Cleared", 5)
    end,
    DoubleClick = true,
})

local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "wrench")

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "Custom Cursor",
    Default = true,
    Callback = function(value)
        Library.ShowCustomCursor = value
    end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "Notification Side",
    Callback = function(value)
        Library:SetNotifySide(value)
    end,
})

MenuGroup:AddDivider()

MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", {
        Default = "RightShift",
        NoUI = true,
        Text = "Menu keybind",
    })

MenuGroup:AddButton({
    Text = "Open Loader Next Time",
    Func = function()
        disableAutoLoad(true)
    end,
    DoubleClick = false,
    Tooltip = "Disable auto-load so the loader UI opens next injection",
})

MenuGroup:AddButton("Unload", function()
    Library:Unload()
end)

Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("ProtectorLoader")
SaveManager:SetFolder("ProtectorLoader/settings")

SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:AddThemeOptions(Tabs.Settings)

SaveManager:LoadAutoloadConfig()

notify("Protector Loader", "Ready.", 5)

task.spawn(function()
    task.wait(0.5)

    local mode = tostring(savedConfig.mode or "")

    if mode ~= "keyless" and mode ~= "key" and mode ~= "premium" then
        setAutoText("Auto-load: Not active")
        return
    end

    if mode ~= "keyless" and trim(savedConfig.key or "") == "" then
        setAutoText("Auto-load disabled: saved key missing.")
        savedConfig.mode = nil
        writeConfig(savedConfig)
        return
    end

    setAutoText("Auto-load mode: " .. mode)

    for i = AUTO_LOAD_SECONDS, 1, -1 do
        if autoCancelled or isExecuting or autoStarted then
            return
        end

        setAutoText("Auto-load in " .. tostring(i) .. "s.")
        task.wait(1)
    end

    if autoCancelled or isExecuting or autoStarted then
        return
    end

    autoStarted = true

    if mode == "keyless" then
        setAutoText("Auto-loading keyless script...")
        loadKeyless(false)
    else
        setAutoText("Auto-loading saved key...")
        loadScriptWithKey(savedConfig.key or "")
    end
end)

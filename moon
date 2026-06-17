local USER_KEY = (...)
USER_KEY = tostring(USER_KEY or ""):gsub("^%s+", ""):gsub("%s+$", "")

local SCRIPTS_BY_GAME_ID = {
    [15002061926] = "88512799538369470635", --Death Ball
    [3541611379] = "41695665062826643352", --TDX
}

local SCRIPT_ID = SCRIPTS_BY_GAME_ID[game.GameId]

if not SCRIPT_ID then
    return
end

local env = (getgenv and getgenv()) or _G
env.MOON_SCRIPT_ID = SCRIPT_ID

if USER_KEY ~= "" then
    env.MOON_KEY = USER_KEY
    env.script_key = USER_KEY
    env.LUAPROT_KEY = USER_KEY
    env.lp_key = USER_KEY
end

local ok, sdk = pcall(function()
    return loadstring(game:HttpGet("https://sdk.luaprot.net/"))()
end)

if not ok or not sdk then
    return
end

sdk.scriptId = SCRIPT_ID

if USER_KEY ~= "" then
    local success, result = pcall(function()
        return sdk:checkKey(USER_KEY)
    end)

    if not success or type(result) ~= "table" then
        return
    end

    if result.status ~= "VALID" then
        return
    end

    env.MOON_PREMIUM = true
end

sdk:loadScript()

local env = (getgenv and getgenv()) or _G

local function clean(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local argKey = clean((...))

local candidates = {
    argKey,
    env.lp_key,
    env.MOON_KEY,
    env.script_key,
    env.LUAPROT_KEY,
}

if _G then
    candidates[#candidates + 1] = _G.lp_key
    candidates[#candidates + 1] = _G.MOON_KEY
    candidates[#candidates + 1] = _G.script_key
    candidates[#candidates + 1] = _G.LUAPROT_KEY
end

local okFenv, fenv = pcall(function()
    return getfenv and getfenv() or nil
end)

if okFenv and type(fenv) == "table" then
    candidates[#candidates + 1] = rawget(fenv, "lp_key")
    candidates[#candidates + 1] = rawget(fenv, "MOON_KEY")
    candidates[#candidates + 1] = rawget(fenv, "script_key")
    candidates[#candidates + 1] = rawget(fenv, "LUAPROT_KEY")
end

local USER_KEY = ""

for _, value in ipairs(candidates) do
    local key = clean(value)
    if key ~= "" then
        USER_KEY = key
        break
    end
end

local SCRIPTS_BY_GAME_ID = {
    [15002061926] = "88512799538369470635", --Death Ball
    [3541611379] = "41695665062826643352", --TDX
}

local SCRIPT_ID = SCRIPTS_BY_GAME_ID[game.GameId]

if not SCRIPT_ID then
    return
end

env.MOON_SCRIPT_ID = SCRIPT_ID

if _G then
    _G.MOON_SCRIPT_ID = SCRIPT_ID
end

if USER_KEY ~= "" then
    env.MOON_KEY = USER_KEY
    env.script_key = USER_KEY
    env.LUAPROT_KEY = USER_KEY
    env.lp_key = USER_KEY

    if _G then
        _G.MOON_KEY = USER_KEY
        _G.script_key = USER_KEY
        _G.LUAPROT_KEY = USER_KEY
        _G.lp_key = USER_KEY
    end
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

    if success and type(result) == "table" and tostring(result.status or ""):upper() == "VALID" then
        env.MOON_PREMIUM = true
        if _G then
            _G.MOON_PREMIUM = true
        end
    else
        env.MOON_PREMIUM = false
        if _G then
            _G.MOON_PREMIUM = false
        end
    end
end

sdk:loadScript()

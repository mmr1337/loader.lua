local env = (getgenv and getgenv()) or _G

local function clean(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local USER_KEY = clean(env.lp_key or (_G and _G.lp_key) or "")

env.MOON_PREMIUM = false
env.MOON_KEY = nil
env.script_key = nil
env.LUAPROT_KEY = nil

local SCRIPTS_BY_GAME_ID = {
    [5166944221] = "88512799538369470635", --Death Ball
    [3541611379] = "41695665062826643352", --TDX
    [10016841656] = "22467996327744126658", --Noob Tower Defense
}

local SCRIPT_ID = SCRIPTS_BY_GAME_ID[game.GameId]
if not SCRIPT_ID then
    return
end

local ok, sdk = pcall(function()
    return loadstring(game:HttpGet("https://sdk.luaprot.net/"))()
end)

if not ok or not sdk then
    return
end

sdk.scriptId = SCRIPT_ID

sdk:loadScript()

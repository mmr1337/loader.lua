local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}

local currentPlaceId = game.PlaceId
local lobbyPlaceId = 9503261072
local gamePlaceId = 11739766412

----------------------------------------------------------------------
-- VIP проверка (общая)
----------------------------------------------------------------------
local isVIP = false
for i = 1, 30 do
    local attr = LocalPlayer:GetAttribute("VIP")
    if attr ~= nil then
        isVIP = (attr == true)
        break
    end
    task.wait(0.5)
end

if not isVIP then
    print("⚠️ VIP не активен, remote events не будут выполняться")
end

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function toTitleCase(str)
    if not str then return str end
    local letters = str:gsub("[^%a]", "")
    if #letters > 0 and letters == letters:upper() then
        return (str:lower():gsub("(%a)([%a]*)", function(first, rest)
            return first:upper() .. rest
        end))
    end
    return str
end

local difficultyToMap = {
    ["Nightmare"] = "NightmareWithMapVoting",
}

----------------------------------------------------------------------
-- IN-GAME (11739766412): Голосование за карту (ТОЛЬКО VIP)
----------------------------------------------------------------------
if currentPlaceId == gamePlaceId then
    if not isVIP then
        print("⚠️ VIP нет — голосование за карту пропущено")
        return
    end

    local mapVoteName = config["mapvoting"]
    if not mapVoteName then return end

    local convertedName = toTitleCase(mapVoteName)
    local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not Remotes then return end

    pcall(function()
        Remotes.MapOverride:FireServer(convertedName)
    end)
    print("✅ MapOverride: " .. convertedName)

    task.wait(1)

    pcall(function()
        Remotes.MapVoteCast:FireServer(convertedName)
    end)
    print("✅ MapVoteCast: " .. convertedName)

    task.wait(1)

    pcall(function()
        Remotes.MapVoteReady:FireServer()
    end)
    print("✅ MapVoteReady")

    return
end

----------------------------------------------------------------------
-- LOBBY (9503261072): Присоединение к APC
-- VIP → remote events (выбор карты) + вход в APC
-- Без VIP → только физический вход в APC (без remote events)
----------------------------------------------------------------------
if currentPlaceId ~= lobbyPlaceId then return end

local autoDifficulty = config["Auto Difficulty"]
local targetMapName
if autoDifficulty then
    targetMapName = difficultyToMap[autoDifficulty] or autoDifficulty
else
    targetMapName = config["Map"] or "Christmas24Part1"
end

local specialMaps = {
    ["Halloween Part 1"] = true,
    ["Halloween Part 2"] = true,
    ["Halloween Part 3"] = true,
    ["Halloween Part 4"] = true,
    ["Tower Battles"] = true,
    ["Christmas24Part1"] = true,
    ["Halloween2025"] = true,
    ["Christmas25Part2"] = true,
    ["Christmas25Part1"] = true,
    ["NightmareWithMapVoting"] = true,
    ["Easy"] = true,
    ["Elite"] = true,
    ["Intermediate"] = true,
    ["Expert"] = true,
    ["Endless"] = true,
    ["Christmas24Part2"] = true
}

local function isInLobby()
    return game.PlaceId == lobbyPlaceId
end

local function matchMap(a, b)
    return tostring(a or "") == tostring(b or "")
end

local function enterDetectorExact(detector)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = detector.CFrame * CFrame.new(0, 0, -2)
    end
end

local function trySetMapIfNeeded()
    if not isVIP then return end

    if specialMaps[targetMapName] then
        local argsPartyType = { "Party" }
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientChangePartyTypeRequest"):FireServer(unpack(argsPartyType))

        local argsMap = { targetMapName }
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientChangePartyMapRequest"):FireServer(unpack(argsMap))

        task.wait(1.5)

        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientStartGameRequest"):FireServer()
    end
end

local function tryEnterMap()
    if not isInLobby() then
        return false
    end

    trySetMapIfNeeded()

    local LeaveQueue = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("LeaveQueue")
    local roots = {
        Workspace:FindFirstChild("APCs"),
        Workspace:FindFirstChild("APCs2"),
        Workspace:FindFirstChild("BasementElevators")
    }

    for _, root in ipairs(roots) do
        if root then
            for _, folder in ipairs(root:GetChildren()) do
                if folder:IsA("Folder") then
                    local apc = folder:FindFirstChild("APC")
                    local detector = apc and apc:FindFirstChild("Detector")
                    local mapDisplay = folder:FindFirstChild("mapdisplay")
                    local screen = mapDisplay and mapDisplay:FindFirstChild("screen")
                    local displayscreen = screen and screen:FindFirstChild("displayscreen")
                    local mapLabel = displayscreen and displayscreen:FindFirstChild("map")
                    local plrCountLabel = displayscreen and displayscreen:FindFirstChild("plrcount")
                    local statusLabel = displayscreen and displayscreen:FindFirstChild("status")

                    if detector and mapLabel and plrCountLabel and statusLabel then
                        if matchMap(mapLabel.Text, targetMapName) then
                            if statusLabel.Text == "TRANSPORTING..." then
                                continue
                            end

                            local countText = plrCountLabel.Text or ""
                            local cur, max = countText:match("(%d+)%s*/%s*(%d+)")
                            cur, max = tonumber(cur), tonumber(max)

                            if not cur or not max then
                                continue
                            end

                            if cur == 0 and max == 4 then
                                enterDetectorExact(detector)
                                return true
                            elseif cur >= 2 and max == 4 and LeaveQueue and isVIP then
                                pcall(LeaveQueue.FireServer, LeaveQueue)
                                task.wait()
                            else
                                -- ждём пока карта освободится
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

while isInLobby() do
    local ok, result = pcall(tryEnterMap)
    if not ok then
        -- ошибка игнорируется
    elseif not result then
        break
    end
    task.wait()
end

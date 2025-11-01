
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}
local targetMapName = config["Map"] or "Christmas24Part1"
local expectedPlaceId = 9503261072

local specialMaps = {
    ["Halloween Part 1"] = true,
    ["Halloween Part 2"] = true,
    ["Halloween Part 3"] = true,
    ["Halloween Part 4"] = true,
    ["Tower Battles"] = true,
    ["Christmas24Part1"] = true,
    ["Christmas24Part2"] = true
}

local function isInLobby()
    return game.PlaceId == expectedPlaceId
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
                            elseif cur >= 2 and max == 4 and LeaveQueue then
                                pcall(LeaveQueue.FireServer, LeaveQueue)
                                task.wait()
                            else
                                -- đợi map trống
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
        -- lỗi bị bỏ qua
    elseif not result then
        break
    end
    task.wait()
end
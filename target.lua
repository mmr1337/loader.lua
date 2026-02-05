local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Проверяем, находимся ли мы уже в целевом place
if game.PlaceId == 9503261072 then
    print("Already in target place, script will not run")
    return
end

local function checkAndVote()
    -- Ждем загрузки структуры
    local game_folder = workspace:WaitForChild("Game", 5)
    if not game_folder then return false end
    
    local mapVoting = game_folder:WaitForChild("MapVoting", 5)
    if not mapVoting then return false end
    
    local votingScreens = mapVoting:WaitForChild("VotingScreens", 5)
    if not votingScreens then return false end
    
    -- Проверяем все VotingScreen от 1 до 4
    for i = 1, 4 do
        local screenName = "VotingScreen" .. i
        local votingScreen = votingScreens:FindFirstChild(screenName)
        
        if votingScreen then
            local screenPart = votingScreen:FindFirstChild("ScreenPart")
            
            if screenPart then
                local surfaceGui = screenPart:FindFirstChild("SurfaceGui")
                
                if surfaceGui then
                    local mapName = surfaceGui:FindFirstChild("MapName")
                    
                    if mapName and mapName.Text == "MILITARY BASE" then
                        -- Найден Military Base, отправляем vote
                        local args = {
                            "Military Base"
                        }
                        ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteCast"):FireServer(unpack(args))
                        print("Voted for Military Base!")
                        
                        -- Отправляем MapVoteReady
                        local readyEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteReady")
                        readyEvent:FireServer()
                        print("Sent MapVoteReady!")
                        
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

-- Основной цикл
local success = false
local maxAttempts = 20
local attempt = 0

while not success and attempt < maxAttempts do
    success = checkAndVote()
    
    if not success then
        attempt = attempt + 1
        wait(1) -- Увеличена задержка для загрузки
    end
end

-- Если не нашли Military Base после всех попыток, телепортируем
if not success then
    print("Military Base not found, teleporting...")
    local player = Players.LocalPlayer
    TeleportService:Teleport(9503261072, player)
end

repeat task.wait() until game:IsLoaded()
if game.PlaceId ~= 2809202155 then return end

--// 📦 Services & Variables
local replicatedFirst = game:GetService("ReplicatedFirst")
local replicatedStorage = game:GetService("ReplicatedStorage")
local plr = game.Players.LocalPlayer
local itemSpawns = workspace["Item_Spawns"].Items
local plrGui = plr.PlayerGui
local coregui = game.CoreGui
local loaded = false
local Option = getgenv().Settings.SellAll and "Option2" or "Option1"
local luckyBought = false

--// 📁 Folder & File Setup
if not isfolder("YBA_AUTOHOP") then makefolder("YBA_AUTOHOP") end
if not isfile("YBA_AUTOHOP/Count.txt") then writefile("YBA_AUTOHOP/Count.txt", "") end
if not isfile("YBA_AUTOHOP/lastLucky.txt") then
    writefile("YBA_AUTOHOP/lastLucky.txt","")
end
if not isfile("YBA_AUTOHOP/theme.mp3") then
    local response = request({Url = "https://raw.githubusercontent.com/crcket/YBA/refs/heads/main/Diavolo%20Theme%20but%20it's%20EPIC%20VERSION%20(King%20Crimson%20Requiem).mp3",Method = "GET"})
    if response.StatusCode == 200 then
        writefile("YBA_AUTOHOP/theme.mp3", response.Body)
        print("File saved successfully!")
    else
        warn("Failed to download file. Status Code:", response.StatusCode)
    end
end

--// ⏳ Wait for Core Game Objects
repeat task.wait() until game:IsLoaded() and game.ReplicatedStorage and game.ReplicatedFirst 
    and plr and plr.Character and plr.PlayerGui and plr:FindFirstChild("PlayerStats")

--// 🔁 ENHANCED Server Hop Function with Retry Mechanism
local function serverHop()
    local gameId = game.PlaceId
    local maxRetries = 100
    local retryDelay = 0.1
    
    for attempt = 1, maxRetries do
        print(`Server hop attempt {attempt}/{maxRetries}`)
        
        local servers, cursor = {}, ""
        local foundServers = false

        -- Retry mechanism for fetching server list
        repeat
            local success, result = pcall(function()
                return game.HttpService:JSONDecode(game:HttpGet(
                    "https://games.roblox.com/v1/games/" .. gameId .. "/servers/Public?sortOrder=Asc&limit=100&cursor=" .. cursor
                ))
            end)

            if success and result and result.data then
                for _, server in ipairs(result.data) do
                    if server.playing >= 14 and server.playing < server.maxPlayers and server.id ~= game.JobId then
                        table.insert(servers, server.id)
                        foundServers = true
                    end
                end
                cursor = result.nextPageCursor or ""
            else
                warn(`Failed to fetch servers on attempt {attempt}: `, result)
                task.wait(retryDelay)
                break
            end
        until cursor == "" or #servers >= 3 -- Tăng số server tìm được để có nhiều lựa chọn

        if foundServers and #servers > 0 then
            local targetServerId = servers[math.random(1, #servers)]
            
            -- Retry mechanism for teleportation
            local teleportSuccess = pcall(function()
                game:GetService("TeleportService"):TeleportToPlaceInstance(gameId, targetServerId, plr)
            end)
            
            if teleportSuccess then
                print(`Successfully initiated teleport to server {targetServerId}`)
                return true
            else
                warn(`Teleport failed on attempt {attempt}`)
            end
        else
            warn(`No suitable servers found on attempt {attempt}`)
        end
        
        -- Wait before retry
        if attempt < maxRetries then
            task.wait(retryDelay * attempt) -- Exponential backoff
        end
    end
    
    warn("All server hop attempts failed. Staying in current server.")
    return false
end

--// 📬 Webhook Notification Handler (Enhanced)
local function webHookHandler(Mode)
    local maxRetries = 3
    
    for attempt = 1, maxRetries do
        local success = pcall(function()
            local lCount = 1
            for _, item in pairs(plr.Backpack:GetChildren()) do
                if item.Name == "Lucky Arrow" then
                    lCount += 1
                end
            end

            local textContent, titleContent, descriptionContent, colorContent, imageContent, thumbnailContent, footerContent

            if Mode == "luckyArrow" then
                local req = request({Url = `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds={plr.UserId}&size=48x48&format=png`})
                local body = game:GetService("HttpService"):JSONDecode(req.Body)

                titleContent = plr.Name
                descriptionContent = os.date("%I:%M %p")
                colorContent = 16776960
                imageContent = {url = "https://static.wikia.nocookie.net/your-bizarre-adventure/images/f/fd/LuckyArrow.png/revision/latest?cb=20221020062009"}
                thumbnailContent = {url = body.data[1].imageUrl}

                if getgenv().Settings.PingOnLuckyArrow and lCount >=9 and readfile("YBA_AUTOHOP/lastLucky.txt") ~= plr.Name then
                    writefile("YBA_AUTOHOP/lastLucky.txt",plr.Name)
                    warn(getgenv().Settings.DiscordID)
                    textContent = `<@{getgenv().Settings.DiscordID}>, your account, {plr.Name} has ~9/9 lucky arrows`
                end
                footerContent = {text = `{lCount}/9 lucky arrows`}
            end

            request({
                Url = getgenv().Settings.URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = game:GetService("HttpService"):JSONEncode({
                    content = textContent,
                    embeds = {{
                        title = titleContent,
                        description = descriptionContent,
                        color = colorContent,
                        image = imageContent,
                        thumbnail = thumbnailContent,
                        footer = footerContent,
                    }}
                })
            })
        end)
        
        if success then
            print(`Webhook sent successfully on attempt {attempt}`)
            return true
        else
            warn(`Webhook failed on attempt {attempt}`)
            if attempt < maxRetries then
                task.wait(1 * attempt) -- Wait longer each retry
            end
        end
    end
    
    warn("All webhook attempts failed")
    return false
end

--// 🎒 Enhanced Inventory Processor with Retry
local function processInventory()
    if not getgenv().Settings.SellAll then return end

    local maxRetries = 3
    
    for attempt = 1, maxRetries do
        local success = pcall(function()
            local uniqueItems = {}
            for _, item in ipairs(plr.Backpack:GetChildren()) do
                uniqueItems[item.Name] = item
            end

            for name, item in pairs(uniqueItems) do
                if name ~= "Lucky Arrow" and name ~= "Stand Arrow" then
                    task.wait(0.5)
                    
                    -- Retry equipping tool
                    local equipSuccess = pcall(function()
                        plr.Character.Humanoid:EquipTool(item)
                    end)
                    
                    if equipSuccess then
                        -- Retry selling
                        pcall(function()
                            plr.Character.RemoteEvent:FireServer("EndDialogue", {
                                NPC = "Merchant",
                                Option = Option,
                                Dialogue = "Dialogue5"
                            })
                        end)
                    end
                end
            end
        end)
        
        if success then
            return true
        else
            warn(`Inventory processing failed on attempt {attempt}`)
            if attempt < maxRetries then
                task.wait(1)
            end
        end
    end
    
    warn("All inventory processing attempts failed")
    return false
end

-- Auto Sell Inventory Every 12 Seconds
task.spawn(function()
    while task.wait(12) do
        processInventory()
    end
end)

--// 🔧 Enhanced Main Setup with Retry
local function setup()
    local maxRetries = 3
    
    for attempt = 1, maxRetries do
        local success = pcall(function()
            -- Hook "Returner" InvokeServer call
            local old
            old = hookmetamethod(game, "__namecall", function(self, ...)
                if tostring(self) == "Returner" and tostring(getnamecallmethod()) == "InvokeServer" then
                    return "  ___XP DE KEY"
                end
                return old(self, ...)
            end)

            -- Prevent spawn distance checks
            local vector3Metatable = getrawmetatable(Vector3.new())
            local oldIndex = vector3Metatable.__index
            setreadonly(vector3Metatable, false)
            vector3Metatable.__index = newcclosure(function(self, idx)
                if string.lower(idx) == "magnitude" and getcallingscript() == replicatedFirst.ItemSpawn then
                    return 0
                end
                return oldIndex(self, idx)
            end)
            setreadonly(vector3Metatable, true)

            -- Rename items based on their prompt text
            for _, item in pairs(itemSpawns:GetChildren()) do
                local prox = item:WaitForChild("ProximityPrompt", 9)
                if prox then
                    item.Name = prox.ObjectText
                end
            end

            -- Handle newly spawned items
            itemSpawns.ChildAdded:Connect(function(item)
                print("new item added to workspace")
                local prox = item:WaitForChild("ProximityPrompt", 9)
                if prox then
                    item.Name = prox.ObjectText
                end
                
                for _, v in pairs(itemSpawns:GetDescendants()) do
                    if v:IsA("ProximityPrompt") and v.MaxActivationDistance == 0 and v.Name ~= "Proximity Prompt __" then
                        v.Name = "ProximityPrompt __"
                    end
                end

                for _, v in pairs(itemSpawns:GetChildren()) do
                    if not v:FindFirstChild("ProximityPrompt") then v:Destroy() end
                end
            end)
        end)
        
        if success then
            print(`Setup completed successfully on attempt {attempt}`)
            return true
        else
            warn(`Setup failed on attempt {attempt}`)
            if attempt < maxRetries then
                task.wait(1)
            end
        end
    end
    
    error("Setup failed after all retry attempts")
end

local function checkForKickMessage()
    local message = coregui:FindFirstChild("RobloxPromptGui")
    if message and message:FindFirstChild("ErrorPrompt", true) then
        return true
    end
    return false
end

--// ▶️ Enhanced Game Entry with Retry
local function enterGame()
    local maxRetries = 5
    
    for attempt = 1, maxRetries do
        local success = pcall(function()
            if not plr.Character:FindFirstChild("RemoteEvent") then
                task.wait(1)    
            end
            plr.Character.RemoteEvent:FireServer("PressedPlay")
            loaded = true
        end)
        
        if success then
            print(`Game entry successful on attempt {attempt}`)
            break
        else
            warn(`Game entry failed on attempt {attempt}`)
            if attempt < maxRetries then
                task.wait(2)
            end
        end
    end
    
    task.spawn(function()
        pcall(function()
            workspace:WaitForChild("LoadingScreen",90):WaitForChild("Song",90).SoundId = getcustomasset("YBA_AUTOHOP/theme.mp3")
        end)
    end)
end

--// 🚀 Start Automation with Enhanced Error Handling
if not getgenv().Settings.AutoFarm then return end

enterGame()

repeat task.wait(0.5) until loaded

local console = loadstring(game:HttpGet("https://raw.githubusercontent.com/crcket/ROBLOX/refs/heads/main/crckonsle.lua"))()

task.wait(12)
setup()
print("ran setup")
task.spawn(function()
    pcall(function()
        console.Send(`ran setup @ {game.JobId}!`,"ANNOUNCEMENT")
    end)
end)

--// 🧲 Enhanced Auto Pickup Logic
local isNotOnAlready = true
local lastPickupTime = tick()
local currentItem = nil
local heartbeatConnection = nil

-- Heartbeat loop để dịch chuyển xuống dưới item
local function startItemTeleportLoop()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
    end

    heartbeatConnection = game:GetService("RunService").Heartbeat:Connect(function()
        pcall(function()
            if currentItem and currentItem.Parent and currentItem.PrimaryPart and not isNotOnAlready then
                local itemPos = currentItem.PrimaryPart.Position
                local belowItemPos = itemPos + Vector3.new(0, -10, 0)
                plr.Character.HumanoidRootPart.CFrame = CFrame.new(belowItemPos)
            end
        end)
    end)
end

itemSpawns.ChildAdded:Connect(function(item)
    repeat task.wait() until item.Name ~= "Model" and isNotOnAlready and not plr.Character.HumanoidRootPart.Anchored
    if getgenv().Settings.AutoFarm and item.PrimaryPart and item:FindFirstChild("ProximityPrompt __") then
        print(`-> picking up {item.Name}!`)
        task.spawn(function() 
            pcall(function()
                console.Send(`picking up {item.Name}!`,"ITEM_PICKUP") 
            end)
        end)
        
        lastPickupTime = tick()
        isNotOnAlready = false
        currentItem = item

        -- Bắt đầu loop teleport xuống dưới item
        startItemTeleportLoop()

        task.wait(getgenv().Settings.PickupDelay or 0.5)
        
        -- Enhanced pickup with retry
        local pickupSuccess = false
        for pickupAttempt = 1, 3 do
            local success = pcall(function()
                firesignal(item:FindFirstChildWhichIsA("ProximityPrompt").Triggered)
            end)
            
            if success then
                pickupSuccess = true
                break
            else
                warn(`Pickup attempt {pickupAttempt} failed`)
                task.wait(0.5)
            end
        end
        
        if not pickupSuccess then
            warn("All pickup attempts failed, removing item")
            pcall(function() item.Parent = nil end)
        end
        
        spawn(function()
            task.wait((getgenv().Settings.PickupDelay or 0.5)+0.5)
            if item.Parent then
                pcall(function()
                    firesignal(item:FindFirstChildWhichIsA("ProximityPrompt").Triggered)
                end)
                task.wait((getgenv().Settings.PickupDelay or 0.5)+0.5)
                if item.Parent then
                    item.Parent = nil
                    task.spawn(function()
                        pcall(function()
                            console.Send(`{item.Name} took too long to pick up.. deleting`,"ITEM_TIMEOUT")
                        end)
                    end)
                end
            end
        end)
        
        item.AncestryChanged:Wait()

        -- Dừng loop và reset
        currentItem = nil
        if heartbeatConnection then
            heartbeatConnection:Disconnect()
            heartbeatConnection = nil
        end

        isNotOnAlready = true
        pcall(function()
            plr.Character.HumanoidRootPart.CFrame = CFrame.new(-23, -33, 28)
        end)
    end
end)

--// 🧾 Enhanced Auto Sell When "Message" Pops Up
plrGui.ChildAdded:Connect(function(thing)
    if thing.Name == "Message" then
        task.wait()
        local success = pcall(function()
            local itemName = thing:WaitForChild("TextLabel").Text:match("%d+%s+(.+) in your inventory"):gsub("%(s%)$", "")
            local item = plr.Backpack:FindFirstChild(itemName)
            if item then item.Parent = plr.Character end

            plr.Character.RemoteEvent:FireServer("EndDialogue", {
                NPC = "Merchant",
                Option = Option,
                Dialogue = "Dialogue5"
            })
        end)
        
        if not success then
            warn("Failed to process inventory message")
        end
    end
end)

--// 🍀 Enhanced Auto Buy Lucky Arrows
plr.PlayerStats.Money.Changed:Connect(function()
    pcall(function()
        if not luckyBought and plr.PlayerStats.Money.Value >= 50000 then
            local luckyNum = 0
            for _, v in pairs(plr.Backpack:GetChildren()) do
                if v.Name == "Lucky Arrow" then luckyNum += 1 end
            end
            if luckyNum <= 8 then
                luckyBought = true
                task.wait(1)
                
                -- Retry mechanism for purchase
                for attempt = 1, 3 do
                    local purchaseSuccess = pcall(function()
                        plr.Character.RemoteEvent:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
                    end)
                    
                    if purchaseSuccess then
                        webHookHandler("luckyArrow")
                        local log = `{plr.Name} {os.date("%I:%M %p")}\n`
                        writefile("YBA_AUTOHOP/Count.txt", readfile("YBA_AUTOHOP/Count.txt") .. log)
                        break
                    else
                        warn(`Purchase attempt {attempt} failed`)
                        task.wait(1)
                    end
                end
            else
                luckyBought = true
                if getgenv().Settings.PingOnLuckyArrow then
                    warn(readfile("YBA_AUTOHOP/lastLucky.txt"))
                    if readfile("YBA_AUTOHOP/lastLucky.txt") == plr.Name then
                        -- Already notified
                    else
                        webHookHandler("luckyArrow")
                    end
                    warn("didthislucksend")
                end
                getgenv().Settings.SellAll = false
                Option = "Option1"
            end
        end
    end)
end)

--// ⏰ Enhanced Server Hop Timer with Retry
task.spawn(function()
    while task.wait(0.5) do
        if tick() - lastPickupTime > 6 or checkForKickMessage() then
            print("Initiating server hop due to inactivity or kick message")
            serverHop()
        end
    end
end)
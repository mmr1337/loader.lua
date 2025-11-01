local HttpService = game:GetService("HttpService") local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes") local TowersFolder = game:GetService("Workspace"):WaitForChild("Game"):WaitForChild("Towers") local player = game.Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")

local MODE = getgenv().TDX_Config and getgenv().TDX_Config.Macros or "run" local macroName = getgenv().TDX_Config and getgenv().TDX_Config["Macro Name"] or "y" local macroPath = "tdx/macros/" .. macroName .. ".json" local macro = {} local placedIndex = 1

local function samePos(a, b) return (a - b).Magnitude < 0.05 end

local function countTowerByName(name) local count = 0 for _, tower in ipairs(TowersFolder:GetChildren()) do if tower.Name == name then count += 1 end end return count end

local function findNewTower(name, beforeCount) for _, tower in ipairs(TowersFolder:GetChildren()) do if tower.Name == name then beforeCount -= 1 if beforeCount < 0 then return tower end end end return nil end

local function waitUntilCashEnough(amount) while cashStat.Value < amount do task.wait() end end

if MODE == "run" then macro = HttpService:JSONDecode(readfile(macroPath)) for _, entry in ipairs(macro) do if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)") local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation) or 0 } local beforeCount = countTowerByName(entry.TowerPlaced) local startTime = tick() while tick() - startTime < 1 do waitUntilCashEnough(entry.TowerPlaceCost) local beforeCash = cashStat.Value Remotes.PlaceTower:InvokeServer(unpack(args)) task.wait(0.25) local afterCash = cashStat.Value local afterCount = countTowerByName(entry.TowerPlaced) if afterCash < beforeCash and afterCount > beforeCount then local tower = findNewTower(entry.TowerPlaced, beforeCount) if tower then tower.Name = placedIndex .. "." .. entry.TowerPlaced placedIndex += 1 end break end end elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then local idStr = tostring(entry.TowerIndex) local found = TowersFolder:FindFirstChild(idStr) if not found then continue end waitUntilCashEnough(entry.UpgradeCost) local startTime = tick() while tick() - startTime < 5 do local before = cashStat.Value Remotes.TowerUpgradeRequest:FireServer(tonumber(idStr), tonumber(entry.UpgradePath), 1) task.wait(0.25) local after = cashStat.Value if after < before then break end end elseif entry.ChangeTarget and entry.TargetType then Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType) task.wait(0.2) elseif entry.SellTower then Remotes.SellTower:FireServer(entry.SellTower) task.wait(0.2) end end else local recorded = {} local placing = Remotes:WaitForChild("PlaceTower") local upgrade = Remotes:WaitForChild("TowerUpgradeRequest") local changeTarget = Remotes:WaitForChild("ChangeQueryType") local sellTower = Remotes:WaitForChild("SellTower")

placing.OnClientInvoke = function(...)
	task.defer(function(...)
		local args = {...}
		table.insert(recorded, {
			TowerPlaced = args[2],
			TowerVector = tostring(args[3]),
			Rotation = args[4],
			TowerPlaceCost = cashStat.Value,
			TowerA1 = args[1]
		})
	end, ...)
end

local oldUp = upgrade.FireServer
upgrade.FireServer = function(self, id, path, which)
	task.defer(function()
		table.insert(recorded, {
			TowerIndex = id,
			UpgradePath = path,
			UpgradeCost = cashStat.Value
		})
	end)
	return oldUp(self, id, path, which)
end

local oldChange = changeTarget.FireServer
changeTarget.FireServer = function(self, index, type)
	task.defer(function()
		table.insert(recorded, {
			ChangeTarget = index,
			TargetType = type
		})
	end)
	return oldChange(self, index, type)
end

local oldSell = sellTower.FireServer
sellTower.FireServer = function(self, index)
	task.defer(function()
		table.insert(recorded, {
			SellTower = index
		})
	end)
	return oldSell(self, index)
end

game:BindToClose(function()
	writefile(macroPath, HttpService:JSONEncode(recorded))
end)

end


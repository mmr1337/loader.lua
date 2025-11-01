assert(getscriptbytecode, "⚠️ Yêu cầu exploit hỗ trợ getscriptbytecode!")

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local ok, prodInfo = pcall(function() return MarketplaceService:GetProductInfo(game.GameId) end)
local GAME_NAME = (ok and prodInfo and prodInfo.Name) and prodInfo.Name or tostring(game.GameId)
local SAFE_NAME = GAME_NAME:gsub("[^%w-]", "_")
local OUTPUT_FOLDER = "ModuleTree_" .. SAFE_NAME
makefolder(OUTPUT_FOLDER)

local SKIPPED_FOLDER = OUTPUT_FOLDER .. "/skipped"
makefolder(SKIPPED_FOLDER)

local remoteList, moduleFunctionList, moduleQueue = {}, {}, {}

-- ghi file skip / error
local function write_skipped_file(path, fullPath, note)
	local relPath = path .. ".lua.txt"
	local outPath = SKIPPED_FOLDER .. relPath
	local folderOnly = outPath:match("^(.*)/[^/]+$")
	if folderOnly then
		local accum = ""
		for part in folderOnly:gmatch("[^/]+") do
			accum = accum == "" and part or (accum .. "/" .. part)
			pcall(makefolder, accum)
		end
	end
	writefile(outPath, "-- Instance path: " .. fullPath .. "\n\n-- skipped: " .. note .. "\n")
end

local function write_error_file(path, fullPath, err)
	local relPath = path .. ".lua.txt"
	local outPath = SKIPPED_FOLDER .. relPath
	local folderOnly = outPath:match("^(.*)/[^/]+$")
	if folderOnly then
		local accum = ""
		for part in folderOnly:gmatch("[^/]+") do
			accum = accum == "" and part or (accum .. "/" .. part)
			pcall(makefolder, accum)
		end
	end
	writefile(outPath, "-- Instance path: " .. fullPath .. "\n\n-- decompile error: " .. tostring(err) .. "\n")
end

-- kiểm tra cần retry (GOTO, start, end)
local function shouldRetryBecauseGotoOrStartEnd(str)
	if not str or str == "" then return false end
	local lower = string.lower
	for line in str:gmatch("[^\r\n]+") do
		local trimmed = line:match("^%s*(.-)%s*$") or line
		if trimmed:match("^%-%-%s*KONSTANTERROR:%s*%[%d+%]") then
			local l = lower(trimmed)
			if l:find(" start", 1, true) or l:find(" end", 1, true) then
				return true, "konstanterror start/end"
			end
		end
		if trimmed:match("^%-%-%s*KONSTANTWARNING:") then
			local l = lower(trimmed)
			if l:find("goto", 1, true) then
				return true, "konstantwarning goto"
			end
		end
	end
	return false, nil
end

-- thu thập module
local function collectModules(object, basePath)
	for _, child in ipairs(object:GetChildren()) do
		local currentPath = basePath .. "/" .. child.Name
		if child:IsA("ModuleScript") then
			table.insert(moduleQueue, { obj = child, path = currentPath })
		end
		collectModules(child, currentPath)
	end
end

-- dump một module
local function dumpSingleModule(child, currentPath, threadId, isSupport)
	local fullPath = child:GetFullName():gsub("^Players%." .. LocalPlayer.Name, "Players.LocalPlayer")
	local success, codeOrErr = pcall(decompile, child)
	local codeStr = tostring(codeOrErr or "")
	local toRetry, reason = shouldRetryBecauseGotoOrStartEnd(codeStr)

	local attempt = 1
	while toRetry and attempt <= 20 do
		print(("🔁 dump lại (%s) — %s [thread %d | lần %d | %s]"):format(reason, currentPath, threadId, attempt, isSupport and "SUPPORT" or "MAIN"))
		success, codeOrErr = pcall(decompile, child)
		codeStr = tostring(codeOrErr or "")
		toRetry, reason = shouldRetryBecauseGotoOrStartEnd(codeStr)
		attempt += 1
	end

	if success == true then
		writefile(OUTPUT_FOLDER .. currentPath .. ".lua.txt", codeStr)
		print(("✅ dumped [%s %d]: %s"):format(isSupport and "SUP" or "MAIN", threadId, currentPath))
		for funcName in codeStr:gmatch("[\n\r%s]function%s+([%w_%.]+)%s*%(") do
			table.insert(moduleFunctionList, funcName .. " @ " .. fullPath)
		end
		return true
	else
		local errMsg = tostring(codeOrErr)
		print(("🔥 lỗi [%s %d]: %s | %s"):format(isSupport and "SUP" or "MAIN", threadId, currentPath, errMsg))
		write_error_file(currentPath, fullPath, errMsg)
		return false
	end
end

-- luồng chính
local function workerThread(id)
	while true do
		local item = table.remove(moduleQueue, 1)
		if not item then break end
		local ok = dumpSingleModule(item.obj, item.path, id, false)
		if not ok then
			print(("🧩 tạo 2 luồng hỗ trợ cho module lỗi: %s"):format(item.path))
			for s = 1, 2 do
				task.spawn(function()
					local retryOk = false
					local count = 0
					repeat
						retryOk = dumpSingleModule(item.obj, item.path, s, true)
						count += 1
					until retryOk or count >= 20
				end)
			end
		end
	end
end

-- bắt đầu
local START_MODULE_ROOT = LocalPlayer:FindFirstChild("PlayerScripts")
if START_MODULE_ROOT then
	START_MODULE_ROOT = START_MODULE_ROOT:FindFirstChild("Client") or START_MODULE_ROOT
	print("🔍 collecting modules...")
	collectModules(START_MODULE_ROOT, "")
else
	print("❌ không tìm thấy PlayerScripts/Client")
end

-- 10 luồng chính
for i = 1, 10 do
	task.spawn(function() workerThread(i) end)
end

-- đợi tất cả hoàn tất
repeat task.wait(0.1) until #moduleQueue == 0

-- quét remotes
print("🔍 scanning remotes...")
local function scanRemotesOnly(object)
	for _, child in ipairs(object:GetChildren()) do
		local fullPath = child:GetFullName():gsub("^Players%." .. LocalPlayer.Name, "Players.LocalPlayer")
		if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("BindableEvent") or child:IsA("BindableFunction") then
			table.insert(remoteList, child.ClassName .. " | " .. fullPath)
		end
		scanRemotesOnly(child)
	end
end
scanRemotesOnly(ReplicatedStorage)

if #remoteList > 0 then
	writefile(OUTPUT_FOLDER .. "/remotes_list.txt", table.concat(remoteList, "\n"))
end
if #moduleFunctionList > 0 then
	writefile(OUTPUT_FOLDER .. "/module_functions.txt", table.concat(moduleFunctionList, "\n"))
end

print("✅ hoàn tất dump, dữ liệu lưu tại: " .. OUTPUT_FOLDER)
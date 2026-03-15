local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local dtc = getgenv and getgenv().dtc or nil
newcclosure = newcclosure or function(f) return f end
setreadonly = setreadonly  or function() end
getrawmetatable = getrawmetatable or getmetatable

local _pairs = pairs
local _ipairs = ipairs
local _tostring = tostring
local _tick = tick

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")
local GameClass = PlayerScripts.Client.GameClass

local TowerClass = require(GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(GameClass:WaitForChild("EnemyClass"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseAbilReq = Remotes:WaitForChild("TowerUseAbilityRequest")
local TAtk = Remotes:WaitForChild("TowerAttack")
local TChainAtk = Remotes:WaitForChild("TowerChainAttack")

local Common = ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common")
local TUtils = require(Common:WaitForChild("TowerUtilities"))
local PathHandler = require(Common:WaitForChild("PathHandler"))

local StaticEntityConfigs = Common:WaitForChild("Resources"):WaitForChild("StaticEntities"):WaitForChild("Configs")

local function getStaticEntityCfg(entityType)
  if not entityType then return nil end
  local name = _tostring(entityType):match("[^.]+$")
  if not name then return nil end
  local mod = StaticEntityConfigs:FindFirstChild(name)
  return mod and pcall(require, mod) and require(mod) or nil
end

local StaticEntityBehaviorCache = {}

local SEBE = {Heal = 1, Attack = 2, PathSpawn = 3}

local function getStaticBehavior(entityType)
  local k = _tostring(entityType)
  local v = StaticEntityBehaviorCache[k]
  if v then return v end
  local cfg = getStaticEntityCfg(entityType)
  if not cfg then return nil end
  local behavior
  if cfg.MultiHealData and cfg.MultiHealData.HealAmountPerTarget then
    behavior = SEBE.Heal
  elseif cfg.SpawnPathEntitySequence then
    behavior = SEBE.PathSpawn
  elseif cfg.AttackData then
    behavior = SEBE.Attack
  end
  StaticEntityBehaviorCache[k] = behavior
  return behavior
end

local CONFIG = {
  CheckInterval = 0.25,
  SpecialCheckInterval = 0.25,
  MobsterDelay = 0.5,
  CacheInterval = 0.05,
}

local SETTINGS = {
  Directional = {
    ["Toxicnator"]        = true, ["Ghost"]             = true,
    ["Artillery"]         = true,
    ["Golden Mine Layer"] = true,
    ["Slammer"]           = true,
  },
  SeparateLogic = {
    ["Medic"]          = true, ["Mobster"]         = true,
    ["Golden Mobster"] = true,
  },
  SkipGeneralLogic = {
    ["Helicopter"]       = true, ["Cryo Helicopter"] = true,
    ["Combat Drone"]     = true, ["Machine Gunner"]  = true,
    ["Refractor"]        = true, ["Psycho Slayer"]   = true,
  },
  SkipAirTargeting = {
    ["Slammer"]        = true, ["Mobster"]        = true,
    ["Golden Mobster"] = true, ["Toxicnator"]     = true,
  },
  SkipMedicBuff = {
    ["Refractor"]        = true,
    ["Mine Layer"]       = true,
    ["Golden Mine Layer"]= true,
  },
}

local LoadoutTypes = {}
local Initialized = false

local FEnemies = {}
local EProgCache = {}
local FTowers = {}
local TStunCache = {}
local TKritzCache = {}
local TRangeCache = {}
local TDPSCache = {}
local ALCache = {}
local AUCache = {}
local TStealthCache  = {}
local ACfgCache = {}

local ActEnemies = {}

local NextGenChk = 0
local NextSpcChk = 0
local PathEnds = {}
local MedicPending = {}
local MEDIC_TO = 0.5
local MobLastUsed = {}
local MobPending = {}
local MOB_TO = 0.4

local Q_CAP    = 8
local SQ_h      = table.create(Q_CAP)
local SQ_i     = table.create(Q_CAP)
local SQ_p       = table.create(Q_CAP)
local SQ_th= table.create(Q_CAP)
local SQ_ab   = table.create(Q_CAP)
local SQ_hd      = 1
local SQ_tl      = 0
local SQ_sz      = 0

local SpcRunning = false

local function setTI(n)
  if setthreadidentity then setthreadidentity(n)
  elseif syn then syn.set_thread_identity(n) end
end

local function getTPos(tower)
  return tower:GetPosition()
end

local function getRange(tower)
  local h = tower.Hash
  local v = TRangeCache[h]
  if v then return v end
  v = tower:GetCurrentRange()
  TRangeCache[h] = v
  return v
end

local function getLvls(tower)
  local lh = tower.LevelHandler
  if not lh then return 0, 0 end
  return lh.Path1Level, lh.Path2Level
end

local function invalACache()
  table.clear(AUCache)
end

local function buildAList(hash, ah)
  local map = ah.AbilityIndexToNameMap
  local abs = ah.Abilities
  if not map or not abs then
    ALCache[hash] = nil
    ACfgCache[hash] = nil
    return
  end
  local t = table.create(3)
  local cfgs = table.create(3)
  for i = 1, 3 do
    local n = map[i]
    local ab = n and abs[n] or nil
    t[i] = ab
    cfgs[i] = ab and ab.Config or nil
  end
  ALCache[hash] = t
  ACfgCache[hash] = cfgs
end

local function onTAdd(hash, tower)
  FTowers[hash] = tower

  local ah = tower.AbilityHandler
  if ah then buildAList(hash, ah) end

  TRangeCache[hash] = tower:GetCurrentRange()

  if tower.LevelHandler then
    local levelStats = tower.LevelHandler:GetLevelStats()
    local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or nil
    local result = TUtils.CalculateDPS(levelStats, buffStats)
    TDPSCache[hash] = typeof(result) == "number" and result or 0
  end

  TStealthCache[hash] = tower.Stealth == true

  local bh = tower.BuffHandler
  if bh then
    local stunned = bh:IsStunned()
    local kritz = false
    for _, b in _pairs(bh.ActiveBuffs or {}) do
      if b and b.Name and _tostring(b.Name):match("^MedicKritz") then
        kritz = true; break
      end
    end
    TStunCache[hash] = stunned
    TKritzCache[hash]   = kritz
  end
end

local function onTRemove(hash)
  FTowers[hash]     = nil
  ALCache[hash]   = nil
  TStunCache[hash]  = nil
  TKritzCache[hash]    = nil
  TDPSCache[hash]      = nil
  TRangeCache[hash]    = nil
  TStealthCache[hash]  = nil
  ACfgCache[hash] = nil
end

local function onEAdd(hash, enemy)
  if enemy.IsFakeEnemy then return end
  FEnemies[hash] = enemy
  local mh = enemy.MovementHandler
  if mh then
    local pi = mh.PathIndex or 0
    EProgCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
  end
end

local function onERemove(hash)
  FEnemies[hash]    = nil
  EProgCache[hash] = nil
end

local function hookFn(tbl, key, wrapper)
  local orig = rawget(tbl, key) or tbl[key]
  if not orig then return end

  if clonefunction and detour_function then
    local ok, cloned = pcall(clonefunction, orig)
    if ok and cloned then
      pcall(detour_function, orig, newcclosure(function(...)
        return wrapper(cloned, ...)
      end))
      return
    end
  end

  local mt = getrawmetatable and getrawmetatable(tbl)
  if mt and setreadonly then pcall(setreadonly, mt, false) end
  tbl[key] = newcclosure and newcclosure(function(...) return wrapper(orig, ...) end)
        or function(...) return wrapper(orig, ...) end
end

local function hookAHC()

  local ahcPath = GameClass:FindFirstChild("TowerClass")
          and GameClass.TowerClass:FindFirstChild("AbilityHandlerClass")

  local ahc = nil
  if ahcPath then
    local ok, m = pcall(require, ahcPath)
    if ok then ahc = m end
  end

  if not ahc then
    local ok, upvals = pcall(debug.getupvalues, TowerClass.New)
    if ok and upvals then
      for _, v in _pairs(upvals) do
        if type(v) == "table" and rawget(v, "_GenerateAbilities") then
          ahc = v; break
        end
      end
    end
  end

  if not ahc then

    return false
  end

  hookFn(ahc, "_GenerateAbilities", function(orig, self, ...)
    orig(self, ...)
    local tower = self.Tower
    if tower and tower.Hash then
      buildAList(tower.Hash, self)
      table.clear(AUCache)
    end
  end)

  local ahcPath2 = GameClass:FindFirstChild("TowerClass")
           and GameClass.TowerClass:FindFirstChild("AbilityHandlerClass")
           and GameClass.TowerClass.AbilityHandlerClass:FindFirstChild("AbilityClass")
  local ac = nil
  if ahcPath2 then
    local ok, m = pcall(require, ahcPath2)
    if ok then ac = m end
  end
  if not ac then
    local ok, upvals = pcall(debug.getupvalues, ahc._GenerateAbilities)
    if ok and upvals then
      for _, v in _pairs(upvals) do
        if type(v) == "table" and rawget(v, "BeginCooldown") and rawget(v, "CanUse") then
          ac = v; break
        end
      end
    end
  end
  if ac then
    hookFn(ac, "BeginCooldown", function(orig, ab, ...)
      orig(ab, ...)
      AUCache[ab] = false
    end)
  end

  return true
end

local function hookTC()

  hookFn(TowerClass, "New", function(orig, ...)
    local tower = orig(...)
    if tower and tower.Hash then
      onTAdd(tower.Hash, tower)
    end
    return tower
  end)

  hookFn(TowerClass, "Destroy", function(orig, tower, ...)
    local hash = tower and tower.Hash
    orig(tower, ...)
    if hash then onTRemove(hash) end
  end)

  hookFn(TowerClass, "ApplyBuffData", function(orig, tower, ...)
    orig(tower, ...)
    local hash = tower and tower.Hash
    if not hash then return end
    local bh = tower.BuffHandler
    if not bh then return end
    local stunned = bh:IsStunned()
    local kritz = false
    for _, b in _pairs(bh.ActiveBuffs) do
      if b and b.Name and _tostring(b.Name):match("^MedicKritz") then
        kritz = true; break
      end
    end
    TStunCache[hash] = stunned
    TKritzCache[hash]   = kritz
    TRangeCache[hash]   = nil
    TDPSCache[hash]     = nil
  end)

  hookFn(TowerClass, "RemoveBuffData", function(orig, tower, ...)
    orig(tower, ...)
    local hash = tower and tower.Hash
    if not hash then return end
    local bh = tower.BuffHandler
    if not bh then return end
    local stunned = bh:IsStunned()
    local kritz = false
    for _, b in _pairs(bh.ActiveBuffs) do
      if b and b.Name and _tostring(b.Name):match("^MedicKritz") then
        kritz = true; break
      end
    end
    TStunCache[hash] = stunned
    TKritzCache[hash]   = kritz
    TRangeCache[hash]   = nil
    TDPSCache[hash]     = nil
  end)

  hookFn(TowerClass, "SetStealth", function(orig, tower, stealth, ...)
    orig(tower, stealth, ...)
    local hash = tower and tower.Hash
    if hash then TStealthCache[hash] = stealth == true end
  end)

  hookFn(TowerClass, "Upgrade", function(orig, tower, ...)
    if not tower then return orig(tower, ...) end
    local hash = tower.Hash
    local ok = pcall(orig, tower, ...)
    if ok and hash then
      TRangeCache[hash] = nil
      TDPSCache[hash]   = nil
      local ah = tower.AbilityHandler
      if ah then buildAList(hash, ah) end
    end
  end)
end

local function hookEC()
  hookFn(EnemyClass, "New", function(orig, ...)
    local enemy = orig(...)
    if enemy and enemy.Hash then
      onEAdd(enemy.Hash, enemy)
    end
    return enemy
  end)

  hookFn(EnemyClass, "Destroy", function(orig, enemy, ...)
    local hash = enemy and enemy.Hash
    orig(enemy, ...)
    if hash then onERemove(hash) end
  end)
end

local function hookPaths()
  if type(PathHandler) ~= "table" then return end
  local ok, positions = pcall(function()
    return PathHandler.GetEndNodePositions and PathHandler.GetEndNodePositions()
  end)
  if ok and type(positions) == "table" then
    for i, pos in _ipairs(positions) do
      PathEnds[i] = pos
    end
  end
end

local function populate()

  local rawE = EnemyClass.GetEnemies()
  if rawE then
    for hash, enemy in _pairs(rawE) do
      if enemy and not enemy.IsFakeEnemy and enemy.IsAlive then
        onEAdd(hash, enemy)
      end
    end
  end

  local rawT = TowerClass.GetTowers()
  if rawT then
    for hash, tower in _pairs(rawT) do
      if tower then
        onTAdd(hash, tower)
      end
    end
  end
end

local function snapEnemies()
  local arr, n = {}, 0
  for _, e in _pairs(FEnemies) do
    if e.IsAlive then n = n + 1; arr[n] = e end
  end
  return arr
end

local function isUsable(ab)
  if not ab then return false end
  local v = AUCache[ab]
  if v ~= nil then return v end
  v = ab:CanUse()
  AUCache[ab] = v
  return v
end

local function hasUsable(al)
  if not al then return false end
  for i = 1, 3 do
    local ab = al[i]
    if ab == nil then break end
    if isUsable(ab) then return true end
  end
  return false
end

local function useAb(ab)
  if not ab then return end
  AUCache[ab] = false
  local ok = ab:Use()

  if not ok then
    AUCache[ab] = nil
  end
end

local function enqueue(hash, index, pos, targetHash)
  local al = ALCache[hash]
  local ab = al and al[index]
  if ab then
    if not ab:CanUse() then return end
    ab:BeginCooldown()
    AUCache[ab] = false
  end
  if SQ_sz >= Q_CAP then return end
  SQ_tl = SQ_tl % Q_CAP + 1
  SQ_h[SQ_tl]       = hash
  SQ_i[SQ_tl]      = index
  SQ_p[SQ_tl]        = pos
  SQ_th[SQ_tl] = targetHash
  SQ_ab[SQ_tl]    = ab
  SQ_sz = SQ_sz + 1
end

local function cachePaths()
  if next(PathEnds) then return end
  hookPaths()
end

local MAX_E = 200
local ES_p    = table.create(MAX_E)
local ES_a  = table.create(MAX_E)
local ES_h     = table.create(MAX_E)
local ES_g    = table.create(MAX_E)
local ES_b = table.create(MAX_E)
local ES_e  = table.create(MAX_E)
local ESSize = 0

local function buildESnap(enemies)
  local n = 0
  for _, e in _ipairs(enemies) do
    local ep = e:GetPosition()
    if not ep then continue end
    local ec = EProgCache[e.Hash]
    n = n + 1
    ES_p[n]    = ep
    ES_a[n]  = e.IsAirUnit
    ES_h[n]     = e.HealthHandler and e.HealthHandler:GetMaxHealth() or 0
    ES_g[n]    = ec and ec.progress or 0
    ES_b[n] = e.BountyDisplayHandler and e.BountyDisplayHandler.BountyCount or 0
    ES_e[n]  = e
  end
  for i = n + 1, ESSize do
    ES_p[i] = nil; ES_a[i] = nil; ES_h[i] = nil
    ES_g[i] = nil; ES_b[i] = nil; ES_e[i] = nil
  end
  ESSize = n
end

local function getFarEnemy(pos, range, noAir)
  local rsq = range * range
  local px, pz = pos.X, pos.Z
  local best, bestPrg = nil, -1
  for i = 1, ESSize do
    if noAir and ES_a[i] then continue end
    local ep = ES_p[i]; local dx = ep.X - px; local dz = ep.Z - pz
    if dx*dx + dz*dz > rsq then continue end
    if ES_g[i] > bestPrg then bestPrg = ES_g[i]; best = ep end
  end
  return best
end

local function getStrongEnemy(pos, range, noAir)
  local rsq = range * range
  local px, pz = pos.X, pos.Z
  local best, bestHP = nil, -1
  for i = 1, ESSize do
    if noAir and ES_a[i] then continue end
    local ep = ES_p[i]; local dx = ep.X - px; local dz = ep.Z - pz
    if dx*dx + dz*dz > rsq then continue end
    if ES_h[i] > bestHP then bestHP = ES_h[i]; best = ep end
  end
  return best
end

local function getRelicTgt()
  local bestPrg, bestPath = -1, 1
  for i = 1, ESSize do
    if ES_a[i] then continue end
    if ES_g[i] > bestPrg then
      bestPrg = ES_g[i]
      local ek = ES_e[i] and _tostring(ES_e[i]) or ""
      local ec = EProgCache[ek]
      local pi = ec and ec.pathIndex or 1
      if pi >= 1 then bestPath = pi end
    end
  end
  local ok, endNode = pcall(PathHandler.GetEnd, bestPath)
  if ok and endNode then return endNode.Position end
  return PathEnds[1]
end
local function hasEnemy()
  return ESSize > 0
end

local function hasStealthInRange(pos, radius)
  local rsq = radius * radius
  local px, pz = pos.X, pos.Z
  for _, e in _pairs(FEnemies) do
    if not e.IsAlive or not e.Stealth then continue end
    local ep = e:GetPosition()
    if ep then
      local dx = ep.X - px; local dz = ep.Z - pz
      if dx*dx + dz*dz <= rsq then return true end
    end
  end
  return false
end

local function hasStealthEnemy()
  for _, e in _pairs(FEnemies) do
    if e.IsAlive and e.Stealth then return true end
  end
  return false
end

local function hasAtkInRange(pos, range)
  local rsq = range * range
  local px, pz = pos.X, pos.Z
  for _, e in _pairs(FEnemies) do
    if not e.IsAlive or not e.AbilityHandler then continue end
    local ep = e:GetPosition()
    if ep then
      local dx = ep.X - px; local dz = ep.Z - pz
      if dx*dx + dz*dz <= rsq then return true end
    end
  end
  return false
end

local function getBestStealthTgt(selfHash)
  local bestHash, bestDPS, bestDistSq = nil, -1, math.huge
  for h, t in _pairs(FTowers) do
    if h == selfHash or not t.IsAlive then continue end
    if TStealthCache[h] then continue end
    local tp = getTPos(t)
    if not tp then continue end
    local dps = TDPSCache[h] or getDPS(t)
    if dps < bestDPS then continue end
    local minDsq = math.huge
    for _, e in _pairs(FEnemies) do
      if not e.IsAlive or not e.AbilityHandler then continue end
      local ep = e:GetPosition()
      if not ep then continue end
      local dx = ep.X - tp.X; local dz = ep.Z - tp.Z
      local dsq = dx*dx + dz*dz
      local eRange = e.AbilityHandler.AttackRange or 10
      if dsq <= eRange*eRange and dsq < minDsq then
        minDsq = dsq
      end
    end
    if minDsq == math.huge then continue end
    if dps > bestDPS or (dps == bestDPS and minDsq < bestDistSq) then
      bestDPS = dps; bestDistSq = minDsq; bestHash = h
    end
  end
  return bestHash
end

local function checkTowers(selfHash, pos, radius, checkHeal, checkStun, selfOnly)
  if selfOnly then
    local t = FTowers[selfHash]
    if not t then return false end
    if checkHeal then
      local hh = t.HealthHandler
      if hh and hh:GetHealth() < hh:GetMaxHealth() then return true end
    end
    if checkStun and TStunCache[selfHash] then return true end
    return false
  end
  local rsq = radius and radius * radius or nil
  local px = pos and pos.X or 0
  local pz = pos and pos.Z or 0
  for h, t in _pairs(FTowers) do
    if not t.IsAlive then continue end
    if rsq and h ~= selfHash then
      local tp = getTPos(t)
      if not tp then continue end
      local dx = tp.X - px; local dz = tp.Z - pz
      if dx*dx + dz*dz > rsq then continue end
    end
    if checkHeal then
      local hh = t.HealthHandler
      if hh and hh:GetHealth() < hh:GetMaxHealth() then return true end
    end
    if checkStun and TStunCache[h] then return true end
  end
  return false
end

local function getDPS(tower)
  local h = tower.Hash
  local v = TDPSCache[h]
  if v then return v end
  if not tower.LevelHandler then return 0 end
  local levelStats = tower.LevelHandler:GetLevelStats()
  local buffStats = tower.BuffHandler and tower.BuffHandler:GetStatMultipliers() or nil
  local result = TUtils.CalculateDPS(levelStats, buffStats)
  v = typeof(result) == "number" and result or 0
  TDPSCache[h] = v
  return v
end

local function isMedicBuff(tower)
  return TKritzCache[tower.Hash] == true
end

local function getMedicTgt(medicTower, medicHash)
  local medicPos = getTPos(medicTower)
  if not medicPos then return nil end
  local medicRangeSq = getRange(medicTower) ^ 2
  local bestHash, bestDPS = nil, -1
  for hash, tower in _pairs(FTowers) do
    if hash == medicHash or not tower.IsAlive then continue end
    if SETTINGS.SkipMedicBuff[tower.Type or ""] then continue end
    if isMedicBuff(tower) then continue end
    local tPos = getTPos(tower)
    if not tPos then continue end
    local _dx = tPos.X - medicPos.X; local _dz = tPos.Z - medicPos.Z
    if _dx*_dx + _dz*_dz > medicRangeSq then continue end
    local dps = TDPSCache[hash] or getDPS(tower)
    if dps > bestDPS then bestDPS = dps; bestHash = hash end
  end
  return bestHash
end

local function needsHeal(medicHash)
  for h, t in _pairs(FTowers) do
    if h == medicHash or not t.IsAlive then continue end
    if t.v10 and t.v10.NoHeal then continue end
    local hh = t.HealthHandler
    if not hh then continue end
    if hh:GetHealth() < hh:GetMaxHealth() then return true end
  end
  return false
end

local function getCMedicTgt(hash)
  local best, bestDPS = nil, -1
  for h, t in _pairs(FTowers) do
    if h == hash or not t.IsAlive then continue end
    if t.v10 and t.v10.NoHeal then continue end
    local tp = getTPos(t)
    if not tp then continue end
    local hh = t.HealthHandler
    if not hh then continue end
    local dps = TDPSCache[h] or getDPS(t)
    if dps > bestDPS then bestDPS = dps; best = tp end
  end
  return best
end

local function getMobTgt(tower)
  local pos = getTPos(tower)
  if not pos then return nil end
  local rsq = getRange(tower)^2
  local now = _tick()
  for id, data in _pairs(MobPending) do
    local e = data.enemy
    local hb = e and e.BountyDisplayHandler and e.BountyDisplayHandler.BountyCount > 0
    if hb or now - data.time > MOB_TO or not (e and e.IsAlive) then
      MobPending[id] = nil
    end
  end
  local bE, bHP, bPrg = nil, -1, -1
  for i = 1, ESSize do
    if ES_a[i] then continue end
    if ES_b[i] > 0 then continue end
    local id = _tostring(ES_e[i])
    if MobPending[id] then continue end
    local _ep = ES_p[i]; local _dx = _ep.X - pos.X; local _dz = _ep.Z - pos.Z
    if _dx*_dx + _dz*_dz > rsq then continue end
    if ES_h[i] > bHP or (ES_h[i] == bHP and ES_g[i] > bPrg) then
      bHP = ES_h[i]; bPrg = ES_g[i]; bE = ES_e[i]
    end
  end
  return bE
end

local function procMobster(tower, hash, now)
  local al = ALCache[hash]
  if not hasUsable(al) then return end
  if MobLastUsed[hash] and now - MobLastUsed[hash] < CONFIG.MobsterDelay then return end
  for i = 1, 3 do
    local ab = al[i]
    if isUsable(ab) then
      local e = getMobTgt(tower)
      if e then
        local ep = e:GetPosition()
        if ep then
          enqueue(hash, i, ep, nil)
          MobPending[_tostring(e)] = { enemy=e, time=now }
          MobLastUsed[hash] = now
          break
        end
      end
    end
  end
end

local function procGeneric(tower, hash, now)
  local al = ALCache[hash]
  if not hasUsable(al) then return end
  local cfgs = ACfgCache[hash]
  if not cfgs then return end

  local pos = getTPos(tower)
  local range = getRange(tower)

  for i = 1, 3 do
    local ab = al[i]
    if not ab or not isUsable(ab) then continue end
    local cfg = cfgs[i]
    if not cfg then continue end

    local tPos, allow = nil, false

    if cfg.SpawnStaticEntityData then
      local sed = cfg.SpawnStaticEntityData
      local entry = (type(sed) == "table" and sed[1]) and sed[1] or sed
      local entityType = entry and (entry.StaticEntityType or entry.Name)
      local beh = entityType and getStaticBehavior(entityType)
      if beh == SEBE.Heal then
        local now2 = _tick()
        local pd = MedicPending[hash]
        if pd then
          if now2 - pd.time > MEDIC_TO then MedicPending[hash] = nil
          else allow = false end
        end
        if not (MedicPending[hash]) and needsHeal(hash) then
          local th = getCMedicTgt(hash)
          if th then
            enqueue(hash, i, nil, th)
            MedicPending[hash] = { time = now2 }
            break
          end
        end
      elseif beh == SEBE.Attack or beh == SEBE.PathSpawn then
        local cr = cfg.ManualAimCustomRange or (cfg.ManualAimInfiniteRange and 9999 or range)
        if cfg.IsManualAimAtPath or cfg.IsManualAimAtGround then
          if cfg.ManualAimInfiniteRange then
            tPos = getRelicTgt()
          elseif pos then
            tPos = getFarEnemy(pos, cr, false)
          end
          allow = tPos ~= nil
        else
          allow = hasEnemy()
        end
      end
    end

    if cfg.SpawnPathEntityData and hasEnemy() then
      if cfg.IsManualAimAtPath then
        if cfg.ManualAimInfiniteRange then
          tPos = getRelicTgt()
        elseif pos then
          tPos = getFarEnemy(pos, range, false)
        end
        allow = tPos ~= nil
      else
        allow = true
      end
    end

    if not allow and cfg.HasRevealEffect and pos then
      local radius = cfg.UseTowerRangeForRadius and range or (cfg.EffectRadius or range)
      allow = hasStealthInRange(pos, radius)
    end

    if cfg.ProjectileHitDataAffectTowers then
      local phd = cfg.ProjectileHitData
      if phd and phd.TowerStealthDuration then
        local th = getBestStealthTgt(hash)
        if th then enqueue(hash, i, nil, th); break end
      elseif not allow then
        allow = hasEnemy()
        if allow and (cfg.IsManualAimAtGround or cfg.IsManualAimAtPath) then
          if cfg.ManualAimInfiniteRange then
            tPos = getRelicTgt()
          elseif pos then
            tPos = getFarEnemy(pos, range, false)
          end
          allow = tPos ~= nil
        end
      end
    end

    if not allow and cfg.RadiusDamage and cfg.EffectRadius and pos then
      local rsq = cfg.EffectRadius * cfg.EffectRadius
      local px, pz = pos.X, pos.Z
      for ei = 1, ESSize do
        local ep = ES_p[ei]
        local dx = ep.X - px; local dz = ep.Z - pz
        if dx*dx + dz*dz <= rsq then allow = true; break end
      end
    end

    if not allow and cfg.ProjectileHitData and not cfg.ProjectileHitDataAffectTowers then
      local phd = cfg.ProjectileHitData
      local hasEffect = phd.IsSplash or phd.SpawnStaticEntityData
      if hasEffect and (cfg.IsManualAimAtPath or cfg.IsManualAimAtGround) then
        if cfg.ManualAimInfiniteRange then
          tPos = getRelicTgt()
        elseif pos then
          tPos = getFarEnemy(pos, cfg.ManualAimCustomRange or range, false)
        end
        allow = tPos ~= nil
      elseif hasEffect and pos then
        tPos = getFarEnemy(pos, range, false)
        allow = tPos ~= nil
      end
    end

    if not allow and cfg.HasRadiusEffect and pos then
      local selfOnly = cfg.TargetSelf == true
      local radius = cfg.UseTowerRangeForRadius and range or (cfg.EffectRadius or range)
      if cfg.TowerBuffNames then
        allow = true
      end
      if not allow and (cfg.HealPercentage or cfg.HealAmount or cfg.Unstun) then
        allow = checkTowers(hash, pos, radius,
          cfg.HealPercentage ~= nil or cfg.HealAmount ~= nil,
          cfg.Unstun == true,
          selfOnly)
      end
    end

    if allow then
      enqueue(hash, i, tPos, nil)
      break
    end
  end
end

local function procAttack(attackHash, now)
  local atTower = FTowers[attackHash]
  if not atTower then return end
  local atPos = getTPos(atTower)
  if not atPos then return end

  for hash, tower in _pairs(FTowers) do
    if hash == attackHash or not tower.IsAlive then continue end
    local tp = getTPos(tower)
    if not tp then continue end
    local _dx = tp.X - atPos.X; local _dz = tp.Z - atPos.Z
    if _dx*_dx + _dz*_dz > getRange(tower)^2 then continue end
    local al = ALCache[hash]
    if not al then continue end
    local tType = tower.Type

    if tType == "Medic" then
      local _, p2 = getLvls(tower)
      if p2 < 4 then continue end
      if MedicPending[hash] then
        local pd = MedicPending[hash]
        local targetTower = pd.tower
        local timedOut = now - pd.time > MEDIC_TO
        local buffed = targetTower and targetTower.IsAlive and isMedicBuff(targetTower)
        if buffed or timedOut then
          MedicPending[hash] = nil
        else
          continue
        end
      end
      for i = 1, 3 do
        local ab = al[i]
        if isUsable(ab) then
          local th = getMedicTgt(tower, hash)
          if th then
            local targetTower = FTowers[th]
            enqueue(hash, i, nil, th)
            MedicPending[hash] = { tower = targetTower, time = now }
            break
          end
        end
      end
    end
  end
end

TAtk.OnClientEvent:Connect(newcclosure(function(data)
  if not Initialized or not next(FTowers) then return end
  local now = _tick()
  task.spawn(function()
    setTI(2)
    for _, d in _ipairs(data) do
      if d and d.X then procAttack(d.X, now) end
    end
  end)
end))

TChainAtk.OnClientEvent:Connect(newcclosure(function(data)
  if not Initialized or not next(FTowers) then return end
  local now = _tick()
  task.spawn(function()
    setTI(2)
    for _, d in _ipairs(data) do
      if d and d[1] then procAttack(d[1], now) end
    end
  end)
end))

RunService.RenderStepped:Connect(newcclosure(function()
  if not Initialized then return end
  local now = _tick()
  invalACache()

  if not next(FTowers) then return end

  if now < NextSpcChk then return end
  NextSpcChk = now + CONFIG.SpecialCheckInterval
  if SpcRunning then return end

  SpcRunning = true
  task.spawn(function()
    setTI(2)
    for hash, tower in _pairs(FTowers) do
      if not tower.IsAlive then continue end
      local tType = tower.Type
      if not SETTINGS.SeparateLogic[tType] then continue end
      if tType == "Medic" then
        continue
      end
      if not hasUsable(ALCache[hash]) then continue end
      if tType == "Mobster" or tType == "Golden Mobster" then
        local _, p2 = getLvls(tower)
        if p2 >= 3 and p2 <= 5 then procMobster(tower, hash, now) end
      else
        procGeneric(tower, hash, now)
      end
    end
    SpcRunning = false
  end)
end))

RunService.Heartbeat:Connect(newcclosure(function()
  if not Initialized then return end
  local now = _tick()
  invalACache()

  if not next(FTowers) then return end
  if now < NextGenChk then return end
  NextGenChk = now + CONFIG.CheckInterval

  cachePaths()
  buildESnap(ActEnemies)

  for hash, tower in _pairs(FTowers) do
    if not tower.IsAlive then continue end
    local tType = tower.Type
    if SETTINGS.SeparateLogic[tType] or SETTINGS.SkipGeneralLogic[tType] then continue end

    local al = ALCache[hash]
    if not hasUsable(al) then continue end

    local p1 = getLvls(tower)
    local pos = getTPos(tower)
    if not pos then continue end
    local range = getRange(tower)
    local noAir = SETTINGS.SkipAirTargeting[tType]

    for idx = 1, 3 do
      local ab = al[idx]
      if not isUsable(ab) then continue end

      local tPos, allow = nil, true

      if tType == "Jet Trooper" then
        allow = (idx == 2)

      elseif tType == "Toxicnator" then
        tPos = getStrongEnemy(pos, range, noAir)
        allow = tPos ~= nil

      else
        local cr = range

        local isDirect = SETTINGS.Directional[tType]
        local needPos = isDirect == true
        if ab.IsManualAimAtGround or ab.IsManualAimAtPath then needPos = true end

        if needPos then
          if ab.ManualAimInfiniteRange then
            tPos = getRelicTgt()
          else
            tPos = getFarEnemy(pos, ab.ManualAimCustomRange or cr, noAir)
          end
          allow = tPos ~= nil
        elseif not isDirect then
          local rsq = cr * cr
          local has = false
          local _px, _pz = pos.X, pos.Z
          for i = 1, ESSize do
            if noAir and ES_a[i] then continue end
            local _ep = ES_p[i]; local _dx = _ep.X - _px; local _dz = _ep.Z - _pz
            if _dx*_dx + _dz*_dz <= rsq then has = true; break end
          end
          allow = has
        end
      end

      if allow then
        if tPos then enqueue(hash, idx, tPos, nil)
        else useAb(ab) end
      end
    end
  end
end))

task.spawn(function()
  setTI(2)

  local ok, DataStoreResult = pcall(function()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    local loadout = lp:GetAttribute("Loadout") or {}
    if typeof(loadout) == "string" then
      for name in loadout:gmatch("[^,]+") do
        LoadoutTypes[name:match("^%s*(.-)%s*$")] = true
      end
    elseif typeof(loadout) == "table" then
      for _, name in _ipairs(loadout) do
        LoadoutTypes[name] = true
      end
    end
  end)
  if not ok then
  end

  repeat task.wait(0.1) until EnemyClass.GetEnemies() and TowerClass.GetTowers()

  populate()

  hookTC()
  hookEC()
  hookAHC()

  ActEnemies = snapEnemies()

  Initialized = true

  local progressEvent = dtc and dtc.CustomEvent and dtc.CustomEvent.new()
  if progressEvent then
    progressEvent:Connect(newcclosure(function(hash, pi, pct)
      EProgCache[hash] = { progress = pi + pct, pathIndex = pi }
    end))
  end

  local hookedMetatables = {}

  local function hookMovementHandler(hash, mh)
    if not mh then return end
    local mt = getrawmetatable(mh)
    if not mt then return end
    if hookedMetatables[mt] then
      local pi = mh.PathIndex or 0
      EProgCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
      return
    end
    hookedMetatables[mt] = true
    if setreadonly then setreadonly(mt, false) end
    local origNI = rawget(mt, "__newindex")
    mt.__newindex = newcclosure(function(t, k, v)
      if origNI then origNI(t, k, v) else rawset(t, k, v) end
      if k == "PathIndex" or k == "PathPercentage" then
        local pi = k == "PathIndex"       and v or (rawget(t, "PathIndex")       or 0)
        local pct = k == "PathPercentage"  and v or (rawget(t, "PathPercentage")  or 0)
        if progressEvent then progressEvent:Fire(hash, pi, pct) end
      end
    end)
    local pi = mh.PathIndex or 0
    EProgCache[hash] = { progress = pi + (mh.PathPercentage or 0), pathIndex = pi }
  end

  for hash, enemy in _pairs(FEnemies) do
    hookMovementHandler(hash, enemy.MovementHandler)
  end

  local _origOnEnemyAdded = onEAdd
  onEAdd = newcclosure(function(hash, enemy)
    _origOnEnemyAdded(hash, enemy)
    hookMovementHandler(hash, enemy.MovementHandler)
  end)

  while true do
    task.wait(CONFIG.CacheInterval)
    for k, e in _pairs(FEnemies) do
      if not e.IsAlive then onERemove(k) end
    end
    ActEnemies = snapEnemies()
  end
end)

task.spawn(function()
  setTI(2)
  while true do
    if SQ_sz > 0 then
      local h = SQ_hd
      local ok, serverCooldown = UseAbilReq:InvokeServer(
        SQ_h[h], SQ_i[h], SQ_p[h], SQ_th[h])
      local ab = SQ_ab[h]
      SQ_h[h] = nil; SQ_p[h] = nil; SQ_th[h] = nil; SQ_ab[h] = nil
      SQ_hd = h % Q_CAP + 1
      SQ_sz = SQ_sz - 1
      if ab then
        if ok and serverCooldown then
          ab.CooldownRemaining = serverCooldown
        elseif not ok then
          ab.CooldownRemaining = 0
          AUCache[ab] = nil
        end
      end
    end
    task.wait(0.03)
  end
end)

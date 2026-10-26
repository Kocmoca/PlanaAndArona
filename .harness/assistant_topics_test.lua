-- ===========================================================================
-- 桩测试：助手话题数据层
--   AssistantTopics.lua（gameplay 取数）+ AssistantTopics_UI.lua（UI 取数）
--   + CallTopicFunctions.lua（按钮入口）+ SummonAssistant.lua（召唤侧）
--
-- 要证明的事：
--   ① PlanaAssistant.sql 里写进 Kocmoca_Assistant_Topics 的**每一个** TopicBranch，
--      都能在 topicBranchFunctions 里找到函数（反过来也不许多注册）；
--   ② 16 个分支都能跑通、都返回 table（不抛错、不返回 nil）；
--   ③ 关键口径正确：
--      - 外国列表排除自己与助手玩家；本国分支只看自己；
--      - 领土内敌军只算"交战 + 站在自己地块上"；
--      - 被劫掠改良 / 区域、残血单位、缺粮、宜居不足、忠诚下降 都能被挑出来；
--      - 间谍两个分支走 allUnitsTypeTable + GetSpyOperations（自定义间谍类型也认）；
--      - UI 专属数据（粮食/宜居、忠诚、被劫掠区域、流言、每回合收入）只经
--        ExposedMembers.PlanaAssistantUI 取；UI 层没就绪时分支降级成空表、不抛错；
--      - 核弹 / 国库 / 流言 / 生产进度 取数与原版 UI 同源；
--   ④ CallTopicBranch 对未知分支 / 分支抛错都返回 nil 且不向外抛。
--
-- 跑法（工作目录 = 本项目根）：lua .harness/assistant_topics_test.lua
-- ===========================================================================
local UI_TOPICS_MODULE = "AssistantTopics_UI.lua"
local TOPICS_MODULE = "AssistantTopics.lua"
local CALL_MODULE = "CallTopicFunctions.lua"
local CALL_UI_MODULE = "AssistantTopics_Call_UI.lua"
local SQL_MODULE = "PlanaAssistant.sql"

local pass, fail = 0, 0
local function Check(name, cond, detail)
	if cond then
		pass = pass + 1
		print("  [OK]   " .. name)
	else
		fail = fail + 1
		print("  [FAIL] " .. name .. (detail ~= nil and ("   -> " .. tostring(detail)) or ""))
	end
end
local function Section(title) print("\n== " .. title) end

-- ---------------------------------------------------------------------------
-- 引擎桩
-- ---------------------------------------------------------------------------
local function NewInfoTable(list, keyField)
	local byKey = {}
	for _, row in ipairs(list) do
		if row.Index ~= nil then byKey[row.Index] = row end
		if keyField ~= nil and row[keyField] ~= nil then byKey[row[keyField]] = row end
	end
	setmetatable(byKey, { __call = function()
		local i = 0
		return function() i = i + 1; return list[i] end
	end })
	return byKey
end

local UNIT_WARRIOR = { Index = 1, UnitType = 'UNIT_WARRIOR', Name = 'LOC_UNIT_WARRIOR_NAME', Combat = 20 }
local UNIT_SPY     = { Index = 2, UnitType = 'UNIT_SPY',     Name = 'LOC_UNIT_SPY_NAME',     Combat = 0, Spy = true }
local UNIT_SETTLER = { Index = 3, UnitType = 'UNIT_SETTLER', Name = 'LOC_UNIT_SETTLER_NAME', Combat = 0 }
local UNIT_CUSTOM_SPY = { Index = 4, UnitType = 'UNIT_CUSTOM_SPY', Name = 'LOC_UNIT_CUSTOM_SPY_NAME', Combat = 0, Spy = true }
local BUILDING_PYRAMIDS = { Index = 11, BuildingType = 'BUILDING_PYRAMIDS', Name = 'LOC_BUILDING_PYRAMIDS_NAME', IsWonder = true, Cost = 220 }
local BUILDING_MONUMENT = { Index = 12, BuildingType = 'BUILDING_MONUMENT', Name = 'LOC_BUILDING_MONUMENT_NAME', IsWonder = false, Cost = 60 }
local DISTRICT_CAMPUS  = { Index = 21, DistrictType = 'DISTRICT_CAMPUS', Name = 'LOC_DISTRICT_CAMPUS_NAME' }
local IMPROVEMENT_FARM = { Index = 31, ImprovementType = 'IMPROVEMENT_FARM', Name = 'LOC_IMPROVEMENT_FARM_NAME' }
local WMD_NUKE = { Index = 41, WeaponType = 'WMD_NUCLEAR_DEVICE', Name = 'LOC_WMD_NUCLEAR_DEVICE_NAME' }
local WMD_THERMO = { Index = 42, WeaponType = 'WMD_THERMONUCLEAR_DEVICE', Name = 'LOC_WMD_THERMONUCLEAR_DEVICE_NAME' }
local OP_STEAL_TECH = { Index = 105, OperationType = 'OP_STEAL_TECH', Description = 'LOC_OP_STEAL_TECH_NAME', Icon = 'ICON_OP_STEAL_TECH' }
local ASSISTANT_PLANA_ROW = { AssistantType = 'ASSISTANT_PLANA', LeaderType = 'LEADER_KOCMOCA_PLANA' }

GameInfo = {
	Units = NewInfoTable({ UNIT_WARRIOR, UNIT_SPY, UNIT_SETTLER, UNIT_CUSTOM_SPY }, 'UnitType'),
	Buildings = NewInfoTable({ BUILDING_PYRAMIDS, BUILDING_MONUMENT }, 'BuildingType'),
	Districts = NewInfoTable({ DISTRICT_CAMPUS }, 'DistrictType'),
	Improvements = NewInfoTable({ IMPROVEMENT_FARM }, 'ImprovementType'),
	WMDs = NewInfoTable({ WMD_NUKE, WMD_THERMO }, 'WeaponType'),
	UnitOperations = NewInfoTable({ OP_STEAL_TECH }, 'OperationType'),
	Kocmoca_Assistants = NewInfoTable({ ASSISTANT_PLANA_ROW }, 'AssistantType'),
	Leaders = { LEADER_TRAJAN = { Name = 'LOC_LEADER_TRAJAN_NAME' },
		LEADER_KOCMOCA_PLANA = { Name = 'LOC_LEADER_KOCMOCA_PLANA_NAME' },
		LEADER_TOMYRIS = { Name = 'LOC_LEADER_TOMYRIS_NAME' } },
	Civilizations = { CIVILIZATION_ROME = { Name = 'LOC_CIVILIZATION_ROME_NAME' },
		CIVILIZATION_SCYTHIA = { Name = 'LOC_CIVILIZATION_SCYTHIA_NAME' } },
	-- Support_Functions 载入时要用
	TerrainClasses = { TERRAIN_CLASS_WATER = { Index = 1 }, TERRAIN_CLASS_MOUNTAIN = { Index = 2 } },
}

-- 地图：10x10，plotIndex = y*10 + x
local MAP_SIZE = 10
local plotOwners = {}
local function NewPlot(x, y)
	local plotIndex = y * MAP_SIZE + x
	return {
		GetX = function() return x end,
		GetY = function() return y end,
		GetIndex = function() return plotIndex end,
		GetOwner = function() return plotOwners[plotIndex] or -1 end,
		IsImprovementPillaged = function() return false end,
		GetImprovementType = function() return -1 end,
		GetDistrictType = function() return -1 end,
	}
end
Map = {
	GetPlot = function(x, y)
		if x == nil or y == nil or x < 0 or y < 0 or x >= MAP_SIZE or y >= MAP_SIZE then return nil end
		return NewPlot(x, y)
	end,
	GetPlotByIndex = function(plotIndex)
		if plotIndex == nil or plotIndex < 0 or plotIndex >= MAP_SIZE * MAP_SIZE then return nil end
		return NewPlot(plotIndex % MAP_SIZE, math.floor(plotIndex / MAP_SIZE))
	end,
	GetPlotCount = function() return MAP_SIZE * MAP_SIZE end,
	GetPlotDistance = function(x1, y1, x2, y2)
		return math.max(math.abs(x1 - x2), math.abs(y1 - y2))
	end,
}

local function NewCollection(list)
	return { Members = function()
		local i = 0
		return function()
			i = i + 1
			local value = list[i]
			if value == nil then return nil end
			return i, value
		end
	end }
end

-- 单位桩
local function NewUnitStub(id, typeIndex, ownerID, x, y, damage)
	local unit = { id = id, typeIndex = typeIndex, ownerID = ownerID, x = x, y = y, damage = damage or 0 }
	function unit.GetID() return id end
	function unit.GetType() return typeIndex end
	function unit.GetOwner() return ownerID end
	function unit.GetX() return x end
	function unit.GetY() return y end
	function unit.GetDamage() return unit.damage end
	function unit.GetCombat() return (GameInfo.Units[typeIndex] ~= nil and GameInfo.Units[typeIndex].Combat) or 0 end
	function unit.GetMilitaryFormation() return 0 end
	function unit.GetSpyOperation() return unit.spyOperation end
	function unit.GetSpyOperationEndTurn() return unit.spyEndTurn end
	return unit
end

-- 城市桩
local function NewCityStub(id, ownerID, x, y, options)
	options = options or {}
	local city = { id = id, ownerID = ownerID, x = x, y = y }
	function city.GetID() return id end
	function city.GetOwner() return ownerID end
	function city.GetName() return 'LOC_CITY_STUB_' .. tostring(id) end
	function city.GetX() return x end
	function city.GetY() return y end
	function city.GetPopulation() return options.population or 5 end
	function city.GetGrowth() return options.growth end
	function city.GetCulturalIdentity() return options.culturalIdentity end
	function city.GetDistricts() return NewCollection(options.districts or {}) end
	local pillagedBuildings = options.pillagedBuildings or {}
	function city.GetBuildings()
		return { IsPillaged = function(_, buildingIndex) return pillagedBuildings[buildingIndex] == true end }
	end
	return city
end

-- 区域桩
local function NewDistrictStub(id, ownerID, city, x, y, pillaged)
	local district = { id = id }
	function district.GetID() return id end
	function district.GetType() return DISTRICT_CAMPUS.Index end
	function district.GetCity() return city end
	function district.GetX() return x end
	function district.GetY() return y end
	function district.IsPillaged() return pillaged == true end
	return district
end

-- 玩家桩
local players = {}
local function NewPlayerStub(playerID, options)
	options = options or {}
	local state = {
		playerID = playerID,
		units = options.units or {},
		cities = options.cities or {},
		districts = options.districts or {},
		atWarWith = options.atWarWith or {},
		goldBalance = options.goldBalance or 0,
		goldYield = options.goldYield or 0,
		weaponCounts = options.weaponCounts or {},
	}
	local player = {}
	function player.GetID() return playerID end
	function player.IsMajor() return options.isMajor ~= false end
	function player.GetUnits() return NewCollection(state.units) end
	function player.GetCities() return NewCollection(state.cities) end
	function player.GetDistricts() return NewCollection(state.districts) end
	function player.GetDiplomacy()
		-- 冒号调用：第一个参数是 self（支持函数里就是 firstPlayer:GetDiplomacy():IsAtWarWith(id)）
		return { IsAtWarWith = function(_, otherID) return state.atWarWith[otherID] == true end,
			HasMet = function() return true end }
	end
	function player.GetTreasury()
		return { GetGoldBalance = function() return state.goldBalance end,
			GetGoldYield = function() return state.goldYield end }
	end
	function player.GetWMDs()
		return { GetWeaponCount = function(_, weaponIndex) return state.weaponCounts[weaponIndex] or 0 end }
	end
	player.GetName = function() return 'LOC_PLAYER_' .. tostring(playerID) end
	player.state = state
	return player
end

Players = setmetatable({}, { __index = function(t, key)
	local p = NewPlayerStub(key)
	rawset(t, key, p)
	return p
end })

PlayerConfigurations = {
	[0] = { GetPlayerName = function() return 'LOC_PLAYER_TRAJAN' end,
		GetLeaderTypeName = function() return 'LEADER_TRAJAN' end,
		GetCivilizationTypeName = function() return 'CIVILIZATION_ROME' end },
	[1] = { GetPlayerName = function() return 'LOC_PLAYER_TOMYRIS' end,
		GetLeaderTypeName = function() return 'LEADER_TOMYRIS' end,
		GetCivilizationTypeName = function() return 'CIVILIZATION_SCYTHIA' end },
	[2] = { GetPlayerName = function() return 'LOC_PLAYER_2' end,
		GetLeaderTypeName = function() return 'LEADER_TRAJAN' end,
		GetCivilizationTypeName = function() return 'CIVILIZATION_ROME' end },
	[4] = { GetPlayerName = function() return 'LOC_PLAYER_PLANA' end,
		GetLeaderTypeName = function() return 'LEADER_KOCMOCA_PLANA' end,
		GetCivilizationTypeName = function() return 'CIVILIZATION_ROME' end },
}

PlayerManager = {
	GetAliveMajorIDs = function() return { 0, 1, 2, 4 } end,
	GetWasEverAliveMajorIDs = function() return { 0, 1, 2, 4 } end,
	GetAliveIDs = function() return { 0, 1, 2, 3, 4 } end,
}

local allUnits = {}   -- { [playerID] = { [unitID] = unit } }
UnitManager = {
	GetUnit = function(playerID, unitID)
		local playerUnits = allUnits[playerID]
		return playerUnits ~= nil and playerUnits[unitID] or nil
	end,
}

CityManager = {
	GetDistrictAt = function(x, y)
		for _, player in pairs(Players) do
			for _, district in ipairs((player.state and player.state.districts) or {}) do
				if district.GetX() == x and district.GetY() == y then return district end
			end
		end
		return nil
	end,
	GetCity = function(playerID, cityID)
		local player = Players[playerID]
		if player == nil or player.state == nil then return nil end
		for _, city in ipairs(player.state.cities or {}) do
			if city:GetID() == cityID then return city end
		end
		return nil
	end,
}

Cities = {
	GetPlotPurchaseCity = function(plot)
		if plot == nil then return nil end
		local ownerID = plot:GetOwner()
		if ownerID == -1 then return nil end
		local player = Players[ownerID]
		if player == nil then return nil end
		local cityList = player.state ~= nil and player.state.cities or {}
		for _, city in ipairs(cityList) do
			if city.GetX() == plot:GetX() and city.GetY() == plot:GetY() then
				return city
			end
		end
		-- 间谍站在城市区域内即可（桩里简化成"有城市就算"）
		return cityList[1]
	end,
}

local gossipTable = nil
local gameProps = {}
Game = {
	GetLocalPlayer = function() return 0 end,
	GetCurrentGameTurn = function() return 50 end,
	GetProperty = function(_, key) return gameProps[key] end,
	SetProperty = function(_, key, value) gameProps[key] = value end,
	GetGossipManager = function()
		return { GetRecentVisibleGossipStrings = function(_, earliestTurn, viewerID, subjectID)
			if gossipTable == nil then return nil end
			return gossipTable[subjectID] or {}
		end }
	end,
}

-- Mod Misc Tool 暴露的运行时数据
local productionByCity = {}
local spyOperationByUnit = {}
ExposedMembers = {
	ModMiscToolScript = { allUnitsTypeTable = {} },
	ModMiscToolUI = {
		GetCityProductionInfoUI = function(playerID, cityID)
			return productionByCity[playerID .. ':' .. cityID]
		end,
		GetSpyOperations = function(playerID, unitID)
			local operation = spyOperationByUnit[playerID .. ':' .. unitID]
			if operation == nil then return nil, nil, nil end
			return operation.index, operation.remaining, operation.total
		end,
	},
}

include = function() end   -- 桩里直接 require 真实支持函数文件

-- ---------------------------------------------------------------------------
-- 载入真实代码：支持函数 → 话题数据层 → 调用入口
-- ---------------------------------------------------------------------------
local function LoadRealFile(path)
	local chunk = assert(loadfile(path), "loadfile 失败: " .. path)
	chunk()
end

LoadRealFile("../Basilissa Mod Misc Tools/ModTool_Support_Functions.lua")
LoadRealFile(UI_TOPICS_MODULE)   -- UI 端取数：先挂到 ExposedMembers.PlanaAssistantUI
LoadRealFile(TOPICS_MODULE)      -- gameplay 话题层
LoadRealFile(CALL_MODULE)
LoadRealFile(CALL_UI_MODULE)

-- ---------------------------------------------------------------------------
Section('① 分支映射与 SQL 一致')
-- ---------------------------------------------------------------------------
local sqlBranches, sqlSeen = {}, {}
local sqlFile = assert(io.open(SQL_MODULE, "rb"), "读不到 " .. SQL_MODULE)
local sqlText = sqlFile:read("*a")
sqlFile:close()
for topicBranch in sqlText:gmatch("'(TOPIC_BRANCH_[A-Z_]+)'") do
	if sqlSeen[topicBranch] ~= true then
		sqlSeen[topicBranch] = true
		table.insert(sqlBranches, topicBranch)
	end
end

local registered = {}
for _, topicBranch in ipairs(GetTopicBranchFunctionNames()) do
	registered[topicBranch] = true
end

local missing, extra = {}, {}
for _, topicBranch in ipairs(sqlBranches) do
	if registered[topicBranch] ~= true then table.insert(missing, topicBranch) end
end
for topicBranch, _ in pairs(registered) do
	if sqlSeen[topicBranch] ~= true then table.insert(extra, topicBranch) end
end

Check('SQL 里共有 21 个 TopicBranch', #sqlBranches == 21, #sqlBranches)
Check('SQL 的每个分支都有函数', #missing == 0, table.concat(missing, ","))
Check('没有多注册 SQL 里不存在的分支', #extra == 0, table.concat(extra, ","))
Check('注册数量 = SQL 数量', #GetTopicBranchFunctionNames() == #sqlBranches)

-- ---------------------------------------------------------------------------
Section('② 构造场景数据')
-- ---------------------------------------------------------------------------
plotOwners = {}
for x = 0, 3 do
	for y = 0, 3 do
		plotOwners[y * MAP_SIZE + x] = 0   -- 玩家 0 的领土
	end
end
plotOwners[8 * MAP_SIZE + 8] = 2

local selfCity = NewCityStub(10, 0, 0, 0, {
	population = 7,
	growth = { GetFoodSurplus = function() return -2 end, GetFood = function() return 3 end,
		GetAmenities = function() return 1 end, GetAmenitiesNeeded = function() return 3 end },
	culturalIdentity = { GetLoyaltyPerTurn = function() return -1.5 end, GetLoyalty = function() return 40 end,
		GetMaxLoyalty = function() return 100 end, GetLoyaltyLevel = function() return 2 end },
	pillagedBuildings = { [BUILDING_MONUMENT.Index] = true },
})
local happyCity = NewCityStub(11, 0, 2, 2, {
	growth = { GetFoodSurplus = function() return 2 end, GetFood = function() return 9 end,
		GetAmenities = function() return 5 end, GetAmenitiesNeeded = function() return 3 end },
	culturalIdentity = { GetLoyaltyPerTurn = function() return 1 end, GetLoyalty = function() return 80 end,
		GetMaxLoyalty = function() return 100 end, GetLoyaltyLevel = function() return 4 end },
})
local pillagedDistrict = NewDistrictStub(30, 0, selfCity, 0, 0, true)
local healthyDistrict = NewDistrictStub(31, 0, happyCity, 2, 2, false)

local foreignCity = NewCityStub(20, 1, 5, 5, { population = 4 })
productionByCity['1:20'] = { productionType = 'building', typeIndex = BUILDING_PYRAMIDS.Index,
	typeName = 'BUILDING_PYRAMIDS', name = 'LOC_BUILDING_PYRAMIDS_NAME', progress = 120, cost = 220 }
productionByCity['0:10'] = { productionType = 'unit', typeIndex = UNIT_WARRIOR.Index,
	typeName = 'UNIT_WARRIOR', name = 'LOC_UNIT_WARRIOR_NAME', progress = 10, cost = 40 }

-- 单位：自己 1 个残血战士；外国 1 个在自己领土的战士 + 1 个在自己领土外的战士
local myWarrior = NewUnitStub(100, UNIT_WARRIOR.Index, 0, 0, 1, 60)
local enemyInTerritory = NewUnitStub(200, UNIT_WARRIOR.Index, 1, 2, 2, 0)
local enemyOutside = NewUnitStub(201, UNIT_WARRIOR.Index, 1, 8, 8, 0)
local mySettler = NewUnitStub(101, UNIT_SETTLER.Index, 0, 3, 3, 0)

-- 间谍：玩家 1 的 UNIT_SPY 在自己领土(1,1)，正在执行 105；玩家 2 的自定义间谍在(8,8) 没行动
local foreignSpy = NewUnitStub(300, UNIT_SPY.Index, 1, 1, 1, 0)
foreignSpy.spyOperation = OP_STEAL_TECH.Index
foreignSpy.spyEndTurn = 55
local customSpy = NewUnitStub(301, UNIT_CUSTOM_SPY.Index, 2, 8, 8, 0)
customSpy.spyOperation = -1
local spyTargetCity = NewCityStub(12, 0, 1, 1, {})
Players[0].state.cities = { selfCity, happyCity, spyTargetCity }
Players[1].state.cities = { foreignCity }
-- 助手玩家（幽灵 40）的首城：召唤侧 OnCityTransfered 要按 (1,1) 认首城
Players[40].state.cities = { NewCityStub(12, 40, 1, 1, {}) }
Players[1].state.atWarWith = { [0] = true }
Players[0].state.atWarWith = { [1] = true }
Players[1].state.goldBalance = 500
Players[1].state.goldYield = 17.5
Players[1].state.weaponCounts = { [WMD_NUKE.Index] = 2, [WMD_THERMO.Index] = 1 }
Players[0].state.cities = { selfCity, happyCity, spyTargetCity }

Players[0].state.units = { myWarrior, mySettler }
Players[1].state.units = { enemyInTerritory, enemyOutside, foreignSpy }
Players[2].state.units = { customSpy }
Players[3].state.units = {}
Players[4].state.units = { NewUnitStub(400, UNIT_WARRIOR.Index, 4, 0, 0, 0) }
allUnits[4] = { [400] = NewUnitStub(400, UNIT_WARRIOR.Index, 4, 0, 0, 0) }

Players[0].state.districts = { pillagedDistrict, healthyDistrict }
allUnits[0] = { [100] = myWarrior, [101] = mySettler }
allUnits[1] = { [200] = enemyInTerritory, [201] = enemyOutside, [300] = foreignSpy }
allUnits[2] = { [301] = customSpy }

SpyIndex = {
	[1] = { UNIT_SPY = { [300] = { unitType = 'UNIT_SPY', removed = false, damage = 0 } } },
	[2] = { UNIT_CUSTOM_SPY = { [301] = { unitType = 'UNIT_CUSTOM_SPY', removed = false, damage = 0 } } },
	[0] = { UNIT_WARRIOR = { [100] = { unitType = 'UNIT_WARRIOR', removed = false, damage = 60 } } },
}
ExposedMembers.ModMiscToolScript.allUnitsTypeTable = SpyIndex

spyOperationByUnit['1:300'] = { index = OP_STEAL_TECH.Index, remaining = 5, total = 12 }
gossipTable = {
	[1] = { { '他们的军队正在向你边境移动。', 48 }, { '他们刚建好了一座奇观。', 47 } },
	[2] = { { '他们的国库吃紧。', 46 } },
}

-- Mod Misc Tool 的 Asset 表桩：改良归属走这里（不扫地图）
local assetPlotIndexes = {
	['0:IMPROVEMENT_FARM'] = { 1 * MAP_SIZE + 0 },
	['0:DISTRICT_CAMPUS'] = { 0 * MAP_SIZE + 0, 2 * MAP_SIZE + 2 },   -- 城市(0,0) 一个、城市(2,2) 一个
}
ExposedMembers.ModMiscToolScript.GetPlayerAssetPlotIndexes = function(playerID, assetType)
	return assetPlotIndexes[playerID .. ':' .. assetType] or {}
end

-- 地图上的"被劫掠农场"：plot (0,1) 属于玩家 0
local pillagedPlotIndex = 1 * MAP_SIZE + 0
-- 区域地块：0 号地块是被劫掠的区域，22 号是完好的区域
local districtPlotIndexes = { [0] = true, [22] = true }
local plotByIndexCalls = 0
local baseGetPlotByIndex = Map.GetPlotByIndex
Map.GetPlotByIndex = function(plotIndex)
	plotByIndexCalls = plotByIndexCalls + 1
	local plot = baseGetPlotByIndex(plotIndex)
	if plot ~= nil and plotIndex == pillagedPlotIndex then
		plot.GetImprovementType = function() return IMPROVEMENT_FARM.Index end
		plot.IsImprovementPillaged = function() return true end
	end
	if plot ~= nil and districtPlotIndexes[plotIndex] then
		plot.GetDistrictType = function() return DISTRICT_CAMPUS.Index end
	end
	return plot
end

-- Mod Misc Tool 的 Asset 表（按地块记账）：GetPillageStatus 就是扫这张表，不扫地图
ExposedMembers.ModMiscToolScript.playerPlotsInfo = {
	[0] = {
		[pillagedPlotIndex] = { ['IMPROVEMENT_FARM'] = true },
		[0] = { ['DISTRICT_CAMPUS'] = true },
		[22] = { ['DISTRICT_CAMPUS'] = true },
	},
}
ExposedMembers.ModMiscToolUI.GetBuildingsIndexAtPlotUI = function() return { BUILDING_MONUMENT.Index } end

-- ---------------------------------------------------------------------------
Section('③ 外国分支（按玩家查 / 一次拿全）')
-- ---------------------------------------------------------------------------
-- 外国信息类：前端先选目标玩家，后端只算这一个玩家
local military = GetPlayerMilitaryUnitsList(1)
Check('按目标玩家取军事：玩家 1 的分组表', military[UNIT_WARRIOR.Index] ~= nil)
Check('单位数据保留 Basilissa 原字段（unitID/unitType/formation）', (function()
	local unitData = military[UNIT_WARRIOR.Index][0][1]
	return unitData.unitID == 200 and unitData.unitType == 'UNIT_WARRIOR' and unitData.formation == 0
end)())
Check('同一函数查自己也是同一套结构', GetPlayerMilitaryUnitsList(0)[UNIT_WARRIOR.Index] ~= nil)

local production = GetPlayerProductionProgress(1)
Check('按目标玩家取生产：只有该玩家的在建城市', #production == 1
	and production[1].productionInfo.typeName == 'BUILDING_PYRAMIDS')

local economy = GetPlayerEconomy(1)
Check('按目标玩家取经济：国库 500 / 每回合 17.5',
	economy.goldBalance == 500 and economy.goldYield == 17.5)

local spyAction = GetAllSpyUnitOfPlayer(1)
Check('按目标玩家取间谍行动：在偷科技', spyAction[300] ~= nil
	and spyAction[300].spyOperation == OP_STEAL_TECH.Index)

local gossip = GetGossipHistory(1)
Check('按目标玩家取流言（观看者=本地玩家）', #gossip == 2 and gossip[1].turn ~= nil)

-- 一次拿全的分支（奇观 / 核弹）
local wonderProgress = GetForeignWonderBuildProgress()
local wonderOfOne = nil
for _, entry in ipairs(wonderProgress) do if entry.playerID == 1 then wonderOfOne = entry end end
Check('奇观进度一次拿全：玩家 1 在建金字塔', wonderOfOne ~= nil
	and wonderOfOne.productionInfo.typeName == 'BUILDING_PYRAMIDS')
Check('奇观位置与进度同源', #GetForeignWonderLocation() == #wonderProgress)

local nukeInfo = GetForeignNukeNum()
Check('核弹一次拿全，且按 standard / extensive 分类返回', nukeInfo.standard ~= nil
	and nukeInfo.extensive ~= nil
	and nukeInfo.standard[1]['WMD_NUCLEAR_DEVICE'] == 2
	and nukeInfo.standard[1]['WMD_THERMONUCLEAR_DEVICE'] == 1)

-- ---------------------------------------------------------------------------
Section('④ 本国分支')
-- ---------------------------------------------------------------------------
Check('先筛敌对玩家：只有玩家 1 和自己交战', (function()
	local ids = GetEnemyPlayerIDs(0)
	return #ids == 1 and ids[1] == 1
end)())

-- 只允许查"交战玩家"的部队：记录 GetPlayerUnitsList 被问到的玩家
local enemyQueryCalls = {}
local originalGetPlayerUnitsList = GetPlayerUnitsList
GetPlayerUnitsList = function(playerID)
	table.insert(enemyQueryCalls, playerID)
	return originalGetPlayerUnitsList(playerID)
end
local enemies = GetEnemiesInTerritory(0)
GetPlayerUnitsList = originalGetPlayerUnitsList
Check('领土内敌军：只算交战 + 站在自己地块上', #enemies == 1 and enemies[1].unitID == 200,
	#enemies)
Check('领土内敌军：只遍历交战玩家的部队（不扫所有玩家）',
	#enemyQueryCalls == 1 and enemyQueryCalls[1] == 1, table.concat(enemyQueryCalls, ","))

local loyalties = GetLoyaltyDecreasingCities(0)
Check('忠诚下降只挑 GetLoyaltyPerTurn < 0 的城市', #loyalties == 1 and loyalties[1].cityID == 10
	and loyalties[1].loyaltyPerTurn == -1.5)

local starving = GetPopulationDecreasingCities(0)
Check('缺粮城市 = 粮食盈余 < 0', #starving == 1 and starving[1].cityID == 10
	and starving[1].foodSurplus == -2)

local lowAmenity = GetLowAmenityCities(0)
Check('宜居不足 = 宜居 < 需求', #lowAmenity == 1 and lowAmenity[1].cityID == 10
	and lowAmenity[1].amenitiesNet == -2)

local spiesInTerritory = GetSpyActionInTerritory(0)
Check('领土内敌谍：玩家 1 的间谍（在自己地块）', #spiesInTerritory == 1
	and spiesInTerritory[1].spyOwnerID == 1 and spiesInTerritory[1].unitID == 300)
Check('敌谍带正在执行的行动', spiesInTerritory[1].operation ~= nil
	and spiesInTerritory[1].operation.spyOperation == OP_STEAL_TECH.Index)

local pillageStatus = GetPillageStatus(0)
Check('GetPillageStatus 返回三类劫掠表（改良/建筑/区域）',
	type(pillageStatus['improvement']) == 'table'
	and type(pillageStatus['building']) == 'table'
	and type(pillageStatus['district']) == 'table')
Check('GetPillageStatus：被劫掠的农场/区域/建筑被标出来，完好区域不算',
	pillageStatus['improvement'][pillagedPlotIndex] == true
	and pillageStatus['district'][0] == true
	and pillageStatus['district'][22] == nil
	and pillageStatus['building'][0] == true
	and pillageStatus['building'][22] == nil)

plotByIndexCalls = 0
local pillageAssets = GetPillagedAssets(0)
Check('劫掠合并成一条分支：三类分开返回', type(pillageAssets['improvement']) == 'table'
	and type(pillageAssets['building']) == 'table'
	and type(pillageAssets['district']) == 'table')
Check('劫掠分类：改良 1 / 建筑 1 / 区域 1',
	#pillageAssets['improvement'] == 1 and #pillageAssets['building'] == 1
	and #pillageAssets['district'] == 1)
Check('劫掠条目都带跳转坐标', pillageAssets['improvement'][1].iX ~= nil
	and pillageAssets['improvement'][1].iY ~= nil
	and pillageAssets['district'][1].plotIndex ~= nil)
Check('改良分类只挑自己地块上的', pillageAssets['improvement'][1].improvementType == 'IMPROVEMENT_FARM')
Check('建筑分类只留该城被劫掠的', pillageAssets['building'][1].buildingType == 'BUILDING_MONUMENT'
	and pillageAssets['building'][1].cityID == 10)
Check('区域分类只挑 IsPillaged 的', pillageAssets['district'][1].districtID == 30)
Check('劫掠分支不扫地图：只取 Asset 表里那几个地块', plotByIndexCalls <= 6, plotByIndexCalls)
Check('Asset 表没登记的资产不会被误报', (function()
	local savedPlots = ExposedMembers.ModMiscToolScript.playerPlotsInfo[0]
	ExposedMembers.ModMiscToolScript.playerPlotsInfo[0] = {}
	local emptyAssets = GetPillagedAssets(0)
	ExposedMembers.ModMiscToolScript.playerPlotsInfo[0] = savedPlots
	return #emptyAssets['improvement'] == 0 and #emptyAssets['building'] == 0
		and #emptyAssets['district'] == 0
end)())

local lowHealth = GetLowHealthUnits(0)
Check('残血单位阈值 50：只挑 60 伤害的战士', #lowHealth == 1 and lowHealth[1].unitID == 100
	and lowHealth[1].damage == 60)

-- ---------------------------------------------------------------------------
Section('⑤ 间谍索引（自定义类型 / 没有行动）')
-- ---------------------------------------------------------------------------
local allSpies = GetAllSpyUnitDataOfPlayer(2)
Check('自定义间谍类型也认（Units.Spy=true）', allSpies[301] ~= nil)
local actingSpies = GetAllSpyUnitOfPlayer(2)
Check('没在行动的间谍不进"行动表"', next(actingSpies) == nil)

-- ---------------------------------------------------------------------------
Section('⑥ 调用入口（targeted 规则）')
-- ---------------------------------------------------------------------------
Check('TopicNeedsTarget：外国军事/流言/生产/间谍/经济要选目标', (function()
	return TopicNeedsTarget('TOPIC_BRANCH_FOREIGN_MILITARY_UNITS')
		and TopicNeedsTarget('TOPIC_BRANCH_GOSSIP_HISTORY')
		and TopicNeedsTarget('TOPIC_BRANCH_FOREIGN_PRODUCTION_PROGRESS')
		and TopicNeedsTarget('TOPIC_BRANCH_FOREIGN_SPY_ACTION')
		and TopicNeedsTarget('TOPIC_BRANCH_FOREIGN_ECONOMY')
end)())
Check('TopicNeedsTarget：奇观/核弹/敌军/劫掠一次拿全', (function()
	return not TopicNeedsTarget('TOPIC_BRANCH_FOREIGN_WONDER_BUILD_PROGRESS')
		and not TopicNeedsTarget('TOPIC_BRANCH_FOREIGN_NUKE_NUM')
		and not TopicNeedsTarget('TOPIC_BRANCH_ENEMIES_IN_TERRITORY')
		and not TopicNeedsTarget('TOPIC_BRANCH_PILLAGED_ASSETS')
end)())

local result = CallTopicBranch('TOPIC_BRANCH_LOW_HEALTH_UNITS')
Check('CallTopicBranch 走通一个全量分支（不用目标）', type(result) == 'table' and #result == 1)
Check('targeted 分支缺目标 ⇒ nil', CallTopicBranch('TOPIC_BRANCH_FOREIGN_ECONOMY') == nil)
Check('targeted 分支给目标 ⇒ 只返回该玩家', (function()
	local economy = CallTopicBranch('TOPIC_BRANCH_FOREIGN_ECONOMY', 1)
	return economy ~= nil and economy.goldBalance == 500
end)())
Check('未知分支返回 nil', CallTopicBranch('TOPIC_BRANCH_DOES_NOT_EXIST') == nil)
Check('后端暴露给 UI：PlanaAssistantScript 的入口都在',
	ExposedMembers.PlanaAssistantScript ~= nil
	and type(ExposedMembers.PlanaAssistantScript.CallTopicBranch) == 'function'
	and type(ExposedMembers.PlanaAssistantScript.TopicNeedsTarget) == 'function'
	and type(ExposedMembers.PlanaAssistantScript.GetTopicBranchFunctionNames) == 'function'
	and type(ExposedMembers.PlanaAssistantScript.TopicIsAction) == 'function'
	and type(ExposedMembers.PlanaAssistantScript.RunTopicAction) == 'function')

-- 分支内部抛错时，CallTopicBranch 不许把错误抛给 UI
local originalGetPlotByIndex = Map.GetPlotByIndex
Map.GetPlotByIndex = function() error('boom') end
Check('分支抛错 ⇒ 返回 nil（不向外抛）',
	CallTopicBranch('TOPIC_BRANCH_PILLAGED_ASSETS') == nil)
Map.GetPlotByIndex = originalGetPlotByIndex

-- ---------------------------------------------------------------------------
Section('⑦ 召唤侧（SummonAssistant.lua）')
-- ---------------------------------------------------------------------------
local initUnitCalls = {}
UnitManager.InitUnit = function(playerID, unitType, x, y)
	table.insert(initUnitCalls, { playerID = playerID, unitType = unitType, x = x, y = y })
	return { GetID = function() return 900 + #initUnitCalls end }
end
Events = setmetatable({}, { __index = function(t, key)
	local ev = { Add = function() return true end, Remove = function() end, Call = function() end }
	rawset(t, key, ev)
	return ev
end })

LoadRealFile("SummonAssistant.lua")

-- 坏档：assistantInActive 里混进非表数据，InitializeAssistantPlayersData 不许抛错
gameProps['kocmoca_assistants_in_active_table_prop'] = { [5] = 'garbage' }
LoadData()
local okBadSave = pcall(InitializeAssistantPlayersData)
Check('坏档数据不会让 InitializeAssistantPlayersData 抛错', okBadSave)

-- 正常档：两层表 assistantInActive[召唤者][assistantType] = assistantData
gameProps['kocmoca_assistants_in_active_table_prop'] = {
	[0] = {
		['ASSISTANT_PLANA'] = {
			playerID = 40, ownerID = 0, assistantType = 'ASSISTANT_PLANA',
			unitType = 'UNIT_SPY', starterCityPlotIndex = 11,
		},
	},
}
LoadData()
InitializeAssistantPlayersData()
OnCityTransfered(40, 12, 0, 1)
Check('召唤数据按助手玩家（幽灵）索引：城市过户后补建单位',
	#initUnitCalls == 2 and initUnitCalls[1].unitType == 'UNIT_SETTLER'
	and initUnitCalls[2].unitType == 'UNIT_SPY')
Check('unitID 写回两层存档表', gameProps['kocmoca_assistants_in_active_table_prop'][0]['ASSISTANT_PLANA'].unitID == 902,
	gameProps['kocmoca_assistants_in_active_table_prop'][0]['ASSISTANT_PLANA'].unitID)
Check('只对助手自己的首城生效（别的城市不补建）', (function()
	initUnitCalls = {}
	OnCityTransfered(40, 99, 0, 1)
	return #initUnitCalls == 0
end)())

-- ---------------------------------------------------------------------------
Section('⑧ UI 取数层（AssistantTopics_UI.lua）与降级')
-- ---------------------------------------------------------------------------
local assistantUI = ExposedMembers.PlanaAssistantUI
Check('UI 端把 5 个取数函数挂到 ExposedMembers.PlanaAssistantUI', assistantUI ~= nil
	and type(assistantUI.GetCityGrowthInfo) == 'function'
	and type(assistantUI.GetCityLoyaltyInfo) == 'function'
	and type(assistantUI.GetGossipHistory) == 'function'
	and type(assistantUI.GetPlayerGoldYield) == 'function'
	and type(assistantUI.GetPlayerMaintenance) == 'function')

local growthInfo = assistantUI ~= nil and assistantUI.GetCityGrowthInfo(0, 10) or nil
Check('UI 取数：粮食盈余 / 宜居净值', growthInfo ~= nil
	and growthInfo.foodSurplus == -2 and growthInfo.amenitiesNet == -2)

local loyaltyInfo = assistantUI ~= nil and assistantUI.GetCityLoyaltyInfo(0, 10) or nil
Check('UI 取数：忠诚每回合 -1.5', loyaltyInfo ~= nil and loyaltyInfo.loyaltyPerTurn == -1.5)
Check('UI 取数：没有 GetCulturalIdentity 的城市返回 nil（资料片没开也不炸）',
	assistantUI.GetCityLoyaltyInfo(0, 12) == nil)
Check('UI 取数：城市不存在返回 nil', assistantUI.GetCityGrowthInfo(0, 999) == nil)

-- UI 层没就绪（还没加载/被重置）时，gameplay 侧只能降级成空表，不能抛错
local savedAssistantUI = ExposedMembers.PlanaAssistantUI
ExposedMembers.PlanaAssistantUI = nil
Check('UI 层缺失：人口/宜居/忠诚 分支给空表（劫掠分支不依赖 UI）', (function()
	local pillageWithoutUI = GetPillagedAssets(0)
	return #GetPopulationDecreasingCities(0) == 0 and #GetLowAmenityCities(0) == 0
		and #GetLoyaltyDecreasingCities(0) == 0 and #pillageWithoutUI['district'] == 1
end)())
Check('UI 层缺失：流言分支给空表', #GetGossipHistory(1) == 0)
Check('UI 层缺失：经济分支仍给出国库余额（只缺每回合收入）', (function()
	local economyInfo = GetPlayerEconomy(1)
	return economyInfo ~= nil and economyInfo.goldBalance == 500
		and economyInfo.goldYield == nil
end)())
ExposedMembers.PlanaAssistantUI = savedAssistantUI

-- ---------------------------------------------------------------------------
Section('⑨ UI 调用约定（AssistantTopics_Call_UI.lua）')
-- ---------------------------------------------------------------------------
Check('UI 端能问"这个分支要不要先选目标"',
	AssistantTopicNeedsTarget('TOPIC_BRANCH_FOREIGN_ECONOMY') == true
	and AssistantTopicNeedsTarget('TOPIC_BRANCH_FOREIGN_WONDER_BUILD_PROGRESS') == false)

local targets = GetAssistantTopicTargets(0)
Check('目标玩家列表排除自己、带名字和图标', #targets >= 1
	and targets[1].playerID ~= 0 and targets[1].playerName ~= nil and targets[1].leaderIcon ~= nil)

Check('缺目标时 UI 层直接拒绝（不调后端）',
	CallAssistantTopic('TOPIC_BRANCH_FOREIGN_ECONOMY', nil) == nil)
Check('给目标时 UI 层调通后端（只回该玩家）', (function()
	local economy = CallAssistantTopic('TOPIC_BRANCH_FOREIGN_ECONOMY', 1)
	return economy ~= nil and economy.goldBalance == 500
end)())
Check('全量分支不需要目标', type(CallAssistantTopic('TOPIC_BRANCH_PILLAGED_ASSETS')) == 'table')

-- 点击实例跳地图（GrayFox/Norn_UI 同款 UI.LookAtPlot）
local jumpRecords = {}
UI = { LookAtPlot = function(iX, iY) table.insert(jumpRecords, { iX = iX, iY = iY }) end }
Check('点击实例 → UI.LookAtPlot(iX, iY)', JumpToAssistantTopicEntry({ iX = 3, iY = 4 }) == true
	and #jumpRecords == 1 and jumpRecords[1].iX == 3 and jumpRecords[1].iY == 4)
Check('没有坐标的条目不跳', JumpToAssistantTopicEntry({ playerID = 1 }) == false
	and #jumpRecords == 1)

-- 分类展示：劫掠三类、核弹两类、通用键值表
local pillageSections = GetPillageDisplaySections(pillageAssets)
Check('劫掠展示分区：改良/建筑/区域（各自带 LOC label）', #pillageSections == 3
	and pillageSections[1].kind == 'improvement' and pillageSections[1].label ~= nil
	and pillageSections[2].kind == 'building' and pillageSections[3].kind == 'district')

local nukeSections = GetNukeDisplaySections(nukeInfo)
Check('核弹展示分区：standard / extensive', #nukeSections == 2
	and nukeSections[1].kind == 'standard' and nukeSections[2].kind == 'extensive'
	and nukeSections[1].players[1]['WMD_NUCLEAR_DEVICE'] == 2)

local keyedSections = GetKeyedDisplaySections({ [2] = 'b', [1] = 'a' })
Check('通用键值表 → 有序分区（数字键按数值排）', #keyedSections == 2
	and keyedSections[1].key == 1 and keyedSections[2].key == 2)

-- ---------------------------------------------------------------------------
Section('⑩ 行动类框架（Smiling Professor：城市 ×4 + 军团 ×2）')
-- ---------------------------------------------------------------------------
Check('SQL 登记了 Smiling Professor：场景 SHALE、话题类型 ACTION',
	sqlText:find('ASSISTANT_SMILING_PROFESSOR') ~= nil
	and sqlText:find('IMG_ASSISTANT_SCENE_SHALE') ~= nil
	and sqlText:find('ASSISTANT_TOPIC_ACTION') ~= nil)

Check('TopicIsAction：六条行动分支为真，信息分支为假', (function()
	local actionBranches = {
		'TOPIC_BRANCH_CITY_AUTO_REPAIR',
		'TOPIC_BRANCH_CITY_AUTO_FILL_BUILDINGS',
		'TOPIC_BRANCH_CITY_AUTO_REPEAT_PROJECTS',
		'TOPIC_BRANCH_CITY_AUTO_BUILD_IMPROVEMENTS',
		'TOPIC_BRANCH_CORPS_ASSIGN_UNITS',
		'TOPIC_BRANCH_CORPS_SET_TASKS',
	}
	for _, topicBranch in ipairs(actionBranches) do
		if TopicIsAction(topicBranch) ~= true then return false end
	end
	return TopicIsAction('TOPIC_BRANCH_PILLAGED_ASSETS') == false
end)())
Check('旧的"自动调兵"分支已移除', TopicIsAction('TOPIC_BRANCH_AUTO_DISPATCH_ARMY') == false
	and GetTopicBranchFunction('TOPIC_BRANCH_AUTO_DISPATCH_ARMY') == nil)

local repairPlan = CallTopicBranch('TOPIC_BRANCH_CITY_AUTO_REPAIR')
Check('城市修复计划：只含区域和建筑（不再带改良）',
	repairPlan ~= nil and repairPlan.actionType == 'city_auto_repair'
	and repairPlan.implemented == false
	and #repairPlan.entries['district'] == 1 and #repairPlan.entries['building'] == 1
	and repairPlan.entries['improvement'] == nil)

for _, case in ipairs({
	{ 'TOPIC_BRANCH_CITY_AUTO_FILL_BUILDINGS', 'city_auto_fill_buildings' },
	{ 'TOPIC_BRANCH_CITY_AUTO_REPEAT_PROJECTS', 'city_auto_repeat_projects' },
	{ 'TOPIC_BRANCH_CITY_AUTO_BUILD_IMPROVEMENTS', 'city_auto_build_improvements' },
	{ 'TOPIC_BRANCH_CORPS_SET_TASKS', 'corps_set_tasks' },
}) do
	local plan = CallTopicBranch(case[1])
	Check('占位计划：' .. case[1] .. '（implemented=false，空表）',
		plan ~= nil and plan.actionType == case[2] and plan.implemented == false
		and type(plan.entries) == 'table' and next(plan.entries) == nil)
end

local corpsPlan = CallTopicBranch('TOPIC_BRANCH_CORPS_ASSIGN_UNITS')
Check('军团分配计划：预览里是自己的军事单位', corpsPlan.actionType == 'corps_assign_units'
	and #corpsPlan.entries >= 1 and corpsPlan.entries[1].unitType ~= nil)

Check('行动执行层未接：RunTopicAction 统一返回 false',
	RunTopicAction('TOPIC_BRANCH_CITY_AUTO_REPAIR', repairPlan.entries) == false)

Check('UI 端能识别行动分支并调执行（框架返回 false）',
	AssistantTopicIsAction('TOPIC_BRANCH_CORPS_SET_TASKS') == true
	and AssistantTopicIsAction('TOPIC_BRANCH_FOREIGN_ECONOMY') == false
	and RunAssistantTopicAction('TOPIC_BRANCH_CORPS_SET_TASKS', {}) == false)

-- ---------------------------------------------------------------------------
print(string.format("\n== 结果：%d 项通过，%d 项失败", pass, fail))
if fail > 0 then os.exit(1) end

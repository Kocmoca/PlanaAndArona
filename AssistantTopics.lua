include('ModTool_Support_Functions.lua')

-- ===========================================================================
-- 助手（Plana / Arona）话题数据层 —— 跑在 **gameplay** 上下文
--
-- 数据来源：
--   ① Mod Misc Tool 的辅助函数库（开头 include 的 ModTool_Support_Functions.lua：
--      GetPlayerCitiesList / GetPlayerUnitsList / GetCityPlotIndex / CoordinateToPlotIndex /
--      IsUnitValidEnemyForPlayer / GetUnitIconAndName …）；
--   ② Mod Misc Tool 经 ExposedMembers 暴露的运行时数据 / UI 函数
--      （ModMiscToolScript.allUnitsTypeTable / GetPlayerAssetPlotIndexes、
--        ModMiscToolUI.GetCityProductionInfoUI / GetSpyOperations）—— 全都 pcall，拿不到就返回空；
--   ③ 本 mod 的 UI 端取数（AssistantTopics_UI.lua → ExposedMembers.PlanaAssistantUI）：
--      粮食/宜居、忠诚、被劫掠区域、流言历史、每回合金币。这几项 gameplay 端没有可靠接口，
--      按"UI 里写好、ExposedMembers 调"的约定走 UI；拿不到就这一项留空，不猜接口。
--
-- 调用时机（性能约束，别改成"打开界面就预取"）：
--   本文件**只在玩家点了某个对话选项时**被 CallTopicBranch 调一次：算这一次、返回一次，
--   算完不缓存、也不在文件加载 / 面板打开时跑任何遍历。
--   一个分支的代价大约是 O(玩家数 × 城市数) 或 O(自己资产数)（见各函数注释），
--   **不要为了某个分支去扫整张地图**：改良/区域的归属在 Mod Misc Tool 的 Asset 表里，
--   按类型问 GetPlayerAssetPlotIndexes 即可（PILLAGED_* 两个分支就是这么做的）。
--   新增分支也守这条：函数体内现算，别搞模块级缓存/预取。
--
-- 返回约定（UI 只按这些字段渲染）：
--   * "外国"类分支**不按外国裁剪**：执行层直接把所有存活主流玩家算完，按 playerID 存表
--     （result[playerID] = ...），UI 想显示谁自己挑；
--   * "本国"类分支（领土/忠诚/宜居/被劫掠/残血）必须指定 selfPlayerID —— 语义上属于某个人；
--   * 一律返回 table；没有内容返回空表，不返回 nil；名称给 LOC key / ICON 名，由 UI 本地化。
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 本地小工具
-- ---------------------------------------------------------------------------

-- 安全调方法：接口不在（资料片没开 / 对象是残缺句柄）就返回 nil，不抛错。
local function SafeCall(object, methodName, ...)
	if object == nil or methodName == nil then return nil end
	local method = object[methodName]
	if method == nil then return nil end
	local ok, result = pcall(method, object, ...)
	if not ok then return nil end
	return result
end

-- 玩家名（LOC key；原版 ActionPanel.lua 也是 Locale.Lookup(GetPlayerName())）
local function GetPlayerDisplayName(playerID)
	local playerConfig = PlayerConfigurations[playerID]
	if playerConfig == nil then return nil end
	return SafeCall(playerConfig, 'GetPlayerName')
end

-- 单位类型信息（走 Mod Misc Tool 的 GetUnitIconAndName）
local function GetUnitTypeInfo(unitTypeIndex)
	if unitTypeIndex == nil then return nil, nil, nil, nil end
	local unitRow = GameInfo.Units[unitTypeIndex]
	if unitRow == nil then return nil, nil, nil, nil end
	local unitIcon, unitPortrait, unitName = GetUnitIconAndName(unitTypeIndex)
	return unitRow.UnitType, unitName, unitIcon, unitPortrait
end

-- 所有活着的玩家（含城邦 / 蛮族）：查"谁进了我的领土"要用这个
local function GetOtherAlivePlayerIDs(selfPlayerID)
	local result = {}
	for _, playerID in ipairs(PlayerManager.GetAliveIDs()) do
		if playerID ~= selfPlayerID then
			table.insert(result, playerID)
		end
	end
	return result
end

-- 城市名/坐标一套（各分支复用）
local function GetCityBrief(city)
	if city == nil then return nil end
	return {
		cityID = SafeCall(city, 'GetID'),
		cityName = SafeCall(city, 'GetName'),
		iX = SafeCall(city, 'GetX'),
		iY = SafeCall(city, 'GetY'),
		plotIndex = GetCityPlotIndex(city),
	}
end

-- 当前生产（Mod Misc Tool 的 UI 接口；暴露点还没就绪时返回 nil）
local function GetCityProductionInfo(playerID, cityID)
	if ExposedMembers == nil or ExposedMembers.ModMiscToolUI == nil then return nil end
	local getter = ExposedMembers.ModMiscToolUI.GetCityProductionInfoUI
	if getter == nil then return nil end
	local ok, productionInfo = pcall(getter, playerID, cityID)
	if not ok then return nil end
	return productionInfo
end

-- 间谍行动（Mod Misc Tool 的 UI 接口；同上）
local function GetSpyOperations(playerID, unitID)
	if ExposedMembers == nil or ExposedMembers.ModMiscToolUI == nil then return nil, nil, nil end
	local getter = ExposedMembers.ModMiscToolUI.GetSpyOperations
	if getter == nil then return nil, nil, nil end
	local ok, spyOperation, spyRemainingTurns, spyTotalTurns = pcall(getter, playerID, unitID)
	if not ok then return nil, nil, nil end
	return spyOperation, spyRemainingTurns, spyTotalTurns
end

-- 调本 mod 的 UI 端取数（ExposedMembers.PlanaAssistantUI.*）；拿不到/报错返回 nil
local ASSISTANT_UI_NAMESPACE = 'PlanaAssistantUI'

local function CallAssistantUI(functionName, ...)
	if ExposedMembers == nil then return nil end
	local uiMembers = ExposedMembers[ASSISTANT_UI_NAMESPACE]
	if uiMembers == nil then return nil end
	local uiFunction = uiMembers[functionName]
	if uiFunction == nil then return nil end
	local ok, result = pcall(uiFunction, ...)
	if not ok then
		print("[PlanaAssistant] UI 取数失败: " .. tostring(functionName) .. " -> " .. tostring(result))
		return nil
	end
	return result
end

-- 调 Mod Misc Tool 暴露的 gameplay 接口（Asset 表等）；拿不到/报错都返回 nil
local function CallModMiscScript(functionName, ...)
	if ExposedMembers == nil then return nil end
	local script = ExposedMembers.ModMiscToolScript
	if script == nil then return nil end
	local scriptFunction = script[functionName]
	if scriptFunction == nil then return nil end
	local ok, result = pcall(scriptFunction, ...)
	if not ok then
		print("[PlanaAssistant] ModMiscTool 接口失败: " .. tostring(functionName) .. " -> " .. tostring(result))
		return nil
	end
	return result
end

-- ===========================================================================
-- 一、外国情报（ASSISTANT_TOPIC_FOREIGN_INFORMATION）
-- ===========================================================================
-- 执行层不按"外国"裁剪：这些函数把所有存活主流玩家算完，按 playerID 存表，
-- UI 想显示谁就取 result[playerID]（要不要过滤自己/助手，是 UI 的事）。

-- 单个玩家的陆军分组：list[unitTypeIndex][militaryFormation] = { unitData, ... }
-- （Basilissa 原实现；只修 unitTypeIndex 未定义、player/units 为 nil 时返回 nil 的两处）
function GetPlayerMilitaryUnitsList(playerID)
	local list = {}
	local player = Players[playerID]
	if player == nil then return list end
	local units = player:GetUnits()
	if units == nil then return list end
	local combatUnits = {}
	for i, unit in units:Members() do
		if unit:GetCombat() > 0 then
			table.insert(combatUnits, unit)
		end
	end
	for _,unit in ipairs(combatUnits) do
		local unitTypeIndex = unit:GetType()
		local unitData = {}
		unitData.unitID = unit:GetID()
		unitData.unitTypeIndex = unitTypeIndex
		unitData.unitType = GameInfo.Units[unitTypeIndex].UnitType
		unitData.formation = unit:GetMilitaryFormation()
		if list[unitTypeIndex] == nil then list[unitTypeIndex] = {} end
		if list[unitTypeIndex][unitData.formation] == nil then list[unitTypeIndex][unitData.formation] = {} end
		table.insert(list[unitTypeIndex][unitData.formation], unitData)
	end
	return list
end

function GetForeignWonderBuildProgress()
	local list = {}
	local function CheckProductionLists(playerID, city)
		local cityID = city:GetID()
		local productionInfo = GetCityProductionInfo(playerID, cityID)
		if productionInfo == nil then return end
		if productionInfo.productionType ~= 'building' then return end
		local buildingRow = GameInfo.Buildings[productionInfo.typeIndex]
		if buildingRow == nil then return end
		if buildingRow.IsWonder ~= true then return end
		local productionData = {}
		productionData.playerID = playerID
		productionData.cityID = cityID
		productionData.cityName = city:GetName()
		productionData.productionInfo = productionInfo
		table.insert(list, productionData)
	end
	for _,playerID in ipairs(PlayerManager.GetWasEverAliveMajorIDs()) do
		local player = Players[playerID]
		if player ~= nil then
			local playerCities = player:GetCities()
			for _,city in playerCities:Members() do
				CheckProductionLists(playerID, city)
			end
		end
	end
	return list
end

-- 奇观位置：同一份数据（含 cityID/cityName），单列一个分支方便 UI 换措辞
function GetForeignWonderLocation()
	return GetForeignWonderBuildProgress()
end

-- 流言（Gossip）历史：Game.GetGossipManager() 只在原版 UI 里用过（ARXManager.lua），
-- gameplay 端没有验证过 ⇒ 走 UI 取数（AssistantTopics_UI.GetGossipHistory）。
-- 观看者决定能看到什么，所以这里要一个 viewer（缺省 = 本地玩家）。
local GOSSIP_MAX_ENTRIES = 20

function GetGossipHistory(targetPlayerID)
	if targetPlayerID == nil then return {} end
	local gossipList = CallAssistantUI('GetGossipHistory', Game.GetLocalPlayer(), targetPlayerID, GOSSIP_MAX_ENTRIES)
	if gossipList == nil then return {} end
	return gossipList
end

-- 核弹数量（Basilissa 原实现）：playerWMDs[playerID][WeaponType] = count
-- 修三处：① 外层 extensiveWMDs 被同名 local 遮蔽（写进了每玩家的表）；② 少 ipairs；
--        ③ player:GetWMDs() / ExposedMembers.KocmocaWeaponScript 可能不存在
function GetForeignNukeNum()
	local standardWMDs = {}
	local extensiveWMDs = {}
	for _,playerID in ipairs(PlayerManager.GetAliveMajorIDs()) do
		local wmdTable, extensiveTable = GetPlayerWMDs(playerID)
		standardWMDs[playerID] = wmdTable
		extensiveWMDs[playerID] = extensiveTable
	end
	-- 键值对返回：UI 按 standard / extensive 两类分区展示
	-- （原来直接 return 两张表，调度层的 pcall 只接得住第一个，扩展表到不了 UI）
	return {
		standard = standardWMDs,
		extensive = extensiveWMDs,
	}
end

function GetPlayerWMDs(playerID)
	local player = Players[playerID]
	if player == nil then return {}, {} end
	--always return table
	local playerWMDs = player:GetWMDs()
	local wmdTable = {}
	local extensiveTable = {}
	if playerWMDs == nil then return wmdTable, extensiveTable end
	for weaponRow in GameInfo.WMDs() do
		if weaponRow.WeaponType ~= 'WMD_KOCMOCA_DUMMY_WH' then
			local count = playerWMDs:GetWeaponCount(weaponRow.Index) or 0
			wmdTable[weaponRow.WeaponType] = count
		end
	end
	local weaponScript = ExposedMembers.KocmocaWeaponScript
	if GameInfo.WMDs['WMD_KOCMOCA_DUMMY_WH'] ~= nil and weaponScript ~= nil then
		--extensive wmd
		for wmdRow in GameInfo.Kocmoca_WMD_Weapon_Types() do
			local weaponType = wmdRow.WeaponType
			extensiveTable[weaponType] = weaponScript.GetWeaponNumber(playerID, weaponType)
		end
	end
	return wmdTable, extensiveTable
end

-- 外国城市的生产进度：result[playerID] = { {city..., productionInfo}, ... }
function GetPlayerProductionProgress(playerID)
	local cities = {}
	for _,city in ipairs(GetPlayerCitiesList(playerID)) do
		local entry = GetCityProduction(playerID, city)
		if entry ~= nil then table.insert(cities, entry) end
	end
	return cities
end

function GetCityProduction(playerID, city)
	local productionInfo = GetCityProductionInfo(playerID, city:GetID())
	if productionInfo == nil then return nil end
	local entry = GetCityBrief(city)
	entry.productionInfo = productionInfo
	return entry
end

-- 外国间谍正在干什么：result[playerID] = { [unitID] = operationData }
-- 数据来自 Mod Misc Tool 的 allUnitsTypeTable（gameplay 侧缓存了所有玩家的单位），
-- 也就是"助手全知"的情报；要按玩家可见性收紧就在 UI 层过滤。
function GetPlayerEconomy(playerID)
	local player = Players[playerID]
	if player == nil then return nil end
	local treasury = player:GetTreasury()
	local goldYield = CallAssistantUI('GetPlayerGoldYield', playerID)
	local maintenance = CallAssistantUI('GetPlayerMaintenance', playerID)
	local netGold = nil
	if goldYield ~= nil and maintenance ~= nil then netGold = goldYield - maintenance end
	return {
		goldBalance = SafeCall(treasury, 'GetGoldBalance') or 0,
		goldYield = goldYield,
		maintenance = maintenance,
		netGold = netGold,
	}
end

-- ===========================================================================
-- 二、本国情报（ASSISTANT_TOPIC_NATIONAL_INFORMATION）
-- ===========================================================================
-- 这些分支必须指定 selfPlayerID —— 语义上属于某个玩家。

-- 领土内的敌军：**先筛出和我交战的玩家，再取他们的部队**
-- （原来是把所有玩家的所有单位过一遍再逐个判交战，玩家/单位一多就白跑）
function GetEnemiesInTerritory(selfPlayerID)
	local result = {}
	for _,enemyPlayerID in ipairs(GetEnemyPlayerIDs(selfPlayerID)) do
		for _,unit in ipairs(GetPlayerUnitsList(enemyPlayerID)) do
			local entry = GetEnemyUnitInTerritory(selfPlayerID, enemyPlayerID, unit)
			if entry ~= nil then table.insert(result, entry) end
		end
	end
	return result
end

-- 与我交战的玩家：一次外交查询一个玩家（原版 Diplomacy:IsAtWarWith 同款，辅助库里就是 IsPlayerAtWar）
function GetEnemyPlayerIDs(selfPlayerID)
	local result = {}
	for _,playerID in ipairs(PlayerManager.GetAliveIDs()) do
		if playerID ~= selfPlayerID and IsPlayerAtWar(selfPlayerID, playerID) then
			table.insert(result, playerID)
		end
	end
	return result
end

function GetEnemyUnitInTerritory(selfPlayerID, unitOwnerID, unit)
	if IsUnitValidEnemyForPlayer(selfPlayerID, unit) ~= true then return nil end
	local iX, iY = unit:GetX(), unit:GetY()
	local plot = Map.GetPlot(iX, iY)
	if plot == nil then return nil end
	if plot:GetOwner() ~= selfPlayerID then return nil end
	local unitType, unitName, unitIcon = GetUnitTypeInfo(unit:GetType())
	return {
		unitOwnerID = unitOwnerID,
		unitOwnerName = GetPlayerDisplayName(unitOwnerID),
		unitID = unit:GetID(),
		unitType = unitType,
		unitName = unitName,
		unitIcon = unitIcon,
		damage = unit:GetDamage(),
		iX = iX,
		iY = iY,
		plotIndex = plot:GetIndex(),
	}
end

-- 忠诚正在下降的城市：GetCulturalIdentity 只在 UI 里验证过（Expansion1/CityPanelCulture.lua），
-- gameplay 端没有可靠接口 ⇒ 走 UI 取数；资料片没开时 UI 返回 nil，本分支就是空表。
function GetLoyaltyDecreasingCities(selfPlayerID)
	local result = {}
	for _,city in ipairs(GetPlayerCitiesList(selfPlayerID)) do
		local entry = GetCityLoyaltyDecrease(selfPlayerID, city)
		if entry ~= nil then table.insert(result, entry) end
	end
	return result
end

function GetCityLoyaltyDecrease(selfPlayerID, city)
	local loyaltyInfo = CallAssistantUI('GetCityLoyaltyInfo', selfPlayerID, city:GetID())
	if loyaltyInfo == nil then return nil end
	if loyaltyInfo.loyaltyPerTurn == nil then return nil end
	if loyaltyInfo.loyaltyPerTurn >= 0 then return nil end
	local entry = GetCityBrief(city)
	entry.loyalty = loyaltyInfo.loyalty
	entry.maxLoyalty = loyaltyInfo.maxLoyalty
	entry.loyaltyPerTurn = loyaltyInfo.loyaltyPerTurn
	entry.loyaltyLevel = loyaltyInfo.loyaltyLevel
	return entry
end

-- 人口正在下降的城市
-- ⚠️ 原版没有"人口每回合变化"的接口，用**粮食赤字**近似：
--    foodSurplus < 0 ⇒ 正在饿肚子，粮仓一空就掉人口（读数走 UI，gameplay 端未验证）。
function GetPopulationDecreasingCities(selfPlayerID)
	local result = {}
	for _,city in ipairs(GetPlayerCitiesList(selfPlayerID)) do
		local entry = GetCityPopulationDecrease(selfPlayerID, city)
		if entry ~= nil then table.insert(result, entry) end
	end
	return result
end

function GetCityPopulationDecrease(selfPlayerID, city)
	local growthInfo = CallAssistantUI('GetCityGrowthInfo', selfPlayerID, city:GetID())
	if growthInfo == nil then return nil end
	if growthInfo.foodSurplus == nil then return nil end
	if growthInfo.foodSurplus >= 0 then return nil end
	local entry = GetCityBrief(city)
	entry.population = growthInfo.population
	entry.food = growthInfo.food
	entry.foodSurplus = growthInfo.foodSurplus
	return entry
end

-- 宜居度不够的城市：amenities < amenitiesNeeded（原版 CitySupport.lua 的算法，读数走 UI）
function GetLowAmenityCities(selfPlayerID)
	local result = {}
	for _,city in ipairs(GetPlayerCitiesList(selfPlayerID)) do
		local entry = GetCityLowAmenity(selfPlayerID, city)
		if entry ~= nil then table.insert(result, entry) end
	end
	return result
end

function GetCityLowAmenity(selfPlayerID, city)
	local growthInfo = CallAssistantUI('GetCityGrowthInfo', selfPlayerID, city:GetID())
	if growthInfo == nil then return nil end
	if growthInfo.amenitiesNet == nil then return nil end
	if growthInfo.amenitiesNet >= 0 then return nil end
	local entry = GetCityBrief(city)
	entry.population = growthInfo.population
	entry.amenities = growthInfo.amenities
	entry.amenitiesNeeded = growthInfo.amenitiesNeeded
	entry.amenitiesNet = growthInfo.amenitiesNet
	return entry
end

-- 我方领土里的敌方间谍：位置 = 单位所在地块 owner == 自己
--   有正在执行的行动就把 operation 一起带上；只是路过 / 赶路就 operation = nil。
function GetSpyActionInTerritory(selfPlayerID)
	local result = {}
	for _,otherPlayerID in ipairs(GetOtherAlivePlayerIDs(selfPlayerID)) do
		for unitID, unitData in pairs(GetAllSpyUnitDataOfPlayer(otherPlayerID)) do
			local entry = GetSpyInTerritory(selfPlayerID, otherPlayerID, unitID, unitData)
			if entry ~= nil then table.insert(result, entry) end
		end
	end
	return result
end

function GetSpyInTerritory(selfPlayerID, spyOwnerID, unitID, unitData)
	local unit = UnitManager.GetUnit(spyOwnerID, unitID)
	if unit == nil then return nil end
	local iX, iY = unit:GetX(), unit:GetY()
	local plot = Map.GetPlot(iX, iY)
	if plot == nil then return nil end
	if plot:GetOwner() ~= selfPlayerID then return nil end
	local unitType, unitName, unitIcon = GetUnitTypeInfo(unitData.unitType)
	return {
		spyOwnerID = spyOwnerID,
		spyOwnerName = GetPlayerDisplayName(spyOwnerID),
		unitID = unitID,
		unitType = unitType,
		unitName = unitName,
		unitIcon = unitIcon,
		iX = iX,
		iY = iY,
		plotIndex = plot:GetIndex(),
		operation = GetSpyActionInfo(spyOwnerID, unitID),
	}
end

-- 被劫掠的资产：改良 / 建筑 / 区域**合并成一条分支**，返回时按类别分好，UI 分类展示。
-- 位置和状态都由 GetPillageStatus 从 Asset 表算好（不扫地图），这里只把 plotIndex 翻成展示字段。
function GetPillagedAssets(selfPlayerID)
	local pillagedPlots = GetPillageStatus(selfPlayerID)
	return {
		improvement = GetPillagedImprovementEntries(pillagedPlots['improvement']),
		building = GetPillagedBuildingEntries(pillagedPlots['building']),
		district = GetPillagedDistrictEntries(pillagedPlots['district']),
	}
end

function GetPillagedImprovementEntries(pillagedImprovementPlots)
	local result = {}
	for plotIndex in pairs(pillagedImprovementPlots) do
		local entry = GetPillagedImprovement(plotIndex)
		if entry ~= nil then table.insert(result, entry) end
	end
	return result
end

function GetPillagedBuildingEntries(pillagedBuildingPlots)
	local result = {}
	for plotIndex in pairs(pillagedBuildingPlots) do
		for _,entry in ipairs(GetPillagedBuildingsInPlot(plotIndex)) do
			table.insert(result, entry)
		end
	end
	return result
end

function GetPillagedDistrictEntries(pillagedDistrictPlots)
	local result = {}
	for plotIndex in pairs(pillagedDistrictPlots) do
		local entry = GetPillagedDistrict(plotIndex)
		if entry ~= nil then table.insert(result, entry) end
	end
	return result
end

function GetPillagedImprovement(plotIndex)
	local plot = Map.GetPlotByIndex(plotIndex)
	if plot == nil then return nil end
	local improvementTypeIndex = plot:GetImprovementType()
	local improvementRow = improvementTypeIndex ~= nil and GameInfo.Improvements[improvementTypeIndex] or nil
	return {
		iX = plot:GetX(),
		iY = plot:GetY(),
		plotIndex = plotIndex,
		improvementType = improvementRow ~= nil and improvementRow.ImprovementType or nil,
		improvementName = improvementRow ~= nil and improvementRow.Name or nil,
	}
end

function GetPillageStatus(playerID)
	local pillagedPlots = {}
	pillagedPlots['improvement'] = {}
	pillagedPlots['building'] = {}
	pillagedPlots['district'] = {}
	local allPlayerPlots = ExposedMembers.ModMiscToolScript.playerPlotsInfo
	if allPlayerPlots == nil then return pillagedPlots end
	local playerPlots = allPlayerPlots[playerID]
	if playerPlots == nil then return pillagedPlots end
	local function CheckDistrictAndBuildingPillage(plotIndex, plot)
		local disType = plot:GetDistrictType()
		if disType == -1 then return end
		local iX = plot:GetX()
		local iY = plot:GetY()
		local district = CityManager.GetDistrictAt(iX, iY)
		if district ~= nil and district:IsPillaged() then pillagedPlots['district'][plotIndex] = true end
		local getBuildingsAtPlot = ExposedMembers.ModMiscToolUI ~= nil and ExposedMembers.ModMiscToolUI.GetBuildingsIndexAtPlotUI or nil
		local city = GetCityForPlot(iX, iY)
		if getBuildingsAtPlot == nil or city == nil then return end
		local buildingIndexList = getBuildingsAtPlot(iX, iY)
		local cityBuildings = city:GetBuildings()
		for _,buildingIndex in ipairs(buildingIndexList) do
			if cityBuildings:IsPillaged(buildingIndex) then pillagedPlots['building'][plotIndex] = true break end
		end
	end
	for plotIndex, plotData in pairs(playerPlots) do
		local plot = Map.GetPlotByIndex(plotIndex)
		if plot ~= nil and plot:IsImprovementPillaged() then pillagedPlots['improvement'][plotIndex] = true end
		if plot ~= nil then CheckDistrictAndBuildingPillage(plotIndex, plot) end
	end
	return pillagedPlots
end

-- 被劫掠的建筑：GetPillageStatus 只标了"这个地块上有被劫掠的建筑"，
-- 具体是哪一栋要按地块取建筑列表再筛（GetBuildingsIndexInPlot 会自己选 UI / gameplay 的取法）。
function GetPillagedBuildingsInPlot(plotIndex)
	local result = {}
	local plot = Map.GetPlotByIndex(plotIndex)
	if plot == nil then return result end
	local iX = plot:GetX()
	local iY = plot:GetY()
	local city = GetCityForPlot(iX, iY)
	if city == nil then return result end
	local cityBuildings = city:GetBuildings()
	for _,buildingIndex in ipairs(GetBuildingsIndexInPlot(plot)) do
		local entry = GetPillagedBuilding(plotIndex, iX, iY, city, cityBuildings, buildingIndex)
		if entry ~= nil then table.insert(result, entry) end
	end
	return result
end

function GetPillagedBuilding(plotIndex, iX, iY, city, cityBuildings, buildingIndex)
	if cityBuildings:IsPillaged(buildingIndex) ~= true then return nil end
	local buildingRow = GameInfo.Buildings[buildingIndex]
	return {
		iX = iX,
		iY = iY,
		plotIndex = plotIndex,
		buildingType = buildingRow ~= nil and buildingRow.BuildingType or nil,
		buildingName = buildingRow ~= nil and buildingRow.Name or nil,
		cityID = city:GetID(),
		cityName = city:GetName(),
	}
end

function GetPillagedDistrict(plotIndex)
	local plot = Map.GetPlotByIndex(plotIndex)
	if plot == nil then return nil end
	local iX = plot:GetX()
	local iY = plot:GetY()
	local district = CityManager.GetDistrictAt(iX, iY)
	if district == nil then return nil end
	local districtTypeIndex = district:GetType()
	local districtRow = districtTypeIndex ~= nil and GameInfo.Districts[districtTypeIndex] or nil
	local city = GetCityForPlot(iX, iY)
	return {
		districtID = SafeCall(district, 'GetID'),
		districtType = districtRow ~= nil and districtRow.DistrictType or nil,
		districtName = districtRow ~= nil and districtRow.Name or nil,
		iX = iX,
		iY = iY,
		plotIndex = plotIndex,
		cityID = city ~= nil and city:GetID() or nil,
		cityName = city ~= nil and city:GetName() or nil,
	}
end

-- 残血单位：伤害 >= 阈值（默认 50%）。民用单位不吃伤害，自然不会被列进来。
local LOW_HEALTH_DAMAGE_THRESHOLD = 50

function GetLowHealthUnits(selfPlayerID)
	local result = {}
	for _,unit in ipairs(GetPlayerUnitsList(selfPlayerID)) do
		local entry = GetLowHealthUnit(unit)
		if entry ~= nil then table.insert(result, entry) end
	end
	return result
end

function GetLowHealthUnit(unit)
	local damage = unit:GetDamage()
	if damage == nil then return nil end
	if damage < LOW_HEALTH_DAMAGE_THRESHOLD then return nil end
	local unitType, unitName, unitIcon = GetUnitTypeInfo(unit:GetType())
	return {
		unitID = unit:GetID(),
		unitType = unitType,
		unitName = unitName,
		unitIcon = unitIcon,
		damage = damage,
		iX = unit:GetX(),
		iY = unit:GetY(),
	}
end

-- ===========================================================================
-- 三、间谍数据（两个分支共用）
-- ===========================================================================

-- 该玩家所有活着的间谍单位：{ [unitID] = unitData }
-- 数据源是 Mod Misc Tool 的派生索引 allUnitsTypeTable[playerID][unitType][unitID]。
function GetAllSpyUnitDataOfPlayer(playerID)
	local result = {}
	if ExposedMembers == nil or ExposedMembers.ModMiscToolScript == nil then return result end
	local allUnitsTypeTable = ExposedMembers.ModMiscToolScript.allUnitsTypeTable
	if allUnitsTypeTable == nil then return result end
	local playerUnitTypeTable = allUnitsTypeTable[playerID]
	if playerUnitTypeTable == nil then return result end
	for unitTypeText, unitTypeBucket in pairs(playerUnitTypeTable) do
		local unitRow = GameInfo.Units[unitTypeText]
		if unitRow ~= nil and unitRow.Spy == true then
			for unitID, unitData in pairs(unitTypeBucket) do
				if unitData ~= nil and unitData.removed ~= true then
					result[unitID] = unitData
				end
			end
		end
	end
	return result
end

-- 该玩家**正在执行行动**的间谍：{ [unitID] = operationData }
-- （Basilissa 原实现；修：拿不到索引/该玩家没有间谍时返回空表，不再 pairs(nil)）
function GetAllSpyUnitOfPlayer(playerID)
	local playerSpyList = {}
	if ExposedMembers == nil or ExposedMembers.ModMiscToolScript == nil then return playerSpyList end
	local allUnitsTypeTable = ExposedMembers.ModMiscToolScript.allUnitsTypeTable
	if allUnitsTypeTable == nil then return playerSpyList end
	local playerUnitTypeTable = allUnitsTypeTable[playerID]
	if playerUnitTypeTable == nil then return playerSpyList end
	local spyUnitsTable = playerUnitTypeTable['UNIT_SPY']
	if spyUnitsTable == nil then return playerSpyList end
	for unitID,unitData in pairs(spyUnitsTable) do
		if unitData.removed ~= true then
			playerSpyList[unitID] = GetSpyActionInfo(playerID, unitID)
		end
	end
	return playerSpyList
end

-- 某一个间谍正在干什么（Basilissa 原实现；修：unit 判空、unit; 语法、操作/目标城市可空、漏 local）
function GetSpyActionInfo(playerID, unitID)
	local unit = UnitManager.GetUnit(playerID, unitID)
	if unit == nil then return nil end
	if unit:GetDamage() >= 100 then return nil end
	local spyOperation, spyRemainingTurns, spyTotalTurns = GetSpyOperations(playerID, unitID)
	if spyOperation == nil or spyOperation == -1 then return nil end
	local operationInfo = GameInfo.UnitOperations[spyOperation]
	local operationData = {}
	operationData.spyOperation = spyOperation
	operationData.spyRemainingTurns = spyRemainingTurns
	operationData.spyTotalTurns = spyTotalTurns
	operationData.operationIcon = operationInfo ~= nil and operationInfo.Icon or nil
	operationData.operationName = operationInfo ~= nil and operationInfo.Description or nil
	operationData.spyOwnerID = playerID
	operationData.spyOwnerName = GetPlayerDisplayName(playerID)
	operationData.unitID = unitID
	local spyPlot = Map.GetPlot(unit:GetX(), unit:GetY())
	if spyPlot == nil then return operationData end
	operationData.iX = unit:GetX()
	operationData.iY = unit:GetY()
	operationData.plotIndex = spyPlot:GetIndex()
	local targetCity = Cities.GetPlotPurchaseCity(spyPlot)
	if targetCity == nil then return operationData end
	operationData.targetCityID = targetCity:GetID()
	operationData.targetCityName = targetCity:GetName()
	operationData.targetOwnerID = targetCity:GetOwner()
	operationData.targetOwnerName = GetPlayerDisplayName(targetCity:GetOwner())
	return operationData
end

-- 兼容旧名字：历史上这个函数想表达"别的文明的间谍在针对我"，现在直接走领土版
function GetSpiesTargetSelf(playerID)
	return GetSpyActionInTerritory(playerID)
end

-- ===========================================================================
-- 四、行动类（ASSISTANT_TOPIC_ACTION）—— 当前**只搭框架**，执行层还没接
-- ===========================================================================
-- 行动类分支返回"计划"而不是数据列表：
--   { actionType = '...', implemented = false, entries = ... }
-- entries 是只读预览（条目带 iX/iY/plotIndex，UI 照样能点击跳地图）；
-- implemented = false 表示执行层未接 —— 真要动手时由 RunTopicAction 按 actionType 分发。

local ACTION_IMPLEMENTED = false   -- 执行层总开关：接上以后改这里 + 补 RunTopicAction

-- 城市自动修复区域和建筑（预览：只取劫掠分类里的区域 + 建筑，改良不归这条）
function GetCityAutoRepairPlan(selfPlayerID)
	local pillagedAssets = GetPillagedAssets(selfPlayerID)
	return NewActionPlan('city_auto_repair', {
		building = pillagedAssets['building'],
		district = pillagedAssets['district'],
	})
end

-- 城市自动补建筑（预览）
-- TODO(执行层)：需要"每个城市/区域还能补哪些建筑"的数据源（GetBuildingsIndexInPlot 只给已建成的）。
function GetCityAutoFillBuildingsPlan(selfPlayerID)
	return NewActionPlan('city_auto_fill_buildings', {})
end

-- 城市自动重复项目（预览）
-- TODO(执行层)：需要读生产队列的历史项目；先空计划占位。
function GetCityAutoRepeatProjectsPlan(selfPlayerID)
	return NewActionPlan('city_auto_repeat_projects', {})
end

-- 城市自动造改良（预览）
-- TODO(执行层)：需要"可改良地块 + 建造者"的数据；先空计划占位。
function GetCityAutoBuildImprovementsPlan(selfPlayerID)
	return NewActionPlan('city_auto_build_improvements', {})
end

-- 将单位分配给军团（预览：列出自己的军事单位作为候选）
function GetCorpsAssignUnitsPlan(selfPlayerID)
	return NewActionPlan('corps_assign_units', GetOwnMilitaryUnitEntries(selfPlayerID))
end

-- 给军团设置警戒 / 攻击等任务（预览）
-- TODO(执行层)：军团概念还没落地，先空计划占位（以后按任务类型给军团发 Operation）。
function GetCorpsSetTasksPlan(selfPlayerID)
	return NewActionPlan('corps_set_tasks', {})
end

-- 把 GetPlayerMilitaryUnitsList 的"按类型/编队分组"摊平成单位列表
function GetOwnMilitaryUnitEntries(selfPlayerID)
	local entries = {}
	for unitTypeIndex, formationTable in pairs(GetPlayerMilitaryUnitsList(selfPlayerID)) do
		for formation, unitTable in pairs(formationTable) do
			for _, unitData in ipairs(unitTable) do
				table.insert(entries, unitData)
			end
		end
	end
	return entries
end

function NewActionPlan(actionType, entries)
	return {
		actionType = actionType,
		implemented = ACTION_IMPLEMENTED,
		entries = entries,
	}
end

-- 哪些分支属于"行动类"（UI 用它决定是渲染列表还是渲染"预览 + 执行按钮"）
local ACTION_BRANCHES = {
	['TOPIC_BRANCH_CITY_AUTO_REPAIR'] = true,
	['TOPIC_BRANCH_CITY_AUTO_FILL_BUILDINGS'] = true,
	['TOPIC_BRANCH_CITY_AUTO_REPEAT_PROJECTS'] = true,
	['TOPIC_BRANCH_CITY_AUTO_BUILD_IMPROVEMENTS'] = true,
	['TOPIC_BRANCH_CORPS_ASSIGN_UNITS'] = true,
	['TOPIC_BRANCH_CORPS_SET_TASKS'] = true,
}

function TopicIsAction(topicBranch)
	return ACTION_BRANCHES[topicBranch] == true
end

-- ===========================================================================
-- 四、TopicBranch → 函数 的映射
-- ===========================================================================
-- 用 ['字符串键'] 而不是裸标识符（原来那条 `'TOPIC_BRANCH_...' = fn` 是语法错误）。
-- 键必须与 PlanaAssistant.sql 里的 Kocmoca_Assistant_Topics.TopicBranch 一致。

-- 需要前端**先选目标玩家**再查的分支（一次只算一个玩家）；
-- 其余分支（奇观/核弹/敌军/劫掠/本国状态）一次拿全，不需要目标。
local TARGETED_BRANCHES = {
	['TOPIC_BRANCH_FOREIGN_MILITARY_UNITS'] = true,
	['TOPIC_BRANCH_GOSSIP_HISTORY'] = true,
	['TOPIC_BRANCH_FOREIGN_PRODUCTION_PROGRESS'] = true,
	['TOPIC_BRANCH_FOREIGN_SPY_ACTION'] = true,
	['TOPIC_BRANCH_FOREIGN_ECONOMY'] = true,
}

local topicBranchFunctions = {
	-- 外国情报（按目标玩家查：前端先选人）
	['TOPIC_BRANCH_FOREIGN_MILITARY_UNITS'] = GetPlayerMilitaryUnitsList,
	['TOPIC_BRANCH_GOSSIP_HISTORY'] = GetGossipHistory,
	['TOPIC_BRANCH_FOREIGN_PRODUCTION_PROGRESS'] = GetPlayerProductionProgress,
	['TOPIC_BRANCH_FOREIGN_SPY_ACTION'] = GetAllSpyUnitOfPlayer,
	['TOPIC_BRANCH_FOREIGN_ECONOMY'] = GetPlayerEconomy,
	-- 外国情报（一次拿全：奇观是"谁在抢哪座"、核弹是横向对比）
	['TOPIC_BRANCH_FOREIGN_WONDER_BUILD_PROGRESS'] = GetForeignWonderBuildProgress,
	['TOPIC_BRANCH_FOREIGN_WONDER_LOCATION'] = GetForeignWonderLocation,
	['TOPIC_BRANCH_FOREIGN_NUKE_NUM'] = GetForeignNukeNum,
	-- 本国情报（本地玩家）
	['TOPIC_BRANCH_ENEMIES_IN_TERRITORY'] = GetEnemiesInTerritory,
	['TOPIC_BRANCH_LOYALTY_DECREASING'] = GetLoyaltyDecreasingCities,
	['TOPIC_BRANCH_POPULATION_DECREASING'] = GetPopulationDecreasingCities,
	['TOPIC_BRANCH_LOW_AMENITY'] = GetLowAmenityCities,
	['TOPIC_BRANCH_SPY_ACTION_IN_TERRITORY'] = GetSpyActionInTerritory,
	['TOPIC_BRANCH_PILLAGED_ASSETS'] = GetPillagedAssets,
	['TOPIC_BRANCH_LOW_HEALTH_UNITS'] = GetLowHealthUnits,
	-- 行动类（Smiling Professor）：城市四项 + 军团两项，返回计划，执行层未接
	['TOPIC_BRANCH_CITY_AUTO_REPAIR'] = GetCityAutoRepairPlan,
	['TOPIC_BRANCH_CITY_AUTO_FILL_BUILDINGS'] = GetCityAutoFillBuildingsPlan,
	['TOPIC_BRANCH_CITY_AUTO_REPEAT_PROJECTS'] = GetCityAutoRepeatProjectsPlan,
	['TOPIC_BRANCH_CITY_AUTO_BUILD_IMPROVEMENTS'] = GetCityAutoBuildImprovementsPlan,
	['TOPIC_BRANCH_CORPS_ASSIGN_UNITS'] = GetCorpsAssignUnitsPlan,
	['TOPIC_BRANCH_CORPS_SET_TASKS'] = GetCorpsSetTasksPlan,
}

-- 这个分支要不要先选目标玩家（UI 用它决定是否弹选人列表）
function TopicNeedsTarget(topicBranch)
	return TARGETED_BRANCHES[topicBranch] == true
end

-- 取分支对应的函数；没注册就返回 nil（调用方自己决定怎么提示）
function GetTopicBranchFunction(topicBranch)
	if topicBranch == nil then return nil end
	return topicBranchFunctions[topicBranch]
end

-- 已注册的分支名（调试面板 / 自检用）
function GetTopicBranchFunctionNames()
	local names = {}
	for topicBranch, _ in pairs(topicBranchFunctions) do
		table.insert(names, topicBranch)
	end
	table.sort(names)
	return names
end

-- ===========================================================================
-- 助手话题的 **UI 端取数**（AssistantTopics.lua 跑在 gameplay，拿不到这些接口）
--
-- 只做"gameplay 端拿不到、UI 端能拿"的那几项，读完把**纯数据**交回去：
--   * 城市粮食/宜居   city:GetGrowth():GetFoodSurplus() / GetFood() /
--                     GetAmenities() / GetAmenitiesNeeded()        （原版 CitySupport.lua）
--   * 城市忠诚         city:GetCulturalIdentity():GetLoyaltyPerTurn() / GetLoyalty() …（XP1+）
--   * 流言历史         Game.GetGossipManager():GetRecentVisibleGossipStrings(...)（原版 ARXManager.lua）
--   * 每回合金币       player:GetTreasury():GetGoldYield()
--
-- 暴露方式：ExposedMembers.PlanaAssistantUI.<name>，gameplay 侧 AssistantTopics.lua
-- 通过 CallAssistantUI 调（拿不到就返回空，不假设加载顺序）。
-- 返回值一律"纯 table/number"，不带游戏对象，跨上下文传才安全。
-- ===========================================================================

local function SafeCall(object, methodName, ...)
	if object == nil or methodName == nil then return nil end
	local method = object[methodName]
	if method == nil then return nil end
	local ok, result = pcall(method, object, ...)
	if not ok then return nil end
	return result
end

-- 城市ID → 城市对象（UI 端 CityManager 可用；ModTool_Support_UI.lua 也是这么取的）
local function FindCity(playerID, cityID)
	if playerID == nil or cityID == nil then return nil end
	return CityManager.GetCity(playerID, cityID)
end

-- 粮食 / 宜居：给"人口下降""宜居不足"两个分支用
function GetCityGrowthInfo(playerID, cityID)
	local city = FindCity(playerID, cityID)
	if city == nil then return nil end
	local cityGrowth = SafeCall(city, 'GetGrowth')
	if cityGrowth == nil then return nil end
	local amenities = SafeCall(cityGrowth, 'GetAmenities')
	local amenitiesNeeded = SafeCall(cityGrowth, 'GetAmenitiesNeeded')
	return {
		population = SafeCall(city, 'GetPopulation'),
		food = SafeCall(cityGrowth, 'GetFood'),
		foodSurplus = SafeCall(cityGrowth, 'GetFoodSurplus'),
		amenities = amenities,
		amenitiesNeeded = amenitiesNeeded,
		amenitiesNet = (amenities ~= nil and amenitiesNeeded ~= nil) and (amenities - amenitiesNeeded) or nil,
	}
end

-- 忠诚：只有资料片（XP1+）有；拿不到就返回 nil，让 gameplay 分支返回空表
local m_loggedNoCulturalIdentity = false

function GetCityLoyaltyInfo(playerID, cityID)
	local city = FindCity(playerID, cityID)
	if city == nil then return nil end
	local culturalIdentity = SafeCall(city, 'GetCulturalIdentity')
	if culturalIdentity == nil then
		if not m_loggedNoCulturalIdentity then
			m_loggedNoCulturalIdentity = true
			print("[PlanaAssistant][UI] 拿不到 City:GetCulturalIdentity（未开忠诚资料片？）→ 忠诚分支将为空")
		end
		return nil
	end
	return {
		loyalty = SafeCall(culturalIdentity, 'GetLoyalty'),
		maxLoyalty = SafeCall(culturalIdentity, 'GetMaxLoyalty'),
		loyaltyPerTurn = SafeCall(culturalIdentity, 'GetLoyaltyPerTurn'),
		loyaltyLevel = SafeCall(culturalIdentity, 'GetLoyaltyLevel'),
	}
end

-- 流言（Gossip）历史：原版 ARXManager.lua → DrawGossipLog()
--   GetRecentVisibleGossipStrings(earliestTurn, 观看者, 被说的人) → { {文本, 回合}, ... }
--   文本已经是本地化好的字符串；原版只看最近 100 回合。
local GOSSIP_TURN_WINDOW = 100
local DEFAULT_GOSSIP_MAX_ENTRIES = 20

function GetGossipHistory(viewerPlayerID, subjectPlayerID, maxCount)
	local result = {}
	local gossipManager = Game.GetGossipManager()
	if gossipManager == nil then return result end
	if maxCount == nil then maxCount = DEFAULT_GOSSIP_MAX_ENTRIES end
	local earliestTurn = Game.GetCurrentGameTurn() - GOSSIP_TURN_WINDOW
	local ok, gossipTable = pcall(function()
		return gossipManager:GetRecentVisibleGossipStrings(earliestTurn, viewerPlayerID, subjectPlayerID)
	end)
	if not ok or gossipTable == nil then return result end
	local added = 0
	for _, gossipItem in pairs(gossipTable) do
		local gossipText = gossipItem[1]
		if gossipText == nil then break end
		if added >= maxCount then break end
		table.insert(result, { gossipString = gossipText, turn = gossipItem[2] })
		added = added + 1
	end
	return result
end

-- 每回合金币收入（国库余额 gameplay 端自己能读，这里只补"每回合"这一项）
function GetPlayerGoldYield(playerID)
	local player = Players[playerID]
	if player == nil then return nil end
	return SafeCall(player:GetTreasury(), 'GetGoldYield')
end

-- 每回合维护费（可选：gameplay 能读国库余额但读不到这项时用它算净收入）
function GetPlayerMaintenance(playerID)
	local player = Players[playerID]
	if player == nil then return nil end
	return SafeCall(player:GetTreasury(), 'GetTotalMaintenance')
end

-- ---------------------------------------------------------------------------
-- 暴露给 gameplay
-- ---------------------------------------------------------------------------
if not ExposedMembers.PlanaAssistantUI then
	ExposedMembers.PlanaAssistantUI = {}
end
ExposedMembers.PlanaAssistantUI.GetCityGrowthInfo = GetCityGrowthInfo
ExposedMembers.PlanaAssistantUI.GetCityLoyaltyInfo = GetCityLoyaltyInfo
ExposedMembers.PlanaAssistantUI.GetGossipHistory = GetGossipHistory
ExposedMembers.PlanaAssistantUI.GetPlayerGoldYield = GetPlayerGoldYield
ExposedMembers.PlanaAssistantUI.GetPlayerMaintenance = GetPlayerMaintenance

include('ModTool_Support_Functions.lua')

local assistantInActive = {}
local assistantPlayers = {}

function SaveData()
	Game:SetProperty('kocmoca_assistants_in_active_table_prop', assistantInActive)
end

function LoadData()
	assistantInActive = Game:GetProperty('kocmoca_assistants_in_active_table_prop') or {}
end

-- 把 unitID 写回存档表（两层表：assistantInActive[召唤者 playerID][assistantType] = assistantData）
-- 召唤数据没落表时（旧档/被清过）只改内存里的 assistantData，不去索引 nil
local function SetAssistantUnitID(assistantData, unitID)
	assistantData.unitID = unitID
	local assistantsOfOwner = assistantInActive[assistantData.ownerID]
	if assistantsOfOwner == nil then return end
	local storedData = assistantsOfOwner[assistantData.assistantType]
	if storedData == nil then return end
	storedData.unitID = unitID
end

function InitializeAssistantPlayersData()
	-- assistantInActive 是**两层**表：assistantInActive[召唤者 playerID][assistantType] = assistantData
	-- （原来只写了一层循环，第二个变量拿到的是内层表，再拿它当 assistantType 用就是 nil ⇒ 索引报错）
	for ownerID, assistantsOfOwner in pairs(assistantInActive) do
		if type(assistantsOfOwner) == 'table' then
			for assistantType, assistantData in pairs(assistantsOfOwner) do
				if type(assistantData) == 'table' and assistantData.playerID ~= nil then
					assistantPlayers[assistantData.playerID] = assistantData
				end
			end
		end
	end
end

function StartSummonAssistant(playerID, cityID, assistantType)
	if assistantInActive[playerID] == nil then assistantInActive[playerID] = {} end
	if assistantInActive[playerID][assistantType] ~= nil then
		print('assistant already summoned: ' .. tostring(assistantType))
		return
	end
	SummonAssistant(playerID, cityID, assistantType)
end

function SummonAssistant(playerID, cityID, assistantType)
	if assistantInActive[playerID] == nil then assistantInActive[playerID] = {} end
	local city = CityManager.GetCity(playerID, cityID)
	if city == nil then return end
	local iX = city:GetX()
	local iY = city:GetY()
	local plotIndex = CoordinateToPlotIndex(iX, iY)
	if plotIndex == nil then return end
	local assistantRow = GameInfo.Kocmoca_Assistants[assistantType]
	if assistantRow == nil then return end
	local leaderType = assistantRow.LeaderType
	local unitType = assistantRow.UnitType
	if leaderType == nil then return end
	local playerLeaderType, playerCivType = GetPlayerLeaderAndCivType(playerID)
	if playerLeaderType == leaderType then return end
	-- 幽灵池接口来自 Mod Misc Tool；没装/没就绪时不要直接索引 nil
	local modMiscScript = ExposedMembers ~= nil and ExposedMembers.ModMiscToolScript or nil
	local getAvailableGhostPlayerID = modMiscScript ~= nil and modMiscScript.GetAvailableGhostPlayerID or nil
	if getAvailableGhostPlayerID == nil then
		print('[PlanaAssistant] 没有 Mod Misc Tool 的幽灵池接口，召唤中止')
		return
	end
	local ghostID = getAvailableGhostPlayerID()
	if ghostID == nil then
		print('[PlanaAssistant] 幽灵池已空，召唤中止')
		return
	end
	local assistantData = {}
	assistantData.playerID = ghostID
	assistantData.leaderType = leaderType
	assistantData.unitType = unitType
	assistantData.civType = playerCivType
	assistantData.starterCityPlotIndex = plotIndex
	assistantData.starterCityX = iX
	assistantData.starterCityY = iY
	assistantData.ownerID = playerID
	assistantData.assistantType = assistantType
	assistantInActive[playerID][assistantType] = assistantData
	assistantPlayers[assistantData.playerID] = assistantData
	SaveData()
	--[[]
	--use local player's full civ level and civ type
	local playerConfig = WorldBuilder.PlayerManager():GetPlayerConfig(playerID)
	WorldBuilder.PlayerManager():SetPlayerLeader(ghostID, assistantData.leaderType, playerConfig.Civ, playerConfig.CivLevel)
	--should make transfer city to ghost player a built in API, in case ghost player system don't know this player was no longer a ghost
	CityManager.TransferCity(city, assistantData.playerID, BY_CULTURAL_IDENTITY)
	--]]
	--Basilissa: get major ghost player and transfer city to it here
end

--Basilissa: 代码风格不要学官方，变量名不要缩写，函数提前返回以及拆分减少嵌套
function MakeAssistantAlliance(playerID, assistantID)
	local vassalAllianceRow = GameInfo.Alliances['ALLIANCE_KOCMOCA_VASSAL']
	if vassalAllianceRow ~= nil then
		--调用vassal system附庸逻辑
		return
	end
	--附庸系统mod未安装的情况
	--永久同盟，且每30回合自动续军事同盟
end

function OnCityTransfered(newOwnerID, cityID, oldOwnerID, transferType)
	local playerID = newOwnerID
	if assistantPlayers[playerID] == nil then return end
	local assistantData = assistantPlayers[playerID]
	local city = CityManager.GetCity(playerID, cityID)
	if city == nil then return end
	local iX = city:GetX()
	local iY = city:GetY()
	local plotIndex = CoordinateToPlotIndex(iX, iY)
	if plotIndex == nil then return end
	if assistantData.starterCityPlotIndex ~= plotIndex then return end
	print('assistant first city')
	UnitManager.InitUnit(playerID, 'UNIT_SETTLER', iX, iY)
	if assistantData.unitType == nil then return end
	local assistantUnit = UnitManager.InitUnit(playerID, assistantData.unitType, iX, iY)
	if assistantUnit == nil then return end
	local assistantUnitID = assistantUnit:GetID()
	SetAssistantUnitID(assistantData, assistantUnitID)
	SaveData()
end

function TurnEnd()
	CheckInitUnit()
	SaveData()
end

function CheckInitUnit()
	for assistantID, assistantData in pairs(assistantPlayers) do
		CheckAssistantUnit(assistantID, assistantData)
	end
end

function CheckAssistantUnit(playerID, assistantData)
	local unitType = assistantData.unitType
	if unitType == nil then return end
	local unitID = assistantData.unitID
	if unitID == nil then return end
	local unit = UnitManager.GetUnit(playerID, unitID)
	if unit ~= nil and unit:GetDamage() < 100 then return end
	local iX, iY = GetCapitalCoordinate(playerID)
	if iX == nil or iY == nil then return end
	local assistantUnit = UnitManager.InitUnit(playerID, assistantData.unitType, iX, iY)
	if assistantUnit == nil then return end
	local assistantUnitID = assistantUnit:GetID()
	SetAssistantUnitID(assistantData, assistantUnitID)
end

function Initialize()
	LoadData()
	InitializeAssistantPlayersData()
	Events.CityTransfered.Add(OnCityTransfered)
	Events.TurnEnd.Add(TurnEnd)
end
Events.LoadGameViewStateDone.Add(Initialize)

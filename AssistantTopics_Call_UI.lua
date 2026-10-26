include('ModTool_Support_Functions.lua')

-- ===========================================================================
-- 助手话题 —— **UI 端调用约定**（对话面板只认这一层）
--
-- 流程：
--   ① 面板先问 AssistantTopicNeedsTarget(topicBranch)：
--        为 true  → 先弹"选择目标玩家"（GetAssistantTopicTargets），选完再查；
--        为 false → 奇观 / 核弹 / 领土敌军 / 劫掠 / 本国状态这类"一次拿全"，不用选人。
--   ② CallAssistantTopic(topicBranch, targetPlayerID) 调 gameplay 后端（ExposedMembers），
--      拿回纯数据自己渲染。
--   ③ 结果里每条实例都带 iX/iY/plotIndex；点击它调 JumpToAssistantTopicEntry(entry)，
--      地图直接跳过去（GrayFox 的 UI/Norn_UI.lua 也是 UI.LookAtPlot）。
--
-- 性能口径：所有取数都发生在点击之后 —— 面板打开时不要预调 CallAssistantTopic。
-- ===========================================================================

local ASSISTANT_SCRIPT_NAMESPACE = 'PlanaAssistantScript'

local function GetScriptAPI()
	if ExposedMembers == nil then return nil end
	return ExposedMembers[ASSISTANT_SCRIPT_NAMESPACE]
end

-- 这个分支要不要先选目标玩家
function AssistantTopicNeedsTarget(topicBranch)
	local scriptAPI = GetScriptAPI()
	if scriptAPI == nil or scriptAPI.TopicNeedsTarget == nil then return false end
	local ok, needsTarget = pcall(scriptAPI.TopicNeedsTarget, topicBranch)
	return ok and needsTarget == true
end

-- 目标玩家选择列表（选完把 playerID 传给 CallAssistantTopic）
function GetAssistantTopicTargets(selfPlayerID)
	if selfPlayerID == nil then selfPlayerID = Game.GetLocalPlayer() end
	local targets = {}
	for _, playerID in ipairs(PlayerManager.GetAliveMajorIDs()) do
		if playerID ~= selfPlayerID then
			local leaderIcon, leaderName = GetLeaderIconAndName(playerID)
			table.insert(targets, {
				playerID = playerID,
				playerName = leaderName,
				leaderIcon = leaderIcon,
			})
		end
	end
	return targets
end

-- 调后端：targeted 分支必须给 targetPlayerID；其余分支忽略它
function CallAssistantTopic(topicBranch, targetPlayerID)
	local scriptAPI = GetScriptAPI()
	if scriptAPI == nil or scriptAPI.CallTopicBranch == nil then
		print("[PlanaAssistant][UI] 后端接口还没就绪（ExposedMembers.PlanaAssistantScript）")
		return nil
	end
	if AssistantTopicNeedsTarget(topicBranch) and targetPlayerID == nil then
		print("[PlanaAssistant][UI] 这个分支要先选目标玩家: " .. tostring(topicBranch))
		return nil
	end
	local ok, result = pcall(scriptAPI.CallTopicBranch, topicBranch, targetPlayerID)
	if not ok then
		print("[PlanaAssistant][UI] 话题分支调用失败: " .. tostring(topicBranch)
			.. " -> " .. tostring(result))
		return nil
	end
	return result
end

-- 点击一条实例 → 地图跳过去（entry 要带 iX/iY；没有坐标的条目返回 false，不跳）
function JumpToAssistantTopicEntry(entry)
	if entry == nil then return false end
	local iX = entry.iX
	local iY = entry.iY
	if iX == nil or iY == nil then return false end
	UI.LookAtPlot(iX, iY)
	return true
end

-- 劫掠分支的展示分类（固定顺序；label 是 LOC key，文案在 Text 里补）
local PILLAGE_SECTION_ORDER = {
	{ kind = 'improvement', label = 'LOC_ASSISTANT_PILLAGED_IMPROVEMENTS' },
	{ kind = 'building', label = 'LOC_ASSISTANT_PILLAGED_BUILDINGS' },
	{ kind = 'district', label = 'LOC_ASSISTANT_PILLAGED_DISTRICTS' },
}

function GetPillageDisplaySections(pillageAssets)
	local sections = {}
	if pillageAssets == nil then return sections end
	for _, sectionInfo in ipairs(PILLAGE_SECTION_ORDER) do
		local entries = pillageAssets[sectionInfo.kind]
		if entries ~= nil and #entries > 0 then
			table.insert(sections, {
				kind = sectionInfo.kind,
				label = sectionInfo.label,
				entries = entries,
			})
		end
	end
	return sections
end

-- ---------------------------------------------------------------------------
-- 键值表 → 有序分区：后端统一用键值对返回（[key] = value），UI 直接按分区渲染
-- （数字键按数值排，其它按字符串排）
-- ---------------------------------------------------------------------------
local function CompareSectionKeys(leftKey, rightKey)
	if type(leftKey) == 'number' and type(rightKey) == 'number' then
		return leftKey < rightKey
	end
	return tostring(leftKey) < tostring(rightKey)
end

function GetKeyedDisplaySections(keyedTable)
	local sections = {}
	if keyedTable == nil then return sections end
	local keys = {}
	for key in pairs(keyedTable) do table.insert(keys, key) end
	table.sort(keys, CompareSectionKeys)
	for _, key in ipairs(keys) do
		table.insert(sections, { key = key, value = keyedTable[key] })
	end
	return sections
end

-- 核弹：后端返回 { standard = [playerID][WeaponType], extensive = ... }，这里分两区
local NUKE_SECTION_ORDER = {
	{ kind = 'standard', label = 'LOC_ASSISTANT_NUKE_STANDARD' },
	{ kind = 'extensive', label = 'LOC_ASSISTANT_NUKE_EXTENSIVE' },
}

function GetNukeDisplaySections(nukeInfo)
	local sections = {}
	if nukeInfo == nil then return sections end
	for _, sectionInfo in ipairs(NUKE_SECTION_ORDER) do
		local playerWeapons = nukeInfo[sectionInfo.kind]
		if playerWeapons ~= nil and next(playerWeapons) ~= nil then
			table.insert(sections, {
				kind = sectionInfo.kind,
				label = sectionInfo.label,
				players = playerWeapons,
			})
		end
	end
	return sections
end

-- ---------------------------------------------------------------------------
-- 行动类：先预览（CallAssistantTopic 拿 plan）→ 玩家确认 → RunAssistantTopicAction 执行
-- 执行层未接时，后端统一返回 false；UI 按 plan.implemented 决定按钮是否可点。
-- ---------------------------------------------------------------------------
function AssistantTopicIsAction(topicBranch)
	local scriptAPI = GetScriptAPI()
	if scriptAPI == nil or scriptAPI.TopicIsAction == nil then return false end
	local ok, isAction = pcall(scriptAPI.TopicIsAction, topicBranch)
	return ok and isAction == true
end

function RunAssistantTopicAction(topicBranch, actionEntries)
	local scriptAPI = GetScriptAPI()
	if scriptAPI == nil or scriptAPI.RunTopicAction == nil then
		print("[PlanaAssistant][UI] 后端接口还没就绪（RunTopicAction）")
		return false
	end
	local ok, succeeded = pcall(scriptAPI.RunTopicAction, topicBranch, actionEntries)
	if not ok then
		print("[PlanaAssistant][UI] 行动执行失败: " .. tostring(topicBranch)
			.. " -> " .. tostring(succeeded))
		return false
	end
	return succeeded == true
end

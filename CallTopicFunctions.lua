--Basilissa: call functions ONLY when button clicked

-- ===========================================================================
-- 按钮回调入口（gameplay 侧，UI 经 ExposedMembers.PlanaAssistantScript 调）
--
-- 用法（UI 侧点一次按钮/选完目标玩家后调一次）：
--   local data = CallTopicBranch(topicBranch, targetPlayerID)
--     topicBranch    : Kocmoca_Assistant_Topics.TopicBranch（'TOPIC_BRANCH_...'）
--     targetPlayerID : **只有 TopicNeedsTarget() 为真的分支要传**（外国军事/流言/生产/间谍/经济），
--                      UI 必须先让玩家选好目标；其余分支（奇观/核弹/敌军/劫掠/本国状态）不用传。
--   返回：分支函数产出的 table；分支没注册 / 缺目标 / 执行报错 ⇒ nil（只打日志，不弹错）
--
-- 性能口径：**不要在 Initialize / 打开对话面板时预调**这些分支（那等于每次开界面都做一遍
-- 玩家/城市/地图遍历）。正确用法就是上面的"点一次算一次"，算完即弃。
--
-- 为什么包 pcall：这些分支要读一堆运行时接口（生产队列、间谍缓存、忠诚资料片…），
-- 少一个就整段对话炸掉不值当 —— 宁可这一次没内容，也不要把面板卡死。
-- ===========================================================================

function CallTopicBranch(topicBranch, targetPlayerID)
	local topicFunction = GetTopicBranchFunction(topicBranch)
	if topicFunction == nil then
		print("[PlanaAssistant] 未注册的话题分支: " .. tostring(topicBranch))
		return nil
	end
	local argumentPlayerID = Game.GetLocalPlayer()
	if TopicNeedsTarget(topicBranch) then
		if targetPlayerID == nil then
			print("[PlanaAssistant] 该分支需要先选目标玩家: " .. tostring(topicBranch))
			return nil
		end
		argumentPlayerID = targetPlayerID
	end
	local ok, result = pcall(topicFunction, argumentPlayerID)
	if not ok then
		print("[PlanaAssistant] 话题分支执行失败: " .. tostring(topicBranch)
			.. " -> " .. tostring(result))
		return nil
	end
	return result
end

-- ---------------------------------------------------------------------------
-- 行动类：UI 预览确认后调这里执行
-- **执行层还没接** —— 现在统一打日志返回 false（框架占位），
-- 以后按 plan.actionType 分发到具体执行函数（修理/补建筑/调兵）即可，UI 不用改。
-- ---------------------------------------------------------------------------
function RunTopicAction(topicBranch, actionEntries)
	print("[PlanaAssistant] 行动执行层未接入: " .. tostring(topicBranch))
	return false
end

-- ---------------------------------------------------------------------------
-- 暴露给 UI（包装一层，避免本文件比 AssistantTopics.lua 先加载时抓到 nil）
-- ---------------------------------------------------------------------------
if not ExposedMembers.PlanaAssistantScript then
	ExposedMembers.PlanaAssistantScript = {}
end
ExposedMembers.PlanaAssistantScript.CallTopicBranch = function(topicBranch, targetPlayerID)
	return CallTopicBranch(topicBranch, targetPlayerID)
end
ExposedMembers.PlanaAssistantScript.TopicNeedsTarget = function(topicBranch)
	return TopicNeedsTarget(topicBranch)
end
ExposedMembers.PlanaAssistantScript.GetTopicBranchFunctionNames = function()
	return GetTopicBranchFunctionNames()
end
ExposedMembers.PlanaAssistantScript.TopicIsAction = function(topicBranch)
	return TopicIsAction(topicBranch)
end
ExposedMembers.PlanaAssistantScript.RunTopicAction = function(topicBranch, actionEntries)
	return RunTopicAction(topicBranch, actionEntries)
end

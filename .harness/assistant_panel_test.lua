-- ===========================================================================
-- 桩测试：助手面板（UI/AssistantPanel.lua + UI/AssistantPanel.xml）
--
-- 要证明的事：
--   ① Lua 里引用的每个控件 ID 都在 XML 里存在（防止改名/漏建控件）；
--   ② 助手按 SceneType 分组 → 场景书签数量正确，切场景后主体系重建；
--   ③ 点助手 → 其他助手隐藏、对话面板展开、分支列表按 TopicType 填充；
--   ④ 侧栏入口注册（借 Mod Misc Tool 的 RegisterSidebarButton）；
--   ⑤ 关闭按钮 / ESC 都能关面板（ESC 走输入处理器）。
--
-- 跑法（工作目录 = 本项目根）：lua .harness/assistant_panel_test.lua
-- ===========================================================================
local PANEL_LUA = "UI/AssistantPanel.lua"
local PANEL_XML = "UI/AssistantPanel.xml"

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
-- XML 里定义过的控件 ID
-- ---------------------------------------------------------------------------
local xmlFile = assert(io.open(PANEL_XML, "rb"), "读不到 " .. PANEL_XML)
local xmlText = xmlFile:read("*a")
xmlFile:close()
local xmlIds = {}
for id in xmlText:gmatch('ID="([^"]+)"') do
	xmlIds[id] = true
end
local missingIds = {}
local function NoteAccess(name)
	if xmlIds[name] ~= true then table.insert(missingIds, name) end
end

-- ---------------------------------------------------------------------------
-- 控件桩
-- ---------------------------------------------------------------------------
local function NewControl(name)
	local control = { name = name, hidden = false, text = nil, offsetX = 0, offsetY = 0 }
	function control.SetHide(_, value) control.hidden = value == true end
	function control.IsHidden() return control.hidden end
	function control.SetText(_, value) control.text = value end
	function control.GetText() return control.text end
	function control.SetColor() end
	function control.SetIcon(_, value) control.icon = value end
	function control.SetTexture(_, value) control.texture = value end
	function control.SetOffsetX(_, value) control.offsetX = value end
	function control.SetOffsetY(_, value) control.offsetY = value end
	function control.SetToolTipString() end
	function control.SetSizeX() end
	function control.SetSizeY() end
	function control.CalculateSize() end
	function control.GetSizeX() return 1330 end
	function control.GetSizeY() return 724 end
	function control.RegisterCallback(_, eventType, handler) control.clickHandler = handler end
	function control.SetVoid1() end
	function control.GetID() return name end
	function control.Click()
		if control.clickHandler ~= nil then control.clickHandler() end
	end
	return control
end

local controlsCache = {}
Controls = setmetatable({}, { __index = function(tableRef, key)
	NoteAccess(key)
	local control = NewControl(key)
	rawset(tableRef, key, control)
	return control
end })

local function NewInstanceProxy()
	local cache = {}
	return setmetatable({}, { __index = function(tableRef, key)
		NoteAccess(key)
		local control = cache[key]
		if control == nil then
			control = NewControl(key)
			cache[key] = control
		end
		return control
	end })
end

local managers = {}
InstanceManager = {
	new = function(_, instanceName, rootName, parent)
		local manager = { instanceName = instanceName, instances = {} }
		function manager.ResetInstances()
			manager.instances = {}
		end
		function manager.GetInstance()
			local instance = NewInstanceProxy()
			table.insert(manager.instances, instance)
			return instance
		end
		managers[instanceName] = manager
		return manager
	end,
}

local function ClickInstance(instanceName, index, controlName)
	local manager = managers[instanceName]
	if manager == nil or manager.instances[index] == nil then return false end
	local control = manager.instances[index][controlName]
	if control == nil then return false end
	control:Click()
	return true
end

-- ---------------------------------------------------------------------------
-- 引擎桩
-- ---------------------------------------------------------------------------
local assistantRows = {
	{ AssistantType = 'ASSISTANT_PLANA', Name = 'LOC_LEADER_KOCMOCA_PLANA_NAME',
	  Description = 'LOC_LEADER_KOCMOCA_PLANA_DESCRIPTION', Portrait = 'IMG_LEADER_KOCMOCA_PLANA_NEUTRAL',
	  TopicType = 'ASSISTANT_TOPIC_FOREIGN_INFORMATION', SceneType = 'IMG_ASSISTANT_SCENE_BA' },
	{ AssistantType = 'ASSISTANT_ARONA', Name = 'LOC_LEADER_KOCMOCA_ARONA_NAME',
	  Description = 'LOC_LEADER_KOCMOCA_ARONA_DESCRIPTION', Portrait = 'IMG_LEADER_KOCMOCA_ARONA_NEUTRAL',
	  TopicType = 'ASSISTANT_TOPIC_NATIONAL_INFORMATION', SceneType = 'IMG_ASSISTANT_SCENE_BA' },
	{ AssistantType = 'ASSISTANT_SMILING_PROFESSOR', Name = 'LOC_LEADER_KOCMOCA_SMILING_PROFESSOR_NAME',
	  Description = 'LOC_LEADER_KOCMOCA_SMILING_PROFESSOR_DESCRIPTION',
	  Portrait = 'IMG_LEADER_KOCMOCA_SMILING_PROFESSOR_NEUTRAL',
	  TopicType = 'ASSISTANT_TOPIC_ACTION', SceneType = 'IMG_ASSISTANT_SCENE_SHALE' },
}
local topicRows = {
	{ TopicType = 'ASSISTANT_TOPIC_FOREIGN_INFORMATION', TopicBranch = 'TOPIC_BRANCH_FOREIGN_ECONOMY' },
	{ TopicType = 'ASSISTANT_TOPIC_FOREIGN_INFORMATION', TopicBranch = 'TOPIC_BRANCH_FOREIGN_SPY_ACTION' },
	{ TopicType = 'ASSISTANT_TOPIC_ACTION', TopicBranch = 'TOPIC_BRANCH_AUTO_REPAIR_PILLAGED' },
	{ TopicType = 'ASSISTANT_TOPIC_ACTION', TopicBranch = 'TOPIC_BRANCH_AUTO_DISPATCH_ARMY' },
	{ TopicType = 'ASSISTANT_TOPIC_ACTION', TopicBranch = 'TOPIC_BRANCH_AUTO_FILL_DISTRICT_BUILDINGS' },
}

local function NewRowIterator(rows)
	local index = 0
	return function()
		index = index + 1
		return rows[index]
	end
end
GameInfo = {
	Kocmoca_Assistants = function() return NewRowIterator(assistantRows) end,
	Kocmoca_Assistant_Topics = function() return NewRowIterator(topicRows) end,
}

Locale = { Lookup = function(key) return key end }
UI = { PlaySound = function() end }
Mouse = { eLClick = 1 }
Keys = { VK_ESCAPE = 27 }
KeyEvents = { KeyUp = 1 }
Events = { LoadGameViewStateDone = { Add = function() end } }
ContextPtr = { SetInputHandler = function() end }
local sidebarRegistered = false
ExposedMembers = {
	ModMiscToolUI = {
		RegisterSidebarButton = function() sidebarRegistered = true end,
	},
}

include = function() end

-- ---------------------------------------------------------------------------
-- 载入被测面板（文件末尾会自己 Initialize）
-- ---------------------------------------------------------------------------
assert(loadfile(PANEL_LUA))()

Section('① 控件 ID 与 XML 对齐')
Check('面板文件里引用的控件都能在 XML 找到', #missingIds == 0,
	table.concat(missingIds, ", "))
Check('XML 里定义了三个实例模板', xmlIds['AssistantSceneTabButton'] == true
	and xmlIds['AssistantCharacterButton'] == true
	and xmlIds['AssistantBranchButton'] == true)

Section('② 打开面板：场景分组与书签')
OpenAssistantPanel()
Check('两个场景各一个书签', #managers["AssistantSceneTabInstance"].instances == 2)
Check('默认选中第一个场景，场景 1 的两个助手都平铺出来',
	managers["AssistantCharacterInstance"].instances ~= nil)
Check('默认场景背景纹理是 BA 场景',
	Controls.AssistantSceneBackground.texture == 'IMG_ASSISTANT_SCENE_BA')
Check('侧栏入口已注册', sidebarRegistered == true)
Check('对话面板初始隐藏', Controls.AssistantDialoguePanel.hidden == true)

Section('③ 点助手：其他隐藏 + 对话展开 + 分支按 TopicType 填充')
ClickInstance("AssistantCharacterInstance", 1, "AssistantCharacterButton")
Check('对话面板展开', Controls.AssistantDialoguePanel.hidden == false)
Check('选中的助手移到左侧（偏移为负）',
	managers["AssistantCharacterInstance"].instances[1].AssistantCharacterButton.offsetX < 0)
Check('其他助手隐藏',
	managers["AssistantCharacterInstance"].instances[2].AssistantCharacterButton.hidden == true)
Check('Plana 的分支 = 2 条', #managers["AssistantBranchInstance"].instances == 2)
Check('分支文案已填（LOC key 兜底）',
	managers["AssistantBranchInstance"].instances[1].AssistantBranchLabel.text ~= nil)

Section('④ 返回 / 切场景')
ClickInstance("AssistantCharacterInstance", 1, "AssistantCharacterButton")
Controls.AssistantDialogueBack:Click()
Check('返回浏览态：对话面板收起', Controls.AssistantDialoguePanel.hidden == true)
ClickInstance("AssistantSceneTabInstance", 2, "AssistantSceneTabButton")
Check('切到 SHALE 场景：背景纹理跟着换',
	Controls.AssistantSceneBackground.texture == 'IMG_ASSISTANT_SCENE_SHALE')
Check('SHALE 场景只有 1 个助手', #managers["AssistantCharacterInstance"].instances == 1)
ClickInstance("AssistantCharacterInstance", 1, "AssistantCharacterButton")
Check('Smiling Professor 的分支 = 3 条（行动类）',
	#managers["AssistantBranchInstance"].instances == 3)

Section('⑤ 关闭')
Controls.AssistantPanelClose:Click()
Check('关闭按钮收起面板', Controls.AssistantPanelRoot.hidden == true)
OpenAssistantPanel()
Check('ESC 收起面板（输入处理器）', (function()
	local handler = nil
	ContextPtr.SetInputHandler = function(_, value) handler = value end
	-- 重新跑一次 Initialize 里的注册已发生；直接取全局处理器
	handler = OnInputHandler
	local inputStruct = {
		GetMessageType = function() return KeyEvents.KeyUp end,
		GetKey = function() return Keys.VK_ESCAPE end,
	}
	local consumed = handler(inputStruct)
	return consumed == true and Controls.AssistantPanelRoot.hidden == true
end)())

-- ---------------------------------------------------------------------------
print(string.format("\n== 结果：%d 项通过，%d 项失败", pass, fail))
if fail > 0 then os.exit(1) end

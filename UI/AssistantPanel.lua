-- ===========================================================================
-- 助手面板（Plana / Arona / Smiling Professor）—— UI 逻辑
--
-- 布局与配色见同目录 AssistantPanel.xml（Blue Archive 扁平风：白 + 淡蓝纯色块）
--
-- 行为：
--   ① 左侧场景栏：场景 = Kocmoca_Assistants.SceneType 去重，书签式按钮切换；
--   ② 主体：该场景的助手按 Kocmoca_Assistants 全部平铺在背景上；
--   ③ 点助手 → 该助手移到左侧、其余隐藏，右侧展开对话面板（分支来自
--      Kocmoca_Assistant_Topics 里同 TopicType 的行）；
--   ④ 点分支 → **暂不展开**（授权者 2026-10-26：分支面板待商议，先只记录）。
--
-- 贴图口径：全部取 Assets/Processed 里从 Blue Archive 图集拆出来的图标
--   （下表 TEXTURES 注释里写的是对应文件名），由 civ6tex 出 DDS 后注册成 ICON_*：
--     ICON_ASSISTANT_PANEL    ← atlas_icons/face_blue_sparkle.png   （侧栏入口）
--     ICON_ASSISTANT_CLOSE    ← atlas_icons/cross_blue.png          （关闭）
--     ICON_ASSISTANT_BACK     ← atlas_icons/arrow_left_navy.png     （返回）
--     ICON_ASSISTANT_SCENE_TAB← atlas_icons/tag_blue.png            （场景书签）
--     ICON_ASSISTANT_BULLET   ← atlas_icons/check_cyan.png          （分支行首）
-- 场景背景 = Kocmoca_Assistants.SceneType（IMG_ASSISTANT_SCENE_*）
-- 助手立绘 = Kocmoca_Assistants.Portrait（IMG_LEADER_*_NEUTRAL）
-- ===========================================================================

include("InstanceManager")
include("SupportFunctions")
-- 面板会用到的 UI 侧取数/调用层（ImportFiles 里已登记）
include("AssistantTopics_UI.lua")
include("AssistantTopics_Call_UI.lua")

local TEXTURES = {
    panelEntry = 'ICON_ASSISTANT_PANEL',
    close = 'ICON_ASSISTANT_CLOSE',
    back = 'ICON_ASSISTANT_BACK',
    sceneTab = 'ICON_ASSISTANT_SCENE_TAB',
    bullet = 'ICON_ASSISTANT_BULLET',
}

local CHARACTER_WIDTH = 200
local CHARACTER_GAP = 24
local CHARACTER_SIDE_MARGIN = 28
local DEFAULT_SCENE_AREA_WIDTH = 1330

local m_SceneTabIM = nil
local m_CharacterIM = nil
local m_BranchIM = nil

local m_Scenes = {}                 -- { { sceneType, assistants = { row, ... } }, ... }
local m_SelectedScene = nil
local m_SelectedAssistantIndex = nil
local m_CharacterInstances = {}     -- [i] = instance controls
local m_SidebarRegistered = false

-- ---------------------------------------------------------------------------
-- 文本：优先 LOC，没有就退回"由数据名收拾出来"的占位（不写死用户可见文案）
-- ---------------------------------------------------------------------------
local function LocalizeOrFallback(locKey, fallbackText)
    local text = Locale.Lookup(locKey)
    if text ~= nil and text ~= locKey then return text end
    return fallbackText
end

local function GetSceneLabel(sceneType)
    local fallback = tostring(sceneType):gsub('^IMG_ASSISTANT_SCENE_', ''):gsub('_', ' ')
    return LocalizeOrFallback('LOC_' .. tostring(sceneType), fallback)
end

local function GetBranchLabel(topicBranch)
    local fallback = tostring(topicBranch):gsub('^TOPIC_BRANCH_', ''):gsub('_', ' ')
    return LocalizeOrFallback('LOC_' .. tostring(topicBranch), fallback)
end

-- ---------------------------------------------------------------------------
-- 数据：助手按场景分组；分支按 TopicType 取
-- ---------------------------------------------------------------------------
local function LoadAssistantScenes()
    local scenes = {}
    local sceneIndex = {}
    if GameInfo.Kocmoca_Assistants == nil then
        print("[PlanaAssistant][UI] Kocmoca_Assistants 表不存在（SQL 没加载？）")
        return scenes
    end
    for assistantRow in GameInfo.Kocmoca_Assistants() do
        local sceneType = assistantRow.SceneType
        if sceneType == nil then sceneType = 'IMG_ASSISTANT_SCENE_BA' end
        local scene = sceneIndex[sceneType]
        if scene == nil then
            scene = { sceneType = sceneType, assistants = {} }
            sceneIndex[sceneType] = scene
            table.insert(scenes, scene)
        end
        table.insert(scene.assistants, assistantRow)
    end
    return scenes
end

local function GetAssistantTopicBranches(topicType)
    local branches = {}
    if topicType == nil or GameInfo.Kocmoca_Assistant_Topics == nil then return branches end
    for topicRow in GameInfo.Kocmoca_Assistant_Topics() do
        if topicRow.TopicType == topicType then
            table.insert(branches, topicRow.TopicBranch)
        end
    end
    return branches
end

-- ---------------------------------------------------------------------------
-- 场景栏
-- ---------------------------------------------------------------------------
local function RebuildSceneTabs()
    m_SceneTabIM:ResetInstances()
    for index, scene in ipairs(m_Scenes) do
        local instance = m_SceneTabIM:GetInstance()
        instance.AssistantSceneTabLabel:SetText(GetSceneLabel(scene.sceneType))
        -- 书签图标优先用该场景第一个助手的 ICON_*，没有就退回通用书签图标
        local firstAssistant = scene.assistants[1]
        local sceneIcon = firstAssistant ~= nil and firstAssistant.Icon or TEXTURES.sceneTab
        instance.AssistantSceneTabIcon:SetIcon(sceneIcon)
        instance.AssistantSceneTabButton:RegisterCallback(Mouse.eLClick, function()
            SelectScene(index)
        end)
        scene.tabInstance = instance
    end
    Controls.AssistantSceneStack:CalculateSize()
    Controls.AssistantSceneScroll:CalculateSize()
end

local function RefreshSceneTabSelection()
    for _, scene in ipairs(m_Scenes) do
        local instance = scene.tabInstance
        if instance ~= nil then
            local selected = (scene == m_SelectedScene)
            instance.AssistantSceneTabBlock:SetColor(selected and "126,200,240,255" or "255,255,255,235")
            instance.AssistantSceneTabAccent:SetHide(not selected)
            instance.AssistantSceneTabLabel:SetColor(selected and "255,255,255,255" or "96,132,160,255")
        end
    end
end

-- ---------------------------------------------------------------------------
-- 主体：助手平铺 / 选中
-- ---------------------------------------------------------------------------
local function GetSceneAreaWidth()
    local width = Controls.AssistantSceneArea:GetSizeX()
    if width == nil or width <= 0 then return DEFAULT_SCENE_AREA_WIDTH end
    return width
end

local function LayoutCharacters()
    m_CharacterIM:ResetInstances()
    m_CharacterInstances = {}
    m_SelectedAssistantIndex = nil
    if m_SelectedScene == nil then return end

    local assistants = m_SelectedScene.assistants
    local count = #assistants
    local areaWidth = GetSceneAreaWidth()
    local step = CHARACTER_WIDTH + CHARACTER_GAP
    local totalWidth = count * CHARACTER_WIDTH + math.max(0, count - 1) * CHARACTER_GAP
    local startX = -totalWidth / 2 + CHARACTER_WIDTH / 2

    for index, assistantRow in ipairs(assistants) do
        local instance = m_CharacterIM:GetInstance()
        instance.AssistantCharacterPortrait:SetTexture(assistantRow.Portrait)
        instance.AssistantCharacterName:SetText(Locale.Lookup(assistantRow.Name))
        instance.AssistantCharacterSelectBar:SetHide(true)
        instance.AssistantCharacterButton:SetHide(false)
        instance.AssistantCharacterButton:SetOffsetX(math.floor(startX + (index - 1) * step))
        instance.AssistantCharacterButton:SetOffsetY(0)
        instance.AssistantCharacterButton:RegisterCallback(Mouse.eLClick, function()
            SelectAssistant(index)
        end)
        m_CharacterInstances[index] = instance
    end
end

function SelectScene(index)
    local scene = m_Scenes[index]
    if scene == nil then return end
    m_SelectedScene = scene
    Controls.AssistantSceneBackground:SetTexture(scene.sceneType)
    Controls.AssistantDialoguePanel:SetHide(true)
    Controls.AssistantEmptyHint:SetHide(#scene.assistants > 0)
    RefreshSceneTabSelection()
    LayoutCharacters()
end

function SelectAssistant(index)
    if m_SelectedScene == nil or m_CharacterInstances[index] == nil then return end
    m_SelectedAssistantIndex = index
    local areaWidth = GetSceneAreaWidth()
    local leftEdgeOffset = -areaWidth / 2 + CHARACTER_SIDE_MARGIN + CHARACTER_WIDTH / 2

    for characterIndex, instance in ipairs(m_CharacterInstances) do
        local selected = (characterIndex == index)
        instance.AssistantCharacterButton:SetHide(not selected)
        instance.AssistantCharacterSelectBar:SetHide(not selected)
        if selected then
            instance.AssistantCharacterButton:SetOffsetX(math.floor(leftEdgeOffset))
        end
    end
    ShowDialogue(m_SelectedScene.assistants[index])
end

function ShowBrowsing()
    Controls.AssistantDialoguePanel:SetHide(true)
    LayoutCharacters()
end

-- ---------------------------------------------------------------------------
-- 对话面板
-- ---------------------------------------------------------------------------
function ShowDialogue(assistantRow)
    Controls.AssistantDialoguePanel:SetHide(false)
    PopulateBranchList(assistantRow.TopicType)
end

function PopulateBranchList(topicType)
    m_BranchIM:ResetInstances()
    local branches = GetAssistantTopicBranches(topicType)
    for _, topicBranch in ipairs(branches) do
        local instance = m_BranchIM:GetInstance()
        instance.AssistantBranchIcon:SetIcon(TEXTURES.bullet)
        instance.AssistantBranchLabel:SetText(GetBranchLabel(topicBranch))
        instance.AssistantBranchButton:RegisterCallback(Mouse.eLClick, function()
            OnBranchClicked(topicBranch)
        end)
    end
    Controls.AssistantBranchStack:CalculateSize()
    Controls.AssistantBranchScroll:CalculateSize()
end

-- 分支面板**待商议**：现在只记录点击，不展开二级面板
function OnBranchClicked(topicBranch)
    print("[PlanaAssistant][UI] 点击分支: " .. tostring(topicBranch))
end

-- ---------------------------------------------------------------------------
-- 打开 / 关闭
-- ---------------------------------------------------------------------------
function RefreshAssistantPanel()
    Controls.AssistantEmptyHint:SetText(LocalizeOrFallback('LOC_ASSISTANT_PANEL_NO_DATA', ''))
    m_Scenes = LoadAssistantScenes()
    m_SelectedScene = nil
    RebuildSceneTabs()
    Controls.AssistantDialoguePanel:SetHide(true)
    if #m_Scenes > 0 then
        SelectScene(1)
    else
        Controls.AssistantEmptyHint:SetHide(false)
    end
end

function OpenAssistantPanel()
    RefreshAssistantPanel()
    Controls.AssistantPanelRoot:SetHide(false)
    UI.PlaySound("UI_Screen_Open")
end

function CloseAssistantPanel()
    Controls.AssistantPanelRoot:SetHide(true)
    UI.PlaySound("UI_Screen_Close")
end

function ToggleAssistantPanel()
    if Controls.AssistantPanelRoot:IsHidden() then
        OpenAssistantPanel()
    else
        CloseAssistantPanel()
    end
end

function OnInputHandler(inputStruct)
    if Controls.AssistantPanelRoot:IsHidden() then return false end
    if inputStruct:GetMessageType() == KeyEvents.KeyUp and inputStruct:GetKey() == Keys.VK_ESCAPE then
        CloseAssistantPanel()
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 侧栏入口（借 Mod Misc Tool 的左侧透明工具栏；没装就不注册）
-- ---------------------------------------------------------------------------
local function TryRegisterSidebarButton()
    if m_SidebarRegistered then return end
    if ExposedMembers == nil or ExposedMembers.ModMiscToolUI == nil then return end
    local registerSidebarButton = ExposedMembers.ModMiscToolUI.RegisterSidebarButton
    if registerSidebarButton == nil then return end
    local label = LocalizeOrFallback('LOC_ASSISTANT_PANEL_ENTRY', '')
    registerSidebarButton(TEXTURES.panelEntry, label, '', ToggleAssistantPanel)
    m_SidebarRegistered = true
    print("[PlanaAssistant][UI] 侧栏入口已注册")
end

-- ---------------------------------------------------------------------------
-- 初始化
-- ---------------------------------------------------------------------------
function Initialize()
    Controls.AssistantPanelRoot:SetHide(true)
    m_SceneTabIM = InstanceManager:new("AssistantSceneTabInstance", "AssistantSceneTabButton",
        Controls.AssistantSceneStack)
    m_CharacterIM = InstanceManager:new("AssistantCharacterInstance", "AssistantCharacterButton",
        Controls.AssistantCharacterLayer)
    m_BranchIM = InstanceManager:new("AssistantBranchInstance", "AssistantBranchButton",
        Controls.AssistantBranchStack)

    Controls.AssistantPanelCloseIcon:SetIcon(TEXTURES.close)
    Controls.AssistantDialogueBackIcon:SetIcon(TEXTURES.back)
    Controls.AssistantPanelClose:RegisterCallback(Mouse.eLClick, CloseAssistantPanel)
    Controls.AssistantDialogueBack:RegisterCallback(Mouse.eLClick, ShowBrowsing)
    ContextPtr:SetInputHandler(OnInputHandler, true)

    TryRegisterSidebarButton()
    Events.LoadGameViewStateDone.Add(TryRegisterSidebarButton)

    if ExposedMembers ~= nil then
        if ExposedMembers.PlanaAssistantPanel == nil then ExposedMembers.PlanaAssistantPanel = {} end
        ExposedMembers.PlanaAssistantPanel.Open = OpenAssistantPanel
        ExposedMembers.PlanaAssistantPanel.Close = CloseAssistantPanel
        ExposedMembers.PlanaAssistantPanel.Toggle = ToggleAssistantPanel
    end
end
Initialize()

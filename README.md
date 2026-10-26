# Plana and Arona

碧蓝档案风格的 AI 助手领袖模组：三位助手（Plana / Arona / Smiling Professor）作为
`CIVILIZATION_RUSSIA` 下的领袖，配一套扁平风助手面板与对话分支。

## 目录

| 路径 | 内容 |
|---|---|
| `AssistantDefine.sql` | `Kocmoca_Assistants` / `Kocmoca_Assistant_Topics` 建表 |
| `PlanaAssistant.sql` | 三位助手与 21 条对话分支 |
| `AssistantTopics.lua` | 后端取数层 + TopicBranch 分发（点一次算一次，不扫地图） |
| `CallTopicFunctions.lua` | 分支调用入口（targeted / 一次性），暴露给 UI |
| `SummonAssistant.lua` | 助手召唤与存档 |
| `AssistantTopics_UI.lua` / `AssistantTopics_Call_UI.lua` | UI 侧取数与调用约定 |
| `UI/AssistantPanel.xml` + `.lua` | 助手面板（左侧场景书签、场景平铺、右侧对话） |
| `Data/Assistant_Leaders.xml` | 三位领袖（不写 Config，不进可选列表，能力留空） |
| `Data/Assistant_Icon.xml` | 领袖与面板图标注册（散装 DDS） |
| `Text/` | 中英文文本（领袖、面板、分支标题） |
| `XLPs/`、`Artdefs/FallbackLeaders.artdef`、`PlanaAssistant.dep` | 领袖正式立绘（LeaderFallback 包）与普通 UITexture 打包 |
| `BasilissaAssistants.modinfo` | 模组定义 |
| `.harness/` | 桩测试（无需游戏即可跑） |

## 测试

```bash
lua .harness/assistant_topics_test.lua   # 话题/数据层
lua .harness/assistant_panel_test.lua    # 面板（XML/Lua 控件对齐 + 交互）
```

## 贴图与打包（不在本仓库）

`Assets/`（原始素材与拆图）、`Icons/`（散装图标 DDS）、`Textures/`（cook 输入）、
`Platforms/`（BLP 产物）体积较大，未纳入版本库。重建方式（工具：Civ6TextureTools）：

```bash
# 1) 图标（散装 DDS + 注册 XML）
python3 -m civ6tex icons Assets/Processed/avatars/ICON_LEADER_KOCMOCA_PLANA.png \
    --name ICON_LEADER_KOCMOCA_PLANA --type Leaders --out Icons --register Data/Assistant_Icon.xml
# 2) 领袖立绘 / 场景背景（UITexture + LeaderFallback 两个包）
python3 -m civ6tex uitexture --entry IMG_ASSISTANT_SCENE_BA=Assets/Processed/backgrounds/IMG_ASSISTANT_SCENE_BA.png \
    --staging . --out . --package IMG_UITexture --xlp XLPs/UITexture.xlp --no-cook
# 3) 用 SDK 烘焙 BLP
python3 -m civ6tex cook XLPs/UITexture.xlp --staging . --stewpot Platforms/Windows/BLPs \
    --cooker "$CIV6_SDK/AssetModTools/Cooker/Civ6AssetCooker_FinalRelease.exe" --wine wine
```

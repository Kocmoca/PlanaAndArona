# Processed 资产（由 Civ6TextureTools 生成）

源图在 `../`（Assets 根），这里只放**处理好的成品**，全部 RGBA / 透明背景，可直接进 DDS 管线。

## avatars/ —— 领袖图标（圆形裁剪）

| 文件 | 尺寸 | 来源 |
|---|---|---|
| `ICON_LEADER_KOCMOCA_PLANA.png` | 256×256 | `PlanaIcon.webp`（圆形裁剪 + 缩放） |
| `ICON_LEADER_KOCMOCA_ARONA.png` | 256×256 | `Arona_Icon.webp` |
| `ICON_LEADER_KOCMOCA_SMILING_PROFESSOR.png` | 256×256 | `Smiling_Professor_Icon.webp` |

* 圆外 alpha = 0（圆形蒙版与原 alpha 相乘，不吞素材自带的透明）；
* 256 是官方 `Leaders` 图标类型的最大档（`civ6tex types --match Leader` → 32/45/48/50/55/64/80/256），
  要出多档直接用 `civ6tex icons <png> --name ICON_LEADER_... --type Leaders --out ...`。

## portraits/ —— 领袖立绘（高度 1024）

`IMG_LEADER_KOCMOCA_*_NEUTRAL.png`，高度统一 1024、宽度按原比例（501–534），保留透明背景。

| 文件 | 尺寸 | 来源 |
|---|---|---|
| `IMG_LEADER_KOCMOCA_PLANA_NEUTRAL.png` | 534×1024 | `PlanaPortrait.webp` |
| `IMG_LEADER_KOCMOCA_ARONA_NEUTRAL.png` | 523×1024 | `Arona_Portrait.webp` |
| `IMG_LEADER_KOCMOCA_ARONA_NEUTRAL_2.png` | 533×1024 | `Arona_Portrait_2.webp` |
| `IMG_LEADER_KOCMOCA_SMILING_PROFESSOR_NEUTRAL.png` | 501×1024 | `Smiling_Professor_Portrait.webp` |

## backgrounds/ —— 助手对话背景（1920×1010）

统一按"**等比覆盖 + 居中裁切**"处理（`civ6tex img fit --mode cover`）：填满画框、不拉伸变形。

| 文件 | 尺寸 | 来源 | 处理 |
|---|---|---|---|
| `IMG_ASSISTANT_SCENE_BA.png` | 1920×1010 | `IMG_ASSISTANT_SCENE_BA.webp`（1920×1080） | 1:1 像素，上下各裁 35px |
| `IMG_ASSISTANT_SCENE_SHALE.png` | 1920×1010 | `IMG_ASSISTANT_SCENE_SHALE.jpeg`（1280×899） | 先 ×1.5 到 1920×1349，再上下各裁 170px |

要"不裁内容"的话改成 `--mode contain`（四周补透明边）；要精确拉伸不裁就用
`civ6tex img resize --size 1920x1010`。

## atlas_icons/ —— `Icons.png` 拆出来的图标

* 420 个独立 PNG（`<外观名>.png`，命名见 `manifest.json`；126 个只有柔和阴影/光斑的碎片
  仍保留 `icon_NNN.png` 编号）；
* `manifest.json`：每个图标的 bbox、宽高、不透明像素数、峰值 alpha、主色、名字；
* `contact_1..5.png`：带编号的联络表（每格左上角编号 = manifest 里的 index），找图先看这个；
* `names.json`：本次按外观命名的映射（`编号 → 名字`），后续改名照这个格式继续加。

重新生成 / 调整参数（工作目录 = `Civ6TextureTools`）：

```bash
# 拆（可调 --alpha-threshold / --min-pixels / --gap / --padding）
python3 -m civ6tex atlas split "../Plana and Arona/Assets/Icons.png" \
    --out "../Plana and Arona/Assets/Processed/atlas_icons"

# 补名字
python3 -m civ6tex atlas name "../Plana and Arona/Assets/Processed/atlas_icons" \
    --map "../Plana and Arona/Assets/Processed/atlas_icons/names.json"
```

## 备注

* 命名用的是**外观描述**（颜色 + 物体 + 形态），不是游戏内原名——素材来源没有随图元数据。
* 圆形头像的裁切圆心是图片中心；某张头像构图偏了的话，用
  `civ6tex img crop-circle <src> <dst> --diameter N --center X Y` 重裁。

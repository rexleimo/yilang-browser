# 一览 Yilan · Logo 方案

四个矢量方案（SVG 源文件 + 1024px PNG 渲染稿 + 对比总览图）：

| 方案 | 文件 | 一句话 |
|------|------|--------|
| C1 环视之眼（推荐） | `c1_gaze.svg` | 品牌「圆 + 点」符号的放大重述，延续官网视觉 |
| C2 书签墙 | `c2_wall.svg` | 招牌设计直接画进图标，产品叙事最强 |
| C3「一」字笔触 | `c3_yi.svg` | 一横一点，极简，小尺寸辨识度最高 |
| C4 展开的全景 | `c4_panorama.svg` | 卡片展开成扇，「打开网页，一览无余」 |

`preview.png` / `preview.html` 是四案对比总览（含设计说明）。

## 选定后如何应用到 App

用 [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) 一键生成全部平台启动图标：

```bash
flutter pub add dev:flutter_launcher_icons
```

`pubspec.yaml` 追加：

```yaml
flutter_launcher_icons:
  image_path: "design/logo/c1_gaze.png"   # 换成你选定的 PNG
  android: true
  ios: true
  remove_alpha_ios: true
```

然后：

```bash
flutter pub get
dart run flutter_launcher_icons
```

官网 favicon 同步：把选定 SVG 简化版替换 `website/favicon.svg` 与 `og-image.png`。

## AI 风格化版本（可选）

RexAI 生图 API 当前额度不足（402）。充值后可用下面存好的提示词直接生成
AI 风格化版本（模型 `gpt-image-2`，尺寸 1024x1024，脚本见
`~/.agents/skills/rexai-image-generation/scripts/rexai-image.ps1`）：

1. **环视之眼**：`iOS app icon design, rounded square with flat vector style: a minimal geometric eye formed by one bold white circular outline with a small glowing bright-indigo dot at its upper right, deep indigo to violet gradient background (#4353C4 to #6a4cf5), centered composition, generous negative space, premium modern tech aesthetic, crisp edges, no text, no letters, no watermark`

2. **书签墙**：`iOS app icon design, rounded square, flat vector style: a 2x2 grid of rounded bookmark tiles, one tile glowing bright indigo-violet with a small white dot, three tiles in soft translucent white, on a near-black dark background with subtle violet gradient glow, premium minimal tech aesthetic, crisp edges, no text, no letters, no watermark`

3. **「一」字笔触**：`iOS app icon design, rounded square, flat vector style: a single elegant white horizontal brushstroke bar with a small glowing indigo dot floating above its right end, on a deep indigo to dark navy gradient background, zen minimal composition, generous negative space, premium aesthetic, no text, no letters, no watermark`

4. **展开的全景**：`iOS app icon design, rounded square, flat vector style: three overlapping translucent rounded cards fanning out like a hand of cards suggesting a wide panoramic view, front card bright white with minimal indigo page elements, back cards translucent indigo and violet, on a deep indigo to dark navy gradient background, premium tech aesthetic, crisp edges, no text, no letters, no watermark`

> 提示：AI 生成结果需要人工检查一致性（渐变角度、色值偏差），选定后建议仍以
> SVG 矢量版为最终源文件，AI 版本仅作风格参考或宣传图素材。

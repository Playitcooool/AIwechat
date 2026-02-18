# AIwechat

AIwechat 现在提供 **SwiftUI macOS UI** 版本（推荐）和原有 Python 版本（保留）。

## SwiftUI 版本（推荐）

特性：
- 原生 macOS 窗口（SwiftUI）
- 自动监听剪贴板并触发
- 仅微信前台触发（可配置）
- 多轮上下文记忆
- 每条建议独立显示，`👍` 点赞后自动复制
- 点赞数据自动写入本地 `JSONL` 偏好数据集
- training-free 风格学习：基于点赞数据自动生成本地风格画像并注入生成上下文

### 1. 环境

- macOS 13+
- Xcode Command Line Tools 或 Xcode（含 Swift 5.9+）

### 2. 配置

编辑 `Sources/AIwechatMac/AssistantViewModel.swift` 中 `AppConfig`：

- `openAIAPIKey`
- `openAIModel`
- `openAIBaseURL`
- `systemPrompt`
- `enableContextMemory`
- `contextWindowSize`
- `wechatOnlyMode`
- `strictWechatDetection`
- `ignoreSelfPrefixes`
- `myName`
- `pollInterval`
- `enableStyleLearning`
- `minFeedbackForStyle`
- `maxStyleSamples`

### 3. 运行

```bash
swift run AIwechatMac
```

如果你想用 Xcode 打开：

```bash
open Package.swift
```

### 4. 打包为 `.app`（双击运行）

在项目根目录执行：

```bash
swift build -c release

APP_DIR="dist/AIwechat.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/AIwechatMac "$APP_DIR/Contents/MacOS/AIwechat"
chmod +x "$APP_DIR/Contents/MacOS/AIwechat"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AIwechat</string>
    <key>CFBundleIdentifier</key>
    <string>com.aiwechat.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AIwechat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign - "$APP_DIR"
```

生成后的应用路径：`dist/AIwechat.app`  
首次打开若被 Gatekeeper 拦截，右键应用选择“打开”再确认一次即可。

### 5. 数据集路径

点赞反馈默认写入：

- `~/AIwechat/preferences.jsonl`
- `~/AIwechat/style_profile.json`（自动生成的风格画像）

每行一条记录，包含：
- `timestamp`
- `sourceMessage`
- `contextMessages`
- `candidates`
- `chosen`
- `model`

当反馈样本达到 `minFeedbackForStyle` 后，程序会：
1. 读取 `preferences.jsonl`
2. 总结你的句长/语气/收尾偏好
3. 写入 `style_profile.json`
4. 在后续生成时自动加到 prompt（training-free）

## Python 版本（保留）

仓库里仍保留 `app.py` 版本，便于对照或回退。

## 说明

- 不使用微信官方 API。
- 当前触发机制是“复制消息 -> 自动生成建议”。
- 如果后续要做到“收到消息自动触发（无需复制）”，需要 OCR/桌面自动化方案。

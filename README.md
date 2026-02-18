# AIwechat
自用！！！！
用来回复那些不知道怎么回复的女孩子的消息

一个不依赖微信官方 API 的本地微信回复助手：
- 监听剪贴板（你复制消息时触发）
- 用 `ChatOpenAI` 生成 3 条独立回复建议
- `PySide6` 悬浮窗展示建议
- 每条建议支持 `👍` 反馈：自动复制 + 记录偏好数据集

## 功能

- 自动监听剪贴板并生成回复建议
- 多轮上下文记忆（可配置最近 N 条）
- 微信前台过滤（减少其他应用误触发）
- 过滤疑似自己消息（前缀/昵称）
- 点赞反馈写入本地 `JSONL`，可用于后续风格训练
- 无边框、可拖拽、常驻置顶窗口

## 环境要求

- Python 3.11+
- macOS（微信前台检测逻辑基于 `osascript`；其他系统可运行，但前台检测能力会弱化）

## 安装

```bash
conda create -n aiwechat python=3.11 -y
conda activate aiwechat
pip install -r requirements.txt
```

## 配置

直接编辑 `app.py` 顶部配置项：

- `OPENAI_API_KEY`：必填
- `OPENAI_MODEL`：模型名
- `OPENAI_BASE_URL`：可选，本地网关/代理地址（如 LM Studio）
- `SYSTEM_PROMPT`：系统提示词
- `ENABLE_CONTEXT_MEMORY`：是否开启上下文记忆
- `CONTEXT_WINDOW_SIZE`：上下文条数
- `WECHAT_ONLY_MODE`：仅微信前台触发
- `STRICT_WECHAT_DETECTION`：前台检测失败时是否拦截
- `IGNORE_SELF_MESSAGE_PREFIXES`：自己消息前缀过滤
- `MY_NAME`：你的昵称（用于过滤自己消息）
- `FEEDBACK_DATASET_PATH`：偏好数据集路径（默认 `data/preferences.jsonl`）
- `POLL_INTERVAL_MS`：剪贴板轮询间隔

## 运行

```bash
python app.py
```

## 使用流程

1. 打开微信聊天窗口
2. 复制对方消息（`Cmd + C`）
3. 程序自动生成 3 条独立建议（分条显示）
4. 点击某条右侧 `👍`：
- 自动复制该条
- 记录偏好样本到本地 `JSONL`
5. 或点击“复制全部”一次复制三条

## 偏好数据集

默认路径：`data/preferences.jsonl`

每行一条 JSON 记录，字段包含：
- `timestamp`
- `source_message`
- `context_messages`
- `candidates`
- `chosen`
- `model`

## 常见问题

1. 切换微信后窗口会最小化
- 已通过窗口类型和状态处理修复；请用最新代码运行。

2. 输出里出现 `[]` 或引号
- 已做输出清洗与解析兜底；仍出现时可调整 `SYSTEM_PROMPT` 并重试。

3. 非微信内容被误触发
- 打开 `WECHAT_ONLY_MODE`
- 设 `STRICT_WECHAT_DETECTION = True`

## 边界说明

- 本项目不读取微信数据库，不调用微信官方 API。
- “仅微信触发”是前台窗口级过滤，不是系统级强鉴权。
- 如果需要“收到消息就自动触发（无需复制）”，需要 OCR/自动化方案，复杂度更高。

import os
import platform
import re
import subprocess
import sys
from collections import deque
from datetime import datetime
import json

import pyperclip
from langchain_openai import ChatOpenAI

# Suppress noisy ICC warnings on some macOS display profiles.
os.environ.setdefault("QT_LOGGING_RULES", "qt.gui.icc.warning=false")

from PySide6.QtCore import QEvent, QEasingCurve, QPoint, QPropertyAnimation, QThread, QTimer, Qt, Signal
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import (
    QApplication,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

OPENAI_API_KEY = "no_need"
OPENAI_MODEL = "lmstudio-community-qwen3-4b-instruct-2507-mlx"
OPENAI_BASE_URL = "http://127.0.0.1:1234/v1"
SYSTEM_PROMPT = (
    "你是一个微信聊天助手。请基于对方消息，生成3条不同风格的中文回复建议："
    "1) 友好简短 2) 详细专业 3) 幽默自然。"
    "要求：自然口语、不过度夸张、每条不超过60字。"
)

ENABLE_CONTEXT_MEMORY = True
CONTEXT_WINDOW_SIZE = 6
WECHAT_ONLY_MODE = True
STRICT_WECHAT_DETECTION = False
WECHAT_APP_HINTS = ("WeChat", "微信")
IGNORE_SELF_MESSAGE_PREFIXES = ("我:", "我：", "Me:", "Me：")
MY_NAME = ""
POLL_INTERVAL_MS = 800
FEEDBACK_DATASET_PATH = "data/preferences.jsonl"


class GenerateWorker(QThread):
    done = Signal(str)
    failed = Signal(str)

    def __init__(self, llm: ChatOpenAI, system_prompt: str, prompt: str):
        super().__init__()
        self.llm = llm
        self.system_prompt = system_prompt
        self.prompt = prompt

    def run(self):
        try:
            resp = self.llm.invoke(
                [
                    ("system", self.system_prompt),
                    ("human", self.prompt),
                ]
            )
            content = resp.content if hasattr(resp, "content") else str(resp)
            self.done.emit(content.strip())
        except Exception as exc:
            self.failed.emit(str(exc))


class WeChatReplyAssistant(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("WeChat Reply")
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Window)
        self.setAttribute(Qt.WA_TranslucentBackground, False)
        self.resize(420, 360)

        self.last_clipboard = ""
        self.running = True
        self.generating = False
        self.pending_message = ""
        self.drag_active = False
        self.drag_position = QPoint()
        self.context_messages = deque(maxlen=max(1, CONTEXT_WINDOW_SIZE))
        self.last_user_message = ""
        self.last_context_snapshot = []
        self.last_suggestions = []

        self.llm = self._create_llm()
        self.worker = None

        self._build_ui()
        self._init_timer()

    def _create_llm(self):
        api_key = OPENAI_API_KEY.strip()
        if not api_key or api_key == "your_openai_api_key":
            return None

        kwargs = {
            "model": OPENAI_MODEL,
            "temperature": 0.7,
            "api_key": api_key,
        }
        if OPENAI_BASE_URL.strip():
            kwargs["base_url"] = OPENAI_BASE_URL.strip()
        return ChatOpenAI(**kwargs)

    def _build_ui(self):
        self.setStyleSheet(
            """
            QWidget {
                background: #0f172a;
                font-family: 'PingFang SC', 'SF Pro Display', 'Helvetica Neue';
                color: #e6edf9;
            }
            QFrame#titlebar {
                background: transparent;
            }
            QLabel#title {
                color: #dbe7ff;
                font-size: 13px;
                font-weight: 600;
            }
            QLabel#status {
                background: #12213a;
                border: 1px solid #2a3f61;
                border-radius: 11px;
                padding: 8px 10px;
                color: #9fb2d8;
                font-size: 12px;
            }
            QFrame#suggestionCard {
                background: #111c30;
                border: 1px solid #2a3f61;
                border-radius: 10px;
            }
            QLabel#suggestionText {
                color: #f3f7ff;
                font-size: 13px;
                padding: 8px;
            }
            QPushButton {
                border-radius: 10px;
                padding: 7px 12px;
                border: none;
                font-size: 12px;
            }
            QPushButton#first {
                background: #2563eb;
                color: #ffffff;
            }
            QPushButton#all {
                background: #10b981;
                color: #ffffff;
                font-weight: 600;
            }
            QPushButton#clear {
                background: #1f2937;
                color: #cdd7e6;
            }
            QPushButton#like {
                background: #1f2937;
                color: #f59e0b;
                min-width: 36px;
                max-width: 36px;
                min-height: 36px;
                max-height: 36px;
                border-radius: 18px;
                font-size: 16px;
                padding: 0;
            }
            QPushButton#close {
                background: #be2b44;
                color: #ffd9df;
                min-width: 24px;
                max-width: 24px;
                min-height: 24px;
                max-height: 24px;
                border-radius: 12px;
                padding: 0;
            }
            QPushButton:hover {
                opacity: 0.92;
            }
            """
        )

        root = QVBoxLayout()
        root.setContentsMargins(14, 12, 14, 14)
        root.setSpacing(10)

        titlebar = QFrame()
        titlebar.setObjectName("titlebar")
        title_layout = QHBoxLayout(titlebar)
        title_layout.setContentsMargins(2, 0, 2, 0)
        title_layout.setSpacing(8)

        title = QLabel("AI 回复助手")
        title.setObjectName("title")
        self.close_btn = QPushButton("×")
        self.close_btn.setObjectName("close")
        self.close_btn.clicked.connect(self.close)
        title_layout.addWidget(title)
        title_layout.addStretch()
        title_layout.addWidget(self.close_btn)
        self.titlebar = titlebar
        root.addWidget(titlebar)

        self.status_label = QLabel("自动监听中（微信前台 + 剪贴板）")
        self.status_label.setObjectName("status")
        self.status_label.setWordWrap(True)
        root.addWidget(self.status_label)

        self.suggestion_scroll = QScrollArea()
        self.suggestion_scroll.setWidgetResizable(True)
        self.suggestion_scroll.setFrameShape(QFrame.NoFrame)
        self.suggestion_container = QWidget()
        self.suggestion_layout = QVBoxLayout(self.suggestion_container)
        self.suggestion_layout.setContentsMargins(0, 0, 0, 0)
        self.suggestion_layout.setSpacing(8)
        self.suggestion_scroll.setWidget(self.suggestion_container)
        root.addWidget(self.suggestion_scroll)

        actions = QHBoxLayout()
        actions.setSpacing(8)

        self.clear_btn = QPushButton("清空上下文")
        self.clear_btn.setObjectName("clear")
        self.clear_btn.clicked.connect(self.clear_context)

        self.copy_all_btn = QPushButton("复制全部")
        self.copy_all_btn.setObjectName("all")
        self.copy_all_btn.clicked.connect(self.copy_all_suggestions)

        actions.addWidget(self.copy_all_btn)
        actions.addWidget(self.clear_btn)

        root.addLayout(actions)
        self.setLayout(root)
        self._setup_show_animation()
        self._render_suggestions([])

    def _setup_show_animation(self):
        self.fade_anim = QPropertyAnimation(self, b"windowOpacity")
        self.fade_anim.setDuration(220)
        self.fade_anim.setStartValue(0.0)
        self.fade_anim.setEndValue(1.0)
        self.fade_anim.setEasingCurve(QEasingCurve.OutCubic)

    def showEvent(self, event):
        super().showEvent(event)
        self.fade_anim.start()

    def changeEvent(self, event):
        super().changeEvent(event)
        if event.type() == QEvent.WindowStateChange and self.windowState() & Qt.WindowMinimized:
            # Keep the assistant visible when switching to WeChat or other apps.
            QTimer.singleShot(0, self.showNormal)

    def _init_timer(self):
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._poll_clipboard)
        self.timer.start(POLL_INTERVAL_MS)

    def _poll_clipboard(self):
        if WECHAT_ONLY_MODE and not self._is_wechat_foreground():
            return
        try:
            text = pyperclip.paste().strip()
        except Exception:
            return
        if not self._is_new_message(text):
            return

        self.last_clipboard = text
        if self._looks_like_self_message(text):
            self.status_label.setText("已忽略疑似自己消息")
            return

        if ENABLE_CONTEXT_MEMORY:
            self.context_messages.append(text)

        if self.generating:
            self.pending_message = text
            self.status_label.setText("生成中，已缓存最新消息")
            return

        self.generate_reply(text)

    def _is_new_message(self, text: str) -> bool:
        if not text or text == self.last_clipboard:
            return False
        if len(text) < 2 or len(text) > 1200:
            return False
        if re.fullmatch(r"[\d\W_]+", text):
            return False
        return True

    def _looks_like_self_message(self, text: str) -> bool:
        stripped = text.strip()
        for prefix in IGNORE_SELF_MESSAGE_PREFIXES:
            if stripped.startswith(prefix):
                return True
        if MY_NAME and stripped.startswith(f"{MY_NAME}:"):
            return True
        if MY_NAME and stripped.startswith(f"{MY_NAME}："):
            return True
        return False

    def _is_wechat_foreground(self) -> bool:
        if platform.system() != "Darwin":
            return not STRICT_WECHAT_DETECTION
        try:
            script = (
                'tell application "System Events" to get name of first application process '
                "whose frontmost is true"
            )
            result = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True,
                text=True,
                timeout=1.0,
                check=False,
            )
            if result.returncode != 0:
                return not STRICT_WECHAT_DETECTION
            app_name = result.stdout.strip()
            return any(hint in app_name for hint in WECHAT_APP_HINTS)
        except Exception:
            return not STRICT_WECHAT_DETECTION

    def _build_prompt(self, user_msg: str) -> str:
        output_rule = (
            "请严格输出一个 JSON 数组，长度必须是3。"
            '示例：["回复1","回复2","回复3"]。'
            "每个元素必须是一条可直接发送的完整回复。"
            "不要输出任何额外文字、序号、解释或代码块，不要在单个元素里塞多条回复。"
        )
        if not ENABLE_CONTEXT_MEMORY:
            return (
                f"对方消息：\n{user_msg}\n\n"
                "请输出3条不同风格的中文回复建议。\n"
                f"{output_rule}"
            )

        history = list(self.context_messages)
        history_lines = [f"{idx + 1}. {msg}" for idx, msg in enumerate(history)]
        history_block = "\n".join(history_lines) if history_lines else "(无)"
        return (
            "以下是最近复制到剪贴板的消息（按时间从旧到新）：\n"
            f"{history_block}\n\n"
            f"当前最新消息：\n{user_msg}\n\n"
            "请结合上下文输出3条不同风格的中文回复建议。\n"
            f"{output_rule}"
        )

    def generate_reply(self, user_msg: str):
        if not self.llm:
            self.status_label.setText("请在 app.py 设置 OPENAI_API_KEY")
            return

        self.generating = True
        self.last_user_message = user_msg
        self.last_context_snapshot = list(self.context_messages)
        self.status_label.setText("生成中...")

        prompt = self._build_prompt(user_msg)
        self.worker = GenerateWorker(self.llm, SYSTEM_PROMPT, prompt)
        self.worker.done.connect(self._on_generate_success)
        self.worker.failed.connect(self._on_generate_failed)
        self.worker.start()

    def _on_generate_success(self, content: str):
        self.generating = False
        self.last_suggestions = self._parse_suggestions(content)
        self._render_suggestions(self.last_suggestions)
        if ENABLE_CONTEXT_MEMORY:
            self.status_label.setText(f"已生成（上下文 {len(self.context_messages)} 条）")
        else:
            self.status_label.setText("已生成")
        self._consume_pending_message()

    def _on_generate_failed(self, err: str):
        self.generating = False
        self.last_suggestions = []
        self._render_suggestions([])
        self.status_label.setText(f"生成失败：{err}")
        self._consume_pending_message()

    def _consume_pending_message(self):
        if not self.pending_message:
            return
        next_msg = self.pending_message
        self.pending_message = ""
        self.generate_reply(next_msg)

    def copy_all_suggestions(self):
        text = "\n".join(self.last_suggestions).strip()
        if text:
            QGuiApplication.clipboard().setText(text)
            self.status_label.setText("已复制全部")

    def clear_context(self):
        self.context_messages.clear()
        self.status_label.setText("上下文已清空")

    def _parse_suggestions(self, content: str):
        text = content.strip()
        if not text:
            return []

        def _clean_item(item: str):
            cleaned = item.strip()
            cleaned = re.sub(r"^```[a-zA-Z]*", "", cleaned).strip()
            cleaned = re.sub(r"```$", "", cleaned).strip()
            cleaned = re.sub(r"^\d+[\).、:：\s]*", "", cleaned)
            cleaned = cleaned.replace("\\n", " ").replace('\\"', '"').replace("\\'", "'")

            # Unwrap common wrappers: quotes, brackets.
            for _ in range(3):
                prev = cleaned
                cleaned = cleaned.strip(" \t\n\r\"'“”‘’")
                if (cleaned.startswith("[") and cleaned.endswith("]")) or (
                    cleaned.startswith("（") and cleaned.endswith("）")
                ):
                    inner = cleaned[1:-1].strip()
                    # If this is a JSON list string like ["xxx"], extract first item.
                    try:
                        maybe_list = json.loads(cleaned)
                        if isinstance(maybe_list, list) and maybe_list:
                            cleaned = str(maybe_list[0]).strip()
                        else:
                            cleaned = inner
                    except Exception:
                        cleaned = inner
                if cleaned == prev:
                    break

            cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
            return cleaned

        # 1) Prefer strict JSON array parsing.
        normalized = text
        if normalized.startswith("```"):
            normalized = re.sub(r"^```[a-zA-Z]*", "", normalized).strip()
            normalized = re.sub(r"```$", "", normalized).strip()
        json_match = re.search(r"\[[\s\S]*\]", normalized)
        if json_match:
            try:
                data = json.loads(json_match.group(0))
                if isinstance(data, list):
                    parsed = [_clean_item(str(x)) for x in data if str(x).strip()]
                    parsed = [x for x in parsed if x]
                    if parsed:
                        return parsed[:3]
            except Exception:
                pass

        # 2) Fallback: split by inline numbering like "1) ... 2) ... 3) ..."
        pattern = re.compile(
            r"(?:^|[\s\n])(?:[1-9])[\.、\)）:：]\s*(.*?)(?=(?:[\s\n](?:[1-9])[\.、\)）:：]\s*)|$)",
            re.S,
        )
        chunks = [c.strip() for c in pattern.findall(text) if c.strip()]
        chunks = [_clean_item(c) for c in chunks if _clean_item(c)]
        if chunks:
            return chunks[:3]

        # 3) Fallback: by lines.
        lines = [_clean_item(line) for line in text.splitlines() if line.strip()]
        lines = [line for line in lines if line]
        if lines:
            return lines[:3]

        last = _clean_item(text)
        if last.startswith("[") and last.endswith("]"):
            try:
                data = json.loads(last)
                if isinstance(data, list):
                    cleaned = [_clean_item(str(x)) for x in data if str(x).strip()]
                    cleaned = [x for x in cleaned if x]
                    if cleaned:
                        return cleaned[:3]
            except Exception:
                pass
        return [last] if last else []

    def _clear_suggestion_cards(self):
        while self.suggestion_layout.count():
            item = self.suggestion_layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()

    def _render_suggestions(self, suggestions):
        self._clear_suggestion_cards()
        if not suggestions:
            placeholder = QLabel("暂无建议")
            placeholder.setStyleSheet("color: #8aa0c9; padding: 8px 4px;")
            self.suggestion_layout.addWidget(placeholder)
            self.suggestion_layout.addStretch()
            return

        for idx, text in enumerate(suggestions, start=1):
            card = QFrame()
            card.setObjectName("suggestionCard")
            card_layout = QHBoxLayout(card)
            card_layout.setContentsMargins(8, 6, 8, 6)
            card_layout.setSpacing(8)

            label = QLabel(f"{idx}. {text}")
            label.setObjectName("suggestionText")
            label.setWordWrap(True)

            like_btn = QPushButton("👍")
            like_btn.setObjectName("like")
            like_btn.setToolTip("点赞并复制")
            like_btn.clicked.connect(lambda _, s=text: self._on_like_suggestion(s))

            card_layout.addWidget(label, 1)
            card_layout.addWidget(like_btn, 0)
            self.suggestion_layout.addWidget(card)

        self.suggestion_layout.addStretch()

    def _on_like_suggestion(self, suggestion: str):
        QGuiApplication.clipboard().setText(suggestion)
        self._append_feedback_record(suggestion)
        self.status_label.setText("已点赞并复制")

    def _append_feedback_record(self, chosen: str):
        record = {
            "timestamp": datetime.utcnow().isoformat(timespec="seconds") + "Z",
            "source_message": self.last_user_message,
            "context_messages": self.last_context_snapshot,
            "candidates": self.last_suggestions,
            "chosen": chosen,
            "model": OPENAI_MODEL,
        }
        try:
            os.makedirs(os.path.dirname(FEEDBACK_DATASET_PATH), exist_ok=True)
            with open(FEEDBACK_DATASET_PATH, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
        except Exception as exc:
            self.status_label.setText(f"记录偏好失败：{exc}")

    def mousePressEvent(self, event):
        target = self.childAt(event.position().toPoint())
        is_title_area = False
        while target is not None:
            if target is self.titlebar:
                is_title_area = True
                break
            target = target.parentWidget()
        if event.button() == Qt.LeftButton and is_title_area:
            self.drag_active = True
            self.drag_position = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
            event.accept()
            return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if self.drag_active and (event.buttons() & Qt.LeftButton):
            self.move(event.globalPosition().toPoint() - self.drag_position)
            event.accept()
            return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self.drag_active = False
        super().mouseReleaseEvent(event)


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = WeChatReplyAssistant()
    window.show()
    sys.exit(app.exec())

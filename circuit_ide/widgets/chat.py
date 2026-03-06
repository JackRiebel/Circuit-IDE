"""
Chat Panel Widget for Circuit IDE.

Provides the AI conversation interface with streaming support.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import List, Optional

from rich.markdown import Markdown
from rich.text import Text
from textual.containers import Horizontal, Vertical
from textual.message import Message
from textual.reactive import reactive
from textual.widgets import Input, RichLog, Static


@dataclass
class ChatMessage:
    """Represents a single chat message."""

    role: str  # "user", "assistant", "tool", "system"
    content: str
    timestamp: datetime = field(default_factory=datetime.now)
    tool_name: Optional[str] = None
    tool_status: Optional[str] = None  # "pending", "success", "error"

    @property
    def display_role(self) -> str:
        """Get display name for the role."""
        return {
            "user": "You",
            "assistant": "Agent",
            "tool": f"Tool: {self.tool_name or 'unknown'}",
            "system": "System",
        }.get(self.role, self.role.title())

    @property
    def role_color(self) -> str:
        """Get color for the role."""
        return {
            "user": "cyan",
            "assistant": "green",
            "tool": "yellow",
            "system": "magenta",
        }.get(self.role, "white")


class ChatMessageWidget(Static):
    """Widget for displaying a single chat message."""

    def __init__(self, message: ChatMessage):
        self.message = message
        super().__init__(classes=f"chat-message chat-message-{message.role}")

    def compose(self):
        # Create formatted content
        header = Text()
        header.append(self.message.display_role, style=f"bold {self.message.role_color}")
        header.append(" ")
        header.append(self.message.timestamp.strftime("%H:%M"), style="dim")

        yield Static(header, classes="chat-message-header")

        # Message content - render as markdown for assistant messages
        if self.message.role == "assistant":
            try:
                content = Markdown(self.message.content)
            except Exception:
                content = self.message.content
        elif self.message.role == "tool":
            # Tool calls get special formatting
            content = Text()
            status_icon = {
                "pending": "⏳",
                "success": "✓",
                "error": "✗",
            }.get(self.message.tool_status, "•")
            status_color = {
                "pending": "yellow",
                "success": "green",
                "error": "red",
            }.get(self.message.tool_status, "white")

            content.append(f"[{self.message.tool_name}] ", style="bold cyan")
            content.append(status_icon, style=status_color)
            if self.message.content:
                content.append(f" {self.message.content[:100]}", style="dim")
        else:
            content = self.message.content

        yield Static(content, classes="chat-message-content")


class ToolCallWidget(Static):
    """Widget for displaying a tool call inline."""

    def __init__(self, tool_name: str, detail: str = "", status: str = "pending"):
        self.tool_name = tool_name
        self.detail = detail
        self.status = status
        super().__init__(classes="tool-call")
        self._update_display()

    def _update_display(self) -> None:
        """Update the display based on current status."""
        status_icon = {
            "pending": "⏳",
            "success": "✓",
            "error": "✗",
        }.get(self.status, "•")
        status_style = {
            "pending": "yellow",
            "success": "green",
            "error": "red",
        }.get(self.status, "white")

        text = Text()
        text.append(f"  [{self.tool_name}]", style="bold cyan")
        if self.detail:
            text.append(f" {self.detail[:50]}", style="dim")
        text.append(f" {status_icon}", style=status_style)

        self.update(text)

    def set_status(self, status: str) -> None:
        """Update the tool call status."""
        self.status = status
        self._update_display()


class ChatLog(RichLog):
    """Scrollable chat message log."""

    def __init__(
        self,
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(
            highlight=True,
            markup=True,
            name=name,
            id=id,
            classes=classes,
        )
        self._messages: List[ChatMessage] = []

    def add_message(self, message: ChatMessage) -> None:
        """Add a message to the chat log."""
        self._messages.append(message)

        # Format based on role
        if message.role == "user":
            self.write(Text())  # Spacing
            text = Text()
            text.append("You: ", style="bold cyan")
            text.append(message.content)
            self.write(text)

        elif message.role == "assistant":
            self.write(Text())  # Spacing
            text = Text()
            text.append("Agent: ", style="bold green")
            self.write(text)
            # Write content as markdown
            try:
                self.write(Markdown(message.content))
            except Exception:
                self.write(message.content)

        elif message.role == "tool":
            status_icon = {
                "pending": "⏳",
                "success": "✓",
                "error": "✗",
            }.get(message.tool_status, "•")
            status_style = {
                "pending": "yellow",
                "success": "green",
                "error": "red",
            }.get(message.tool_status, "white")

            text = Text()
            text.append(f"  [{message.tool_name}]", style="bold yellow")
            if message.content:
                text.append(f" {message.content[:60]}", style="dim")
            text.append(f" {status_icon}", style=status_style)
            self.write(text)

        elif message.role == "system":
            text = Text()
            text.append(f"[System] {message.content}", style="dim magenta")
            self.write(text)

        self.scroll_end(animate=False)

    def add_streaming_content(self, content: str) -> None:
        """Add streaming content (append to last message)."""
        # For streaming, we write directly
        self.write(content, expand=True)
        self.scroll_end(animate=False)

    def add_tool_call(self, tool_name: str, detail: str = "", status: str = "pending") -> None:
        """Add a tool call indicator."""
        msg = ChatMessage(role="tool", content=detail, tool_name=tool_name, tool_status=status)
        self.add_message(msg)

    def clear_messages(self) -> None:
        """Clear all messages."""
        self._messages.clear()
        self.clear()


class ChatInput(Input):
    """Input field for chat messages."""

    class MessageSubmitted(Message):
        """Message sent when user submits a message."""

        def __init__(self, content: str) -> None:
            self.content = content
            super().__init__()

    def __init__(
        self,
        placeholder: str = "Ask the agent...",
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(
            placeholder=placeholder,
            name=name,
            id=id,
            classes=classes,
        )
        self._history: List[str] = []
        self._history_index: int = -1

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle message submission."""
        content = self.value.strip()
        if content:
            # Add to history
            self._history.append(content)
            self._history_index = len(self._history)

            # Clear input
            self.value = ""

            # Post message
            self.post_message(self.MessageSubmitted(content))

    def action_cursor_up(self) -> None:
        """Navigate to previous history entry."""
        if self._history and self._history_index > 0:
            self._history_index -= 1
            self.value = self._history[self._history_index]

    def action_cursor_down(self) -> None:
        """Navigate to next history entry."""
        if self._history_index < len(self._history) - 1:
            self._history_index += 1
            self.value = self._history[self._history_index]
        elif self._history_index == len(self._history) - 1:
            self._history_index = len(self._history)
            self.value = ""


class ChatPanel(Vertical):
    """Complete chat panel with message log and input."""

    class UserMessage(Message):
        """Message sent when user submits a chat message."""

        def __init__(self, content: str) -> None:
            self.content = content
            super().__init__()

    # Reactive state
    is_processing: reactive[bool] = reactive(False)

    def __init__(
        self,
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(name=name, id=id, classes=classes)
        self._log: Optional[ChatLog] = None
        self._input: Optional[ChatInput] = None

    def compose(self):
        yield Static("CHAT", id="chat-header")

        self._log = ChatLog(id="chat-messages")
        yield self._log

        with Horizontal(id="chat-input-container"):
            self._input = ChatInput(id="chat-input")
            yield self._input

    def on_chat_input_message_submitted(self, event: ChatInput.MessageSubmitted) -> None:
        """Handle user message submission."""
        # Add to log
        if self._log:
            self._log.add_message(ChatMessage(role="user", content=event.content))

        # Forward the message
        self.post_message(self.UserMessage(event.content))

    def add_user_message(self, content: str) -> None:
        """Add a user message to the log."""
        if self._log:
            self._log.add_message(ChatMessage(role="user", content=content))

    def add_assistant_message(self, content: str) -> None:
        """Add an assistant message to the log."""
        if self._log:
            self._log.add_message(ChatMessage(role="assistant", content=content))

    def add_streaming_content(self, content: str) -> None:
        """Add streaming content."""
        if self._log:
            self._log.add_streaming_content(content)

    def add_tool_call(self, tool_name: str, detail: str = "", status: str = "pending") -> None:
        """Add a tool call indicator."""
        if self._log:
            self._log.add_tool_call(tool_name, detail, status)

    def add_system_message(self, content: str) -> None:
        """Add a system message to the log."""
        if self._log:
            self._log.add_message(ChatMessage(role="system", content=content))

    def clear(self) -> None:
        """Clear all messages."""
        if self._log:
            self._log.clear_messages()

    def set_input_enabled(self, enabled: bool) -> None:
        """Enable or disable the input field."""
        if self._input:
            self._input.disabled = not enabled

    def focus_input(self) -> None:
        """Focus the chat input."""
        if self._input:
            self._input.focus()

    def watch_is_processing(self, processing: bool) -> None:
        """React to processing state changes."""
        self.set_input_enabled(not processing)
        if self._input:
            self._input.placeholder = "Processing..." if processing else "Ask the agent..."

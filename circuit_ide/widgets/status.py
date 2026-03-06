"""
Status Widgets for Circuit IDE.

Provides agent status display and status bar.
"""

from typing import Dict, Optional

from rich.text import Text
from textual.containers import Horizontal, Vertical
from textual.reactive import reactive
from textual.widgets import Static


class AgentStatusWidget(Vertical):
    """Widget showing agent status and metrics."""

    # Reactive properties
    model: reactive[str] = reactive("gpt-4o")
    tokens_used: reactive[int] = reactive(0)
    cost_estimate: reactive[float] = reactive(0.0)
    auto_approve: reactive[bool] = reactive(False)
    thinking_mode: reactive[bool] = reactive(False)
    is_thinking: reactive[bool] = reactive(False)
    current_operation: reactive[str] = reactive("")

    def __init__(
        self,
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(name=name, id=id, classes=classes)

    def compose(self):
        yield Static("AGENT", id="agent-panel-header")

        # Model
        yield Horizontal(
            Static("Model:", classes="agent-stat-label"),
            Static(self.model, id="stat-model", classes="agent-stat-value"),
            classes="agent-stat",
        )

        # Tokens
        yield Horizontal(
            Static("Tokens:", classes="agent-stat-label"),
            Static(self._format_tokens(), id="stat-tokens", classes="agent-stat-value"),
            classes="agent-stat",
        )

        # Cost
        yield Horizontal(
            Static("Cost:", classes="agent-stat-label"),
            Static(self._format_cost(), id="stat-cost", classes="agent-stat-value"),
            classes="agent-stat",
        )

        # Auto-approve
        yield Horizontal(
            Static("Auto:", classes="agent-stat-label"),
            Static(
                self._format_bool(self.auto_approve), id="stat-auto", classes="agent-stat-value"
            ),
            classes="agent-stat",
        )

        # Thinking mode
        yield Horizontal(
            Static("Think:", classes="agent-stat-label"),
            Static(
                self._format_bool(self.thinking_mode), id="stat-think", classes="agent-stat-value"
            ),
            classes="agent-stat",
        )

        # Thinking indicator
        yield Static("", id="agent-thinking")

    def _format_tokens(self) -> str:
        """Format token count."""
        if self.tokens_used >= 1000:
            return f"{self.tokens_used / 1000:.1f}k"
        return str(self.tokens_used)

    def _format_cost(self) -> str:
        """Format cost estimate."""
        return f"${self.cost_estimate:.4f}"

    def _format_bool(self, value: bool) -> str:
        """Format boolean as ON/OFF."""
        return "ON" if value else "OFF"

    def watch_model(self, model: str) -> None:
        """Update model display."""
        try:
            self.query_one("#stat-model", Static).update(model)
        except Exception:
            pass

    def watch_tokens_used(self, tokens: int) -> None:
        """Update tokens display."""
        try:
            self.query_one("#stat-tokens", Static).update(self._format_tokens())
        except Exception:
            pass

    def watch_cost_estimate(self, cost: float) -> None:
        """Update cost display."""
        try:
            self.query_one("#stat-cost", Static).update(self._format_cost())
        except Exception:
            pass

    def watch_auto_approve(self, auto: bool) -> None:
        """Update auto-approve display."""
        try:
            widget = self.query_one("#stat-auto", Static)
            text = Text(self._format_bool(auto))
            if auto:
                text.stylize("green")
            widget.update(text)
        except Exception:
            pass

    def watch_thinking_mode(self, thinking: bool) -> None:
        """Update thinking mode display."""
        try:
            widget = self.query_one("#stat-think", Static)
            text = Text(self._format_bool(thinking))
            if thinking:
                text.stylize("yellow")
            widget.update(text)
        except Exception:
            pass

    def watch_is_thinking(self, thinking: bool) -> None:
        """Update thinking indicator."""
        try:
            widget = self.query_one("#agent-thinking", Static)
            if thinking:
                widget.update(Text("🤔 Thinking...", style="yellow italic"))
            else:
                widget.update("")
        except Exception:
            pass

    def watch_current_operation(self, operation: str) -> None:
        """Update current operation display."""
        try:
            widget = self.query_one("#agent-thinking", Static)
            if operation:
                widget.update(Text(f"⚙️ {operation}", style="cyan"))
            elif not self.is_thinking:
                widget.update("")
        except Exception:
            pass

    def update_stats(
        self,
        model: Optional[str] = None,
        tokens: Optional[int] = None,
        cost: Optional[float] = None,
        auto_approve: Optional[bool] = None,
        thinking_mode: Optional[bool] = None,
    ) -> None:
        """Update multiple stats at once."""
        if model is not None:
            self.model = model
        if tokens is not None:
            self.tokens_used = tokens
        if cost is not None:
            self.cost_estimate = cost
        if auto_approve is not None:
            self.auto_approve = auto_approve
        if thinking_mode is not None:
            self.thinking_mode = thinking_mode


class StatusBar(Horizontal):
    """Bottom status bar showing various IDE state."""

    def __init__(
        self,
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(name=name, id=id, classes=classes)
        self._items: Dict[str, str] = {}

    def compose(self):
        yield Static("", id="footer-left")
        yield Static("", id="footer-right")

    def set_left(self, *items: str) -> None:
        """Set left-side status items."""
        text = "  ".join(items)
        try:
            self.query_one("#footer-left", Static).update(text)
        except Exception:
            pass

    def set_right(self, *items: str) -> None:
        """Set right-side status items."""
        text = "  ".join(items)
        try:
            self.query_one("#footer-right", Static).update(text)
        except Exception:
            pass

    def show_message(self, message: str, duration: float = 3.0) -> None:
        """Show a temporary message in the status bar."""
        self.set_left(message)
        # In a full implementation, we'd set a timer to clear this

    def update_keybindings(self) -> None:
        """Update displayed keybindings."""
        bindings = "F1:Help  F2:Files  F3:Editor  F4:Chat  F5:Terminal  F10:Quit"
        self.set_left(bindings)


class HeaderBar(Horizontal):
    """Top header bar with title and status."""

    def __init__(
        self,
        title: str = "Circuit IDE",
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        self._title = title
        super().__init__(name=name, id=id, classes=classes)

    def compose(self):
        yield Static(f" {self._title}", id="header-title")
        yield Static("", id="header-status")

    def set_title(self, title: str) -> None:
        """Update the title."""
        self._title = title
        try:
            self.query_one("#header-title", Static).update(f" {title}")
        except Exception:
            pass

    def set_status(self, status: str) -> None:
        """Update the status text."""
        try:
            self.query_one("#header-status", Static).update(f"{status} ")
        except Exception:
            pass

    def update_token_display(self, tokens: int) -> None:
        """Update token count in header."""
        if tokens >= 1000:
            display = f"📊 {tokens / 1000:.1f}k tokens"
        else:
            display = f"📊 {tokens} tokens"
        self.set_status(display)

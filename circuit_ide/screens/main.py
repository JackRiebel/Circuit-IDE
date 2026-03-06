"""
Main Screen for Circuit IDE.

The primary workspace with file tree, editor, chat, and status panels.
"""

from pathlib import Path
from typing import Optional

from textual import work
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Static

from ..widgets import (
    AgentStatusWidget,
    ChatPanel,
    CodeEditor,
    FileTreeWidget,
    StatusBar,
    TerminalWidget,
)
from ..widgets.editor import EditorPanel
from ..widgets.status import HeaderBar


class MainScreen(Screen):
    """Main IDE workspace screen."""

    CSS_PATH = "../styles/circuit.tcss"

    BINDINGS = [
        Binding("f1", "show_help", "Help"),
        Binding("f2", "focus_files", "Files"),
        Binding("f3", "focus_editor", "Editor"),
        Binding("f4", "focus_chat", "Chat"),
        Binding("f5", "focus_terminal", "Terminal"),
        Binding("f10", "quit", "Quit"),
        Binding("ctrl+b", "toggle_sidebar", "Toggle Sidebar"),
        Binding("ctrl+p", "quick_open", "Quick Open"),
        Binding("ctrl+k", "command_palette", "Commands"),
        Binding("ctrl+s", "save_file", "Save"),
        Binding("ctrl+n", "new_chat", "New Chat"),
    ]

    def __init__(
        self,
        project_dir: str | Path,
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(name=name, id=id, classes=classes)
        self.project_dir = Path(project_dir).resolve()

        # Widget references
        self._header: Optional[HeaderBar] = None
        self._file_tree: Optional[FileTreeWidget] = None
        self._editor_panel: Optional[EditorPanel] = None
        self._chat_panel: Optional[ChatPanel] = None
        self._agent_status: Optional[AgentStatusWidget] = None
        self._terminal: Optional[TerminalWidget] = None
        self._status_bar: Optional[StatusBar] = None

        # State
        self._sidebar_visible: bool = True
        self._terminal_visible: bool = False

    def compose(self):
        """Create the main layout."""
        # Header
        self._header = HeaderBar(f"Circuit IDE - {self.project_dir.name}", id="header")
        yield self._header

        # Main content area
        with Horizontal(id="main-container"):
            # Left sidebar - File tree
            with Vertical(id="sidebar"):
                yield Static("FILES", id="file-tree-header")
                self._file_tree = FileTreeWidget(self.project_dir, id="file-tree")
                yield self._file_tree

            # Right content area
            with Vertical(id="content"):
                # Editor panel (top)
                self._editor_panel = EditorPanel(id="editor-container")
                yield self._editor_panel

                # Bottom panel - Chat and Agent Status
                with Horizontal(id="bottom-panel"):
                    # Agent status (left)
                    self._agent_status = AgentStatusWidget(id="agent-panel")
                    yield self._agent_status

                    # Chat panel (right)
                    self._chat_panel = ChatPanel(id="chat-container")
                    yield self._chat_panel

        # Status bar
        self._status_bar = StatusBar(id="footer")
        yield self._status_bar

    def on_mount(self) -> None:
        """Called when screen is mounted."""
        # Update status bar with keybindings
        if self._status_bar:
            self._status_bar.update_keybindings()

        # Focus chat input by default
        if self._chat_panel:
            self._chat_panel.focus_input()

    # File tree events
    def on_file_tree_widget_file_selected(self, event: FileTreeWidget.FileSelected) -> None:
        """Handle file selection from tree."""
        if self._editor_panel:
            self._editor_panel.load_file(event.path)
            self._editor_panel.editor.focus()

    # Chat events
    def on_chat_panel_user_message(self, event: ChatPanel.UserMessage) -> None:
        """Handle user message from chat."""
        # This will be connected to the agent
        self.process_user_message(event.content)

    @work(exclusive=True)
    async def process_user_message(self, message: str) -> None:
        """Process a user message through the agent."""
        if self._chat_panel:
            self._chat_panel.is_processing = True

        if self._agent_status:
            self._agent_status.is_thinking = True

        try:
            # Get agent from app
            agent = self.app.agent if hasattr(self.app, "agent") else None

            if agent:
                await self._run_agent_chat(agent, message)
            else:
                # No agent - show placeholder response
                await self._simulate_agent_response(message)
        except Exception as e:
            if self._chat_panel:
                self._chat_panel.add_system_message(f"Error: {e}")
        finally:
            if self._chat_panel:
                self._chat_panel.is_processing = False

            if self._agent_status:
                self._agent_status.is_thinking = False

    async def _run_agent_chat(self, agent, message: str) -> None:
        """Run actual agent chat."""
        # Track current tool for status updates

        def on_content(chunk: str):
            """Handle streaming content."""
            if self._chat_panel:
                self._chat_panel.add_streaming_content(chunk)

        try:
            # Call the agent
            await agent.chat(message, on_content=on_content)

            # Update stats after response
            if self._agent_status:
                stats = agent.get_token_stats()
                cost_stats = agent.get_cost_stats()

                self._agent_status.update_stats(
                    tokens=stats["session_total"],
                    cost=cost_stats.get("total_cost", 0),
                )

            # Refresh file tree in case files were modified
            if self._file_tree:
                self._file_tree.action_refresh()

        except Exception as e:
            if self._chat_panel:
                self._chat_panel.add_system_message(f"Agent error: {e}")

    async def _simulate_agent_response(self, message: str) -> None:
        """Simulate an agent response (placeholder)."""
        import asyncio

        # Show "thinking"
        await asyncio.sleep(0.5)

        if self._chat_panel:
            # Simulate tool call
            self._chat_panel.add_tool_call("read_file", "src/main.py", "success")
            await asyncio.sleep(0.3)

            # Add response
            response = f"I received your message: '{message[:50]}...'\n\n"
            response += "**Note:** Agent not connected. Please configure credentials.\n\n"
            response += "To connect the agent:\n"
            response += "1. Run `circuit-agent` first to configure credentials\n"
            response += "2. Restart Circuit IDE\n"
            self._chat_panel.add_assistant_message(response)

    # Editor events
    def on_code_editor_file_saved(self, event: CodeEditor.FileSaved) -> None:
        """Handle file save event."""
        if self._status_bar:
            self._status_bar.show_message(f"Saved: {event.path.name}")

    # Actions
    def action_focus_files(self) -> None:
        """Focus the file tree."""
        if self._file_tree:
            self._file_tree.focus()

    def action_focus_editor(self) -> None:
        """Focus the editor."""
        if self._editor_panel and self._editor_panel.editor:
            self._editor_panel.editor.focus()

    def action_focus_chat(self) -> None:
        """Focus the chat input."""
        if self._chat_panel:
            self._chat_panel.focus_input()

    def action_focus_terminal(self) -> None:
        """Focus the terminal."""
        if self._terminal:
            self._terminal.focus_input()

    def action_toggle_sidebar(self) -> None:
        """Toggle the sidebar visibility."""
        self._sidebar_visible = not self._sidebar_visible
        sidebar = self.query_one("#sidebar", Vertical)
        sidebar.display = self._sidebar_visible

    def action_save_file(self) -> None:
        """Save the current file."""
        if self._editor_panel and self._editor_panel.editor:
            self._editor_panel.editor.save_file()

    def action_new_chat(self) -> None:
        """Start a new chat session."""
        if self._chat_panel:
            self._chat_panel.clear()
            self._chat_panel.add_system_message("New conversation started")
            self._chat_panel.focus_input()

    def action_quick_open(self) -> None:
        """Open quick file search."""
        # Placeholder - would open a command palette
        self.notify("Quick open coming soon...")

    def action_command_palette(self) -> None:
        """Open command palette."""
        # Placeholder - would open a command palette
        self.notify("Command palette coming soon...")

    def action_show_help(self) -> None:
        """Show help screen."""
        self.notify("Help: F1-Help F2-Files F3-Editor F4-Chat F10-Quit")

    def action_quit(self) -> None:
        """Quit the application."""
        self.app.exit()

    # Public methods for agent integration
    def update_agent_status(
        self,
        model: Optional[str] = None,
        tokens: Optional[int] = None,
        cost: Optional[float] = None,
        auto_approve: Optional[bool] = None,
        thinking_mode: Optional[bool] = None,
    ) -> None:
        """Update agent status display."""
        if self._agent_status:
            self._agent_status.update_stats(
                model=model,
                tokens=tokens,
                cost=cost,
                auto_approve=auto_approve,
                thinking_mode=thinking_mode,
            )

    def add_chat_message(self, role: str, content: str) -> None:
        """Add a message to the chat panel."""
        if self._chat_panel:
            if role == "user":
                self._chat_panel.add_user_message(content)
            elif role == "assistant":
                self._chat_panel.add_assistant_message(content)
            elif role == "system":
                self._chat_panel.add_system_message(content)

    def add_tool_call(self, tool_name: str, detail: str = "", status: str = "pending") -> None:
        """Add a tool call indicator to the chat."""
        if self._chat_panel:
            self._chat_panel.add_tool_call(tool_name, detail, status)

    def open_file(self, path: Path) -> None:
        """Open a file in the editor."""
        if self._editor_panel:
            self._editor_panel.load_file(path)

    def refresh_file_tree(self) -> None:
        """Refresh the file tree."""
        if self._file_tree:
            self._file_tree.action_refresh()

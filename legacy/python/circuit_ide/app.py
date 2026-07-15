"""
Circuit IDE Application.

Main Textual application for the AI-powered Terminal IDE.
Now uses the unified service layer for cleaner architecture.
"""

import sys
from pathlib import Path
from typing import Optional

from textual import work
from textual.app import App
from textual.binding import Binding

from .screens import MainScreen

# Add parent directory to path for imports
_parent = Path(__file__).parent.parent
if str(_parent) not in sys.path:
    sys.path.insert(0, str(_parent))


class CircuitIDE(App):
    """Circuit IDE - AI-powered Terminal IDE."""

    TITLE = "Circuit IDE"
    SUB_TITLE = "AI-Powered Coding Assistant"

    CSS_PATH = "styles/circuit.tcss"

    BINDINGS = [
        Binding("ctrl+q", "quit", "Quit", show=False),
        Binding("ctrl+c", "quit", "Quit", show=False),
    ]

    def __init__(self, project_dir: str | Path = ".", theme: str = "dark", **kwargs):
        """Initialize Circuit IDE.

        Args:
            project_dir: Project directory to open
            theme: Color theme (dark/light)
            **kwargs: Additional arguments for App
        """
        super().__init__(**kwargs)
        self.project_dir = Path(project_dir).resolve()
        self.theme_name = theme

        # Service layer instance
        self._service = None

        # Screen reference
        self._main_screen: Optional[MainScreen] = None

    def on_mount(self) -> None:
        """Called when app is mounted."""
        # Push the main screen
        self._main_screen = MainScreen(self.project_dir)
        self.push_screen(self._main_screen)

        # Try to connect using service layer
        self._try_init_service()

    @work(exclusive=True)
    async def _try_init_service(self) -> None:
        """Try to initialize and connect the Agent Service."""
        try:
            from circuit_agent.service import AgentService, EventType

            # Create service instance
            self._service = AgentService(
                working_dir=str(self.project_dir),
                model="gpt-4o",
                auto_approve=False,
            )

            # Subscribe to events for UI updates
            self._service.on(EventType.MESSAGE_CHUNK, self._on_message_chunk)
            self._service.on(EventType.TOOL_CALL_STARTED, self._on_tool_started)
            self._service.on(EventType.TOOL_CALL_COMPLETED, self._on_tool_completed)
            self._service.on(EventType.TOOL_CALL_ERROR, self._on_tool_error)
            self._service.on(EventType.TOKENS_UPDATED, self._on_tokens_updated)
            self._service.on(EventType.CONFIRMATION_NEEDED, self._on_confirmation_needed)

            # Try to connect with saved credentials
            connected = await self._service.connect_with_saved_credentials()

            if connected:
                # Update status
                if self._main_screen:
                    self._main_screen.update_agent_status(
                        model=self._service.state.model,
                        auto_approve=self._service.state.auto_approve,
                        thinking_mode=self._service.state.thinking_mode,
                    )
                self.notify("Agent connected", severity="information")
            else:
                self.notify(
                    "Agent credentials not found. Run circuit_agent first to configure.",
                    severity="warning",
                )

        except ImportError as e:
            self.notify(f"Could not load agent: {e}", severity="warning")
        except Exception as e:
            self.notify(f"Agent initialization failed: {e}", severity="error")

    @property
    def service(self):
        """Get the Agent Service instance."""
        return self._service

    # =========================================================================
    # Event Handlers
    # =========================================================================

    def _on_message_chunk(self, event) -> None:
        """Handle streaming message chunk."""
        chunk = event.data.get("chunk", "")
        if self._main_screen and chunk:
            self._main_screen._chat_panel.add_streaming_content(chunk)

    def _on_tool_started(self, event) -> None:
        """Handle tool call started event."""
        tool_call = event.data.get("tool_call")
        if self._main_screen and tool_call:
            self._main_screen._chat_panel.add_tool_call(tool_call.name, tool_call.detail, "pending")

    def _on_tool_completed(self, event) -> None:
        """Handle tool call completed event."""
        tool_call = event.data.get("tool_call")
        if self._main_screen and tool_call:
            self._main_screen._chat_panel.add_tool_call(tool_call.name, tool_call.detail, "success")

    def _on_tool_error(self, event) -> None:
        """Handle tool call error event."""
        tool_call = event.data.get("tool_call")
        error = event.data.get("error", "")
        if self._main_screen and tool_call:
            self._main_screen._chat_panel.add_tool_call(tool_call.name, error[:50], "error")

    def _on_tokens_updated(self, event) -> None:
        """Handle token update event."""
        if self._main_screen:
            total = event.data.get("session_total", 0)
            # Rough cost estimate
            cost = total * 0.00001
            self._main_screen.update_agent_status(
                tokens=total,
                cost=cost,
            )

    def _on_confirmation_needed(self, event) -> None:
        """Handle confirmation request."""
        request = event.data.get("request")
        if request:
            # For TUI, we can show a confirmation dialog
            # For now, auto-reject if auto_approve is off
            # TODO: Implement proper confirmation dialog
            if self._service and self._service.state.auto_approve:
                self._service.approve_confirmation(request.id)
            else:
                # Auto-reject for now - proper TUI dialog would be better
                self._service.reject_confirmation(request.id)
                self.notify(
                    f"Tool '{request.tool_call.name}' requires confirmation", severity="warning"
                )

    # =========================================================================
    # Message Handling
    # =========================================================================

    @work(exclusive=True)
    async def send_message(self, message: str) -> None:
        """Send a message to the agent and stream the response."""
        if not self._service or not self._service.is_connected:
            if self._main_screen:
                self._main_screen.add_chat_message(
                    "system", "Agent not connected. Please configure credentials first."
                )
            return

        if self._main_screen:
            self._main_screen._chat_panel.is_processing = True
            self._main_screen._agent_status.is_thinking = True

        try:
            # Send message through service
            await self._service.send_message(message)

            # Update stats from service
            if self._main_screen and self._service:
                stats = self._service.get_token_stats()
                costs = self._service.get_cost_stats()

                self._main_screen.update_agent_status(
                    tokens=stats.get("session_total", 0),
                    cost=costs.get("total_cost_usd", 0),
                )

        except Exception as e:
            if self._main_screen:
                self._main_screen.add_chat_message("system", f"Error: {e}")
        finally:
            if self._main_screen:
                self._main_screen._chat_panel.is_processing = False
                self._main_screen._agent_status.is_thinking = False

    def action_quit(self) -> None:
        """Quit the application."""
        self.exit()


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        prog="circuit-ide", description="Circuit IDE - AI-powered Terminal IDE"
    )
    parser.add_argument("directory", nargs="?", default=".", help="Project directory to open")
    parser.add_argument("--theme", choices=["dark", "light"], default="dark", help="Color theme")

    args = parser.parse_args()

    # Resolve directory
    project_dir = Path(args.directory).resolve()
    if not project_dir.is_dir():
        print(f"Error: '{args.directory}' is not a valid directory")
        sys.exit(1)

    # Run the app
    app = CircuitIDE(project_dir=project_dir, theme=args.theme)
    app.run()


if __name__ == "__main__":
    main()

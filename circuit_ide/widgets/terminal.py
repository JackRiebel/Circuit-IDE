"""
Terminal Widget for Circuit IDE.

Provides embedded terminal functionality for command output.
"""

import asyncio
from typing import List, Optional

from rich.text import Text
from textual import work
from textual.containers import Vertical
from textual.message import Message
from textual.reactive import reactive
from textual.widgets import Input, RichLog, Static


class TerminalOutput(RichLog):
    """Widget for displaying terminal output."""

    def __init__(
        self,
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(
            highlight=True,
            markup=True,
            wrap=True,
            name=name,
            id=id,
            classes=classes,
        )
        self._command_history: List[str] = []

    def write_command(self, command: str) -> None:
        """Write a command to the terminal."""
        text = Text()
        text.append("$ ", style="bold green")
        text.append(command, style="bold")
        self.write(text)
        self._command_history.append(command)

    def write_output(self, output: str, is_error: bool = False) -> None:
        """Write command output."""
        style = "red" if is_error else ""
        for line in output.split("\n"):
            if line:
                text = Text(line, style=style)
                self.write(text)

    def write_status(self, status: str, success: bool = True) -> None:
        """Write a status message."""
        icon = "✓" if success else "✗"
        color = "green" if success else "red"
        text = Text()
        text.append(f"{icon} ", style=color)
        text.append(status, style="dim")
        self.write(text)


class TerminalWidget(Vertical):
    """Complete terminal widget with input and output."""

    class CommandSubmitted(Message):
        """Message sent when a command is submitted."""

        def __init__(self, command: str) -> None:
            self.command = command
            super().__init__()

    class CommandCompleted(Message):
        """Message sent when a command completes."""

        def __init__(self, command: str, return_code: int, stdout: str, stderr: str) -> None:
            self.command = command
            self.return_code = return_code
            self.stdout = stdout
            self.stderr = stderr
            super().__init__()

    # Reactive state
    working_directory: reactive[str] = reactive(".")
    is_running: reactive[bool] = reactive(False)

    def __init__(
        self,
        working_dir: str = ".",
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(name=name, id=id, classes=classes)
        self.working_directory = working_dir
        self._output: Optional[TerminalOutput] = None
        self._input: Optional[Input] = None
        self._history: List[str] = []
        self._history_index: int = 0

    def compose(self):
        yield Static("TERMINAL", classes="panel-header")

        self._output = TerminalOutput(id="terminal-output")
        yield self._output

        self._input = Input(placeholder="Enter command...", id="terminal-input")
        yield self._input

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Handle command submission."""
        command = event.value.strip()
        if command:
            self._history.append(command)
            self._history_index = len(self._history)

            # Clear input
            if self._input:
                self._input.value = ""

            # Execute command
            self.run_command(command)

    @work(exclusive=True)
    async def run_command(self, command: str) -> None:
        """Run a command asynchronously."""
        self.is_running = True

        if self._output:
            self._output.write_command(command)

        try:
            # Handle cd specially
            if command.startswith("cd "):
                path = command[3:].strip()
                import os

                try:
                    new_path = os.path.abspath(os.path.join(self.working_directory, path))
                    if os.path.isdir(new_path):
                        self.working_directory = new_path
                        if self._output:
                            self._output.write_status(f"Changed to {new_path}")
                    else:
                        if self._output:
                            self._output.write_output(
                                f"cd: no such directory: {path}", is_error=True
                            )
                except Exception as e:
                    if self._output:
                        self._output.write_output(str(e), is_error=True)
            else:
                # Run in subprocess
                process = await asyncio.create_subprocess_shell(
                    command,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    cwd=self.working_directory,
                )

                stdout, stderr = await process.communicate()

                stdout_text = stdout.decode("utf-8", errors="replace")
                stderr_text = stderr.decode("utf-8", errors="replace")

                if self._output:
                    if stdout_text:
                        self._output.write_output(stdout_text)
                    if stderr_text:
                        self._output.write_output(stderr_text, is_error=True)

                    if process.returncode == 0:
                        self._output.write_status("Command completed")
                    else:
                        self._output.write_status(f"Exit code: {process.returncode}", success=False)

                # Post completion message
                self.post_message(
                    self.CommandCompleted(
                        command=command,
                        return_code=process.returncode or 0,
                        stdout=stdout_text,
                        stderr=stderr_text,
                    )
                )

        except Exception as e:
            if self._output:
                self._output.write_output(f"Error: {e}", is_error=True)
                self._output.write_status("Command failed", success=False)

        finally:
            self.is_running = False

    def run_agent_command(self, command: str, show_output: bool = True) -> None:
        """Run a command initiated by the agent."""
        if show_output and self._output:
            text = Text()
            text.append("[Agent] ", style="bold cyan")
            text.append("$ ", style="bold green")
            text.append(command, style="bold")
            self._output.write(text)

        self.run_command(command)

    def write_agent_output(self, output: str, is_error: bool = False) -> None:
        """Write output from agent-initiated commands."""
        if self._output:
            self._output.write_output(output, is_error)

    def clear(self) -> None:
        """Clear the terminal output."""
        if self._output:
            self._output.clear()

    def focus_input(self) -> None:
        """Focus the terminal input."""
        if self._input:
            self._input.focus()

    def watch_is_running(self, running: bool) -> None:
        """React to running state changes."""
        if self._input:
            self._input.disabled = running
            self._input.placeholder = "Running..." if running else "Enter command..."

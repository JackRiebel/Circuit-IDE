"""
UI utilities for Circuit Agent - colors, terminal helpers, display functions.
"""

import os
import re
import sys
import difflib
from typing import Optional


class Colors:
    """ANSI color codes for terminal output."""
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    MAGENTA = "\033[95m"
    BLUE = "\033[94m"
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"


# Shorthand alias
C = Colors


def clear_screen():
    """Clear the terminal screen."""
    os.system('cls' if os.name == 'nt' else 'clear')


def clear_line():
    """Clear the current line in terminal."""
    print("\r" + " " * 80 + "\r", end="", flush=True)


def print_header(working_dir: str):
    """Print the application header."""
    print(f"""
{C.CYAN}╔══════════════════════════════════════════════════════════╗
║               Circuit Agent v4.0                          ║
║         AI-Powered Coding Assistant                       ║
╚══════════════════════════════════════════════════════════╝{C.RESET}

{C.BOLD}Working Directory:{C.RESET} {C.GREEN}{working_dir}{C.RESET}
""")


def print_welcome():
    """Print the welcome message with available commands."""
    print(f"""
{C.CYAN}{'─' * 60}{C.RESET}
{C.BOLD}Circuit Agent v4.0 Ready!{C.RESET}

{C.DIM}Commands:{C.RESET}  /help /save /load /cost /audit /think /auto /quit

{C.DIM}Tools:{C.RESET}  File ops, search, commands, git, web search & fetch

{C.GREEN}New in v4.0:{C.RESET}
  - Parallel tool execution for faster multi-file operations
  - Secret detection warns before committing sensitive data
  - Cost tracking with /cost command
  - Audit logging with /audit command

{C.DIM}Tips:{C.RESET}
  - Type 'a' during confirmation to auto-approve all actions
  - Create CIRCUIT.md for project-specific instructions
  - Use /think on to see agent's reasoning process
{C.CYAN}{'─' * 60}{C.RESET}
""")


def print_help():
    """Print detailed help information."""
    print(f"""
{C.BOLD}Commands:{C.RESET}
  /help, /h    - Show this help
  /files       - List files in working directory
  /clear, /c   - Clear conversation history
  /history     - Show recent conversation
  /model       - Change model
  /tokens      - Show token usage for session
  /undo [file] - Restore file from backup
  /config      - Show current configuration
  /git         - Quick git status
  /auto        - Toggle auto-approve mode
  /stream      - Toggle response streaming
  /logout      - Delete saved credentials
  /quit, /q    - Exit

{C.BOLD}Session Management:{C.RESET}
  /save [name] - Save current session
  /load [name] - Load a saved session (shows list if no name)
  /sessions    - List all saved sessions
  /compact     - Compress old messages to save tokens

{C.BOLD}v4.0 Features:{C.RESET}
  /cost        - Show estimated API costs for session
  /audit       - Show audit log statistics
  /audit recent - Show recent audit entries
  /think [on|off] - Toggle thinking mode (shows agent reasoning)

{C.BOLD}During Confirmations:{C.RESET}
  y            - Yes, allow this action
  n            - No, cancel this action
  a            - Allow this and all future actions (auto-approve)

{C.BOLD}Security Features (v4.0):{C.RESET}
  - Secret detection warns before writing files with API keys, passwords, etc.
  - Audit logging tracks all tool calls and API usage
  - Cost tracking helps monitor API expenses

{C.BOLD}Tips:{C.RESET}
  - Ask the agent to explore the codebase first
  - Be specific about what you want to change
  - Use /auto to skip confirmations (use with caution!)
  - Use web_search to look up error messages
  - Create a CIRCUIT.md file for project-specific instructions
  - Use /think on to understand agent's reasoning

{C.BOLD}Configuration:{C.RESET}
  Config:     ~/.config/circuit-agent/config.json
  Sessions:   ~/.config/circuit-agent/sessions/
  Audit logs: ~/.config/circuit-agent/audit/
  Global:     ~/.config/circuit-agent/CIRCUIT.md
  Project:    ./CIRCUIT.md (auto-loaded)
""")


def print_token_usage(prompt_tokens: int, completion_tokens: int,
                      session_prompt: int, session_completion: int):
    """Print token usage statistics."""
    total = prompt_tokens + completion_tokens
    session_total = session_prompt + session_completion
    print(f"\n{C.DIM}Tokens: {prompt_tokens:,} in / {completion_tokens:,} out ({total:,}) | "
          f"Session: {session_total:,} total{C.RESET}")


def show_diff(old_text: str, new_text: str, path: str, max_lines: int = 30) -> None:
    """Display a unified diff with colors."""
    old_lines = old_text.splitlines(keepends=True)
    new_lines = new_text.splitlines(keepends=True)

    # Ensure lines end with newline for proper diff display
    if old_lines and not old_lines[-1].endswith('\n'):
        old_lines[-1] += '\n'
    if new_lines and not new_lines[-1].endswith('\n'):
        new_lines[-1] += '\n'

    diff = list(difflib.unified_diff(
        old_lines, new_lines,
        fromfile=f"a/{path}",
        tofile=f"b/{path}",
        lineterm=''
    ))

    if not diff:
        print(f"{C.DIM}(no visible changes){C.RESET}")
        return

    for line in diff[:max_lines]:
        line = line.rstrip('\n')
        if line.startswith('+++') or line.startswith('---'):
            print(f"{C.BOLD}{line}{C.RESET}")
        elif line.startswith('+'):
            print(f"{C.GREEN}{line}{C.RESET}")
        elif line.startswith('-'):
            print(f"{C.RED}{line}{C.RESET}")
        elif line.startswith('@@'):
            print(f"{C.CYAN}{line}{C.RESET}")
        else:
            print(line)

    if len(diff) > max_lines:
        print(f"{C.DIM}... ({len(diff) - max_lines} more lines){C.RESET}")


def print_tool_call(tool_name: str, detail: str = ""):
    """Print a tool call indicator."""
    if detail:
        # Truncate long details
        if len(detail) > 60:
            detail = detail[:57] + "..."
        print(f"{C.DIM}  [{tool_name}] {detail}{C.RESET}")
    else:
        print(f"{C.DIM}  [{tool_name}]{C.RESET}")


def print_error(message: str):
    """Print an error message."""
    print(f"  {C.RED}Error: {message}{C.RESET}")


def print_success(message: str):
    """Print a success message."""
    print(f"  {C.GREEN}{message}{C.RESET}")


def print_warning(message: str):
    """Print a warning message."""
    print(f"  {C.YELLOW}{message}{C.RESET}")


def print_info(message: str):
    """Print an info message."""
    print(f"  {C.DIM}{message}{C.RESET}")


def confirm(prompt: str, default: bool = False) -> bool:
    """Ask for user confirmation."""
    suffix = "[Y/n]" if default else "[y/N]"
    response = input(f"\n{C.CYAN}{prompt} {suffix}:{C.RESET} ").strip().lower()

    if not response:
        return default
    return response in ('y', 'yes')


def spinner_frame(frame: int) -> str:
    """Get a spinner frame for progress indication."""
    frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
    return frames[frame % len(frames)]


class StreamingMarkdownRenderer:
    """Renders streamed markdown with syntax-highlighted code blocks for the terminal."""

    def __init__(self):
        self._buffer = ""
        self._in_code_block = False
        self._code_lang = ""
        self._code_lines: list[str] = []

    def feed(self, chunk: str):
        """Process a chunk of streamed text."""
        self._buffer += chunk

        while '\n' in self._buffer:
            line, self._buffer = self._buffer.split('\n', 1)
            self._process_line(line)

    def flush(self):
        """Flush any remaining buffered content."""
        if self._buffer:
            if self._in_code_block:
                self._code_lines.append(self._buffer)
            else:
                print(self._format_inline(self._buffer), end="", flush=True)
            self._buffer = ""

        if self._in_code_block:
            self._render_code_block()
            self._in_code_block = False

    def _process_line(self, line: str):
        stripped = line.strip()

        if stripped.startswith('```'):
            if self._in_code_block:
                self._render_code_block()
                self._in_code_block = False
            else:
                self._in_code_block = True
                self._code_lang = stripped[3:].strip()
                self._code_lines = []
            return

        if self._in_code_block:
            self._code_lines.append(line)
        else:
            print(self._format_line(line), flush=True)

    def _format_line(self, line: str) -> str:
        stripped = line.strip()

        if stripped.startswith('### '):
            return f"{C.BOLD}{C.CYAN}{stripped[4:]}{C.RESET}"
        if stripped.startswith('## '):
            return f"{C.BOLD}{C.CYAN}{stripped[3:]}{C.RESET}"
        if stripped.startswith('# '):
            return f"{C.BOLD}{C.CYAN}{stripped[2:]}{C.RESET}"

        if stripped.startswith('- ') or stripped.startswith('* '):
            indent = len(line) - len(line.lstrip())
            content = self._format_inline(stripped[2:])
            return f"{' ' * indent}{C.CYAN}•{C.RESET} {content}"

        match = re.match(r'^(\s*)(\d+)\.\s+(.+)', line)
        if match:
            return f"{match.group(1)}{C.CYAN}{match.group(2)}.{C.RESET} {self._format_inline(match.group(3))}"

        if stripped.startswith('> '):
            return f"{C.DIM}│ {self._format_inline(stripped[2:])}{C.RESET}"

        if stripped in ('---', '***', '___'):
            return f"{C.DIM}{'─' * 50}{C.RESET}"

        return self._format_inline(line)

    def _format_inline(self, text: str) -> str:
        text = re.sub(r'`([^`]+)`', f'{C.YELLOW}\\1{C.RESET}', text)
        text = re.sub(r'\*\*(.+?)\*\*', f'{C.BOLD}\\1{C.RESET}', text)
        text = re.sub(r'(?<!\*)\*([^*]+)\*(?!\*)', f'\033[3m\\1{C.RESET}', text)
        return text

    def _render_code_block(self):
        code = '\n'.join(self._code_lines)
        highlighted = self._highlight_code(code, self._code_lang)

        lang_label = f" {self._code_lang} " if self._code_lang else ""
        border_len = max(50, 4 + len(lang_label))
        print(f"{C.DIM}┌─{lang_label}{'─' * (border_len - 2 - len(lang_label))}┐{C.RESET}")
        for hl_line in highlighted.splitlines():
            print(f"{C.DIM}│{C.RESET} {hl_line}")
        print(f"{C.DIM}└{'─' * border_len}┘{C.RESET}")

    def _highlight_code(self, code: str, lang: str) -> str:
        try:
            from pygments import highlight
            from pygments.lexers import get_lexer_by_name, guess_lexer
            from pygments.formatters import Terminal256Formatter

            if lang:
                try:
                    lexer = get_lexer_by_name(lang)
                except Exception:
                    lexer = guess_lexer(code)
            else:
                try:
                    lexer = guess_lexer(code)
                except Exception:
                    return code

            return highlight(code, lexer, Terminal256Formatter(style='monokai')).rstrip()
        except Exception:
            return code


def render_markdown(text: str) -> str:
    """Render a complete markdown string for terminal display."""
    renderer = StreamingMarkdownRenderer()
    import io
    from contextlib import redirect_stdout

    buf = io.StringIO()
    with redirect_stdout(buf):
        renderer.feed(text + '\n')
        renderer.flush()
    return buf.getvalue().rstrip('\n')

"""
Keybinding definitions for Circuit IDE.
"""

from typing import Dict, Tuple

# Default keybindings: action -> (key, description)
KEYBINDINGS: Dict[str, Tuple[str, str]] = {
    # Navigation
    "focus_files": ("f2", "Focus file tree"),
    "focus_editor": ("f3", "Focus editor"),
    "focus_chat": ("f4", "Focus chat"),
    "focus_terminal": ("f5", "Focus terminal"),
    # Panels
    "toggle_sidebar": ("ctrl+b", "Toggle sidebar"),
    "toggle_terminal": ("ctrl+`", "Toggle terminal"),
    # Commands
    "command_palette": ("ctrl+k", "Command palette"),
    "quick_open": ("ctrl+p", "Quick open file"),
    # Editor
    "save_file": ("ctrl+s", "Save file"),
    "goto_line": ("ctrl+g", "Go to line"),
    "find": ("ctrl+f", "Find in file"),
    "find_all": ("ctrl+shift+f", "Find in all files"),
    # Agent
    "new_chat": ("ctrl+n", "New chat"),
    "stop_agent": ("ctrl+c", "Stop agent"),
    "toggle_auto_approve": ("ctrl+a", "Toggle auto-approve"),
    "toggle_thinking": ("ctrl+t", "Toggle thinking mode"),
    # Session
    "save_session": ("ctrl+shift+s", "Save session"),
    "load_session": ("ctrl+shift+l", "Load session"),
    # Help
    "show_help": ("f1", "Show help"),
    "quit": ("f10", "Quit"),
}


def get_binding_description(action: str) -> str:
    """Get the description for a keybinding action."""
    if action in KEYBINDINGS:
        return KEYBINDINGS[action][1]
    return ""


def get_binding_key(action: str) -> str:
    """Get the key for a keybinding action."""
    if action in KEYBINDINGS:
        return KEYBINDINGS[action][0]
    return ""


def format_keybindings_help() -> str:
    """Format all keybindings as help text."""
    lines = ["Keyboard Shortcuts", "=" * 40, ""]

    categories = {
        "Navigation": ["focus_files", "focus_editor", "focus_chat", "focus_terminal"],
        "Panels": ["toggle_sidebar", "toggle_terminal"],
        "Commands": ["command_palette", "quick_open"],
        "Editor": ["save_file", "goto_line", "find", "find_all"],
        "Agent": ["new_chat", "stop_agent", "toggle_auto_approve", "toggle_thinking"],
        "Session": ["save_session", "load_session"],
        "Help": ["show_help", "quit"],
    }

    for category, actions in categories.items():
        lines.append(f"\n{category}")
        lines.append("-" * len(category))
        for action in actions:
            if action in KEYBINDINGS:
                key, desc = KEYBINDINGS[action]
                lines.append(f"  {key:<15} {desc}")

    return "\n".join(lines)

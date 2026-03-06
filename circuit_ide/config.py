"""
Configuration for Circuit IDE.
"""

import json
from pathlib import Path
from typing import Any, Dict

# Default configuration
DEFAULT_CONFIG = {
    "theme": "dark",
    "editor": {
        "tab_size": 4,
        "show_line_numbers": True,
        "word_wrap": False,
        "highlight_current_line": True,
    },
    "file_tree": {
        "show_hidden": False,
        "ignored_patterns": [
            "__pycache__",
            "*.pyc",
            ".git",
            "node_modules",
            ".venv",
            "venv",
            ".tox",
            "dist",
            "build",
            ".next",
            ".cache",
            "*.egg-info",
        ],
    },
    "chat": {
        "show_timestamps": True,
        "show_token_count": True,
    },
    "agent": {
        "model": "gpt-4o",
        "auto_approve": False,
        "thinking_mode": False,
        "stream_responses": True,
    },
    "keybindings": {
        "focus_files": "f2",
        "focus_editor": "f3",
        "focus_chat": "f4",
        "focus_terminal": "f5",
        "command_palette": "ctrl+k",
        "quick_open": "ctrl+p",
        "toggle_file_tree": "ctrl+b",
        "toggle_terminal": "ctrl+`",
        "new_chat": "ctrl+n",
        "save_session": "ctrl+s",
    },
}

# Config directory
CONFIG_DIR = Path.home() / ".config" / "circuit-ide"
CONFIG_FILE = CONFIG_DIR / "config.json"


class IDEConfig:
    """Manage IDE configuration."""

    def __init__(self):
        self._config = DEFAULT_CONFIG.copy()
        self._load()

    def _load(self):
        """Load configuration from file."""
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, "r") as f:
                    user_config = json.load(f)
                self._merge(user_config)
            except (json.JSONDecodeError, IOError):
                pass

    def _merge(self, user_config: Dict[str, Any]):
        """Merge user config with defaults."""

        def deep_merge(base: dict, override: dict) -> dict:
            result = base.copy()
            for key, value in override.items():
                if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                    result[key] = deep_merge(result[key], value)
                else:
                    result[key] = value
            return result

        self._config = deep_merge(self._config, user_config)

    def save(self):
        """Save configuration to file."""
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(self._config, f, indent=2)

    def get(self, key: str, default: Any = None) -> Any:
        """Get a config value by dot-notation key (e.g., 'editor.tab_size')."""
        keys = key.split(".")
        value = self._config
        for k in keys:
            if isinstance(value, dict) and k in value:
                value = value[k]
            else:
                return default
        return value

    def set(self, key: str, value: Any):
        """Set a config value by dot-notation key."""
        keys = key.split(".")
        target = self._config
        for k in keys[:-1]:
            if k not in target:
                target[k] = {}
            target = target[k]
        target[keys[-1]] = value

    @property
    def theme(self) -> str:
        return self._config.get("theme", "dark")

    @property
    def editor(self) -> Dict[str, Any]:
        return self._config.get("editor", {})

    @property
    def file_tree(self) -> Dict[str, Any]:
        return self._config.get("file_tree", {})

    @property
    def chat(self) -> Dict[str, Any]:
        return self._config.get("chat", {})

    @property
    def agent(self) -> Dict[str, Any]:
        return self._config.get("agent", {})

    @property
    def keybindings(self) -> Dict[str, str]:
        return self._config.get("keybindings", {})


# Global config instance
config = IDEConfig()

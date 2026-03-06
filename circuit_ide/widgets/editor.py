"""
Code Editor Widget for Circuit IDE.

Provides syntax-highlighted code editing with line numbers.
"""

from pathlib import Path
from typing import Optional

from textual import events
from textual.containers import Horizontal, Vertical
from textual.message import Message
from textual.reactive import reactive
from textual.widgets import Static, TextArea

# Try to import pygments for syntax highlighting
try:
    import importlib.util

    PYGMENTS_AVAILABLE = importlib.util.find_spec("pygments") is not None
except Exception:
    PYGMENTS_AVAILABLE = False


# Language detection by extension
LANGUAGE_MAP = {
    ".py": "python",
    ".js": "javascript",
    ".ts": "typescript",
    ".jsx": "jsx",
    ".tsx": "tsx",
    ".go": "go",
    ".rs": "rust",
    ".rb": "ruby",
    ".java": "java",
    ".c": "c",
    ".cpp": "cpp",
    ".h": "c",
    ".hpp": "cpp",
    ".cs": "csharp",
    ".php": "php",
    ".swift": "swift",
    ".kt": "kotlin",
    ".html": "html",
    ".css": "css",
    ".scss": "scss",
    ".sass": "sass",
    ".less": "less",
    ".vue": "vue",
    ".svelte": "svelte",
    ".json": "json",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".xml": "xml",
    ".sql": "sql",
    ".md": "markdown",
    ".sh": "bash",
    ".bash": "bash",
    ".zsh": "zsh",
    ".fish": "fish",
    ".ps1": "powershell",
    ".dockerfile": "dockerfile",
    "Dockerfile": "dockerfile",
    "Makefile": "makefile",
}


class CodeEditor(TextArea):
    """Code editor with syntax highlighting and line numbers."""

    BINDINGS = [
        ("ctrl+s", "save", "Save"),
        ("ctrl+g", "goto_line", "Go to Line"),
        ("ctrl+f", "find", "Find"),
        ("ctrl+d", "duplicate_line", "Duplicate Line"),
        ("ctrl+/", "toggle_comment", "Comment"),
    ]

    # Messages
    class FileSaved(Message):
        """Message sent when file is saved."""

        def __init__(self, path: Path) -> None:
            self.path = path
            super().__init__()

    class FileModified(Message):
        """Message sent when content is modified."""

        def __init__(self, path: Path, modified: bool) -> None:
            self.path = path
            self.modified = modified
            super().__init__()

    class CursorMoved(Message):
        """Message sent when cursor position changes."""

        def __init__(self, line: int, column: int) -> None:
            self.line = line
            self.column = column
            super().__init__()

    # Reactive properties
    current_file: reactive[Optional[Path]] = reactive(None)
    is_modified: reactive[bool] = reactive(False)
    language: reactive[str] = reactive("text")
    read_only: reactive[bool] = reactive(False)

    def __init__(
        self,
        text: str = "",
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        """Initialize the code editor."""
        super().__init__(
            text,
            language="python",  # Default
            show_line_numbers=True,
            name=name,
            id=id,
            classes=classes,
        )
        self._original_content: str = ""
        self._undo_stack: list[str] = []
        self._redo_stack: list[str] = []

    def load_file(self, path: Path) -> bool:
        """Load a file into the editor.

        Args:
            path: Path to the file to load

        Returns:
            True if successful, False otherwise
        """
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()

            self.current_file = path
            self._original_content = content
            self.text = content
            self.is_modified = False

            # Detect language
            self.language = self._detect_language(path)
            self._update_syntax_highlighting()

            # Reset undo/redo
            self._undo_stack = []
            self._redo_stack = []

            return True
        except Exception as e:
            self.notify(f"Error loading file: {e}", severity="error")
            return False

    def save_file(self, path: Optional[Path] = None) -> bool:
        """Save the current content to file.

        Args:
            path: Path to save to (defaults to current_file)

        Returns:
            True if successful, False otherwise
        """
        save_path = path or self.current_file
        if not save_path:
            self.notify("No file to save", severity="warning")
            return False

        try:
            with open(save_path, "w", encoding="utf-8") as f:
                f.write(self.text)

            self._original_content = self.text
            self.is_modified = False

            if path:
                self.current_file = path
                self.language = self._detect_language(path)

            self.post_message(self.FileSaved(save_path))
            return True
        except Exception as e:
            self.notify(f"Error saving file: {e}", severity="error")
            return False

    def _detect_language(self, path: Path) -> str:
        """Detect programming language from file path."""
        # Check by filename first
        if path.name in LANGUAGE_MAP:
            return LANGUAGE_MAP[path.name]

        # Then by extension
        ext = path.suffix.lower()
        return LANGUAGE_MAP.get(ext, "text")

    def _update_syntax_highlighting(self) -> None:
        """Update syntax highlighting for current language."""
        # Textual's TextArea handles this through the language property
        try:
            # Map our language names to Textual's supported languages
            textual_languages = {
                "python": "python",
                "javascript": "javascript",
                "typescript": "javascript",  # Close enough
                "json": "json",
                "markdown": "markdown",
                "css": "css",
                "html": "html",
                "sql": "sql",
                "yaml": "yaml",
                "toml": "toml",
            }
            lang = textual_languages.get(self.language, "python")
            self.language = lang
        except Exception:
            pass

    def on_text_area_changed(self, event: TextArea.Changed) -> None:
        """Handle text changes."""
        new_modified = self.text != self._original_content
        if new_modified != self.is_modified:
            self.is_modified = new_modified
            if self.current_file:
                self.post_message(self.FileModified(self.current_file, new_modified))

    def on_key(self, event: events.Key) -> None:
        """Handle key events."""
        # Track cursor position
        if hasattr(self, "cursor_location"):
            line, col = self.cursor_location
            self.post_message(self.CursorMoved(line + 1, col + 1))

    def action_save(self) -> None:
        """Save the current file."""
        self.save_file()

    def action_goto_line(self) -> None:
        """Go to a specific line."""
        # This would normally open a dialog
        pass

    def action_duplicate_line(self) -> None:
        """Duplicate the current line."""
        if not self.text:
            return

        lines = self.text.split("\n")
        line, col = self.cursor_location

        if 0 <= line < len(lines):
            lines.insert(line + 1, lines[line])
            self.text = "\n".join(lines)

    def action_toggle_comment(self) -> None:
        """Toggle comment on the current line."""
        if not self.text:
            return

        comment_chars = {
            "python": "#",
            "javascript": "//",
            "typescript": "//",
            "go": "//",
            "rust": "//",
            "c": "//",
            "cpp": "//",
            "java": "//",
            "csharp": "//",
            "ruby": "#",
            "bash": "#",
            "yaml": "#",
            "toml": "#",
        }

        comment = comment_chars.get(self.language, "#")
        lines = self.text.split("\n")
        line, col = self.cursor_location

        if 0 <= line < len(lines):
            current_line = lines[line]
            stripped = current_line.lstrip()

            if stripped.startswith(comment):
                # Remove comment
                indent = len(current_line) - len(stripped)
                lines[line] = current_line[:indent] + stripped[len(comment) :].lstrip()
            else:
                # Add comment
                indent = len(current_line) - len(stripped)
                lines[line] = current_line[:indent] + comment + " " + stripped

            self.text = "\n".join(lines)

    def scroll_to_line(self, line: int) -> None:
        """Scroll to show a specific line."""
        if line > 0:
            # Move cursor to line
            self.cursor_location = (line - 1, 0)

    def highlight_lines(self, start: int, end: int, style: str = "highlight") -> None:
        """Highlight a range of lines (for showing changes)."""
        # This is a placeholder - would need custom rendering
        pass

    def apply_diff(self, old_text: str, new_text: str) -> None:
        """Apply a diff and highlight changes."""
        self.text = new_text
        # In a full implementation, we'd highlight the changes

    def watch_read_only(self, read_only: bool) -> None:
        """React to read_only changes."""
        self.disabled = read_only


class EditorHeader(Horizontal):
    """Header bar for the editor showing filename and status."""

    def __init__(self):
        super().__init__(id="editor-header")

    def compose(self):
        yield Static("No file open", id="editor-filename")
        yield Static("", id="editor-modified")
        yield Static("Ln 1, Col 1", id="editor-position")

    def update_file(self, path: Optional[Path], modified: bool = False) -> None:
        """Update the displayed filename."""
        filename_widget = self.query_one("#editor-filename", Static)
        modified_widget = self.query_one("#editor-modified", Static)

        if path:
            filename_widget.update(path.name)
            modified_widget.update("●" if modified else "")
        else:
            filename_widget.update("No file open")
            modified_widget.update("")

    def update_position(self, line: int, column: int) -> None:
        """Update cursor position display."""
        position_widget = self.query_one("#editor-position", Static)
        position_widget.update(f"Ln {line}, Col {column}")


class EditorPanel(Vertical):
    """Complete editor panel with header and editor."""

    def __init__(
        self,
        name: str | None = None,
        id: str | None = None,
        classes: str | None = None,
    ):
        super().__init__(name=name, id=id, classes=classes)
        self._editor: Optional[CodeEditor] = None
        self._header: Optional[EditorHeader] = None

    def compose(self):
        self._header = EditorHeader()
        yield self._header

        self._editor = CodeEditor(id="code-editor")
        yield self._editor

    @property
    def editor(self) -> Optional[CodeEditor]:
        """Get the code editor widget."""
        return self._editor

    def load_file(self, path: Path) -> bool:
        """Load a file into the editor."""
        if self._editor:
            success = self._editor.load_file(path)
            if success and self._header:
                self._header.update_file(path, False)
            return success
        return False

    def on_code_editor_file_modified(self, event: CodeEditor.FileModified) -> None:
        """Handle file modification events."""
        if self._header:
            self._header.update_file(event.path, event.modified)

    def on_code_editor_cursor_moved(self, event: CodeEditor.CursorMoved) -> None:
        """Handle cursor movement events."""
        if self._header:
            self._header.update_position(event.line, event.column)

"""
Circuit IDE Widgets.

Custom Textual widgets for the IDE interface.
"""

from .chat import ChatPanel
from .editor import CodeEditor
from .file_tree import FileTreeWidget
from .status import AgentStatusWidget, StatusBar
from .terminal import TerminalWidget

__all__ = [
    "FileTreeWidget",
    "CodeEditor",
    "ChatPanel",
    "AgentStatusWidget",
    "StatusBar",
    "TerminalWidget",
]

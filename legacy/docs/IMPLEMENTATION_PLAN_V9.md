# Circuit IDE v9.0 - Phased Implementation Plan

**Created**: January 6, 2026
**Objective**: Fix all identified bugs and implement missing features
**Total Phases**: 5
**Estimated Scope**: Comprehensive overhaul

---

## Phase 1: Critical Bug Fixes (URGENT)

### 1.1 Fix Event Loop Architecture
**Priority**: P0 (Critical)
**Files**: `circuit_ide_gui/main.py`

**Problem**: AgentWorker creates new event loops for each operation, breaking async event handling.

**Solution**: Use persistent event loop with QThread properly.

```python
# BEFORE (broken):
class AgentWorker(QObject):
    @Slot()
    def connect_agent(self):
        self._loop = asyncio.new_event_loop()  # New each time!
        asyncio.set_event_loop(self._loop)
        try:
            result = self._loop.run_until_complete(...)
        finally:
            self._loop.close()  # Closes immediately!

# AFTER (fixed):
class AgentWorker(QObject):
    def __init__(self):
        super().__init__()
        self._loop = asyncio.new_event_loop()  # Single persistent loop
        self._running = False

    def start_loop(self):
        """Start the event loop in a thread."""
        def run():
            asyncio.set_event_loop(self._loop)
            self._running = True
            self._loop.run_forever()

        self._thread = threading.Thread(target=run, daemon=True)
        self._thread.start()

    @Slot()
    def connect_agent(self):
        if not self._running:
            self.start_loop()

        future = asyncio.run_coroutine_threadsafe(
            self.service.connect_with_saved_credentials(),
            self._loop
        )
        try:
            result = future.result(timeout=30)
            self.connected.emit(result)
        except Exception as e:
            self.connected.emit(False)

    @Slot(str)
    def send_message(self, text: str):
        future = asyncio.run_coroutine_threadsafe(
            self.service.send_message(text),
            self._loop
        )
        # Handle result via callback to avoid blocking

    def stop(self):
        if self._loop:
            self._loop.call_soon_threadsafe(self._loop.stop)
```

**Implementation Steps**:
1. Create persistent event loop in AgentWorker.__init__
2. Start loop in background thread
3. Use `asyncio.run_coroutine_threadsafe()` for all async calls
4. Add proper cleanup in closeEvent
5. Test streaming responses work correctly

### 1.2 Add Proper Error Display
**Priority**: P0
**Files**: `circuit_ide_gui/main.py`

**Changes**:
```python
# In AgentWorker.init_service():
def init_service(self, working_dir: str):
    try:
        from circuit_agent.service import AgentService, EventType
        self.service = AgentService(...)
        # ... register handlers ...
        self.service_ready.emit(True, "")
    except Exception as e:
        self.service_ready.emit(False, str(e))

# Add new signal:
class AgentWorker(QObject):
    service_ready = Signal(bool, str)  # success, error_message

# In CircuitIDEWindow:
self.worker.service_ready.connect(self._on_service_ready)

def _on_service_ready(self, success: bool, error: str):
    if not success:
        self.chat_panel.add_message("system", f"Service initialization failed: {error}")
        self.statusBar().showMessage(f"Error: {error}")
```

### 1.3 Fix GitPanel Missing Refresh
**Priority**: P1
**Files**: `circuit_ide_gui/main.py:1816-1818`

```python
def _do_push(self):
    ok, out, err = self._run_git(["push"])
    self.status_label.setText(out if ok else err)
    self.refresh()  # ADD THIS LINE
```

---

## Phase 2: Integrated Terminal

### 2.1 Terminal Widget Design
**Priority**: P1 (High)
**New Files**: Embedded in `main.py`

**Architecture**:
```
┌─────────────────────────────────────────────────────────┐
│  Editor Tabs                                            │
│  ┌─────────────────────────────────────────────────────┐│
│  │                                                     ││
│  │              Code Editor Area                       ││
│  │                                                     ││
│  └─────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────┤
│  [Terminal] [Problems] [Output]              [─][□][×] │
│  ┌─────────────────────────────────────────────────────┐│
│  │ $ python main.py                                    ││
│  │ Hello, World!                                       ││
│  │ $ _                                                 ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 2.2 Terminal Implementation
```python
class TerminalPanel(QWidget):
    """Integrated terminal panel."""

    command_executed = Signal(str, str)  # command, output

    def __init__(self, working_dir: str = None, parent=None):
        super().__init__(parent)
        self.working_dir = Path(working_dir) if working_dir else Path.cwd()
        self.process: Optional[QProcess] = None
        self.history: List[str] = []
        self.history_index = -1

        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # Terminal header with tabs
        header = QWidget()
        header.setStyleSheet(f"background: {Theme.BG_SECONDARY};")
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(8, 4, 8, 4)

        self.tab_bar = QTabWidget()
        self.tab_bar.setTabsClosable(True)
        self.tab_bar.tabCloseRequested.connect(self._close_terminal)
        header_layout.addWidget(self.tab_bar)

        add_btn = IconButton(Icons.plus, "New Terminal")
        add_btn.clicked.connect(self._new_terminal)
        header_layout.addWidget(add_btn)

        # Minimize/maximize buttons
        self.toggle_btn = IconButton(Icons.arrow_down, "Minimize")
        self.toggle_btn.clicked.connect(self._toggle_panel)
        header_layout.addWidget(self.toggle_btn)

        layout.addWidget(header)

        # Terminal output area
        self.output = QPlainTextEdit()
        self.output.setReadOnly(True)
        self.output.setFont(QFont("Consolas", 11))
        self.output.setStyleSheet(f"""
            QPlainTextEdit {{
                background: {Theme.BG_DARK};
                color: {Theme.TEXT_PRIMARY};
                border: none;
                padding: 8px;
            }}
        """)
        layout.addWidget(self.output)

        # Input line
        input_container = QWidget()
        input_container.setStyleSheet(f"background: {Theme.BG_DARK};")
        input_layout = QHBoxLayout(input_container)
        input_layout.setContentsMargins(8, 4, 8, 8)

        self.prompt = QLabel("$")
        self.prompt.setStyleSheet(f"color: {Theme.ACCENT_GREEN}; font-weight: bold;")
        input_layout.addWidget(self.prompt)

        self.input = QLineEdit()
        self.input.setStyleSheet(f"""
            QLineEdit {{
                background: transparent;
                border: none;
                color: {Theme.TEXT_PRIMARY};
                font-family: 'Consolas', monospace;
                font-size: 11px;
            }}
        """)
        self.input.returnPressed.connect(self._run_command)
        input_layout.addWidget(self.input)

        layout.addWidget(input_container)

    def _run_command(self):
        """Execute the entered command."""
        command = self.input.text().strip()
        if not command:
            return

        self.input.clear()
        self.history.append(command)
        self.history_index = len(self.history)

        # Display command in output
        self._append_output(f"$ {command}\n", Theme.ACCENT_GREEN)

        # Handle built-in commands
        if command == "clear":
            self.output.clear()
            return
        elif command.startswith("cd "):
            self._change_directory(command[3:].strip())
            return

        # Run external command
        self.process = QProcess(self)
        self.process.setWorkingDirectory(str(self.working_dir))
        self.process.readyReadStandardOutput.connect(self._read_stdout)
        self.process.readyReadStandardError.connect(self._read_stderr)
        self.process.finished.connect(self._process_finished)

        # Parse command for shell
        if sys.platform == "win32":
            self.process.start("cmd", ["/c", command])
        else:
            self.process.start("/bin/sh", ["-c", command])

    def _read_stdout(self):
        data = self.process.readAllStandardOutput().data().decode()
        self._append_output(data, Theme.TEXT_PRIMARY)

    def _read_stderr(self):
        data = self.process.readAllStandardError().data().decode()
        self._append_output(data, Theme.ACCENT_RED)

    def _append_output(self, text: str, color: str):
        cursor = self.output.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)

        fmt = QTextCharFormat()
        fmt.setForeground(QColor(color))
        cursor.insertText(text, fmt)

        self.output.setTextCursor(cursor)
        self.output.ensureCursorVisible()

    def _process_finished(self, exit_code: int, status):
        if exit_code != 0:
            self._append_output(f"\nProcess exited with code {exit_code}\n", Theme.WARNING)
        self.process = None

    def _change_directory(self, path: str):
        new_path = (self.working_dir / path).resolve()
        if new_path.is_dir():
            self.working_dir = new_path
            self._append_output(f"Changed to: {new_path}\n", Theme.TEXT_MUTED)
        else:
            self._append_output(f"Directory not found: {path}\n", Theme.ACCENT_RED)

    def keyPressEvent(self, event):
        # Handle history navigation
        if event.key() == Qt.Key.Key_Up:
            if self.history_index > 0:
                self.history_index -= 1
                self.input.setText(self.history[self.history_index])
        elif event.key() == Qt.Key.Key_Down:
            if self.history_index < len(self.history) - 1:
                self.history_index += 1
                self.input.setText(self.history[self.history_index])
            else:
                self.history_index = len(self.history)
                self.input.clear()
        elif event.key() == Qt.Key.Key_C and event.modifiers() & Qt.KeyboardModifier.ControlModifier:
            # Ctrl+C to kill process
            if self.process and self.process.state() == QProcess.ProcessState.Running:
                self.process.kill()
                self._append_output("\n^C\n", Theme.ACCENT_RED)
        else:
            super().keyPressEvent(event)

    def set_working_dir(self, path: str):
        self.working_dir = Path(path)

    def _new_terminal(self):
        # For now, just clear; multi-terminal support later
        self.output.clear()

    def _close_terminal(self, index):
        pass  # Multi-terminal support

    def _toggle_panel(self):
        # Toggle visibility
        self.setVisible(not self.isVisible())
```

### 2.3 Integration with Main Window
```python
class CircuitIDEWindow(QMainWindow):
    def _setup_ui(self):
        # ... existing code ...

        # Create main vertical splitter (editor + terminal)
        editor_terminal_splitter = QSplitter(Qt.Orientation.Vertical)
        editor_terminal_splitter.setHandleWidth(3)

        # Editor tabs
        self.editor_tabs = EditorTabs()
        editor_terminal_splitter.addWidget(self.editor_tabs)

        # Terminal panel (collapsible at bottom)
        self.terminal_panel = TerminalPanel()
        self.terminal_panel.setMinimumHeight(100)
        editor_terminal_splitter.addWidget(self.terminal_panel)

        # Set initial sizes (80% editor, 20% terminal)
        editor_terminal_splitter.setSizes([600, 150])

        # Add to main splitter
        splitter.addWidget(editor_terminal_splitter)
```

---

## Phase 3: Tool Confirmation Dialogs

### 3.1 Confirmation Dialog Widget
```python
class ToolConfirmationDialog(QDialog):
    """Dialog for confirming dangerous tool operations."""

    def __init__(self, request: ConfirmationRequest, parent=None):
        super().__init__(parent)
        self.request = request
        self.result = False

        self.setWindowTitle("Confirm Action")
        self.setMinimumWidth(400)
        self.setModal(True)

        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(16)

        # Icon and message
        header = QHBoxLayout()

        icon_label = QLabel()
        if self.request.is_dangerous:
            icon_label.setPixmap(Icons.warning().pixmap(32, 32))
        else:
            icon_label.setPixmap(Icons.check().pixmap(32, 32))
        header.addWidget(icon_label)

        message = QLabel(self.request.message)
        message.setWordWrap(True)
        message.setStyleSheet(f"font-size: 14px; color: {Theme.TEXT_PRIMARY};")
        header.addWidget(message)
        header.addStretch()

        layout.addLayout(header)

        # Tool details
        details_frame = QFrame()
        details_frame.setStyleSheet(f"""
            QFrame {{
                background: {Theme.BG_TERTIARY};
                border: 1px solid {Theme.BORDER};
                border-radius: 4px;
                padding: 8px;
            }}
        """)
        details_layout = QVBoxLayout(details_frame)

        tool_label = QLabel(f"Tool: {self.request.tool_name}")
        tool_label.setStyleSheet(f"color: {Theme.ACCENT_CYAN}; font-weight: bold;")
        details_layout.addWidget(tool_label)

        if self.request.details:
            detail_label = QLabel(self.request.details)
            detail_label.setStyleSheet(f"color: {Theme.TEXT_SECONDARY}; font-size: 11px;")
            detail_label.setWordWrap(True)
            details_layout.addWidget(detail_label)

        # Show arguments
        args_text = json.dumps(self.request.tool_call.arguments, indent=2)
        args_display = QPlainTextEdit(args_text)
        args_display.setReadOnly(True)
        args_display.setMaximumHeight(100)
        args_display.setStyleSheet(f"""
            QPlainTextEdit {{
                background: {Theme.BG_DARK};
                color: {Theme.TEXT_PRIMARY};
                font-family: 'Consolas', monospace;
                font-size: 10px;
                border: none;
            }}
        """)
        details_layout.addWidget(args_display)

        layout.addWidget(details_frame)

        # Buttons
        buttons = QHBoxLayout()
        buttons.addStretch()

        deny_btn = SecondaryButton("Deny")
        deny_btn.clicked.connect(self.reject)
        buttons.addWidget(deny_btn)

        approve_btn = CompactButton("Approve")
        if self.request.is_dangerous:
            approve_btn.setStyleSheet(approve_btn.styleSheet().replace(
                Theme.ACCENT_BLUE, Theme.ACCENT_RED
            ))
        approve_btn.clicked.connect(self.accept)
        buttons.addWidget(approve_btn)

        layout.addLayout(buttons)

    def accept(self):
        self.result = True
        super().accept()

    def reject(self):
        self.result = False
        super().reject()
```

### 3.2 Connect to AgentService Events
```python
# In CircuitIDEWindow._init_agent():
self.service.on(EventType.CONFIRMATION_NEEDED, self._on_confirmation_needed)

def _on_confirmation_needed(self, event):
    """Show confirmation dialog on main thread."""
    request = event.data.get("request")
    if not request:
        return

    # Must show dialog on main thread
    QTimer.singleShot(0, lambda: self._show_confirmation_dialog(request))

def _show_confirmation_dialog(self, request):
    dialog = ToolConfirmationDialog(request, self)
    result = dialog.exec()

    # Send response back to service
    if self.worker and self.worker.service:
        self.worker.service.respond_to_confirmation(request.id, result == QDialog.DialogCode.Accepted)
```

---

## Phase 4: Editor Enhancements

### 4.1 Find/Replace Widget
```python
class FindReplaceBar(QWidget):
    """Find and replace bar for code editor."""

    find_next = Signal(str, bool)  # pattern, case_sensitive
    find_prev = Signal(str, bool)
    replace_one = Signal(str, str)
    replace_all = Signal(str, str)
    closed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setVisible(False)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 4, 8, 4)
        layout.setSpacing(4)

        # Find row
        find_row = QHBoxLayout()

        self.find_input = CompactLineEdit("Find...")
        self.find_input.textChanged.connect(self._on_find_changed)
        self.find_input.returnPressed.connect(self._find_next)
        find_row.addWidget(self.find_input)

        self.case_check = QCheckBox("Aa")
        self.case_check.setToolTip("Case sensitive")
        find_row.addWidget(self.case_check)

        prev_btn = IconButton(Icons.arrow_up, "Previous")
        prev_btn.clicked.connect(self._find_prev)
        find_row.addWidget(prev_btn)

        next_btn = IconButton(Icons.arrow_down, "Next")
        next_btn.clicked.connect(self._find_next)
        find_row.addWidget(next_btn)

        close_btn = IconButton(Icons.close, "Close")
        close_btn.clicked.connect(self._close)
        find_row.addWidget(close_btn)

        layout.addLayout(find_row)

        # Replace row
        replace_row = QHBoxLayout()

        self.replace_input = CompactLineEdit("Replace...")
        replace_row.addWidget(self.replace_input)

        replace_btn = SecondaryButton("Replace")
        replace_btn.clicked.connect(self._replace_one)
        replace_row.addWidget(replace_btn)

        replace_all_btn = SecondaryButton("Replace All")
        replace_all_btn.clicked.connect(self._replace_all)
        replace_row.addWidget(replace_all_btn)

        replace_row.addStretch()
        layout.addLayout(replace_row)

        # Match count
        self.match_label = QLabel("")
        self.match_label.setStyleSheet(f"color: {Theme.TEXT_MUTED}; font-size: 10px;")
        layout.addWidget(self.match_label)

    def show_find(self):
        self.setVisible(True)
        self.find_input.setFocus()
        self.find_input.selectAll()

    def _on_find_changed(self, text):
        if text:
            self.find_next.emit(text, self.case_check.isChecked())

    def _find_next(self):
        self.find_next.emit(self.find_input.text(), self.case_check.isChecked())

    def _find_prev(self):
        self.find_prev.emit(self.find_input.text(), self.case_check.isChecked())

    def _replace_one(self):
        self.replace_one.emit(self.find_input.text(), self.replace_input.text())

    def _replace_all(self):
        self.replace_all.emit(self.find_input.text(), self.replace_input.text())

    def _close(self):
        self.setVisible(False)
        self.closed.emit()

    def set_match_count(self, current: int, total: int):
        if total > 0:
            self.match_label.setText(f"{current} of {total}")
        else:
            self.match_label.setText("No results")
```

### 4.2 Integrate into CodeEditor
```python
class CodeEditor(QPlainTextEdit):
    def __init__(self, parent=None):
        super().__init__(parent)
        # ... existing init ...

        # Find/replace
        self.find_bar = FindReplaceBar(self)
        self.find_bar.find_next.connect(self._find_next)
        self.find_bar.find_prev.connect(self._find_prev)
        self.find_bar.replace_one.connect(self._replace_one)
        self.find_bar.replace_all.connect(self._replace_all)

        # Keyboard shortcuts
        self.find_action = QAction("Find", self)
        self.find_action.setShortcut(QKeySequence.StandardKey.Find)
        self.find_action.triggered.connect(self.show_find)
        self.addAction(self.find_action)

        self.replace_action = QAction("Replace", self)
        self.replace_action.setShortcut(QKeySequence.StandardKey.Replace)
        self.replace_action.triggered.connect(self.show_replace)
        self.addAction(self.replace_action)

    def show_find(self):
        self.find_bar.show_find()

    def _find_next(self, pattern: str, case_sensitive: bool):
        flags = QTextDocument.FindFlag(0)
        if case_sensitive:
            flags |= QTextDocument.FindFlag.FindCaseSensitively

        cursor = self.textCursor()
        found = self.document().find(pattern, cursor, flags)

        if found.isNull():
            # Wrap around
            found = self.document().find(pattern, 0, flags)

        if not found.isNull():
            self.setTextCursor(found)
```

### 4.3 Unsaved Changes Warning
```python
class EditorTabs(QTabWidget):
    def _close_tab(self, index):
        widget = self.widget(index)
        if isinstance(widget, CodeEditor):
            if widget.document().isModified():
                reply = QMessageBox.question(
                    self,
                    "Unsaved Changes",
                    f"Save changes to {widget.current_file.name if widget.current_file else 'Untitled'}?",
                    QMessageBox.StandardButton.Save |
                    QMessageBox.StandardButton.Discard |
                    QMessageBox.StandardButton.Cancel
                )

                if reply == QMessageBox.StandardButton.Save:
                    widget.save_file()
                elif reply == QMessageBox.StandardButton.Cancel:
                    return  # Don't close

        # Proceed with close
        if path := getattr(widget, 'current_file', None):
            self._open_files.discard(path)
        self.removeTab(index)
```

---

## Phase 5: Polish and Testing

### 5.1 Add Problems/Output Panels
```python
class ProblemsPanel(QWidget):
    """Panel for displaying errors, warnings, and info."""

    def __init__(self, parent=None):
        super().__init__(parent)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        # Filter bar
        filter_bar = QHBoxLayout()

        self.error_btn = CompactButton(f"Errors (0)")
        self.warning_btn = CompactButton(f"Warnings (0)")
        self.info_btn = CompactButton(f"Info (0)")

        filter_bar.addWidget(self.error_btn)
        filter_bar.addWidget(self.warning_btn)
        filter_bar.addWidget(self.info_btn)
        filter_bar.addStretch()

        layout.addLayout(filter_bar)

        # Problems list
        self.list = QListWidget()
        layout.addWidget(self.list)

    def add_problem(self, severity: str, file: str, line: int, message: str):
        item = QListWidgetItem()

        icon = {"error": Icons.close, "warning": Icons.warning, "info": Icons.info}
        color = {"error": Theme.ERROR, "warning": Theme.WARNING, "info": Theme.INFO}

        # ... display logic
```

### 5.2 Status Bar Enhancements
```python
class EnhancedStatusBar(QStatusBar):
    """Status bar with position, encoding, line ending info."""

    def __init__(self, parent=None):
        super().__init__(parent)

        # Cursor position
        self.position_label = QLabel("Ln 1, Col 1")
        self.addPermanentWidget(self.position_label)

        # Encoding
        self.encoding_label = QLabel("UTF-8")
        self.addPermanentWidget(self.encoding_label)

        # Line ending
        self.eol_label = QLabel("LF")
        self.addPermanentWidget(self.eol_label)

        # Language mode
        self.language_label = QLabel("Python")
        self.addPermanentWidget(self.language_label)

        # Indentation
        self.indent_label = QLabel("Spaces: 4")
        self.addPermanentWidget(self.indent_label)

    def update_position(self, line: int, col: int):
        self.position_label.setText(f"Ln {line}, Col {col}")

    def set_language(self, language: str):
        self.language_label.setText(language)
```

### 5.3 Testing Plan
```python
# tests/gui/test_main.py

import pytest
from PySide6.QtWidgets import QApplication
from circuit_ide_gui.main import (
    CircuitIDEWindow, AgentWorker, TerminalPanel,
    ToolConfirmationDialog
)

@pytest.fixture
def app():
    return QApplication([])

@pytest.fixture
def window(app):
    return CircuitIDEWindow()

class TestAgentWorker:
    def test_event_loop_persistence(self, app):
        worker = AgentWorker()
        worker.start_loop()

        assert worker._loop is not None
        assert worker._running is True

        worker.stop()

    def test_send_message_emits_signals(self, app):
        # Test signal emissions
        pass

class TestTerminalPanel:
    def test_command_execution(self, app):
        terminal = TerminalPanel(".")
        terminal._run_command("echo test")

        # Verify output
        pass

    def test_history_navigation(self, app):
        terminal = TerminalPanel(".")
        terminal.history = ["cmd1", "cmd2", "cmd3"]
        terminal.history_index = 3

        # Test up arrow
        pass

class TestToolConfirmation:
    def test_approve_sets_result_true(self, app):
        # Create mock request
        pass
```

---

## Timeline Summary

| Phase | Focus | Scope |
|-------|-------|-------|
| Phase 1 | Critical Bug Fixes | Fix event loop, error display |
| Phase 2 | Integrated Terminal | Full terminal with history, multi-tab |
| Phase 3 | Tool Confirmations | Dangerous operation dialogs |
| Phase 4 | Editor Enhancements | Find/Replace, unsaved warnings |
| Phase 5 | Polish & Testing | Problems panel, status bar, tests |

---

## Implementation Order

1. **Phase 1.1** - Fix event loop (BLOCKING - must do first)
2. **Phase 1.2** - Error display
3. **Phase 1.3** - Git refresh fix
4. **Phase 2** - Terminal panel
5. **Phase 3** - Confirmation dialogs
6. **Phase 4.3** - Unsaved changes warning
7. **Phase 4.1-4.2** - Find/Replace
8. **Phase 5** - Polish

---

## Files to Modify

| File | Changes |
|------|---------|
| `circuit_ide_gui/main.py` | All phases |
| `circuit_agent/service/agent_service.py` | Add respond_to_confirmation method |
| `tests/gui/` | New directory for GUI tests |

---

## Success Criteria

- [ ] AI Agent connects and responds correctly
- [ ] Streaming responses display in real-time
- [ ] Tool confirmations appear for dangerous operations
- [ ] Terminal executes commands with output
- [ ] Find/Replace works in all open files
- [ ] Unsaved changes prompts before closing
- [ ] All existing functionality still works
- [ ] No regression in performance


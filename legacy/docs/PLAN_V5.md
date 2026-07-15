# Circuit Agent v5.0 - Terminal IDE Plan

## Executive Summary

Transform Circuit Agent from a CLI tool that runs in existing terminals into a **purpose-built Terminal IDE** - a dedicated graphical environment optimized for AI-assisted coding. This creates a unified workspace where the AI agent has its own visual interface, specialized for code editing, file management, and intelligent interactions.

---

## Vision

Current state: Circuit Agent runs in a standard terminal (iTerm, Terminal.app, Windows Terminal, etc.)

Future state: Circuit Agent launches its own window - a custom "Terminal IDE" that provides:
- Dedicated AI interaction panel
- Integrated file explorer
- Live code preview/editing
- Visual diff viewer
- Status dashboard
- Multi-pane workspace

Think of it as **VS Code meets Claude Code** - a specialized environment for AI-powered development.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Circuit Terminal IDE                          │
├─────────────────────────────────────────────────────────────────┤
│ ┌─────────────┐ ┌───────────────────────────────────────────┐  │
│ │ File Tree   │ │               Main Editor                  │  │
│ │             │ │  ┌────────────────────────────────────┐   │  │
│ │ 📁 src/     │ │  │ // Current file content            │   │  │
│ │   📄 app.py │ │  │ def main():                        │   │  │
│ │   📄 utils  │ │  │     print("hello")                 │   │  │
│ │ 📁 tests/   │ │  │                                    │   │  │
│ │             │ │  └────────────────────────────────────┘   │  │
│ └─────────────┘ │                                            │  │
│                 ├───────────────────────────────────────────┤  │
│ ┌─────────────┐ │            AI Chat Panel                   │  │
│ │ Agent Panel │ │  You: Fix the bug in auth.py              │  │
│ │             │ │                                            │  │
│ │ 🔧 Tools    │ │  Agent: I'll read the file and fix it.    │  │
│ │ 📊 Tokens   │ │  [read_file] auth.py ✓                    │  │
│ │ 💰 Cost     │ │  [edit_file] auth.py ✓                    │  │
│ │ 📝 History  │ │  Fixed the authentication bug.            │  │
│ └─────────────┘ │                                            │  │
│                 │  > [Your message here...]                  │  │
└─────────────────┴───────────────────────────────────────────────┘
```

---

## Technical Stack Options

### Option A: Electron + React (Cross-Platform Desktop App)
**Pros:**
- Native desktop experience
- Rich UI capabilities (syntax highlighting, themes)
- Access to file system, shell
- Can embed terminal emulator (xterm.js)
- Familiar tech stack for web developers

**Cons:**
- Large bundle size (~150MB)
- Memory intensive
- Requires Node.js runtime

```
circuit-ide/
├── electron/
│   ├── main.ts           # Electron main process
│   ├── preload.ts        # IPC bridge
│   └── ipc-handlers.ts   # File system, shell APIs
├── src/
│   ├── components/
│   │   ├── FileTree/
│   │   ├── Editor/
│   │   ├── ChatPanel/
│   │   ├── Terminal/
│   │   └── StatusBar/
│   ├── stores/           # State management (Zustand/Redux)
│   └── App.tsx
└── python/
    └── circuit_agent/    # Existing Python agent
```

### Option B: Tauri + React (Lightweight Desktop App)
**Pros:**
- Tiny bundle size (~5MB)
- Uses native webview (not Chromium)
- Rust backend for performance
- Still cross-platform

**Cons:**
- Less mature ecosystem
- Rust learning curve
- Some platform differences

### Option C: Python Native GUI (Textual/Rich)
**Pros:**
- Pure Python - no additional runtime
- Text-based but beautiful (Textual library)
- Fast to develop
- Runs in any terminal
- Very lightweight

**Cons:**
- Limited to text-based UI
- No true window, still terminal-based
- Less visually rich

```python
# Example with Textual
from textual.app import App
from textual.widgets import Header, Footer, Tree, TextArea, Static

class CircuitIDE(App):
    CSS_PATH = "circuit_ide.tcss"

    def compose(self):
        yield Header()
        yield FileTree(id="files")
        yield Editor(id="editor")
        yield ChatPanel(id="chat")
        yield StatusBar(id="status")
        yield Footer()
```

### Option D: Web-Based (Local Server + Browser)
**Pros:**
- No installation required
- Works on any platform with browser
- Easy to develop and iterate
- Could become cloud-hosted later

**Cons:**
- Requires browser
- Less "native" feel
- Security considerations

### Recommendation: **Option C (Textual) for v5.0, Option A (Electron) for v6.0**

Start with Textual for rapid development and pure Python ecosystem, then evaluate Electron for a richer GUI in v6.0.

---

## Phase 1: Textual-Based Terminal IDE

### 1.1 Core Layout Components

```
┌──────────────────────────────────────────────────────────────────┐
│ Circuit Agent v5.0                                    ⏱️ Tokens  │
├────────────────┬─────────────────────────────────────────────────┤
│ FILES          │ EDITOR: src/app.py                              │
│ ─────────────  │ ─────────────────────────────────────────────── │
│ 📁 circuit/    │  1│ """                                         │
│   📄 agent.py  │  2│ Main application module.                    │
│   📄 cli.py    │  3│ """                                         │
│   📁 tools/    │  4│                                             │
│     📄 file    │  5│ def main():                                 │
│     📄 git     │  6│     app = Application()                     │
│                │  7│     app.run()                               │
├────────────────┼─────────────────────────────────────────────────┤
│ AGENT          │ CHAT                                            │
│ ─────────────  │ ─────────────────────────────────────────────── │
│ Model: gpt-4o  │ You: Help me refactor the auth module          │
│ Tokens: 15.2k  │                                                 │
│ Cost: $0.23    │ Agent: I'll analyze the authentication code    │
│                │ and suggest improvements. Let me start by      │
│ [Thinking...]  │ reading the relevant files...                  │
│                │                                                 │
│                │ [read_file] src/auth.py ✓                      │
│                │ [read_file] src/models/user.py ✓               │
│                │                                                 │
│                │ > _                                             │
└────────────────┴─────────────────────────────────────────────────┘
│ F1:Help F2:Files F3:Editor F4:Chat F5:Terminal F10:Quit          │
└──────────────────────────────────────────────────────────────────┘
```

### 1.2 Key Widgets

```python
# circuit_ide/widgets/__init__.py

class FileTreeWidget(TreeWidget):
    """Interactive file browser with keyboard navigation."""
    - Show project structure
    - Click/Enter to open file in editor
    - Right-click context menu (rename, delete, new file)
    - Git status indicators (modified, staged, untracked)

class EditorWidget(TextArea):
    """Code editor with syntax highlighting."""
    - Syntax highlighting (via Pygments)
    - Line numbers
    - Current line highlight
    - Scroll to line (for agent navigation)
    - Read-only mode during agent operations
    - Live diff overlay when agent edits

class ChatWidget(ScrollableContainer):
    """AI conversation panel."""
    - Message history with timestamps
    - Streaming response display
    - Tool call indicators with status
    - Thinking mode visualization
    - Code block rendering

class AgentStatusWidget(Static):
    """Agent status and metrics dashboard."""
    - Current model
    - Token usage (session/request)
    - Cost estimate
    - Auto-approve status
    - Thinking mode indicator
    - Active operation indicator

class TerminalWidget(xterm-like):
    """Embedded terminal for command execution."""
    - Shell command output
    - Interactive when needed
    - Agent-initiated commands
    - Color support
```

### 1.3 Core Features

**1.3.1 Live File Sync**
- Editor automatically updates when agent modifies files
- Visual diff highlight showing what changed
- "Accept/Reject" buttons for each change

**1.3.2 Context-Aware File Opening**
- When agent reads a file, it opens in editor
- Scrolls to relevant lines being discussed
- Highlights search results

**1.3.3 Visual Diff Viewer**
- Side-by-side or inline diff display
- Color-coded additions/deletions
- "Stage" changes individually

**1.3.4 Agent Activity Monitor**
- Real-time tool call visualization
- Progress indicators
- Token consumption graph
- Operation timeline

**1.3.5 Smart Command Palette**
```
Ctrl+P → Quick file open
Ctrl+K → Command palette
Ctrl+/ → Focus chat input
Ctrl+B → Toggle file tree
Ctrl+` → Toggle terminal
Ctrl+D → Toggle diff view
```

---

## Phase 2: Advanced Features

### 2.1 Multi-File Operations View

```
┌─────────────────────────────────────────────────────────────────┐
│ BATCH OPERATION: Rename 'userId' to 'user_id' across 12 files   │
├─────────────────────────────────────────────────────────────────┤
│ ☑ src/auth.py          [Line 45, 67, 89]          Preview →    │
│ ☑ src/models/user.py   [Line 12, 34]              Preview →    │
│ ☐ src/api/routes.py    [Line 23, 45, 67, 89]      Preview →    │
│ ☑ tests/test_auth.py   [Line 15, 28]              Preview →    │
│ ...                                                             │
├─────────────────────────────────────────────────────────────────┤
│ [Apply Selected] [Apply All] [Cancel]                           │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Git Integration Panel

```
┌─────────────────────────────────────────────────────────────────┐
│ GIT STATUS                                          main        │
├─────────────────────────────────────────────────────────────────┤
│ Staged (2)                                                      │
│   ✓ src/auth.py                                                 │
│   ✓ src/models/user.py                                          │
│                                                                 │
│ Modified (3)                                                    │
│   ○ src/api/routes.py                                           │
│   ○ tests/test_auth.py                                          │
│   ○ README.md                                                   │
│                                                                 │
│ Commit message: Fix authentication bug in OAuth flow            │
│ ───────────────────────────────────────────────────────         │
│ [Stage All] [Commit] [Push] [Pull]                              │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Project Context Panel

```
┌─────────────────────────────────────────────────────────────────┐
│ PROJECT CONTEXT                                                 │
├─────────────────────────────────────────────────────────────────┤
│ 📋 CIRCUIT.md loaded                                            │
│                                                                 │
│ 🔧 Project: Python FastAPI                                      │
│ 📦 Dependencies: fastapi, sqlalchemy, pydantic                  │
│ 🧪 Tests: pytest (87% coverage)                                 │
│ 📚 Docs: docs/ (15 files)                                       │
│                                                                 │
│ Recent Activity:                                                │
│   • Fixed auth bug (2 min ago)                                  │
│   • Added user validation (15 min ago)                          │
│   • Refactored models (1 hr ago)                                │
│                                                                 │
│ [Edit CIRCUIT.md] [View Full Context]                           │
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Session Management UI

```
┌─────────────────────────────────────────────────────────────────┐
│ SESSIONS                                                        │
├─────────────────────────────────────────────────────────────────┤
│ Active: auth-refactor-2024-01-15                                │
│                                                                 │
│ Saved Sessions:                                                 │
│   📁 auth-refactor-2024-01-15    Today 2:30 PM     [Load]       │
│   📁 api-routes-fix              Yesterday         [Load]       │
│   📁 test-coverage               Jan 10            [Load]       │
│                                                                 │
│ [New Session] [Save Current] [Export]                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 3: Intelligence Enhancements

### 3.1 Predictive File Loading
- Agent learns which files are frequently accessed together
- Pre-loads related files into context
- Suggests relevant files based on current task

### 3.2 Smart Workspace Snapshots
- Auto-save workspace state
- Quick restore points before major operations
- Visual timeline of changes

### 3.3 Collaborative Debugging
```
┌─────────────────────────────────────────────────────────────────┐
│ DEBUG SESSION: test_auth.py::test_login_failure                 │
├─────────────────────────────────────────────────────────────────┤
│ Error: AssertionError: Expected 401, got 500                    │
│                                                                 │
│ Agent Analysis:                                                 │
│ The test expects a 401 Unauthorized but receives 500 Internal   │
│ Server Error. This suggests an unhandled exception in the       │
│ authentication flow.                                            │
│                                                                 │
│ Stack Trace:                                                    │
│   src/auth.py:67 - validate_token()                             │
│   src/auth.py:45 - authenticate()                               │
│                                                                 │
│ Suggested Fix:                                                  │
│   Add try/except block around token validation                  │
│                                                                 │
│ [Apply Fix] [Show More Context] [Explain]                       │
└─────────────────────────────────────────────────────────────────┘
```

### 3.4 Code Review Mode
```
┌─────────────────────────────────────────────────────────────────┐
│ CODE REVIEW: PR #42 - Add OAuth2 support                        │
├─────────────────────────────────────────────────────────────────┤
│ Files Changed: 8 | +234 -56 | 3 comments                        │
│                                                                 │
│ src/auth.py (modified)                                          │
│ ─────────────────────────────────────────────────────────────── │
│ + def validate_oauth_token(token: str) -> User:                 │
│ +     """Validate OAuth2 token and return user."""              │
│ +     try:                                                      │
│ +         payload = jwt.decode(token, SECRET_KEY)               │
│                         ⚠️ Agent: Consider using verify=True    │
│ +         return User.from_dict(payload)                        │
│ +     except jwt.InvalidTokenError:                             │
│ +         raise AuthenticationError("Invalid token")            │
│                                                                 │
│ [Approve] [Request Changes] [Comment]                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Roadmap

### Phase 1: Foundation (v5.0-alpha)
| Task | Priority | Effort |
|------|----------|--------|
| Set up Textual project structure | High | 2 days |
| Implement FileTree widget | High | 2 days |
| Implement Editor widget with highlighting | High | 3 days |
| Implement ChatPanel widget | High | 2 days |
| Integrate existing CircuitAgent | High | 2 days |
| Basic keyboard navigation | High | 1 day |
| Status bar and metrics display | Medium | 1 day |

### Phase 2: Polish (v5.0-beta)
| Task | Priority | Effort |
|------|----------|--------|
| Live file sync on agent edits | High | 2 days |
| Visual diff viewer | High | 3 days |
| Terminal widget integration | Medium | 2 days |
| Command palette | Medium | 1 day |
| Theme support | Low | 1 day |
| Configuration UI | Medium | 2 days |

### Phase 3: Advanced (v5.0)
| Task | Priority | Effort |
|------|----------|--------|
| Git integration panel | Medium | 3 days |
| Multi-file operation view | Medium | 2 days |
| Session management UI | Medium | 2 days |
| Debug integration | Low | 3 days |
| Code review mode | Low | 3 days |

---

## File Structure

```
circuit-ide/
├── circuit_ide/
│   ├── __init__.py
│   ├── __main__.py           # Entry point
│   ├── app.py                # Main Textual application
│   ├── config.py             # IDE configuration
│   │
│   ├── widgets/
│   │   ├── __init__.py
│   │   ├── file_tree.py      # File browser widget
│   │   ├── editor.py         # Code editor widget
│   │   ├── chat.py           # AI chat panel
│   │   ├── terminal.py       # Embedded terminal
│   │   ├── status.py         # Status bar and metrics
│   │   ├── diff_viewer.py    # Visual diff widget
│   │   └── command_palette.py
│   │
│   ├── screens/
│   │   ├── __init__.py
│   │   ├── main.py           # Main workspace screen
│   │   ├── settings.py       # Settings screen
│   │   ├── sessions.py       # Session management screen
│   │   └── git.py            # Git operations screen
│   │
│   ├── styles/
│   │   ├── circuit.tcss      # Main stylesheet
│   │   ├── themes/
│   │   │   ├── dark.tcss
│   │   │   └── light.tcss
│   │
│   └── utils/
│       ├── __init__.py
│       ├── syntax.py         # Syntax highlighting
│       ├── icons.py          # File type icons
│       └── keybindings.py    # Keyboard shortcuts
│
├── circuit_agent/            # Existing agent code
│   └── ...
│
├── tests/
│   └── ...
│
├── pyproject.toml
└── README.md
```

---

## New Dependencies

```toml
[project.dependencies]
textual = ">=0.47.0"      # TUI framework
rich = ">=13.0"           # Rich text formatting (included with textual)
pygments = ">=2.17"       # Syntax highlighting

[project.optional-dependencies]
dev = [
    "textual-dev",        # Development tools
    "pytest-textual",     # Testing
]
```

---

## User Experience Highlights

### Launch Experience
```bash
# Launch the IDE
$ circuit-ide [project-directory]

# Or from existing agent
$ circuit-agent --ide
```

### First-Time Setup
1. IDE opens with project loaded
2. Brief tour highlighting key panels
3. "What would you like to work on?" prompt
4. CIRCUIT.md creation wizard if not present

### Daily Workflow
1. Launch IDE in project directory
2. Resume previous session or start fresh
3. Ask agent to help with task
4. Watch agent work in real-time
5. Review changes in diff viewer
6. Approve, modify, or reject
7. Commit changes via Git panel
8. Save session for later

---

## Success Metrics

- **Productivity**: Time to complete common tasks
- **Clarity**: User understanding of agent actions
- **Control**: Easy to review, modify, or reject changes
- **Discoverability**: Features easy to find and use
- **Performance**: Responsive UI even with large projects

---

## Future Considerations (v6.0+)

### Electron Migration
If Textual proves limiting, migrate to Electron for:
- True multi-window support
- Monaco Editor (VS Code's editor)
- Native OS integration
- Plugin ecosystem

### Cloud Features
- Sync sessions across devices
- Team collaboration
- Shared project context
- Remote agent execution

### AI Enhancements
- Multi-model support (Claude, GPT-4, local models)
- Agent "personalities" for different tasks
- Learning from user preferences
- Autonomous background agents

---

## Conclusion

Circuit Agent v5.0 transforms the AI coding experience from a command-line tool into a purpose-built development environment. By creating a dedicated Terminal IDE, we provide:

1. **Better Visibility** - See exactly what the agent is doing
2. **More Control** - Review and approve changes visually
3. **Improved Workflow** - Integrated file, git, and chat in one place
4. **Professional Experience** - A polished tool for daily use

The Textual-based approach allows rapid development while staying in the Python ecosystem, with a path to richer interfaces in future versions.

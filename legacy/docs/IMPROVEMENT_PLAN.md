# Circuit Agent v6.0 - Master Improvement Plan

## Vision: Transform Circuit Agent into the Best AI Coding Assistant

**Goal:** Make Circuit Agent not just competitive with Claude Code, but the **preferred choice** for developers who want a powerful, customizable, and open AI coding assistant.

---

## Part 1: Foundation (Critical - Do First)

### 1.1 Test Suite (Priority: CRITICAL)

Create comprehensive test coverage to enable confident refactoring.

```
tests/
├── conftest.py                 # Shared fixtures
├── unit/
│   ├── test_agent.py           # CircuitAgent class
│   ├── test_tools/
│   │   ├── test_file_tools.py  # File operations
│   │   ├── test_git_tools.py   # Git operations
│   │   └── test_web_tools.py   # Web operations
│   ├── test_streaming.py       # SSE parsing
│   ├── test_security.py        # Secret detection
│   ├── test_context.py         # Context management
│   └── test_errors.py          # Smart errors
├── integration/
│   ├── test_api.py             # API connectivity
│   ├── test_sessions.py        # Session save/load
│   └── test_cli.py             # CLI commands
└── e2e/
    ├── test_workflows.py       # Full agent workflows
    └── test_ui.py              # TUI/GUI tests
```

**Deliverables:**
- [ ] pytest configuration with coverage
- [ ] Mock fixtures for API calls
- [ ] Unit tests for all tools (80%+ coverage)
- [ ] Integration tests for critical paths
- [ ] CI pipeline with GitHub Actions

### 1.2 Security Hardening (Priority: CRITICAL)

Fix critical security issues immediately.

```python
# BEFORE (DANGEROUS)
async with httpx.AsyncClient(verify=False) as client:

# AFTER (SECURE)
import certifi
async with httpx.AsyncClient(
    verify=certifi.where(),  # Use system CA bundle
    timeout=httpx.Timeout(30.0, connect=10.0)
) as client:
```

**Deliverables:**
- [ ] Enable SSL verification with proper CA handling
- [ ] Add `--insecure` flag for corporate proxies (with warning)
- [ ] Use keyring library for credential storage
- [ ] Add input sanitization for all user inputs
- [ ] Security audit and SAST integration

### 1.3 Type System (Priority: HIGH)

Enable strict type checking for reliability.

```python
# Add to pyproject.toml
[tool.mypy]
python_version = "3.10"
strict = true
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
disallow_incomplete_defs = true

# Type all public interfaces
from typing import Protocol, TypedDict, Literal

class ToolResult(TypedDict):
    success: bool
    output: str
    error: str | None

class Tool(Protocol):
    name: str
    description: str
    def execute(self, args: dict[str, Any], confirmed: bool) -> ToolResult: ...
```

**Deliverables:**
- [ ] Add type stubs for all modules
- [ ] Enable mypy strict mode
- [ ] Fix all type errors
- [ ] Add py.typed marker for PEP 561

---

## Part 2: Core Features (High Impact)

### 2.1 Model Context Protocol (MCP) Support

Implement MCP for ecosystem integration with Claude, VS Code, etc.

```python
# circuit_agent/mcp/
├── __init__.py
├── server.py          # MCP server implementation
├── client.py          # MCP client for connecting to other servers
├── transport.py       # stdio, HTTP transport layers
└── tools.py           # Convert our tools to MCP format

# Usage
circuit-agent --mcp-server          # Run as MCP server
circuit-agent --mcp-connect URL     # Connect to MCP server
```

**MCP Features:**
- [ ] Expose Circuit tools as MCP resources
- [ ] Connect to external MCP servers (databases, APIs)
- [ ] Protocol-compliant message handling
- [ ] Tool discovery and negotiation

### 2.2 Vision/Image Support

Add multimodal capabilities for screenshots, diagrams, UI mockups.

```python
# New tools
IMAGE_TOOLS = [
    {
        "name": "analyze_image",
        "description": "Analyze an image file (screenshot, diagram, mockup)",
        "parameters": {
            "path": "Path to image file",
            "question": "What to analyze (optional)"
        }
    },
    {
        "name": "screenshot",
        "description": "Take a screenshot of a window or screen",
        "parameters": {
            "target": "window name, 'screen', or coordinates"
        }
    }
]

# Integration with chat
async def chat(self, user_message: str, images: list[Path] = None):
    content = [{"type": "text", "text": user_message}]
    if images:
        for img in images:
            content.append({
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{encode(img)}"}
            })
```

**Deliverables:**
- [ ] Image encoding/transmission
- [ ] Vision model integration
- [ ] Screenshot tool (cross-platform)
- [ ] Image analysis prompts

### 2.3 Unified Service Layer

Create shared backend for all UIs.

```python
# circuit_agent/service/
├── __init__.py
├── agent_service.py    # Singleton agent manager
├── events.py           # Event bus for UI updates
├── state.py            # Shared state management
└── adapters/
    ├── cli_adapter.py
    ├── tui_adapter.py
    └── gui_adapter.py

class AgentService:
    """Unified backend for all UIs."""

    # Events
    on_message: Signal[ChatMessage]
    on_tool_call: Signal[ToolCall]
    on_confirmation_needed: Signal[ConfirmationRequest]
    on_status_change: Signal[AgentStatus]

    # Methods
    async def send_message(self, content: str, images: list = None) -> str
    def approve_action(self, action_id: str, approved: bool) -> None
    def cancel_operation(self) -> None
```

**Benefits:**
- Single source of truth for agent logic
- Consistent behavior across all UIs
- Easier testing and maintenance
- New UIs (web, VS Code) become trivial

### 2.4 Fast File Search with ripgrep

Replace Python glob/regex with ripgrep for 100x faster search.

```python
# circuit_agent/tools/search.py

class FastSearch:
    """High-performance file search using ripgrep."""

    def __init__(self, working_dir: str):
        self.rg_path = shutil.which("rg")
        self.working_dir = working_dir

    async def search(
        self,
        pattern: str,
        file_pattern: str = None,
        case_sensitive: bool = False,
        max_results: int = 100
    ) -> list[SearchResult]:
        """Search files using ripgrep."""
        args = ["rg", "--json", pattern]
        if not case_sensitive:
            args.append("-i")
        if file_pattern:
            args.extend(["-g", file_pattern])
        args.extend(["--max-count", str(max_results)])

        proc = await asyncio.create_subprocess_exec(
            *args,
            cwd=self.working_dir,
            stdout=asyncio.subprocess.PIPE
        )
        # Parse JSON output...
```

**Deliverables:**
- [ ] ripgrep integration with JSON output
- [ ] Fallback to Python for systems without rg
- [ ] Indexed search for huge repositories
- [ ] Real-time search results streaming

---

## Part 3: Developer Experience (High Value)

### 3.1 Plugin System

Allow users to add custom tools without modifying core code.

```python
# ~/.config/circuit-agent/plugins/my_tool.py
from circuit_agent.plugins import Tool, tool

@tool(
    name="deploy",
    description="Deploy to staging or production",
    confirm=True  # Requires user confirmation
)
async def deploy(environment: str, version: str = "latest") -> str:
    """Deploy the application."""
    # Custom deployment logic
    return f"Deployed {version} to {environment}"

# Plugin discovery
# circuit_agent/plugins/loader.py
def load_plugins(plugin_dir: Path) -> list[Tool]:
    """Auto-discover and load plugins."""
    plugins = []
    for file in plugin_dir.glob("*.py"):
        module = importlib.import_module(file.stem)
        for item in dir(module):
            if hasattr(item, "_circuit_tool"):
                plugins.append(item)
    return plugins
```

**Plugin API:**
- [ ] Decorator-based tool definition
- [ ] Automatic parameter extraction from type hints
- [ ] Async/sync tool support
- [ ] Plugin lifecycle hooks (init, cleanup)
- [ ] Plugin configuration system

### 3.2 Custom Commands

Allow project-specific slash commands.

```
# .circuit/commands/test.md
---
name: test
description: Run project tests with coverage
---
Run the test suite with coverage reporting:
1. First run: `pytest --cov=src --cov-report=html`
2. Open coverage report and summarize any uncovered code
3. Suggest tests for uncovered areas

# Usage
> /test
```

**Deliverables:**
- [ ] Command file format (markdown with frontmatter)
- [ ] Command discovery from `.circuit/commands/`
- [ ] Parameter interpolation
- [ ] Command chaining

### 3.3 Hooks System

Execute custom scripts before/after operations.

```json
// .circuit/hooks.json
{
  "pre-commit": "npm run lint && npm run typecheck",
  "post-write": "prettier --write ${file}",
  "pre-command": {
    "pattern": "npm install",
    "script": "echo 'Installing dependencies...'"
  }
}
```

**Hook Points:**
- [ ] pre/post file write
- [ ] pre/post command execution
- [ ] pre/post commit
- [ ] on error
- [ ] on session start/end

### 3.4 Smart Autocomplete

Add intelligent tab completion throughout.

```python
# circuit_agent/completion/
├── __init__.py
├── completer.py        # Main completion engine
├── file_completer.py   # File path completion
├── command_completer.py # Slash command completion
├── git_completer.py    # Git branch/tag completion
└── history_completer.py # Previous command completion

# Integration with prompt_toolkit
from prompt_toolkit import PromptSession
from prompt_toolkit.completion import Completer

session = PromptSession(
    completer=CircuitCompleter(),
    complete_while_typing=True
)
```

**Completions:**
- [ ] File paths (with fuzzy matching)
- [ ] Slash commands and their arguments
- [ ] Git branches and tags
- [ ] Previous messages
- [ ] Environment variables

---

## Part 4: Advanced Features

### 4.1 Background Tasks

Run long operations without blocking.

```python
# Background task management
class TaskManager:
    """Manage background operations."""

    async def run_background(
        self,
        name: str,
        coro: Coroutine,
        on_progress: Callable = None
    ) -> Task:
        """Start a background task."""
        task = asyncio.create_task(coro)
        self._tasks[name] = task
        return task

    def list_tasks(self) -> list[TaskInfo]:
        """List all running tasks."""
        return [
            TaskInfo(name=k, status=v.done())
            for k, v in self._tasks.items()
        ]

# Usage
> Run tests in background
Agent: I'll run the tests in the background.
  [Background] test-suite started (ID: abc123)

> What's running?
Agent: Currently running:
  - test-suite (abc123): Running... 45s elapsed
```

**Features:**
- [ ] Task lifecycle management
- [ ] Progress reporting
- [ ] Task cancellation
- [ ] Output streaming
- [ ] Task persistence across sessions

### 4.2 Diff Viewer & Merge Tool

Visual diff for file changes.

```python
# circuit_agent/diff/
├── __init__.py
├── differ.py           # Diff generation (unified, split)
├── patcher.py          # Apply patches
├── conflict.py         # Merge conflict resolution
└── viewer.py           # TUI diff viewer

class DiffViewer:
    """Interactive diff viewer."""

    def show_diff(
        self,
        old: str,
        new: str,
        path: str,
        mode: Literal["unified", "split", "inline"] = "unified"
    ) -> None:
        """Display diff with syntax highlighting."""

    def interactive_review(
        self,
        changes: list[FileChange]
    ) -> list[ApprovalDecision]:
        """Review multiple changes interactively."""
```

**Features:**
- [ ] Syntax-highlighted diffs
- [ ] Side-by-side comparison
- [ ] Inline change preview
- [ ] Batch approval/rejection
- [ ] Partial acceptance (select hunks)

### 4.3 Workspace Understanding

Build a semantic model of the codebase.

```python
# circuit_agent/workspace/
├── __init__.py
├── indexer.py          # Code indexer (tree-sitter)
├── symbols.py          # Symbol extraction
├── graph.py            # Dependency graph
├── cache.py            # Persistent cache
└── query.py            # Semantic queries

class WorkspaceIndex:
    """Semantic understanding of the codebase."""

    def get_symbol(self, name: str) -> Symbol | None:
        """Find a symbol by name."""

    def get_references(self, symbol: Symbol) -> list[Reference]:
        """Find all references to a symbol."""

    def get_dependencies(self, file: Path) -> list[Dependency]:
        """Get file dependencies."""

    def search_semantic(self, query: str) -> list[SearchResult]:
        """Semantic code search."""

# Usage in agent
"Where is the User class defined?"
→ Instantly returns: src/models/user.py:15 (class User)

"What calls the authenticate function?"
→ Returns all callers with context
```

**Indexing Features:**
- [ ] Tree-sitter parsing for 20+ languages
- [ ] Symbol extraction (classes, functions, variables)
- [ ] Import/dependency tracking
- [ ] Incremental updates on file change
- [ ] Persistent SQLite cache

### 4.4 Multi-Agent Orchestration

Spawn sub-agents for complex tasks.

```python
class AgentOrchestrator:
    """Coordinate multiple agent instances."""

    async def spawn_agent(
        self,
        task: str,
        working_dir: str = None,
        tools: list[str] = None,
        max_iterations: int = 10
    ) -> AgentResult:
        """Spawn a sub-agent for a specific task."""

    async def parallel_tasks(
        self,
        tasks: list[AgentTask]
    ) -> list[AgentResult]:
        """Run multiple agents in parallel."""

# Usage
> Refactor the entire auth module
Agent: This is a large task. I'll coordinate multiple sub-agents:

  [Agent 1] Analyzing current auth implementation...
  [Agent 2] Researching best practices for JWT auth...
  [Agent 3] Creating migration plan...

  All agents complete. Summary:
  - Current: Session-based auth
  - Proposed: JWT with refresh tokens
  - Files affected: 12
  - Shall I proceed with the refactor?
```

---

## Part 5: IDE Enhancements

### 5.1 TUI Improvements

Make the Textual IDE fully functional.

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Circuit IDE v6.0                    [main] ●3 ↑2  📊 15.2k tokens $0.23│
├────────────────┬────────────────────────────────────────────────────────┤
│ EXPLORER       │ src/app.py                              ⚡ Ln 45, Col 12│
│ ─────────────  │ ────────────────────────────────────────────────────── │
│ 📁 src/        │  43│ class Application:                                │
│   📄 app.py  ●│  44│     """Main application class."""                 │
│   📄 auth.py   │  45│     def __init__(self, config: Config):          │
│   📁 models/   │  46│         self.config = config                     │
│                │  47│         self.db = Database(config.db_url)        │
│ ─────────────  │                                                        │
│ SEARCH         │ ────────────────────────────────────────────────────── │
│ > auth         │  CHAT                                                  │
│   auth.py:12   │  You: Add input validation to the login endpoint      │
│   app.py:89    │                                                        │
│                │  Agent: I'll add validation using Pydantic models...  │
│ ─────────────  │  [edit_file] src/auth.py ✓                            │
│ GIT CHANGES    │  [run_command] pytest tests/test_auth.py ✓            │
│   M auth.py    │                                                        │
│   A models.py  │  Done! Added LoginRequest model with validation.      │
├────────────────┴────────────────────────────────────────────────────────┤
│ TERMINAL ──────────────────────────────────────────────────────────────│
│ $ pytest tests/ -v                                                      │
│ ========================= 12 passed in 2.3s =========================  │
└─────────────────────────────────────────────────────────────────────────┘
│ F1 Help │ F2 Files │ F3 Editor │ F4 Chat │ F5 Term │ Ctrl+K Commands   │
```

**New Features:**
- [ ] Command palette (Ctrl+K)
- [ ] Quick open (Ctrl+P)
- [ ] Find & replace
- [ ] Multi-cursor editing
- [ ] Split panes
- [ ] Git status in sidebar
- [ ] Modified file indicators
- [ ] Breadcrumb navigation

### 5.2 GUI Enhancements

Make the Qt GUI production-ready.

**Features:**
- [ ] File change detection & auto-reload
- [ ] Multi-file diff viewer
- [ ] Integrated terminal (xterm.js or similar)
- [ ] Project-wide search
- [ ] Settings UI with persistence
- [ ] Theme customization
- [ ] Window state persistence
- [ ] Drag-and-drop file support

### 5.3 VS Code Extension

Create a VS Code extension using MCP.

```typescript
// vscode-circuit/
├── package.json
├── src/
│   ├── extension.ts      # Extension entry point
│   ├── mcp-client.ts     # MCP connection
│   ├── chat-panel.ts     # Webview chat UI
│   └── commands.ts       # VS Code commands
└── webview/
    └── chat/             # React chat UI
```

**Features:**
- [ ] Chat sidebar with streaming
- [ ] Inline code suggestions
- [ ] File operation approvals
- [ ] Status bar with token count
- [ ] Keyboard shortcuts

---

## Part 6: Infrastructure

### 6.1 Documentation Site

Build comprehensive docs with MkDocs.

```
docs/
├── index.md              # Overview
├── getting-started/
│   ├── installation.md
│   ├── configuration.md
│   └── first-project.md
├── guides/
│   ├── cli-usage.md
│   ├── ide-guide.md
│   ├── writing-plugins.md
│   └── mcp-integration.md
├── reference/
│   ├── tools.md
│   ├── commands.md
│   ├── api.md
│   └── configuration.md
├── development/
│   ├── architecture.md
│   ├── contributing.md
│   └── testing.md
└── changelog.md
```

**Deliverables:**
- [ ] MkDocs setup with Material theme
- [ ] Auto-generated API docs from docstrings
- [ ] Search functionality
- [ ] Version selector
- [ ] GitHub Pages deployment

### 6.2 CI/CD Pipeline

Comprehensive automation.

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python: ["3.10", "3.11", "3.12"]
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python }}
      - name: Install dependencies
        run: pip install -e ".[dev]"
      - name: Run tests
        run: pytest --cov --cov-report=xml
      - name: Upload coverage
        uses: codecov/codecov-action@v4

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run ruff
        run: ruff check .
      - name: Run mypy
        run: mypy circuit_agent

  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run bandit
        run: bandit -r circuit_agent
      - name: Run safety
        run: safety check
```

**Pipelines:**
- [ ] Test on Python 3.10, 3.11, 3.12
- [ ] Lint with ruff
- [ ] Type check with mypy
- [ ] Security scan with bandit
- [ ] Dependency audit with safety
- [ ] Coverage reporting
- [ ] Auto-release on tag

### 6.3 Package Distribution

Publish to PyPI.

```toml
# pyproject.toml updates
[project]
name = "circuit-agent"
version = "6.0.0"
description = "AI coding assistant for Cisco Circuit"
readme = "README.md"
license = {text = "MIT"}
requires-python = ">=3.10"
classifiers = [
    "Development Status :: 4 - Beta",
    "Environment :: Console",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
]

[project.optional-dependencies]
tui = ["textual>=0.47.0", "rich>=13.0.0"]
gui = ["PySide6>=6.6.0"]
all = ["circuit-agent[tui,gui]"]
```

**Deliverables:**
- [ ] PyPI package publishing
- [ ] Homebrew formula
- [ ] Binary releases (PyInstaller)
- [ ] Docker image
- [ ] Version management with bump2version

---

## Implementation Timeline

### Phase 1: Foundation (Weeks 1-2)
- [ ] Test suite setup
- [ ] SSL verification fix
- [ ] Secure credential storage
- [ ] Type hints throughout
- [ ] CI pipeline

### Phase 2: Core Features (Weeks 3-6)
- [ ] Unified service layer
- [ ] MCP support (basic)
- [ ] Vision/image support
- [ ] Fast search (ripgrep)
- [ ] Plugin system (basic)

### Phase 3: Developer Experience (Weeks 7-10)
- [ ] Custom commands
- [ ] Hooks system
- [ ] Smart autocomplete
- [ ] Background tasks
- [ ] Diff viewer

### Phase 4: Advanced Features (Weeks 11-14)
- [ ] Workspace indexing
- [ ] Multi-agent orchestration
- [ ] Full MCP implementation
- [ ] Advanced plugin API

### Phase 5: Polish (Weeks 15-16)
- [ ] TUI improvements
- [ ] GUI enhancements
- [ ] Documentation site
- [ ] Performance optimization
- [ ] Public release

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Test Coverage | 80%+ |
| Type Coverage | 95%+ |
| Documentation | 100% public APIs |
| Security Issues | 0 critical/high |
| User Satisfaction | 4.5+ stars |
| Performance | <100ms response time |
| Plugin Ecosystem | 10+ community plugins |

---

## Conclusion

This plan transforms Circuit Agent from a working prototype into a world-class AI coding assistant. The key differentiators will be:

1. **Open & Extensible** - Plugin system and MCP support
2. **Secure** - Proper credential handling, audit logging
3. **Fast** - ripgrep search, workspace indexing
4. **Visual** - Professional TUI/GUI interfaces
5. **Enterprise-Ready** - CI/CD mode, hooks, permissions

By implementing these improvements systematically, Circuit Agent will become the preferred AI coding assistant for teams using Cisco infrastructure and beyond.


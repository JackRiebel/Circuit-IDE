# Circuit Agent v3.0 - Enhancement Plan

## Current State (v2.0)

### Metrics
- **6 modules**, ~2,200 lines of code
- **11 tools**: File ops (6) + Git ops (5)
- **Single-threaded**: One agent, sequential tool execution

### What v2.0 Does Well
- Streaming responses with real-time output
- Git integration (status, diff, log, commit, branch)
- Auto-approve mode for faster workflows
- Retry logic with exponential backoff
- Smart error messages with suggestions
- Undo/backup system
- CIRCUIT.md project configuration

### Current Limitations
1. **Single agent** - Can only do one thing at a time
2. **No parallelism** - Sequential tool execution
3. **No web access** - Can't fetch docs or APIs
4. **No memory** - Forgets everything between sessions
5. **No planning** - Dives straight into execution
6. **Limited context** - No compaction for long conversations
7. **No task tracking** - User can't see progress on complex tasks
8. **No code analysis** - Treats code as plain text

---

## v3.0 Vision: Multi-Agent Architecture

Transform from a single agent into an **orchestrated multi-agent system** where specialized agents work in parallel on different aspects of a task.

```
┌─────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR AGENT                       │
│         (Plans, delegates, coordinates, synthesizes)        │
└─────────────────────────────────────────────────────────────┘
           │              │              │              │
           ▼              ▼              ▼              ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
    │  CODER   │   │ REVIEWER │   │ RESEARCH │   │  TESTER  │
    │  AGENT   │   │  AGENT   │   │  AGENT   │   │  AGENT   │
    └──────────┘   └──────────┘   └──────────┘   └──────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
    File ops,      Code review,   Web fetch,     Run tests,
    Git ops        Suggestions    Docs lookup    Analyze output
```

---

## Phase 1: Foundation (High Priority)

### 1.1 Parallel Tool Execution
**Why**: Speed up multi-file operations dramatically

```python
# Before: Sequential (slow)
for file in files:
    result = read_file(file)  # Wait for each

# After: Parallel (fast)
results = await asyncio.gather(*[read_file(f) for f in files])
```

**Implementation**:
- Add `parallel_execute()` method to ToolExecutor
- Agent detects independent operations and batches them
- Show parallel progress indicators

### 1.2 Web Fetch Tool
**Why**: Look up documentation, APIs, error messages

```python
{
    "name": "web_fetch",
    "description": "Fetch content from a URL (documentation, APIs, etc.)",
    "parameters": {
        "url": "URL to fetch",
        "selector": "Optional CSS selector to extract specific content"
    }
}
```

**Implementation**:
- Use httpx for async fetching
- HTML to markdown conversion (html2text or similar)
- Content truncation for large pages
- Cache results to avoid refetching

### 1.3 Web Search Tool
**Why**: Find solutions to errors, discover libraries, research approaches

```python
{
    "name": "web_search",
    "description": "Search the web for information",
    "parameters": {
        "query": "Search query",
        "num_results": "Number of results (default 5)"
    }
}
```

**Implementation**:
- Use DuckDuckGo API (no key required) or similar
- Return title, URL, snippet for each result
- Agent can then use web_fetch on promising results

### 1.4 Session Persistence
**Why**: Resume work across sessions, remember context

```python
# Save session
/save [name]           # Save current conversation
/load [name]           # Load a saved session
/sessions              # List all saved sessions
```

**Implementation**:
- Store in `~/.config/circuit-agent/sessions/`
- Save: history, model, auto_approve state, working_dir
- Auto-save on exit option
- Session naming with timestamps

### 1.5 Context Compaction
**Why**: Handle long conversations without losing context

```python
/compact               # Summarize and compress history
```

**Implementation**:
- Use the LLM to summarize older messages
- Keep recent messages intact
- Store compacted summary as system message
- Track token usage and auto-suggest compaction

---

## Phase 2: Multi-Agent System (Medium Priority)

### 2.1 Sub-Agent Architecture
**Why**: Parallel specialized work, better at complex tasks

```python
class SubAgent:
    """Lightweight agent for specific tasks."""
    def __init__(self, name: str, specialty: str, tools: List[str]):
        self.name = name
        self.specialty = specialty
        self.allowed_tools = tools

    async def execute(self, task: str) -> str:
        # Run with limited tool set and focused prompt
        pass
```

**Agent Types**:
| Agent | Tools | Purpose |
|-------|-------|---------|
| Coder | read, write, edit | Write and modify code |
| Reviewer | read, search | Review code, find issues |
| Researcher | web_search, web_fetch | Look up docs and solutions |
| Tester | read, run_command | Run tests, analyze results |
| Git Agent | git_* | Handle version control |

### 2.2 Orchestrator Agent
**Why**: Coordinate sub-agents for complex tasks

```python
class OrchestratorAgent:
    """Plans and coordinates sub-agents."""

    async def plan(self, task: str) -> List[SubTask]:
        # Break task into sub-tasks
        pass

    async def execute_plan(self, subtasks: List[SubTask]) -> str:
        # Run sub-agents in parallel where possible
        # Synthesize results
        pass
```

**Example Flow**:
```
User: "Add user authentication to the app"

Orchestrator Plan:
1. [Researcher] Look up best practices for auth in this framework
2. [Coder] Read existing code structure
3. [Coder] Implement auth module (parallel with step 1-2 results)
4. [Reviewer] Review the implementation
5. [Tester] Run tests
6. [Git Agent] Commit if tests pass
```

### 2.3 Task Queue & Progress
**Why**: Track complex multi-step operations

```python
@dataclass
class Task:
    id: str
    description: str
    status: Literal["pending", "running", "done", "failed"]
    agent: str
    result: Optional[str]
```

**Commands**:
```
/tasks               # Show current task queue
/task <id>           # Show details of specific task
```

**Display**:
```
┌─────────────────────────────────────────┐
│ Task: Add user authentication           │
├─────────────────────────────────────────┤
│ ✓ Research auth patterns      [Researcher]
│ ✓ Read existing code          [Coder]
│ ● Implement auth module       [Coder]
│ ○ Review implementation       [Reviewer]
│ ○ Run tests                   [Tester]
│ ○ Commit changes              [Git Agent]
└─────────────────────────────────────────┘
```

---

## Phase 3: Intelligence Upgrades (Medium Priority)

### 3.1 Code-Aware Tools
**Why**: Better understanding of code structure

```python
{
    "name": "analyze_code",
    "description": "Analyze code structure - functions, classes, imports",
    "parameters": {
        "path": "File to analyze",
        "include": ["functions", "classes", "imports", "dependencies"]
    }
}
```

**Implementation**:
- Use tree-sitter for parsing (Python, JS, TS, Go, Rust)
- Extract: function signatures, class hierarchies, imports
- Build dependency graph
- Find usages of symbols

### 3.2 Project Memory
**Why**: Remember project-specific knowledge across sessions

```python
/remember <fact>      # Store a fact about this project
/memories             # Show all memories
/forget <id>          # Remove a memory
```

**Storage**: `.circuit/memory.json` in project root

**Auto-memories**:
- Test commands that work
- Build commands
- Common file patterns
- Coding conventions observed

### 3.3 Planning Mode
**Why**: Think before acting on complex tasks

```python
/plan                 # Enter planning mode
```

**In Planning Mode**:
1. Agent analyzes the task
2. Creates a structured plan
3. Identifies risks and dependencies
4. Asks clarifying questions
5. User approves before execution

### 3.4 Diff Preview Mode
**Why**: See all changes before applying

```python
/preview              # Enable preview mode
```

**Behavior**:
- All edits shown as diffs but not applied
- User reviews all changes
- Apply all with single confirmation
- Or selectively apply/reject

---

## Phase 4: Advanced Features (Lower Priority)

### 4.1 Headless/CI Mode
**Why**: Use in scripts and automation

```bash
# Single prompt, auto-approve
circuit-agent -p "Fix all type errors" --auto

# JSON output for parsing
circuit-agent -p "List TODO comments" --json

# Pipe input
cat error.log | circuit-agent -p "Explain this error"
```

### 4.2 Watch Mode
**Why**: Continuous assistance during development

```python
/watch                # Watch for file changes
```

**Behavior**:
- Monitor file changes
- Auto-run tests on save
- Suggest fixes for errors
- Keep context updated

### 4.3 Custom Tool Plugins
**Why**: Extend with project-specific tools

```python
# .circuit/tools/deploy.py
def deploy_to_staging():
    """Deploy current branch to staging environment."""
    # Custom implementation
```

**Auto-discovered** from `.circuit/tools/`

### 4.4 Voice Input
**Why**: Hands-free coding assistance

- Whisper API integration
- Push-to-talk or wake word
- Voice confirmation for actions

---

## New File Structure (v3.0)

```
circuit_agent/
├── __init__.py
├── agent.py              # Main agent (becomes orchestrator)
├── cli.py                # CLI commands
├── config.py             # Configuration
├── tools/                # Tool implementations
│   ├── __init__.py
│   ├── file_tools.py     # read, write, edit, list, search
│   ├── git_tools.py      # git_*, branch operations
│   ├── web_tools.py      # web_fetch, web_search
│   ├── code_tools.py     # analyze_code, find_usages
│   └── executor.py       # ToolExecutor with parallel support
├── agents/               # Sub-agent implementations
│   ├── __init__.py
│   ├── base.py           # BaseAgent class
│   ├── coder.py          # CoderAgent
│   ├── reviewer.py       # ReviewerAgent
│   ├── researcher.py     # ResearcherAgent
│   ├── tester.py         # TesterAgent
│   └── orchestrator.py   # OrchestratorAgent
├── memory/               # Persistence
│   ├── __init__.py
│   ├── session.py        # Session save/load
│   ├── project.py        # Project memory
│   └── compaction.py     # Context compaction
├── streaming.py          # SSE parsing
└── ui/                   # User interface
    ├── __init__.py
    ├── colors.py         # Terminal colors
    ├── display.py        # Output formatting
    ├── progress.py       # Progress indicators
    └── task_view.py      # Task queue display
```

---

## Implementation Priority

### Must Have (v3.0 Core)
| Feature | Effort | Impact |
|---------|--------|--------|
| Parallel tool execution | Medium | High |
| Web fetch tool | Low | High |
| Session persistence | Low | Medium |
| Context compaction | Medium | High |

### Should Have (v3.1)
| Feature | Effort | Impact |
|---------|--------|--------|
| Sub-agent architecture | High | Very High |
| Web search tool | Low | Medium |
| Task queue & progress | Medium | Medium |
| Planning mode | Medium | High |

### Nice to Have (v3.2+)
| Feature | Effort | Impact |
|---------|--------|--------|
| Code analysis tools | High | High |
| Project memory | Medium | Medium |
| Headless/CI mode | Medium | Medium |
| Watch mode | Medium | Medium |
| Custom plugins | High | Medium |

---

## Dependencies to Add

```
# Required for v3.0
html2text>=2020.1.16    # HTML to markdown for web_fetch

# Optional but recommended
tree-sitter>=0.20       # Code parsing for analyze_code
rich>=13.0              # Better terminal UI
duckduckgo-search>=3.0  # Web search without API key
```

---

## Migration Path

### v2.0 → v3.0
1. No breaking changes to CLI
2. Existing CIRCUIT.md works unchanged
3. Saved credentials still valid
4. New features are opt-in

### Backwards Compatibility
- All v2.0 commands continue to work
- Single-agent mode remains default
- Multi-agent activated with `/agents on` or complex tasks

---

## Success Metrics

### Performance
- [ ] 3x faster on multi-file operations (parallel tools)
- [ ] Handle 10x longer conversations (compaction)
- [ ] 90% session resumption success rate

### Capability
- [ ] Can research and implement features without manual doc lookup
- [ ] Can run multiple sub-tasks in parallel
- [ ] Provides progress visibility on complex tasks

### Quality
- [ ] Code review catches common issues
- [ ] Test runner validates changes before commit
- [ ] Planning mode reduces wasted iterations

---

## Questions to Decide

1. **Default mode**: Single agent or orchestrator?
2. **Sub-agent models**: Same model or allow mixing (e.g., mini for research)?
3. **Memory scope**: Per-project only or global patterns?
4. **Plugin format**: Python files or JSON config?
5. **Watch mode**: File-only or include test output?

---

## Next Steps

1. **Implement Phase 1** - Foundation features
2. **Test thoroughly** - Ensure v2.0 compatibility
3. **Design sub-agent prompts** - Critical for multi-agent success
4. **Build task queue UI** - User needs visibility
5. **Document new features** - Update all .md files

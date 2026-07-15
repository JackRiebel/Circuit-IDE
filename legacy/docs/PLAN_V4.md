# Circuit Agent v4.0 - Comprehensive Enhancement Plan

## Executive Summary

Transform Circuit Agent from a capable coding assistant into an **enterprise-grade agentic system** with advanced reasoning, parallel execution, intelligent context management, and extensibility. This plan covers both user-facing features and internal improvements that enhance the agent's capabilities.

---

## Current State Analysis (v3.0)

### What Works Well
- Modular tool architecture (file, git, web tools)
- Streaming responses with token tracking
- Session persistence and context compaction
- Safety features (confirmations, path traversal protection)
- CIRCUIT.md project configuration
- Undo/backup functionality
- Web fetch and search capabilities

### Critical Gaps Identified

| Category | Gap | Impact |
|----------|-----|--------|
| **Execution** | Sequential tool execution only | Slow for multi-file operations |
| **Intelligence** | No reasoning/planning display | User can't see agent thinking |
| **Context** | Simple compaction, no smart management | Context wasted on irrelevant info |
| **Extensibility** | No plugin/MCP support | Can't extend capabilities |
| **CI/Automation** | Interactive-only mode | Can't use in pipelines |
| **Code Understanding** | Text-based editing only | Error-prone, no AST awareness |
| **UX** | No syntax highlighting, tab completion | Poor developer experience |
| **Multimodal** | No image support | Can't process screenshots/diagrams |

---

## Phase 1: Core Intelligence Improvements (High Impact)

### 1.1 Parallel Tool Execution
**Why**: Multi-file operations are 3-5x faster with parallel execution.

The `ToolExecutor` class already has parallel support but isn't used. Enable it.

```python
# In agent.py - Process independent tool calls in parallel
async def _process_tool_calls_parallel(self, tool_calls: list) -> list:
    """Process multiple tool calls in parallel when possible."""
    # Identify independent calls (reads, searches can run in parallel)
    independent = [tc for tc in tool_calls if self._is_read_only_tool(tc)]
    dependent = [tc for tc in tool_calls if not self._is_read_only_tool(tc)]

    # Run independent calls in parallel
    if independent:
        results = await asyncio.gather(*[
            self._process_single_tool(tc) for tc in independent
        ])

    # Run dependent calls sequentially
    for tc in dependent:
        await self._process_single_tool(tc)
```

**Implementation**:
- Add tool dependency analysis
- Parallelize read_file, search_files, list_files, git_status, git_diff, git_log, web_fetch, web_search
- Keep write operations sequential for safety

### 1.2 Thinking/Reasoning Display
**Why**: Users need to understand the agent's decision-making process.

Add a "thinking" mode that shows the agent's reasoning before actions.

```python
# New system prompt addition
THINKING_PROMPT = """
Before taking any action, briefly explain your reasoning using this format:

<thinking>
- What I understand about the request
- What I need to do
- What tools I'll use and why
- Potential issues to watch for
</thinking>

Then proceed with the actions.
"""
```

**Features**:
- Toggle with `/think on|off` command
- Collapsible thinking blocks in terminal
- Option to log thinking to file for complex tasks

### 1.3 Smart Context Management
**Why**: 120K+ tokens available but often wasted on irrelevant context.

```python
class SmartContextManager:
    """Intelligently manages what stays in context."""

    def __init__(self, max_tokens: int = 100000):
        self.max_tokens = max_tokens
        self.priority_files = set()  # Files actively being worked on
        self.relevance_scores = {}   # Track message relevance

    def add_to_context(self, content: str, priority: int = 5):
        """Add content with priority scoring."""
        pass

    def get_optimized_context(self) -> List[Dict]:
        """Return context optimized for current task."""
        # Keep: Recent messages, relevant tool results, active files
        # Compress: Old summaries, large unchanged files
        # Drop: Repetitive errors, superseded file versions
        pass
```

**Strategies**:
- **Priority Queue**: Recent and task-relevant content stays
- **File Deduplication**: Only keep latest version of each file
- **Error Compression**: Summarize repetitive error messages
- **Selective Loading**: Load file sections on-demand, not entire files

### 1.4 LLM-Based Context Compaction
**Why**: Simple text summarization loses important details.

```python
async def smart_compact(self, history: List[Dict]) -> List[Dict]:
    """Use the LLM to create intelligent summaries."""
    prompt = """
    Summarize this conversation history, preserving:
    1. All file paths and their current state (created/modified/deleted)
    2. Key decisions made and why
    3. Any errors encountered and how they were resolved
    4. Current task state and next steps
    5. User preferences and coding style observed

    Be extremely concise but don't lose critical technical details.
    """
    # Use a smaller/faster model for summarization
    summary = await self._call_model(prompt, model="gpt-4o-mini")
    return [{"role": "system", "content": f"[SESSION SUMMARY]\n{summary}"}]
```

---

## Phase 2: Advanced Tool Capabilities (High Impact)

### 2.1 AST-Aware Editing
**Why**: Text-based editing is error-prone. AST editing is precise and reliable.

```python
# New tool definition
{
    "name": "edit_symbol",
    "description": "Edit a function, class, or method by name. More reliable than text matching.",
    "parameters": {
        "path": "File path",
        "symbol_type": "function|class|method",
        "symbol_name": "Name of the symbol to edit",
        "new_code": "Complete new implementation",
        "action": "replace|insert_before|insert_after|delete"
    }
}
```

**Implementation options**:
1. **tree-sitter** (recommended) - Fast, multi-language, no runtime dependency
2. **Python ast module** - Built-in for Python files
3. **TypeScript compiler API** - For JS/TS files

**Supported operations**:
- Find function/class/method by name
- Replace entire implementation
- Insert code before/after symbol
- Rename symbols across file
- Extract function parameters and return type

### 2.2 Multi-File Batch Operations
**Why**: Common operations like renaming or updating imports affect many files.

```python
# New tool definitions
{
    "name": "batch_edit",
    "description": "Apply the same text replacement across multiple files matching a pattern.",
    "parameters": {
        "file_pattern": "Glob pattern (e.g., 'src/**/*.py')",
        "old_text": "Text to find",
        "new_text": "Replacement text",
        "preview": "If true, show changes without applying (default true)"
    }
},
{
    "name": "batch_rename",
    "description": "Rename a symbol across the entire codebase.",
    "parameters": {
        "old_name": "Current name",
        "new_name": "New name",
        "scope": "file|directory|project"
    }
}
```

### 2.3 Code Analysis Tools
**Why**: Understanding code structure enables better assistance.

```python
# New tools for code intelligence
{
    "name": "find_references",
    "description": "Find all references to a symbol in the codebase.",
    "parameters": {
        "symbol": "Name of function, class, or variable",
        "file_pattern": "Optional: Limit search to matching files"
    }
},
{
    "name": "get_symbol_info",
    "description": "Get information about a code symbol (function signature, docstring, etc.)",
    "parameters": {
        "path": "File path",
        "symbol": "Symbol name",
        "include_references": "Whether to include usage references"
    }
},
{
    "name": "analyze_imports",
    "description": "Analyze import structure of a file or project.",
    "parameters": {
        "path": "File or directory path",
        "find_unused": "Whether to identify unused imports",
        "find_circular": "Whether to detect circular dependencies"
    }
}
```

### 2.4 Enhanced Web Tools
**Why**: More reliable and comprehensive web access.

```python
# Improvements to web_fetch
- Add support for JavaScript-rendered pages (optional Playwright/Selenium)
- Add PDF extraction support
- Add RSS/Atom feed parsing
- Better CSS selector support (full BeautifulSoup integration)
- Support for API authentication (headers, tokens)

# New web tools
{
    "name": "github_fetch",
    "description": "Fetch GitHub PR, issue, or file content directly.",
    "parameters": {
        "url": "GitHub URL (PR, issue, file, or repo)",
        "include_comments": "For PRs/issues, include discussion",
        "include_diff": "For PRs, include the diff"
    }
},
{
    "name": "api_request",
    "description": "Make an API request with custom headers and authentication.",
    "parameters": {
        "url": "API endpoint URL",
        "method": "GET|POST|PUT|DELETE",
        "headers": "Custom headers dict",
        "body": "Request body for POST/PUT",
        "auth_type": "none|bearer|basic|api_key"
    }
}
```

### 2.5 Image/Multimodal Support
**Why**: Screenshots, diagrams, and error images are common in development.

```python
# Multimodal message support
{
    "name": "analyze_image",
    "description": "Analyze an image file (screenshot, diagram, error, etc.)",
    "parameters": {
        "path": "Path to image file (PNG, JPG, GIF, WebP)",
        "prompt": "What to look for or analyze in the image"
    }
}

# Implementation
async def analyze_image(self, args: dict) -> str:
    path = args.get("path")
    prompt = args.get("prompt", "Describe this image in detail.")

    # Read and base64 encode image
    with open(path, "rb") as f:
        image_data = base64.b64encode(f.read()).decode()

    # Send multimodal request to GPT-4o
    messages = [{
        "role": "user",
        "content": [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {
                "url": f"data:image/png;base64,{image_data}"
            }}
        ]
    }]
    # Process with vision-capable model
```

---

## Phase 3: Operational Modes (Medium-High Impact)

### 3.1 Headless/CI Mode
**Why**: Enable automation, scripting, and CI/CD integration.

```bash
# Single prompt execution
circuit-agent -p "Fix all TypeScript errors in src/"

# With auto-approve for CI
circuit-agent -p "Run tests and fix failures" --auto-approve

# JSON output for scripting
circuit-agent -p "List all TODO comments" --output json

# Pipe input
cat error.log | circuit-agent -p "Explain this error and suggest a fix"

# File-based prompts
circuit-agent --prompt-file task.md --auto-approve

# Diff-only mode (just show what would change)
circuit-agent -p "Refactor auth module" --dry-run
```

**Implementation**:
```python
# cli.py additions
@click.command()
@click.option('-p', '--prompt', help='Single prompt to execute')
@click.option('--auto-approve', is_flag=True, help='Skip all confirmations')
@click.option('--output', type=click.Choice(['text', 'json', 'markdown']))
@click.option('--prompt-file', type=click.Path(exists=True))
@click.option('--dry-run', is_flag=True, help='Show changes without applying')
@click.option('--max-iterations', default=25, help='Max tool call iterations')
def main(prompt, auto_approve, output, prompt_file, dry_run, max_iterations):
    if prompt or prompt_file:
        run_headless(prompt or Path(prompt_file).read_text(),
                    auto_approve, output, dry_run, max_iterations)
    else:
        run_interactive()
```

### 3.2 Plan Mode
**Why**: Complex tasks benefit from explicit planning and user approval.

```python
PLAN_PROMPT = """
When I ask you to plan something, create a structured plan:

## Plan: [Task Name]

### Overview
[1-2 sentence summary]

### Steps
1. [ ] Step description
   - Details and considerations
2. [ ] Next step
   ...

### Files to Modify
- `path/to/file.py` - What changes
- ...

### Risks & Considerations
- Potential issues to watch for

### Estimated Complexity
[Low/Medium/High] - Brief justification

---
Proceed with this plan? [y/N/edit]
"""
```

**Features**:
- `/plan <task>` - Enter planning mode
- Generate structured plan before execution
- User can approve, reject, or edit plan
- Plan saved to PLAN.md automatically
- Checkpoints after each major step

### 3.3 Watch Mode
**Why**: React to file changes for continuous development assistance.

```python
{
    "name": "watch_files",
    "description": "Watch files for changes and react to them.",
    "parameters": {
        "patterns": ["**/*.py", "**/*.ts"],
        "on_change": "run_tests|lint|typecheck|custom",
        "custom_command": "Optional command to run on changes"
    }
}

# Implementation using watchdog library
class FileWatcher:
    def __init__(self, patterns: List[str], callback):
        self.observer = Observer()
        self.patterns = patterns
        self.callback = callback

    def start(self):
        handler = PatternMatchingEventHandler(patterns=self.patterns)
        handler.on_modified = self._on_change
        self.observer.schedule(handler, '.', recursive=True)
        self.observer.start()
```

### 3.4 Interactive Diff Mode
**Why**: Git-style interactive staging for fine-grained control.

```python
# For git commits, allow interactive hunk selection
def interactive_stage(self, path: str):
    """Allow user to selectively stage hunks."""
    diff = self._get_diff(path)
    hunks = self._parse_hunks(diff)

    for i, hunk in enumerate(hunks):
        print(f"\n{C.CYAN}Hunk {i+1}/{len(hunks)}:{C.RESET}")
        print(hunk.display())

        choice = input("[y]es/[n]o/[s]plit/[q]uit: ")
        if choice == 'y':
            self._stage_hunk(path, hunk)
        elif choice == 's':
            sub_hunks = hunk.split()
            # Recurse on sub-hunks
```

---

## Phase 4: Extensibility & Integration (Medium Impact)

### 4.1 Plugin System
**Why**: Allow users to add custom tools without modifying core code.

```python
# Plugin structure
~/.config/circuit-agent/plugins/
├── my_plugin/
│   ├── __init__.py      # Plugin entry point
│   ├── tools.py         # Tool definitions
│   └── plugin.json      # Metadata

# plugin.json
{
    "name": "my_plugin",
    "version": "1.0.0",
    "description": "Custom tools for my workflow",
    "author": "User",
    "tools": ["custom_deploy", "run_pipeline"]
}

# Plugin loader
class PluginManager:
    def __init__(self, plugins_dir: str):
        self.plugins_dir = Path(plugins_dir)
        self.loaded_plugins = {}

    def load_all(self) -> List[Dict]:
        """Load all plugins and return combined tool definitions."""
        tools = []
        for plugin_dir in self.plugins_dir.iterdir():
            if plugin_dir.is_dir() and (plugin_dir / "plugin.json").exists():
                plugin = self._load_plugin(plugin_dir)
                tools.extend(plugin.get_tools())
        return tools
```

### 4.2 MCP (Model Context Protocol) Support
**Why**: Connect to external tool servers for expanded capabilities.

```python
# MCP client implementation
class MCPClient:
    """Connect to MCP-compatible tool servers."""

    async def connect(self, server_url: str):
        """Connect to an MCP server."""
        self.ws = await websockets.connect(server_url)
        await self._handshake()

    async def list_tools(self) -> List[Dict]:
        """Get available tools from server."""
        response = await self._send({"method": "tools/list"})
        return response["tools"]

    async def call_tool(self, name: str, args: dict) -> Any:
        """Call a tool on the MCP server."""
        response = await self._send({
            "method": "tools/call",
            "params": {"name": name, "arguments": args}
        })
        return response["result"]
```

**Configuration**:
```json
// ~/.config/circuit-agent/mcp.json
{
    "servers": [
        {
            "name": "database",
            "url": "ws://localhost:8080/mcp",
            "tools": ["query_db", "schema_info"]
        },
        {
            "name": "kubernetes",
            "url": "ws://localhost:8081/mcp",
            "tools": ["kubectl", "helm"]
        }
    ]
}
```

### 4.3 Custom Commands/Skills
**Why**: Let users define reusable command sequences.

```markdown
<!-- ~/.config/circuit-agent/commands/deploy.md -->
# Deploy Command

## Trigger
/deploy [environment]

## Steps
1. Run tests: `npm test`
2. Build: `npm run build`
3. If environment is "prod":
   - Require confirmation
   - Run: `./scripts/deploy-prod.sh`
4. Else:
   - Run: `./scripts/deploy-{environment}.sh`

## Success Message
Deployed to {environment} successfully!
```

```python
class CustomCommand:
    """Load and execute custom command definitions."""

    @classmethod
    def from_markdown(cls, path: Path) -> 'CustomCommand':
        """Parse command definition from markdown file."""
        content = path.read_text()
        # Parse trigger, steps, and messages
        return cls(trigger, steps, success_msg)

    async def execute(self, agent: CircuitAgent, args: List[str]):
        """Execute the command steps."""
        for step in self.steps:
            if step.is_conditional:
                if self._evaluate_condition(step.condition, args):
                    await self._run_step(step, agent)
            else:
                await self._run_step(step, agent)
```

### 4.4 GitHub Integration
**Why**: Deep GitHub integration for PR workflows.

```python
# New tools
{
    "name": "gh_pr_create",
    "description": "Create a GitHub pull request from current branch.",
    "parameters": {
        "title": "PR title",
        "body": "PR description (supports markdown)",
        "base": "Base branch (default: main)",
        "draft": "Create as draft PR",
        "reviewers": "List of reviewer usernames"
    }
},
{
    "name": "gh_pr_review",
    "description": "Review a GitHub pull request.",
    "parameters": {
        "pr_number": "PR number to review",
        "action": "comment|approve|request_changes",
        "body": "Review comment"
    }
},
{
    "name": "gh_issue_context",
    "description": "Get full context about a GitHub issue.",
    "parameters": {
        "issue_number": "Issue number",
        "include_comments": "Include all comments",
        "include_linked_prs": "Include linked PRs"
    }
}
```

---

## Phase 5: User Experience Improvements (Medium Impact)

### 5.1 Syntax Highlighting
**Why**: Code is easier to read with proper highlighting.

```python
# Using rich library
from rich.syntax import Syntax
from rich.console import Console

console = Console()

def display_code(code: str, language: str, line_numbers: bool = True):
    """Display code with syntax highlighting."""
    syntax = Syntax(code, language, theme="monokai", line_numbers=line_numbers)
    console.print(syntax)

# Auto-detect language from file extension
LANG_MAP = {
    '.py': 'python', '.js': 'javascript', '.ts': 'typescript',
    '.go': 'go', '.rs': 'rust', '.java': 'java', '.cpp': 'cpp',
    '.rb': 'ruby', '.sh': 'bash', '.yaml': 'yaml', '.json': 'json',
}
```

### 5.2 Tab Completion
**Why**: Faster navigation and fewer typos.

```python
# Using prompt_toolkit
from prompt_toolkit import prompt
from prompt_toolkit.completion import PathCompleter, WordCompleter

# Path completion for file arguments
path_completer = PathCompleter(expanduser=True)

# Command completion
commands = ['/help', '/save', '/load', '/git', '/quit', '/auto', '/think']
command_completer = WordCompleter(commands, ignore_case=True)

# Git branch completion
def get_branch_completer():
    branches = subprocess.check_output(['git', 'branch', '--all']).decode().split()
    return WordCompleter(branches)
```

### 5.3 Progress Indicators
**Why**: Users need feedback during long operations.

```python
from rich.progress import Progress, SpinnerColumn, TextColumn

async def run_with_progress(self, operations: List[Callable]):
    """Run operations with progress display."""
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        transient=True,
    ) as progress:
        task = progress.add_task("Processing...", total=len(operations))

        for op in operations:
            progress.update(task, description=f"Running: {op.__name__}")
            await op()
            progress.advance(task)

# For file searches
def search_with_progress(pattern: str, files: List[Path]):
    with Progress() as progress:
        task = progress.add_task("Searching...", total=len(files))
        for file in files:
            # search logic
            progress.advance(task)
```

### 5.4 Better Error Messages
**Why**: Good errors help users recover quickly.

```python
class SmartError:
    """Generate helpful error messages with suggestions."""

    @staticmethod
    def file_not_found(path: str, working_dir: str) -> str:
        similar = find_similar_files(path, working_dir)
        msg = f"File not found: {path}\n"

        if similar:
            msg += f"\nDid you mean one of these?\n"
            for s in similar[:5]:
                msg += f"  - {s}\n"

        msg += f"\nTip: Use list_files to see available files."
        return msg

    @staticmethod
    def edit_not_found(old_text: str, file_content: str, path: str) -> str:
        similar = find_similar_text(old_text, file_content)
        msg = f"Could not find the text to replace in {path}\n"

        if similar:
            msg += f"\nSimilar text found:\n"
            for line_num, text in similar[:3]:
                msg += f"  Line {line_num}: {text[:80]}...\n"

        msg += f"\nTips:\n"
        msg += f"  - Ensure exact whitespace/indentation match\n"
        msg += f"  - Use read_file to see current content\n"
        msg += f"  - Include more context for unique matching\n"
        return msg
```

### 5.5 Cost Tracking
**Why**: Users need to understand API costs.

```python
# Token to cost mapping (approximate)
COST_PER_1K_TOKENS = {
    "gpt-4o": {"input": 0.005, "output": 0.015},
    "gpt-4o-mini": {"input": 0.00015, "output": 0.0006},
    "gpt-4.1": {"input": 0.01, "output": 0.03},
    "o4-mini": {"input": 0.003, "output": 0.012},
}

def calculate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    rates = COST_PER_1K_TOKENS.get(model, {"input": 0, "output": 0})
    return (input_tokens * rates["input"] + output_tokens * rates["output"]) / 1000

# Display in token usage
def print_token_usage_with_cost(stats: Dict, model: str):
    cost = calculate_cost(model, stats["session_prompt"], stats["session_completion"])
    print(f"Tokens: {stats['session_total']:,} | Est. cost: ${cost:.4f}")
```

---

## Phase 6: Internal Improvements (Invisible to Users)

### 6.1 Intelligent Retry Logic
**Why**: Automatic recovery from transient failures.

```python
class SmartRetry:
    """Intelligent retry with different strategies per error type."""

    STRATEGIES = {
        "rate_limit": {"wait": "exponential", "max_retries": 5},
        "timeout": {"wait": "linear", "max_retries": 3},
        "server_error": {"wait": "exponential", "max_retries": 3},
        "auth_error": {"wait": None, "max_retries": 1, "action": "refresh_token"},
    }

    async def execute_with_retry(self, func, *args, **kwargs):
        for attempt in range(self.max_retries):
            try:
                return await func(*args, **kwargs)
            except RateLimitError:
                wait = self._get_wait_time("rate_limit", attempt)
                await asyncio.sleep(wait)
            except TimeoutError:
                wait = self._get_wait_time("timeout", attempt)
                await asyncio.sleep(wait)
            except AuthError:
                await self._refresh_token()
```

### 6.2 Response Caching
**Why**: Avoid redundant API calls for identical requests.

```python
class ResponseCache:
    """Cache API responses for repeated queries."""

    def __init__(self, max_size: int = 100, ttl: int = 300):
        self.cache = OrderedDict()
        self.max_size = max_size
        self.ttl = ttl

    def _hash_request(self, messages: List[Dict], tools: List) -> str:
        """Create hash of request for cache key."""
        content = json.dumps({"messages": messages, "tools": tools}, sort_keys=True)
        return hashlib.sha256(content.encode()).hexdigest()[:16]

    def get(self, messages: List[Dict], tools: List) -> Optional[str]:
        key = self._hash_request(messages, tools)
        if key in self.cache:
            response, timestamp = self.cache[key]
            if time.time() - timestamp < self.ttl:
                return response
            del self.cache[key]
        return None
```

### 6.3 Tool Result Compression
**Why**: Large tool outputs waste context space.

```python
class ToolResultCompressor:
    """Compress tool outputs to save context space."""

    MAX_RESULT_LENGTH = 8000  # chars

    def compress(self, tool_name: str, result: str) -> str:
        if len(result) <= self.MAX_RESULT_LENGTH:
            return result

        if tool_name == "read_file":
            # Keep first and last portions
            return self._head_tail_compress(result)
        elif tool_name == "search_files":
            # Keep first N matches
            return self._truncate_with_count(result, "matches")
        elif tool_name == "run_command":
            # Keep error output, truncate success output
            return self._prioritize_errors(result)
        else:
            return result[:self.MAX_RESULT_LENGTH] + "\n[truncated]"
```

### 6.4 Model-Specific Optimizations
**Why**: Different models have different strengths.

```python
MODEL_CONFIGS = {
    "gpt-4o": {
        "max_tokens": 4096,
        "supports_vision": True,
        "supports_parallel_tools": True,
        "temperature": 0.7,
    },
    "gpt-4o-mini": {
        "max_tokens": 4096,
        "supports_vision": True,
        "supports_parallel_tools": True,
        "temperature": 0.7,
        "prompt_optimization": "concise",  # Use shorter prompts
    },
    "o4-mini": {
        "max_tokens": 16384,
        "supports_vision": False,
        "supports_parallel_tools": True,
        "temperature": 1.0,  # Reasoning models work better at temp=1
        "extended_thinking": True,
    },
}

def optimize_prompt_for_model(prompt: str, model: str) -> str:
    """Optimize prompt based on model characteristics."""
    config = MODEL_CONFIGS.get(model, {})

    if config.get("prompt_optimization") == "concise":
        # Remove verbose explanations for mini models
        prompt = remove_verbose_sections(prompt)

    if config.get("extended_thinking"):
        # Add thinking encouragement for reasoning models
        prompt += "\n\nThink step by step before acting."

    return prompt
```

### 6.5 Request Queuing & Rate Limiting
**Why**: Prevent API throttling and manage costs.

```python
class RequestQueue:
    """Queue and rate-limit API requests."""

    def __init__(self, max_requests_per_minute: int = 50):
        self.queue = asyncio.Queue()
        self.rate_limit = max_requests_per_minute
        self.request_times = []

    async def enqueue(self, request: Callable) -> Any:
        """Add request to queue and wait for execution."""
        await self._wait_for_rate_limit()
        self.request_times.append(time.time())
        return await request()

    async def _wait_for_rate_limit(self):
        """Wait if we're at the rate limit."""
        now = time.time()
        minute_ago = now - 60
        self.request_times = [t for t in self.request_times if t > minute_ago]

        if len(self.request_times) >= self.rate_limit:
            wait_time = 60 - (now - self.request_times[0])
            await asyncio.sleep(wait_time)
```

### 6.6 Telemetry & Analytics (Opt-in)
**Why**: Understand usage patterns to improve the tool.

```python
class Analytics:
    """Optional, privacy-respecting analytics."""

    def __init__(self, enabled: bool = False):
        self.enabled = enabled
        self.session_data = {
            "tools_used": Counter(),
            "errors": [],
            "session_length": 0,
            "tokens_used": 0,
        }

    def track_tool_use(self, tool_name: str, success: bool):
        if not self.enabled:
            return
        self.session_data["tools_used"][tool_name] += 1

    def get_summary(self) -> Dict:
        """Get session summary for display."""
        return {
            "most_used_tools": self.session_data["tools_used"].most_common(5),
            "total_tool_calls": sum(self.session_data["tools_used"].values()),
            "error_count": len(self.session_data["errors"]),
        }
```

---

## Phase 7: Safety & Security Enhancements

### 7.1 Sandbox Mode
**Why**: Run untrusted commands safely.

```python
class Sandbox:
    """Execute commands in a restricted environment."""

    def __init__(self, working_dir: str):
        self.working_dir = working_dir
        self.allowed_commands = {
            "ls", "cat", "head", "tail", "grep", "find", "wc",
            "python", "node", "npm", "pip", "git", "make"
        }

    def is_allowed(self, command: str) -> bool:
        """Check if command is in allowed list."""
        cmd_parts = shlex.split(command)
        base_cmd = cmd_parts[0] if cmd_parts else ""
        return base_cmd in self.allowed_commands

    def execute_sandboxed(self, command: str) -> str:
        """Execute command with restrictions."""
        if not self.is_allowed(command):
            return f"Command not allowed in sandbox mode: {command}"

        # Use firejail/bubblewrap if available for true sandboxing
        if shutil.which("firejail"):
            command = f"firejail --noprofile {command}"

        return subprocess.run(command, shell=True, capture_output=True).stdout
```

### 7.2 Secret Detection
**Why**: Prevent accidental exposure of secrets.

```python
class SecretDetector:
    """Detect potential secrets in content."""

    PATTERNS = [
        (r'(?i)(api[_-]?key|apikey)\s*[:=]\s*["\']?[\w-]{20,}', "API Key"),
        (r'(?i)(password|passwd|pwd)\s*[:=]\s*["\'][^"\']+["\']', "Password"),
        (r'ghp_[a-zA-Z0-9]{36}', "GitHub Token"),
        (r'sk-[a-zA-Z0-9]{48}', "OpenAI API Key"),
        (r'-----BEGIN (?:RSA |EC |)PRIVATE KEY-----', "Private Key"),
        (r'(?i)bearer\s+[a-zA-Z0-9\-_.]+', "Bearer Token"),
    ]

    def scan(self, content: str) -> List[Dict]:
        """Scan content for potential secrets."""
        findings = []
        for pattern, secret_type in self.PATTERNS:
            matches = re.findall(pattern, content)
            if matches:
                findings.append({
                    "type": secret_type,
                    "count": len(matches),
                    "preview": matches[0][:20] + "***"
                })
        return findings

    def redact(self, content: str) -> str:
        """Redact detected secrets from content."""
        for pattern, _ in self.PATTERNS:
            content = re.sub(pattern, "[REDACTED]", content)
        return content
```

### 7.3 Audit Logging
**Why**: Track all actions for security and debugging.

```python
class AuditLog:
    """Log all agent actions for audit trail."""

    def __init__(self, log_dir: Optional[str] = None):
        self.log_dir = Path(log_dir or "~/.config/circuit-agent/logs").expanduser()
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.session_log = self.log_dir / f"session-{datetime.now():%Y%m%d-%H%M%S}.jsonl"

    def log_action(self, action_type: str, details: Dict):
        """Log an action to the audit trail."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "action": action_type,
            "details": details,
        }

        with open(self.session_log, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def log_tool_call(self, tool_name: str, args: Dict, result: str, success: bool):
        self.log_action("tool_call", {
            "tool": tool_name,
            "args": args,
            "result_preview": result[:200],
            "success": success,
        })
```

---

## Implementation Priority

### Must Have (v4.0)
| Feature | Phase | Effort | Impact |
|---------|-------|--------|--------|
| Parallel tool execution | 1.1 | Low | High |
| Headless/CI mode | 3.1 | Medium | High |
| Smart context management | 1.3 | Medium | High |
| Better error messages | 5.4 | Low | Medium |
| Secret detection | 7.2 | Low | High |

### Should Have (v4.1)
| Feature | Phase | Effort | Impact |
|---------|-------|--------|--------|
| Thinking display | 1.2 | Low | Medium |
| Syntax highlighting | 5.1 | Low | Medium |
| Tab completion | 5.2 | Medium | Medium |
| Cost tracking | 5.5 | Low | Low |
| AST-aware editing | 2.1 | High | High |

### Nice to Have (v4.2+)
| Feature | Phase | Effort | Impact |
|---------|-------|--------|--------|
| Plugin system | 4.1 | High | High |
| MCP support | 4.2 | High | Medium |
| Image support | 2.5 | Medium | Medium |
| Watch mode | 3.3 | Medium | Medium |
| GitHub integration | 4.4 | Medium | Medium |

---

## New Dependencies

```
# Required for v4.0
rich>=13.0           # Syntax highlighting, progress bars
prompt_toolkit>=3.0  # Tab completion, better input

# Optional enhancements
tree_sitter>=0.20    # AST parsing for code intelligence
watchdog>=3.0        # File watching for watch mode
playwright>=1.40     # JavaScript-rendered page fetching

# Security
python-magic>=0.4    # File type detection
```

---

## New Slash Commands

| Command | Description |
|---------|-------------|
| `/think [on\|off]` | Toggle thinking/reasoning display |
| `/plan <task>` | Enter planning mode for complex tasks |
| `/watch [pattern]` | Start file watching mode |
| `/cost` | Show estimated session cost |
| `/plugins` | List loaded plugins |
| `/sandbox [on\|off]` | Toggle sandbox mode for commands |
| `/audit` | Show recent audit log entries |
| `/export [format]` | Export conversation (md/json/html) |

---

## Migration Path

### v3.0 → v4.0
1. No breaking changes to existing tools
2. New tools are additive
3. Existing CIRCUIT.md files work unchanged
4. Sessions from v3.0 loadable in v4.0

### Configuration Changes
```json
// ~/.config/circuit-agent/config.json additions
{
    "v4_features": {
        "parallel_execution": true,
        "thinking_mode": false,
        "syntax_highlighting": true,
        "cost_tracking": true,
        "sandbox_mode": false
    },
    "plugins_dir": "~/.config/circuit-agent/plugins",
    "mcp_servers": []
}
```

---

## Success Metrics

### Performance
- [ ] Multi-file operations 3x faster with parallel execution
- [ ] Context utilization >80% (vs current ~40%)
- [ ] Tool success rate >95% with better error handling

### User Experience
- [ ] Tab completion reduces typos by 50%
- [ ] Thinking mode increases user understanding
- [ ] Syntax highlighting improves code readability

### Reliability
- [ ] Zero secret exposures with detection
- [ ] Full audit trail for all actions
- [ ] Automatic recovery from 90% of transient errors

---

## Timeline Estimate

| Phase | Features | Effort |
|-------|----------|--------|
| Phase 1 | Core Intelligence | 1 week |
| Phase 2 | Advanced Tools | 2 weeks |
| Phase 3 | Operational Modes | 1 week |
| Phase 4 | Extensibility | 2 weeks |
| Phase 5 | UX Improvements | 1 week |
| Phase 6 | Internal Improvements | 1 week |
| Phase 7 | Safety & Security | 1 week |

**Total: ~9 weeks for full v4.0**

Recommended approach: Implement "Must Have" features first (~3 weeks), then iterate.

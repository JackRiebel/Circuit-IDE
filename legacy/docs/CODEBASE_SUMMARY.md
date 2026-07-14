# Circuit Agent v4.0 - Codebase Summary

An AI-powered coding assistant for Cisco Circuit, similar to Claude Code. Operates within a project directory with full file access, git integration, shell command execution, and web access.

## Architecture

```
circuit_agent.py              # Entry point (thin wrapper)
circuit_agent/                # Main package
├── __init__.py               # Package exports, version 4.0.0
├── agent.py                  # CircuitAgent class
├── cli.py                    # Main loop, slash commands, headless mode
├── config.py                 # Credentials, CIRCUIT.md loading
├── streaming.py              # SSE response parsing
├── ui.py                     # Terminal colors, display helpers
├── security.py               # NEW: Secret detection, audit, cost tracking
├── tools/                    # Modular tool implementations
│   ├── __init__.py           # TOOLS list, exports
│   ├── executor.py           # ToolExecutor with parallel support
│   ├── file_tools.py         # File operations
│   ├── git_tools.py          # Git operations
│   └── web_tools.py          # Web fetch & search
└── memory/                   # Session & context management
    ├── __init__.py           # Memory module exports
    ├── session.py            # Session save/load
    └── compaction.py         # Context compaction

Circuit_Chat_Test.py          # Simple chat test (no tools)
```

## Key Components

### `circuit_agent/agent.py` - CircuitAgent Class
The core agent with:
- **Streaming responses** via Server-Sent Events (all responses)
- **Token tracking** (per-request and session totals)
- **Retry logic** with exponential backoff (3 attempts)
- **Auto-approve mode** to skip confirmations
- **Tool execution** via modular tool classes
- **Parallel tool execution** for read-only tools (NEW in v4.0)
- **Session management** (save/load)
- **Context compaction** for long conversations
- **Secret detection** before file writes (NEW in v4.0)
- **Audit logging** for all actions (NEW in v4.0)
- **Cost tracking** per session (NEW in v4.0)

### `circuit_agent/tools/` - Tool Implementations
Modular tool system with 14 tools:

**File Operations (file_tools.py):**
- `read_file` - Read with line numbers, supports line ranges
- `write_file` - Create/overwrite files
- `edit_file` - Find and replace with exact matching
- `list_files` - Glob pattern matching
- `search_files` - Regex search across files
- `run_command` - Shell command execution
- `html_to_markdown` - Convert HTML to markdown (NEW)

**Git Operations (git_tools.py):**
- `git_status` - Working tree status
- `git_diff` - Show changes (working/staged/commits)
- `git_log` - Commit history
- `git_commit` - Stage and commit
- `git_branch` - List/create/switch/delete branches

**Web Operations (web_tools.py):**
- `web_fetch` - Fetch content from URLs, converts HTML to markdown
- `web_search` - Search using DuckDuckGo, returns results with snippets

Also includes:
- `ToolExecutor` - Parallel execution support via asyncio
- `BackupManager` - Automatic backups for undo functionality
- `WebCache` - Caching for web requests

### `circuit_agent/security.py` - Security Module (NEW in v4.0)

**SecretDetector:**
- Scans content for API keys, tokens, passwords
- Supports AWS, GitHub, OpenAI, Slack, and generic patterns
- Warnings during file write confirmations
- Redaction capability for sensitive data

**AuditLogger:**
- Logs all tool calls, API usage, user inputs
- Session-based JSONL log files
- Stored in `~/.config/circuit-agent/audit/`

**CostTracker:**
- Tracks token usage by model
- Estimates API costs
- Per-session and per-model breakdown

### `circuit_agent/memory/` - Session & Context

**Session Management (session.py):**
- Save/load conversation sessions
- Auto-save with timestamps
- List and delete sessions
- Stored in `~/.config/circuit-agent/sessions/`

**Context Compaction (compaction.py):**
- Summarize old messages to reduce tokens
- Keep recent messages intact
- Estimate token usage
- Simple text summary (no LLM required)

### `circuit_agent/cli.py` - Command Line Interface
Main loop with slash commands:
- `/help`, `/files`, `/clear`, `/history`
- `/model`, `/tokens`, `/undo`, `/config`
- `/git`, `/auto`, `/stream`, `/logout`, `/quit`
- `/save [name]`, `/load [name]`, `/sessions`
- `/compact`
- `/cost` (NEW in v4.0)
- `/audit` (NEW in v4.0)
- `/think [on|off]` (NEW in v4.0)

**Headless/CI Mode (NEW in v4.0):**
- `-p, --prompt` - Single prompt execution
- `--prompt-file` - Read prompt from file
- `--auto-approve, -y` - Skip all confirmations
- `-o, --output` - Output format (text/json/markdown)
- `-m, --model` - Select model
- `-v, --version` - Show version

### `circuit_agent/config.py` - Configuration
- Credential loading (config file → env vars → prompt)
- Credential saving with secure permissions (600)
- `CIRCUIT.md` loading (project → global)
- Project type detection

### `circuit_agent/streaming.py` - SSE Parsing
- `StreamingResponse` dataclass for accumulated data
- `StreamingToolCall` for tool call streaming
- `stream_chat_completion()` for real-time responses
- `non_streaming_chat_completion()` fallback

### `circuit_agent/ui.py` - User Interface
- ANSI color codes for terminal output
- Unified diff display with colors
- Token usage display
- Progress indicators
- Updated help text for v4.0

## Features

### Safety
- **Confirmation prompts** for file writes and dangerous commands
- **Path traversal protection** - Can't access outside working directory
- **Dangerous command detection** - Warns on rm -rf, sudo, etc.
- **Automatic backups** before all file modifications
- **Secret detection** - Warns before committing sensitive data (NEW)

### Convenience
- **Auto-approve mode** - Type `a` during confirmation or `/auto`
- **Undo support** - `/undo [file]` restores from backup
- **CIRCUIT.md** - Project-specific instructions
- **Streaming output** - See responses as they generate
- **Token tracking** - Monitor API usage
- **Session persistence** - Save and resume work
- **Context compaction** - Handle long conversations
- **Web access** - Look up docs and search
- **Headless mode** - Run in CI/CD pipelines (NEW)
- **Cost tracking** - Monitor API expenses (NEW)

### Reliability
- **Retry logic** - 3 attempts with exponential backoff
- **Smart error messages** - Suggests similar files/text on errors
- **Token caching** - Automatic OAuth token refresh
- **Web caching** - 5-minute cache for fetched URLs
- **Parallel execution** - Faster multi-file operations (NEW)
- **Audit logging** - Full action history (NEW)

## API Integration

### Authentication
```
POST https://id.cisco.com/oauth2/default/v1/token
Authorization: Basic base64(client_id:client_secret)
Body: grant_type=client_credentials
→ Returns: access_token (1 hour validity)
```

### Chat Completions
```
POST https://chat-ai.cisco.com/openai/deployments/{model}/chat/completions
Headers: api-key: {access_token}
Body: {messages, tools, tool_choice, user: {appkey}}
→ Returns: SSE stream with content and tool_calls
```

## Available Models

| Model | Context | Use Case |
|-------|---------|----------|
| gpt-4.1 | 120K | Complex reasoning |
| gpt-4o | 120K | Fast multimodal (default) |
| gpt-4o-mini | 120K | Quick & efficient |
| o4-mini | 200K | Large documents |

## Configuration Files

| Path | Purpose |
|------|---------|
| `~/.config/circuit-agent/config.json` | Saved credentials |
| `~/.config/circuit-agent/CIRCUIT.md` | Global agent instructions |
| `~/.config/circuit-agent/sessions/` | Saved sessions |
| `~/.config/circuit-agent/audit/` | Audit logs (NEW) |
| `./CIRCUIT.md` | Project-specific instructions |

## Usage

```bash
# Interactive mode
python circuit_agent.py [directory]

# Headless mode (NEW)
python circuit_agent.py -p "Your prompt here" --auto-approve
python circuit_agent.py -p "List TODOs" --output json
```

## Security

- Credentials stored with 600 permissions (owner-only)
- Path traversal attacks prevented via realpath checks
- Dangerous shell patterns detected and require confirmation
- All file modifications backed up automatically
- Secret detection warns before writing sensitive data (NEW)
- Full audit trail of all actions (NEW)

## Dependencies

- **Required**: httpx
- **Optional**: html2text (for better web_fetch output)

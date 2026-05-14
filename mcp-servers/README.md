# Circuit IDE — MCP Servers

Standalone Python MCP servers for Webex Teams, Jira, and GitHub. Each server exposes tools via a JSON-RPC 2.0 HTTP endpoint at `/mcp`, compatible with Circuit IDE's MCP Hub.

## Prerequisites

- Python 3.10+
- `pip install flask requests`

Or install per-server:

```bash
pip install -r webex/requirements.txt
pip install -r jira/requirements.txt
pip install -r github/requirements.txt
pip install -r bot/requirements.txt   # only if using the bot agent
```

## Environment Variables

### Webex Teams

| Variable | Description |
|----------|-------------|
| `WEBEX_TOKEN` | Webex personal access token or bot token |

### Jira

| Variable | Description |
|----------|-------------|
| `JIRA_URL` | Your Jira instance URL (e.g. `https://yoursite.atlassian.net`) |
| `JIRA_EMAIL` | Your Atlassian account email |
| `JIRA_TOKEN` | Jira API token ([create one](https://id.atlassian.net/manage-profile/security/api-tokens)) |

### GitHub

| Variable | Description |
|----------|-------------|
| `GITHUB_TOKEN` | GitHub personal access token with repo scope |

## Running

### All servers at once

```bash
chmod +x start_all.sh
./start_all.sh          # MCP servers only
./start_all.sh --bot    # MCP servers + bot agent
```

This starts:
- Webex on port **5001**
- Jira on port **5002**
- GitHub on port **5003**
- Bot agent on port **8090** (with `--bot` flag)

### Individual servers

```bash
WEBEX_TOKEN=your_token python3 webex/server.py          # port 5001
JIRA_URL=... JIRA_EMAIL=... JIRA_TOKEN=... python3 jira/server.py   # port 5002
GITHUB_TOKEN=your_token python3 github/server.py        # port 5003
```

## Connecting from Circuit IDE

1. Open the **MCP Hub** panel
2. Click **Add Server**
3. Use the **Quick Setup** dropdown to select Webex, Jira, or GitHub
4. The name and URL will be pre-filled — click **Add Server**
5. The server's tools will be discovered automatically

## Verifying with curl

```bash
# List available tools
curl -s http://localhost:5001/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m json.tool

# Call a tool
curl -s http://localhost:5001/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_me","arguments":{}}}' | python3 -m json.tool
```

## Reactive Webex Bot Agent

A standalone bot that listens for Webex messages and responds using LLM + MCP tools. No Flutter UI needed — just a Python script.

### Quick Start

```bash
# 1. Install dependencies
pip install -r bot/requirements.txt

# 2. Install ngrok (https://ngrok.com/download)
# Ensure `ngrok` is on your PATH

# 3. Set required env vars
export WEBEX_TOKEN=your_bot_token
export OPENAI_API_KEY=your_openai_key

# 4. Start MCP servers (in another terminal)
./start_all.sh

# 5. Run the bot
python bot/agent.py
```

### Bot Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WEBEX_TOKEN` | Yes | — | Webex bot access token |
| `OPENAI_API_KEY` | Yes | — | OpenAI API key |
| `OPENAI_MODEL` | No | `gpt-4o` | LLM model to use |
| `BOT_SYSTEM_PROMPT` | No | (built-in) | Custom system prompt |
| `BOT_ROOMS` | No | (all rooms) | Comma-separated room IDs to filter |
| `BOT_PORT` | No | `8090` | Local port for the webhook server |
| `MCP_SERVERS` | No | `localhost:5001-5003` | Comma-separated MCP server URLs |

### How It Works

1. Bot starts a FastAPI server and launches ngrok for a public URL
2. Registers a Webex webhook pointing to `{ngrok_url}/webhook`
3. When a message arrives: fetches text → sends to LLM with all MCP tools → sends response back
4. On shutdown (Ctrl+C): deregisters webhook and stops ngrok

---

## Available Tools

### Webex (11 tools)
`list_rooms`, `get_room`, `create_room`, `list_messages`, `send_message`, `list_people`, `get_me`, `list_memberships`, `create_webhook`, `delete_webhook`, `list_webhooks`

### Jira (10 tools)
`search_issues`, `get_issue`, `create_issue`, `update_issue`, `add_comment`, `transition_issue`, `list_projects`, `assign_issue`, `list_sprints`, `get_sprint_issues`

### GitHub (12 tools)
`get_me`, `list_repos`, `get_repo`, `search_repos`, `list_issues`, `get_issue`, `create_issue`, `list_pull_requests`, `get_pull_request`, `create_pull_request`, `search_code`, `list_actions_runs`

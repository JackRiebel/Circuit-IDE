# Circuit Agent Setup Guide

## Prerequisites

- Python 3.9+
- `httpx` library (`pip install httpx`)
- Cisco employee or partner account with Circuit API access

## Step 1: Get Credentials

1. Go to **https://developer.cisco.com/site/ai-ml/**
2. Click **"Manage Circuit API Keys"**
3. Request a key, then click **"View"** to see:
   - **Client ID** (e.g., `abc123def456...`)
   - **Client Secret** (e.g., `xyz789...`)
   - **App Key** (e.g., `egai-prd-sales-020...`)

## Step 2: Configure Credentials

### Option A: First-Run Prompt (Recommended)
Just run the agent - it will prompt for credentials and offer to save them:
```bash
python circuit_agent.py
```

Credentials are saved to: `~/.config/circuit-agent/config.json`

### Option B: Environment Variables
```bash
export CIRCUIT_CLIENT_ID=your_client_id
export CIRCUIT_CLIENT_SECRET=your_client_secret
export CIRCUIT_APP_KEY=your_app_key
```

### Option C: Manual Config File
Create `~/.config/circuit-agent/config.json`:
```json
{
  "client_id": "your_client_id",
  "client_secret": "your_client_secret",
  "app_key": "your_app_key"
}
```

## Step 3: Run the Agent

```bash
# Current directory
python circuit_agent.py

# Specific project
python circuit_agent.py /path/to/project
```

## Authentication Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Chat Request                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Token Cache Check                           │
│    Is there a valid cached token (with 5-min buffer)?       │
└─────────────────────────────────────────────────────────────┘
                    │                    │
                   YES                   NO
                    │                    │
                    ▼                    ▼
            ┌───────────┐    ┌──────────────────────────────┐
            │Use cached │    │  POST https://id.cisco.com/  │
            │  token    │    │  oauth2/default/v1/token     │
            └───────────┘    │                              │
                    │        │  Auth: Basic base64(id:secret)│
                    │        │  Body: grant_type=client_creds│
                    │        └──────────────────────────────┘
                    │                    │
                    └────────┬───────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│              POST https://chat-ai.cisco.com/                │
│              openai/deployments/{model}/chat/completions    │
│                                                             │
│  Headers: api-key: {access_token}                           │
│  Body: messages, tools, user: {appkey: YOUR_APP_KEY}        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Streaming Response                          │
│         (Server-Sent Events with content/tool calls)        │
└─────────────────────────────────────────────────────────────┘
```

## Available Models

| Model | Context | Best For | Default |
|-------|---------|----------|---------|
| gpt-4.1 | 120K | Complex reasoning | |
| gpt-4o | 120K | Fast multimodal | ✓ |
| gpt-4o-mini | 120K | Quick & efficient | |
| o4-mini | 200K | Large documents | |

## Project Configuration (CIRCUIT.md)

Create `CIRCUIT.md` in your project root for project-specific instructions:

```markdown
## Project Context
This is a React frontend with TypeScript.

## Conventions
- Use functional components with hooks
- Always use TypeScript strict mode
- Run tests before committing

## Important Files
- src/App.tsx - Main application
- src/api/ - API client functions

## Commands
- Dev: `npm run dev`
- Test: `npm test`
- Build: `npm run build`
```

You can also create a global config at `~/.config/circuit-agent/CIRCUIT.md`

## Troubleshooting

### "401 Unauthorized" on token request
- Verify Client ID and Secret are correct (no extra spaces)
- Check if OAuth application is still active

### "403 Forbidden" on chat requests
- Verify App Key is correct
- Check if your account has AI API access
- Contact Cisco IT if access is missing

### "Connection refused" or timeouts
- Check network connectivity to Cisco services
- Verify you're on Cisco VPN if required
- The agent will retry with exponential backoff (3 attempts)

### Tool errors
- **"File not found"**: Agent will suggest similar filenames
- **"Text not found"**: Agent will show similar lines in file
- **"Multiple matches"**: Provide more context in old_text

### Delete saved credentials
```bash
rm ~/.config/circuit-agent/config.json
# Or use /logout command in the agent
```

## Security Notes

1. **Credentials are stored locally** in `~/.config/circuit-agent/` with 600 permissions
2. **Never commit credentials** - the config directory is user-specific
3. **Path traversal protection** - Agent can't access files outside working directory
4. **Dangerous command detection** - Warns before running rm -rf, sudo, etc.
5. **All file changes are backed up** - Use /undo to restore

## Files Overview

```
circuit_agent.py          # Entry point (thin wrapper)
circuit_agent/
├── __init__.py           # Package init, version
├── agent.py              # CircuitAgent class
│                         # - Streaming responses
│                         # - Token tracking
│                         # - Retry logic with backoff
│                         # - Auto-approve mode
├── cli.py                # Main loop, slash commands
├── config.py             # Credential management
│                         # - Config file loading
│                         # - CIRCUIT.md loading
│                         # - Project detection
├── tools.py              # Tool definitions (11 tools)
│                         # - File operations
│                         # - Git operations
│                         # - BackupManager for undo
├── streaming.py          # SSE response parsing
└── ui.py                 # Terminal colors, diff display
```

## Support

- **Cisco Circuit Issues**: Contact Cisco IT or Circuit support
- **Agent Issues**: Check error messages for suggestions
- **Feature Requests**: The agent can modify its own code!

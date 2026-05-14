"""Reactive Webex Bot Agent — listens for messages, responds via LLM + MCP tools."""

import asyncio
import json
import os
import subprocess
import sys
import time
from contextlib import asynccontextmanager

import httpx
import uvicorn
from fastapi import FastAPI, Request
from openai import AsyncOpenAI

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

WEBEX_TOKEN = os.environ.get("WEBEX_TOKEN", "")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o")
BOT_SYSTEM_PROMPT = os.environ.get(
    "BOT_SYSTEM_PROMPT",
    "You are a helpful Webex bot assistant. You can interact with Webex, Jira, "
    "and GitHub via tools. Be concise and helpful.",
)
BOT_ROOMS = [
    r.strip()
    for r in os.environ.get("BOT_ROOMS", "").split(",")
    if r.strip()
]
BOT_PORT = int(os.environ.get("BOT_PORT", "8090"))

MCP_SERVER_URLS = [
    u.strip()
    for u in os.environ.get(
        "MCP_SERVERS",
        "http://localhost:5001/mcp,http://localhost:5002/mcp,http://localhost:5003/mcp",
    ).split(",")
    if u.strip()
]

WEBEX_API = "https://webexapis.com/v1"
MAX_HISTORY = 30
MAX_TOOL_ITERATIONS = 15

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

openai_client: AsyncOpenAI = None  # type: ignore[assignment]
http_client: httpx.AsyncClient = None  # type: ignore[assignment]
bot_person_id: str = ""
webhook_id: str = ""
ngrok_process: subprocess.Popen = None  # type: ignore[assignment]

# tool_name → mcp_server_url
tool_registry: dict[str, str] = {}
# openai-format tool definitions
openai_tools: list[dict] = []
# per-room conversation history: room_id → list of messages (user/assistant only)
room_history: dict[str, list[dict]] = {}
# per-room lock to prevent interleaved processing
room_locks: dict[str, asyncio.Lock] = {}

# ---------------------------------------------------------------------------
# Webex helpers
# ---------------------------------------------------------------------------


def _webex_headers():
    return {
        "Authorization": f"Bearer {WEBEX_TOKEN}",
        "Content-Type": "application/json",
    }


async def webex_get(path: str, params: dict | None = None):
    r = await http_client.get(
        f"{WEBEX_API}{path}", headers=_webex_headers(), params=params
    )
    r.raise_for_status()
    return r.json()


async def webex_post(path: str, body: dict):
    r = await http_client.post(
        f"{WEBEX_API}{path}", headers=_webex_headers(), json=body
    )
    r.raise_for_status()
    return r.json()


async def webex_delete(path: str):
    r = await http_client.delete(f"{WEBEX_API}{path}", headers=_webex_headers())
    r.raise_for_status()


# ---------------------------------------------------------------------------
# MCP server discovery
# ---------------------------------------------------------------------------


def _mcp_to_openai_schema(mcp_schema: dict) -> dict:
    """Convert an MCP inputSchema to an OpenAI function parameters schema."""
    schema = dict(mcp_schema)
    schema.setdefault("type", "object")
    schema.setdefault("properties", {})
    return schema


async def discover_tools():
    """Ping each MCP server, collect tools, build OpenAI tool list."""
    global openai_tools
    openai_tools = []
    tool_registry.clear()

    for url in MCP_SERVER_URLS:
        try:
            r = await http_client.post(
                url,
                json={"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}},
                timeout=5.0,
            )
            r.raise_for_status()
            data = r.json()
            tools = data.get("result", {}).get("tools", [])

            # Derive a server prefix from the URL for namespacing
            # e.g. http://localhost:5001/mcp → "5001"
            server_label = url.split(":")[-1].replace("/mcp", "")

            for t in tools:
                tool_name = t["name"]
                # Namespace to avoid collisions (e.g. both webex and github have get_me)
                namespaced = f"mcp_{server_label}_{tool_name}"
                tool_registry[namespaced] = url

                openai_tools.append({
                    "type": "function",
                    "function": {
                        "name": namespaced,
                        "description": t.get("description", ""),
                        "parameters": _mcp_to_openai_schema(
                            t.get("inputSchema", {"type": "object", "properties": {}})
                        ),
                    },
                })
            print(f"  [OK] {url} — {len(tools)} tools discovered")
        except Exception as exc:
            print(f"  [WARN] {url} — unreachable ({exc})")


async def call_mcp_tool(namespaced_name: str, arguments: dict) -> str:
    """Route a tool call to the correct MCP server via JSON-RPC."""
    url = tool_registry.get(namespaced_name)
    if not url:
        return f"Error: unknown tool '{namespaced_name}'"

    # Strip namespace prefix to get original tool name
    # namespaced = mcp_{port}_{original_name}
    parts = namespaced_name.split("_", 2)
    original_name = parts[2] if len(parts) >= 3 else namespaced_name

    try:
        r = await http_client.post(
            url,
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {"name": original_name, "arguments": arguments},
            },
            timeout=30.0,
        )
        r.raise_for_status()
        data = r.json()
        result = data.get("result", {})
        content_list = result.get("content", [])
        texts = [c.get("text", "") for c in content_list if c.get("type") == "text"]
        return "\n".join(texts) if texts else json.dumps(result)
    except Exception as exc:
        return f"Error calling tool '{namespaced_name}': {exc}"


# ---------------------------------------------------------------------------
# LLM interaction
# ---------------------------------------------------------------------------


async def run_llm_with_tools(room_id: str) -> str:
    """Run the LLM with conversation history and tools, handling tool call loops.

    Uses a local working copy for the tool-call loop so intermediate tool
    messages (assistant w/ tool_calls, tool results) do NOT leak into the
    persistent room_history.  Only user/assistant content pairs are kept.
    """
    persistent = room_history.get(room_id, [])
    # Build a LOCAL messages list: system + copy of persistent history.
    # Tool-loop intermediates are appended only to this local list.
    messages = [{"role": "system", "content": BOT_SYSTEM_PROMPT}] + list(persistent)

    kwargs: dict = {"model": OPENAI_MODEL, "messages": messages}
    if openai_tools:
        kwargs["tools"] = openai_tools

    for _ in range(MAX_TOOL_ITERATIONS):
        response = await openai_client.chat.completions.create(**kwargs)
        choice = response.choices[0]
        msg = choice.message

        if not msg.tool_calls:
            return msg.content or ""

        # Append assistant message with tool calls to LOCAL messages only
        assistant_msg: dict = {"role": "assistant", "content": msg.content or ""}
        assistant_msg["tool_calls"] = [
            {
                "id": tc.id,
                "type": "function",
                "function": {
                    "name": tc.function.name,
                    "arguments": tc.function.arguments,
                },
            }
            for tc in msg.tool_calls
        ]
        messages.append(assistant_msg)

        # Execute each tool call
        for tc in msg.tool_calls:
            try:
                args = json.loads(tc.function.arguments)
            except json.JSONDecodeError:
                args = {}
            print(f"    Tool call: {tc.function.name}({json.dumps(args)[:200]})")
            result = await call_mcp_tool(tc.function.name, args)
            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result,
            })

        # Update kwargs for next iteration
        kwargs["messages"] = messages

    return "I reached the maximum number of tool iterations."


# ---------------------------------------------------------------------------
# Ngrok management
# ---------------------------------------------------------------------------


async def start_ngrok(port: int) -> str:
    """Launch ngrok and return the public HTTPS URL.

    Runs the blocking polling loop in a thread so it doesn't block the
    async event loop.
    """
    global ngrok_process
    ngrok_process = subprocess.Popen(
        ["ngrok", "http", str(port), "--log", "stdout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

    def _poll_ngrok_url() -> str:
        for _ in range(30):
            time.sleep(1)
            try:
                r = httpx.get("http://127.0.0.1:4040/api/tunnels", timeout=3.0)
                tunnels = r.json().get("tunnels", [])
                for t in tunnels:
                    if t.get("proto") == "https":
                        return t["public_url"]
            except Exception:
                continue
        raise RuntimeError("Failed to get ngrok public URL after 30 seconds")

    return await asyncio.to_thread(_poll_ngrok_url)


def stop_ngrok():
    global ngrok_process
    if ngrok_process:
        ngrok_process.terminate()
        try:
            ngrok_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            ngrok_process.kill()
        ngrok_process = None


# ---------------------------------------------------------------------------
# Lifespan (startup + shutdown)
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Handles startup and shutdown logic."""
    global openai_client, http_client, bot_person_id, webhook_id

    if not WEBEX_TOKEN:
        print("ERROR: WEBEX_TOKEN environment variable is required.")
        sys.exit(1)
    if not OPENAI_API_KEY:
        print("ERROR: OPENAI_API_KEY environment variable is required.")
        sys.exit(1)

    openai_client = AsyncOpenAI(api_key=OPENAI_API_KEY)
    http_client = httpx.AsyncClient(timeout=30.0)

    # 1. Get bot identity
    print("Fetching bot identity...")
    me = await webex_get("/people/me")
    bot_person_id = me["id"]
    print(f"  Bot: {me.get('displayName', 'unknown')} ({me.get('emails', ['?'])[0]})")

    # 2. Discover MCP tools
    print("Discovering MCP tools...")
    await discover_tools()
    print(f"  Total tools: {len(openai_tools)}")

    # 3. Start ngrok
    print(f"Starting ngrok tunnel on port {BOT_PORT}...")
    public_url = await start_ngrok(BOT_PORT)
    print(f"  Tunnel: {public_url}")

    # 4. Register webhook
    print("Registering Webex webhook...")
    wh = await webex_post("/webhooks", {
        "name": "circuit-bot-agent",
        "targetUrl": f"{public_url}/webhook",
        "resource": "messages",
        "event": "created",
    })
    webhook_id = wh["id"]
    print(f"  Webhook ID: {webhook_id}")

    print(f"\nBot ready! Listening on {public_url}")
    if BOT_ROOMS:
        print(f"  Filtering to rooms: {BOT_ROOMS}")

    yield  # ---- app serves requests here ----

    # Shutdown
    print("\nShutting down...")

    if webhook_id:
        try:
            await webex_delete(f"/webhooks/{webhook_id}")
            print("  Webhook deregistered.")
        except Exception as exc:
            print(f"  Failed to deregister webhook: {exc}")
        webhook_id = ""

    stop_ngrok()
    print("  Ngrok stopped.")

    await http_client.aclose()
    print("Bot stopped.")


# ---------------------------------------------------------------------------
# App + routes
# ---------------------------------------------------------------------------

app = FastAPI(lifespan=lifespan)


@app.post("/webhook")
async def handle_webhook(request: Request):
    body = await request.json()
    data = body.get("data", {})
    person_id = data.get("personId", "")
    room_id = data.get("roomId", "")
    message_id = data.get("id", "")

    # Skip bot's own messages
    if person_id == bot_person_id:
        return {"status": "skipped (self)"}

    # Skip if room filtering is enabled and room not in list
    if BOT_ROOMS and room_id not in BOT_ROOMS:
        return {"status": "skipped (room filter)"}

    if not message_id:
        return {"status": "skipped (no message id)"}

    # Get per-room lock
    if room_id not in room_locks:
        room_locks[room_id] = asyncio.Lock()

    async with room_locks[room_id]:
        try:
            # Fetch the actual message text
            msg = await webex_get(f"/messages/{message_id}")
            text = msg.get("text", "").strip()
            if not text:
                return {"status": "skipped (empty)"}

            sender = msg.get("personEmail", "unknown")
            print(f"  Message from {sender} in room {room_id[:12]}...: {text[:100]}")

            # Add to room history
            if room_id not in room_history:
                room_history[room_id] = []
            room_history[room_id].append({"role": "user", "content": text})

            # Trim history (only user/assistant pairs, safe to slice)
            if len(room_history[room_id]) > MAX_HISTORY:
                room_history[room_id] = room_history[room_id][-MAX_HISTORY:]

            # Get LLM response
            response_text = await run_llm_with_tools(room_id)

            # Add assistant response to persistent history
            room_history[room_id].append({"role": "assistant", "content": response_text})

            # Send response to Webex
            if response_text:
                await webex_post("/messages", {
                    "roomId": room_id,
                    "markdown": response_text,
                })

            return {"status": "ok"}

        except Exception as exc:
            print(f"  Error handling message: {exc}")
            return {"status": "error", "detail": str(exc)}


@app.get("/health")
async def health():
    return {"status": "ok", "bot_id": bot_person_id}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=BOT_PORT)

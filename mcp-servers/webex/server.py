"""Webex Teams MCP Server — JSON-RPC 2.0 over HTTP (Flask)."""

import os
import json

import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

WEBEX_TOKEN = os.environ.get("WEBEX_TOKEN", "")
API_BASE = "https://webexapis.com/v1"

# ---------------------------------------------------------------------------
# Tool definitions
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "list_rooms",
        "description": "List Webex spaces the authenticated user belongs to.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "max": {
                    "type": "integer",
                    "description": "Max number of rooms to return (default 50).",
                },
            },
        },
    },
    {
        "name": "get_room",
        "description": "Get details of a Webex space by its room ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "roomId": {
                    "type": "string",
                    "description": "The Webex room ID.",
                },
            },
            "required": ["roomId"],
        },
    },
    {
        "name": "create_room",
        "description": "Create a new Webex space.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "description": "Title of the new space.",
                },
            },
            "required": ["title"],
        },
    },
    {
        "name": "list_messages",
        "description": "List recent messages in a Webex space.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "roomId": {
                    "type": "string",
                    "description": "The room ID to fetch messages from.",
                },
                "max": {
                    "type": "integer",
                    "description": "Max messages to return (default 50).",
                },
            },
            "required": ["roomId"],
        },
    },
    {
        "name": "send_message",
        "description": "Send a message to a Webex space.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "roomId": {
                    "type": "string",
                    "description": "The room ID to send the message to.",
                },
                "text": {
                    "type": "string",
                    "description": "Plain-text message body.",
                },
                "markdown": {
                    "type": "string",
                    "description": "Markdown-formatted message body (optional).",
                },
            },
            "required": ["roomId"],
        },
    },
    {
        "name": "list_people",
        "description": "Search for Webex users by email or display name.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "email": {
                    "type": "string",
                    "description": "Email address to search for.",
                },
                "displayName": {
                    "type": "string",
                    "description": "Display name to search for.",
                },
                "max": {
                    "type": "integer",
                    "description": "Max results (default 50).",
                },
            },
        },
    },
    {
        "name": "get_me",
        "description": "Get the authenticated Webex user's own profile.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "list_memberships",
        "description": "List members of a Webex space.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "roomId": {
                    "type": "string",
                    "description": "The room ID to list members for.",
                },
                "max": {
                    "type": "integer",
                    "description": "Max results (default 50).",
                },
            },
            "required": ["roomId"],
        },
    },
    {
        "name": "create_webhook",
        "description": "Create a Webex webhook to receive event notifications.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "A user-friendly name for the webhook.",
                },
                "targetUrl": {
                    "type": "string",
                    "description": "The URL that receives the webhook POST.",
                },
                "resource": {
                    "type": "string",
                    "description": "The resource type (e.g. messages, rooms, memberships).",
                },
                "event": {
                    "type": "string",
                    "description": "The event type (e.g. created, updated, deleted).",
                },
                "filter": {
                    "type": "string",
                    "description": "Optional filter (e.g. roomId=xxx).",
                },
            },
            "required": ["name", "targetUrl", "resource", "event"],
        },
    },
    {
        "name": "delete_webhook",
        "description": "Delete a Webex webhook by its ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "webhookId": {
                    "type": "string",
                    "description": "The ID of the webhook to delete.",
                },
            },
            "required": ["webhookId"],
        },
    },
    {
        "name": "list_webhooks",
        "description": "List all webhooks registered by the authenticated user.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "max": {
                    "type": "integer",
                    "description": "Max results (default 50).",
                },
            },
        },
    },
]

# ---------------------------------------------------------------------------
# Webex API helpers
# ---------------------------------------------------------------------------


def _headers():
    return {
        "Authorization": f"Bearer {WEBEX_TOKEN}",
        "Content-Type": "application/json",
    }


def _get(path, params=None):
    r = requests.get(f"{API_BASE}{path}", headers=_headers(), params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def _post(path, body):
    r = requests.post(f"{API_BASE}{path}", headers=_headers(), json=body, timeout=30)
    r.raise_for_status()
    return r.json()


def _delete(path):
    r = requests.delete(f"{API_BASE}{path}", headers=_headers(), timeout=30)
    r.raise_for_status()
    return {"status": "deleted"}


# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------


def _call_tool(name, args):
    if name == "list_rooms":
        params = {}
        if args.get("max"):
            params["max"] = args["max"]
        return _get("/rooms", params)

    if name == "get_room":
        return _get(f"/rooms/{args['roomId']}")

    if name == "create_room":
        return _post("/rooms", {"title": args["title"]})

    if name == "list_messages":
        params = {"roomId": args["roomId"]}
        if args.get("max"):
            params["max"] = args["max"]
        return _get("/messages", params)

    if name == "send_message":
        body = {"roomId": args["roomId"]}
        if args.get("text"):
            body["text"] = args["text"]
        if args.get("markdown"):
            body["markdown"] = args["markdown"]
        return _post("/messages", body)

    if name == "list_people":
        params = {}
        for k in ("email", "displayName", "max"):
            if args.get(k):
                params[k] = args[k]
        return _get("/people", params)

    if name == "get_me":
        return _get("/people/me")

    if name == "list_memberships":
        params = {"roomId": args["roomId"]}
        if args.get("max"):
            params["max"] = args["max"]
        return _get("/memberships", params)

    if name == "create_webhook":
        body = {
            "name": args["name"],
            "targetUrl": args["targetUrl"],
            "resource": args["resource"],
            "event": args["event"],
        }
        if args.get("filter"):
            body["filter"] = args["filter"]
        return _post("/webhooks", body)

    if name == "delete_webhook":
        return _delete(f"/webhooks/{args['webhookId']}")

    if name == "list_webhooks":
        params = {}
        if args.get("max"):
            params["max"] = args["max"]
        return _get("/webhooks", params)

    raise ValueError(f"Unknown tool: {name}")


# ---------------------------------------------------------------------------
# JSON-RPC 2.0 endpoint
# ---------------------------------------------------------------------------


@app.route("/mcp", methods=["POST"])
def mcp_endpoint():
    body = request.get_json(force=True)
    rpc_id = body.get("id")
    method = body.get("method", "")
    params = body.get("params", {})

    if method == "initialize":
        return jsonify({
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": "webex-mcp", "version": "1.0.0"},
                "capabilities": {"tools": {}},
            },
        })

    if method == "notifications/initialized":
        return jsonify({"jsonrpc": "2.0", "id": rpc_id, "result": {}})

    if method == "tools/list":
        return jsonify({
            "jsonrpc": "2.0",
            "id": rpc_id,
            "result": {"tools": TOOLS},
        })

    if method == "tools/call":
        tool_name = params.get("name", "")
        tool_args = params.get("arguments", {})
        try:
            result = _call_tool(tool_name, tool_args)
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "content": [
                        {"type": "text", "text": json.dumps(result, indent=2)}
                    ],
                },
            })
        except Exception as exc:
            return jsonify({
                "jsonrpc": "2.0",
                "id": rpc_id,
                "result": {
                    "content": [{"type": "text", "text": str(exc)}],
                    "isError": True,
                },
            })

    return jsonify({
        "jsonrpc": "2.0",
        "id": rpc_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    })


if __name__ == "__main__":
    if not WEBEX_TOKEN:
        print("WARNING: WEBEX_TOKEN environment variable is not set.")
    app.run(host="127.0.0.1", port=5001)

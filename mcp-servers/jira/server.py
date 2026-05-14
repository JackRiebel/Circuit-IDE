"""Jira MCP Server — JSON-RPC 2.0 over HTTP (Flask)."""

import os
import json
from base64 import b64encode

import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

JIRA_URL = os.environ.get("JIRA_URL", "").rstrip("/")
JIRA_EMAIL = os.environ.get("JIRA_EMAIL", "")
JIRA_TOKEN = os.environ.get("JIRA_TOKEN", "")

# ---------------------------------------------------------------------------
# Tool definitions
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "search_issues",
        "description": "Search Jira issues using JQL.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "jql": {
                    "type": "string",
                    "description": "JQL query string.",
                },
                "maxResults": {
                    "type": "integer",
                    "description": "Max results to return (default 50).",
                },
                "fields": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Fields to include (default: summary, status, assignee, priority).",
                },
            },
            "required": ["jql"],
        },
    },
    {
        "name": "get_issue",
        "description": "Get full details of a Jira issue by key (e.g. PROJ-123).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "issueKey": {
                    "type": "string",
                    "description": "The issue key, e.g. PROJ-123.",
                },
            },
            "required": ["issueKey"],
        },
    },
    {
        "name": "create_issue",
        "description": "Create a new Jira issue.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "projectKey": {
                    "type": "string",
                    "description": "Project key, e.g. PROJ.",
                },
                "summary": {
                    "type": "string",
                    "description": "Issue summary / title.",
                },
                "issueType": {
                    "type": "string",
                    "description": "Issue type name, e.g. Bug, Task, Story.",
                },
                "description": {
                    "type": "string",
                    "description": "Issue description (plain text).",
                },
            },
            "required": ["projectKey", "summary", "issueType"],
        },
    },
    {
        "name": "update_issue",
        "description": "Update fields on an existing Jira issue.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "issueKey": {
                    "type": "string",
                    "description": "The issue key.",
                },
                "fields": {
                    "type": "object",
                    "description": "Map of field names to new values.",
                },
            },
            "required": ["issueKey", "fields"],
        },
    },
    {
        "name": "add_comment",
        "description": "Add a comment to a Jira issue.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "issueKey": {
                    "type": "string",
                    "description": "The issue key.",
                },
                "body": {
                    "type": "string",
                    "description": "Comment body text.",
                },
            },
            "required": ["issueKey", "body"],
        },
    },
    {
        "name": "transition_issue",
        "description": "Transition a Jira issue to a new status.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "issueKey": {
                    "type": "string",
                    "description": "The issue key.",
                },
                "transitionId": {
                    "type": "string",
                    "description": "The transition ID. Use get_issue to find available transitions.",
                },
            },
            "required": ["issueKey", "transitionId"],
        },
    },
    {
        "name": "list_projects",
        "description": "List all Jira projects visible to the user.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "assign_issue",
        "description": "Assign a Jira issue to a user.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "issueKey": {
                    "type": "string",
                    "description": "The issue key.",
                },
                "accountId": {
                    "type": "string",
                    "description": "Atlassian account ID of the assignee. Use null to unassign.",
                },
            },
            "required": ["issueKey", "accountId"],
        },
    },
    {
        "name": "list_sprints",
        "description": "List sprints for a Jira board.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "boardId": {
                    "type": "integer",
                    "description": "The board ID.",
                },
                "state": {
                    "type": "string",
                    "description": "Filter by state: active, closed, future.",
                },
            },
            "required": ["boardId"],
        },
    },
    {
        "name": "get_sprint_issues",
        "description": "Get issues in a specific sprint.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sprintId": {
                    "type": "integer",
                    "description": "The sprint ID.",
                },
                "maxResults": {
                    "type": "integer",
                    "description": "Max results (default 50).",
                },
            },
            "required": ["sprintId"],
        },
    },
]

# ---------------------------------------------------------------------------
# Jira API helpers
# ---------------------------------------------------------------------------


def _auth_header():
    creds = b64encode(f"{JIRA_EMAIL}:{JIRA_TOKEN}".encode()).decode()
    return {
        "Authorization": f"Basic {creds}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def _get(path, params=None):
    r = requests.get(f"{JIRA_URL}{path}", headers=_auth_header(), params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def _post(path, body):
    r = requests.post(f"{JIRA_URL}{path}", headers=_auth_header(), json=body, timeout=30)
    r.raise_for_status()
    return r.json() if r.content else {"status": "ok"}


def _put(path, body):
    r = requests.put(f"{JIRA_URL}{path}", headers=_auth_header(), json=body, timeout=30)
    r.raise_for_status()
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------


def _call_tool(name, args):
    if name == "search_issues":
        body = {"jql": args["jql"], "maxResults": args.get("maxResults", 50)}
        if args.get("fields"):
            body["fields"] = args["fields"]
        else:
            body["fields"] = ["summary", "status", "assignee", "priority"]
        r = requests.post(
            f"{JIRA_URL}/rest/api/3/search",
            headers=_auth_header(),
            json=body,
            timeout=30,
        )
        r.raise_for_status()
        return r.json()

    if name == "get_issue":
        return _get(f"/rest/api/3/issue/{args['issueKey']}")

    if name == "create_issue":
        body = {
            "fields": {
                "project": {"key": args["projectKey"]},
                "summary": args["summary"],
                "issuetype": {"name": args["issueType"]},
            }
        }
        if args.get("description"):
            body["fields"]["description"] = {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": args["description"]}],
                    }
                ],
            }
        return _post("/rest/api/3/issue", body)

    if name == "update_issue":
        return _put(f"/rest/api/3/issue/{args['issueKey']}", {"fields": args["fields"]})

    if name == "add_comment":
        body = {
            "body": {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": args["body"]}],
                    }
                ],
            }
        }
        return _post(f"/rest/api/3/issue/{args['issueKey']}/comment", body)

    if name == "transition_issue":
        return _post(
            f"/rest/api/3/issue/{args['issueKey']}/transitions",
            {"transition": {"id": args["transitionId"]}},
        )

    if name == "list_projects":
        return _get("/rest/api/3/project")

    if name == "assign_issue":
        return _put(
            f"/rest/api/3/issue/{args['issueKey']}/assignee",
            {"accountId": args["accountId"]},
        )

    if name == "list_sprints":
        params = {}
        if args.get("state"):
            params["state"] = args["state"]
        return _get(f"/rest/agile/1.0/board/{args['boardId']}/sprint", params)

    if name == "get_sprint_issues":
        params = {"maxResults": args.get("maxResults", 50)}
        return _get(f"/rest/agile/1.0/sprint/{args['sprintId']}/issue", params)

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
                "serverInfo": {"name": "jira-mcp", "version": "1.0.0"},
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
    missing = [v for v in ("JIRA_URL", "JIRA_EMAIL", "JIRA_TOKEN") if not os.environ.get(v)]
    if missing:
        print(f"WARNING: Missing environment variables: {', '.join(missing)}")
    app.run(host="127.0.0.1", port=5002)

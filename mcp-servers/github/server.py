"""GitHub MCP Server — JSON-RPC 2.0 over HTTP (Flask).

Self-hosted alternative to the Copilot MCP endpoint.
"""

import os
import json

import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
API_BASE = "https://api.github.com"

# ---------------------------------------------------------------------------
# Tool definitions
# ---------------------------------------------------------------------------

TOOLS = [
    {
        "name": "get_me",
        "description": "Get the authenticated GitHub user's profile.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "list_repos",
        "description": "List repositories for the authenticated user.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sort": {
                    "type": "string",
                    "description": "Sort by: created, updated, pushed, full_name (default updated).",
                },
                "per_page": {
                    "type": "integer",
                    "description": "Results per page (default 30, max 100).",
                },
            },
        },
    },
    {
        "name": "get_repo",
        "description": "Get details of a GitHub repository.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
            },
            "required": ["owner", "repo"],
        },
    },
    {
        "name": "search_repos",
        "description": "Search GitHub repositories.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "q": {"type": "string", "description": "Search query."},
                "sort": {
                    "type": "string",
                    "description": "Sort by: stars, forks, help-wanted-issues, updated.",
                },
                "per_page": {
                    "type": "integer",
                    "description": "Results per page (default 30).",
                },
            },
            "required": ["q"],
        },
    },
    {
        "name": "list_issues",
        "description": "List issues for a GitHub repository.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
                "state": {
                    "type": "string",
                    "description": "Filter by state: open, closed, all (default open).",
                },
                "per_page": {
                    "type": "integer",
                    "description": "Results per page (default 30).",
                },
            },
            "required": ["owner", "repo"],
        },
    },
    {
        "name": "get_issue",
        "description": "Get details of a specific GitHub issue.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
                "issue_number": {"type": "integer", "description": "Issue number."},
            },
            "required": ["owner", "repo", "issue_number"],
        },
    },
    {
        "name": "create_issue",
        "description": "Create a new GitHub issue.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
                "title": {"type": "string", "description": "Issue title."},
                "body": {"type": "string", "description": "Issue body (optional)."},
                "labels": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Labels to apply.",
                },
            },
            "required": ["owner", "repo", "title"],
        },
    },
    {
        "name": "list_pull_requests",
        "description": "List pull requests for a GitHub repository.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
                "state": {
                    "type": "string",
                    "description": "Filter by state: open, closed, all (default open).",
                },
                "per_page": {
                    "type": "integer",
                    "description": "Results per page (default 30).",
                },
            },
            "required": ["owner", "repo"],
        },
    },
    {
        "name": "get_pull_request",
        "description": "Get details of a specific pull request.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
                "pull_number": {"type": "integer", "description": "Pull request number."},
            },
            "required": ["owner", "repo", "pull_number"],
        },
    },
    {
        "name": "create_pull_request",
        "description": "Create a new pull request.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
                "title": {"type": "string", "description": "PR title."},
                "head": {"type": "string", "description": "Branch containing changes."},
                "base": {"type": "string", "description": "Branch to merge into."},
                "body": {"type": "string", "description": "PR description (optional)."},
            },
            "required": ["owner", "repo", "title", "head", "base"],
        },
    },
    {
        "name": "search_code",
        "description": "Search code on GitHub.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "q": {"type": "string", "description": "Search query (e.g. 'addClass repo:jquery/jquery')."},
                "per_page": {
                    "type": "integer",
                    "description": "Results per page (default 30).",
                },
            },
            "required": ["q"],
        },
    },
    {
        "name": "list_actions_runs",
        "description": "List recent GitHub Actions workflow runs for a repository.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "owner": {"type": "string", "description": "Repository owner."},
                "repo": {"type": "string", "description": "Repository name."},
                "status": {
                    "type": "string",
                    "description": "Filter by status: completed, in_progress, queued.",
                },
                "per_page": {
                    "type": "integer",
                    "description": "Results per page (default 30).",
                },
            },
            "required": ["owner", "repo"],
        },
    },
]

# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------


def _headers():
    return {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


def _get(path, params=None):
    r = requests.get(f"{API_BASE}{path}", headers=_headers(), params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def _post(path, body):
    r = requests.post(f"{API_BASE}{path}", headers=_headers(), json=body, timeout=30)
    r.raise_for_status()
    return r.json()


# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------


def _call_tool(name, args):
    if name == "get_me":
        return _get("/user")

    if name == "list_repos":
        params = {}
        if args.get("sort"):
            params["sort"] = args["sort"]
        if args.get("per_page"):
            params["per_page"] = args["per_page"]
        return _get("/user/repos", params)

    if name == "get_repo":
        return _get(f"/repos/{args['owner']}/{args['repo']}")

    if name == "search_repos":
        params = {"q": args["q"]}
        if args.get("sort"):
            params["sort"] = args["sort"]
        if args.get("per_page"):
            params["per_page"] = args["per_page"]
        return _get("/search/repositories", params)

    if name == "list_issues":
        params = {}
        if args.get("state"):
            params["state"] = args["state"]
        if args.get("per_page"):
            params["per_page"] = args["per_page"]
        return _get(f"/repos/{args['owner']}/{args['repo']}/issues", params)

    if name == "get_issue":
        return _get(f"/repos/{args['owner']}/{args['repo']}/issues/{args['issue_number']}")

    if name == "create_issue":
        body = {"title": args["title"]}
        if args.get("body"):
            body["body"] = args["body"]
        if args.get("labels"):
            body["labels"] = args["labels"]
        return _post(f"/repos/{args['owner']}/{args['repo']}/issues", body)

    if name == "list_pull_requests":
        params = {}
        if args.get("state"):
            params["state"] = args["state"]
        if args.get("per_page"):
            params["per_page"] = args["per_page"]
        return _get(f"/repos/{args['owner']}/{args['repo']}/pulls", params)

    if name == "get_pull_request":
        return _get(f"/repos/{args['owner']}/{args['repo']}/pulls/{args['pull_number']}")

    if name == "create_pull_request":
        body = {
            "title": args["title"],
            "head": args["head"],
            "base": args["base"],
        }
        if args.get("body"):
            body["body"] = args["body"]
        return _post(f"/repos/{args['owner']}/{args['repo']}/pulls", body)

    if name == "search_code":
        params = {"q": args["q"]}
        if args.get("per_page"):
            params["per_page"] = args["per_page"]
        return _get("/search/code", params)

    if name == "list_actions_runs":
        params = {}
        if args.get("status"):
            params["status"] = args["status"]
        if args.get("per_page"):
            params["per_page"] = args["per_page"]
        return _get(f"/repos/{args['owner']}/{args['repo']}/actions/runs", params)

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
                "serverInfo": {"name": "github-mcp", "version": "1.0.0"},
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
    if not GITHUB_TOKEN:
        print("WARNING: GITHUB_TOKEN environment variable is not set.")
    app.run(host="127.0.0.1", port=5003)

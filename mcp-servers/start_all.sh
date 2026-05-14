#!/usr/bin/env bash
# Start all MCP servers in the background, optionally with the bot agent.
# Usage: ./start_all.sh [--bot]

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
START_BOT=false

for arg in "$@"; do
    case "$arg" in
        --bot) START_BOT=true ;;
    esac
done

echo "Starting Webex MCP server on port 5001..."
python3 "$DIR/webex/server.py" &
WEBEX_PID=$!

echo "Starting Jira MCP server on port 5002..."
python3 "$DIR/jira/server.py" &
JIRA_PID=$!

echo "Starting GitHub MCP server on port 5003..."
python3 "$DIR/github/server.py" &
GITHUB_PID=$!

PIDS="$WEBEX_PID $JIRA_PID $GITHUB_PID"

echo ""
echo "All MCP servers started:"
echo "  Webex  → http://localhost:5001/mcp  (PID $WEBEX_PID)"
echo "  Jira   → http://localhost:5002/mcp  (PID $JIRA_PID)"
echo "  GitHub → http://localhost:5003/mcp  (PID $GITHUB_PID)"

if [ "$START_BOT" = true ]; then
    echo ""
    echo "Starting Bot Agent on port ${BOT_PORT:-8090}..."
    # Give MCP servers a moment to start
    sleep 2
    python3 "$DIR/bot/agent.py" &
    BOT_PID=$!
    PIDS="$PIDS $BOT_PID"
    echo "  Bot    → http://localhost:${BOT_PORT:-8090}  (PID $BOT_PID)"
fi

echo ""
echo "Press Ctrl+C to stop all servers."

trap "kill $PIDS 2>/dev/null; echo 'All servers stopped.'" EXIT

wait

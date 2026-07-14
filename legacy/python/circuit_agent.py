#!/usr/bin/env python3
"""
Circuit Agent - A Cisco Circuit-powered coding assistant

Works like Claude Code: reads files, writes code, runs commands,
and helps with software engineering tasks in your project directory.

Usage:
    python circuit_agent.py [directory]
    python circuit_agent.py              # Uses current directory
    python circuit_agent.py /path/to/project

Credentials (checked in order):
    1. Config file: ~/.config/circuit-agent/config.json (saved on first run)
    2. Environment variables: CIRCUIT_CLIENT_ID, CIRCUIT_CLIENT_SECRET, CIRCUIT_APP_KEY
    3. Interactive prompt (with option to save)

New in v2.0:
    - Streaming responses for real-time output
    - CIRCUIT.md project configuration files
    - Token usage tracking (/tokens command)
    - Undo functionality (/undo command)
"""

import sys

# Check for httpx before importing the package
try:
    import httpx
except ImportError:
    print("\nError: httpx not installed.")
    print("Install it with: pip install httpx\n")
    sys.exit(1)

# Import and run the CLI
from circuit_agent import main

if __name__ == "__main__":
    main()

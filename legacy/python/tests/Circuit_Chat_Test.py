#!/usr/bin/env python3
"""
Cisco Circuit Chat Test

A standalone tool to test and chat with Cisco Circuit AI.
Enter your credentials and start chatting immediately.

Usage:
    python Circuit_Chat_Test.py
"""

import asyncio
import base64
import json
import os
import sys
from getpass import getpass

try:
    import httpx
except ImportError:
    print("\nError: httpx not installed.")
    print("Install it with: pip install httpx\n")
    sys.exit(1)


# ============================================================================
# Configuration
# ============================================================================

TOKEN_URL = "https://id.cisco.com/oauth2/default/v1/token"
CHAT_BASE_URL = "https://chat-ai.cisco.com/openai/deployments"
API_VERSION = "2025-04-01-preview"

# SSL Configuration - Enable verification by default for security
# Set CIRCUIT_DISABLE_SSL_VERIFY=1 only for development/testing with self-signed certs
SSL_VERIFY = not os.environ.get("CIRCUIT_DISABLE_SSL_VERIFY", "").lower() in ("1", "true", "yes")
if not SSL_VERIFY:
    import warnings
    warnings.warn("SSL verification disabled - NOT recommended for production!", UserWarning)

MODELS = {
    "1": ("gpt-4.1", "GPT-4.1 - Complex reasoning (120K context)"),
    "2": ("gpt-4o", "GPT-4o - Fast multimodal (120K context)"),
    "3": ("gpt-4o-mini", "GPT-4o Mini - Quick & efficient (120K context)"),
    "4": ("o4-mini", "o4-mini - Large context (200K context)"),
}


# ============================================================================
# Terminal Colors
# ============================================================================

class C:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    MAGENTA = "\033[95m"
    BLUE = "\033[94m"
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"


def clear():
    os.system('cls' if os.name == 'nt' else 'clear')


# ============================================================================
# Cisco Circuit Client
# ============================================================================

class CircuitClient:
    def __init__(self, client_id: str, client_secret: str, app_key: str):
        self.client_id = client_id
        self.client_secret = client_secret
        self.app_key = app_key
        self._token = None
        self._expiry = 0
        self.model = "gpt-4o-mini"
        self.history = []

    async def get_token(self) -> str:
        """Get OAuth access token."""
        import time
        if self._token and time.time() < (self._expiry - 300):
            return self._token

        creds = f"{self.client_id}:{self.client_secret}"
        auth = base64.b64encode(creds.encode()).decode()

        async with httpx.AsyncClient(verify=SSL_VERIFY, timeout=30.0) as client:
            r = await client.post(
                TOKEN_URL,
                headers={
                    "Authorization": f"Basic {auth}",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
                data="grant_type=client_credentials",
            )
            if r.status_code != 200:
                raise Exception(f"Auth failed: {r.status_code} - {r.text}")

            data = r.json()
            self._token = data["access_token"]
            self._expiry = time.time() + data.get("expires_in", 3600)
            return self._token

    async def chat(self, message: str) -> str:
        """Send message and get response."""
        token = await self.get_token()

        self.history.append({"role": "user", "content": message})

        url = f"{CHAT_BASE_URL}/{self.model}/chat/completions?api-version={API_VERSION}"

        async with httpx.AsyncClient(verify=SSL_VERIFY, timeout=60.0) as client:
            r = await client.post(
                url,
                headers={"Content-Type": "application/json", "api-key": token},
                json={
                    "messages": self.history,
                    "user": json.dumps({"appkey": self.app_key}),
                    "temperature": 0.7,
                    "max_tokens": 2048,
                },
            )
            if r.status_code != 200:
                raise Exception(f"Chat failed: {r.status_code} - {r.text[:200]}")

            content = r.json()["choices"][0]["message"]["content"]
            self.history.append({"role": "assistant", "content": content})
            return content


# ============================================================================
# Main
# ============================================================================

async def main():
    clear()
    print(f"""
{C.CYAN}╔══════════════════════════════════════════════════════════╗
║             Cisco Circuit Chat Test                      ║
╚══════════════════════════════════════════════════════════╝{C.RESET}

{C.BOLD}Enter your Cisco Circuit credentials:{C.RESET}

  Get these from: {C.CYAN}https://developer.cisco.com/site/ai-ml/{C.RESET}
  → Manage Circuit API Keys → View
""")

    # Get credentials
    client_id = input(f"  {C.CYAN}Client ID:{C.RESET} ").strip()
    client_secret = getpass(f"  {C.CYAN}Client Secret:{C.RESET} ").strip()
    app_key = input(f"  {C.CYAN}App Key:{C.RESET} ").strip()

    if not all([client_id, client_secret, app_key]):
        print(f"\n  {C.RED}✗ All credentials are required{C.RESET}\n")
        sys.exit(1)

    # Test connection
    print(f"\n  {C.DIM}Testing connection...{C.RESET}")
    client = CircuitClient(client_id, client_secret, app_key)

    try:
        await client.get_token()
        print(f"  {C.GREEN}✓ Authentication successful!{C.RESET}")
    except Exception as e:
        print(f"  {C.RED}✗ Authentication failed: {e}{C.RESET}\n")
        sys.exit(1)

    # Select model
    print(f"""
{C.BOLD}Select a model:{C.RESET}
""")
    for k, (_, desc) in MODELS.items():
        print(f"  {C.CYAN}{k}){C.RESET} {desc}")

    choice = input(f"\n  Choice [{C.GREEN}3{C.RESET}]: ").strip() or "3"
    if choice in MODELS:
        client.model = MODELS[choice][0]
    print(f"  {C.GREEN}→ Using {client.model}{C.RESET}")

    # Chat loop
    print(f"""
{C.CYAN}{'─' * 60}{C.RESET}
{C.BOLD}Start chatting!{C.RESET} (type 'quit' to exit, 'clear' to reset)
{C.CYAN}{'─' * 60}{C.RESET}
""")

    while True:
        try:
            user_input = input(f"{C.BLUE}You:{C.RESET} ").strip()

            if not user_input:
                continue
            if user_input.lower() in ['quit', 'exit', 'q']:
                print(f"\n{C.CYAN}Goodbye!{C.RESET}\n")
                break
            if user_input.lower() == 'clear':
                client.history = []
                print(f"  {C.GREEN}✓ Conversation cleared{C.RESET}\n")
                continue

            print(f"{C.DIM}  Thinking...{C.RESET}", end="\r")
            response = await client.chat(user_input)
            print(" " * 20, end="\r")

            print(f"\n{C.MAGENTA}Circuit:{C.RESET} {response}\n")

        except KeyboardInterrupt:
            print(f"\n\n{C.CYAN}Goodbye!{C.RESET}\n")
            break
        except Exception as e:
            print(f"  {C.RED}Error: {e}{C.RESET}\n")


if __name__ == "__main__":
    asyncio.run(main())

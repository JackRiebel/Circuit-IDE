"""
Pytest configuration and shared fixtures for Circuit Agent tests.
"""

import os
import json
import tempfile
import shutil
from pathlib import Path
from typing import Generator, Dict, Any
from unittest.mock import MagicMock, AsyncMock, patch

import pytest


# ============================================================================
# Directory Fixtures
# ============================================================================

@pytest.fixture
def temp_dir() -> Generator[Path, None, None]:
    """Create a temporary directory for test files."""
    path = Path(tempfile.mkdtemp(prefix="circuit_test_"))
    yield path
    shutil.rmtree(path, ignore_errors=True)


@pytest.fixture
def project_dir(temp_dir: Path) -> Path:
    """Create a mock project directory with common files."""
    # Create directory structure
    (temp_dir / "src").mkdir()
    (temp_dir / "tests").mkdir()
    (temp_dir / ".git").mkdir()

    # Create some sample files
    (temp_dir / "README.md").write_text("# Test Project\n\nA test project.")
    (temp_dir / "pyproject.toml").write_text(
        '[project]\nname = "test-project"\nversion = "1.0.0"\n'
    )
    (temp_dir / "src" / "__init__.py").write_text("")
    (temp_dir / "src" / "main.py").write_text(
        'def main():\n    print("Hello, World!")\n\nif __name__ == "__main__":\n    main()\n'
    )
    (temp_dir / "src" / "utils.py").write_text(
        'def add(a, b):\n    return a + b\n\ndef multiply(a, b):\n    return a * b\n'
    )
    (temp_dir / "tests" / "test_main.py").write_text(
        'def test_placeholder():\n    assert True\n'
    )

    return temp_dir


@pytest.fixture
def config_dir(temp_dir: Path) -> Path:
    """Create a temporary config directory."""
    config_path = temp_dir / ".config" / "circuit-agent"
    config_path.mkdir(parents=True)
    return config_path


# ============================================================================
# Mock Credentials
# ============================================================================

@pytest.fixture
def mock_credentials() -> Dict[str, str]:
    """Mock API credentials for testing."""
    return {
        "client_id": "test_client_id_12345",
        "client_secret": "test_client_secret_67890",
        "app_key": "test_app_key_abcdef",
    }


@pytest.fixture
def credentials_file(config_dir: Path, mock_credentials: Dict[str, str]) -> Path:
    """Create a mock credentials file."""
    creds_file = config_dir / "config.json"
    creds_file.write_text(json.dumps(mock_credentials, indent=2))
    return creds_file


# ============================================================================
# Mock API Responses
# ============================================================================

@pytest.fixture
def mock_token_response() -> Dict[str, Any]:
    """Mock OAuth token response."""
    return {
        "access_token": "mock_access_token_xyz",
        "token_type": "Bearer",
        "expires_in": 3600,
    }


@pytest.fixture
def mock_chat_response() -> Dict[str, Any]:
    """Mock chat completion response (non-streaming)."""
    return {
        "id": "chatcmpl-123",
        "object": "chat.completion",
        "created": 1677652288,
        "model": "gpt-4o",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": "This is a test response from the assistant.",
                },
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": 100,
            "completion_tokens": 50,
            "total_tokens": 150,
        },
    }


@pytest.fixture
def mock_chat_response_with_tool_call() -> Dict[str, Any]:
    """Mock chat completion response with a tool call."""
    return {
        "id": "chatcmpl-456",
        "object": "chat.completion",
        "created": 1677652288,
        "model": "gpt-4o",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [
                        {
                            "id": "call_abc123",
                            "type": "function",
                            "function": {
                                "name": "read_file",
                                "arguments": '{"path": "src/main.py"}',
                            },
                        }
                    ],
                },
                "finish_reason": "tool_calls",
            }
        ],
        "usage": {
            "prompt_tokens": 100,
            "completion_tokens": 25,
            "total_tokens": 125,
        },
    }


# ============================================================================
# Mock HTTP Client
# ============================================================================

@pytest.fixture
def mock_httpx_client():
    """Create a mock httpx.AsyncClient."""
    client = AsyncMock()
    return client


@pytest.fixture
def mock_httpx_response():
    """Create a factory for mock httpx responses."""
    def _create_response(
        status_code: int = 200,
        json_data: Dict[str, Any] = None,
        text: str = None
    ):
        response = MagicMock()
        response.status_code = status_code
        response.json.return_value = json_data or {}
        response.text = text or json.dumps(json_data or {})
        return response
    return _create_response


# ============================================================================
# Tool Fixtures
# ============================================================================

@pytest.fixture
def file_tools(project_dir: Path):
    """Create FileTools instance for testing."""
    from circuit_agent.tools import FileTools, BackupManager
    from circuit_agent.errors import SmartError

    backup_manager = BackupManager(str(project_dir))
    smart_error = SmartError(str(project_dir))
    return FileTools(str(project_dir), backup_manager, smart_error)


@pytest.fixture
def git_tools(project_dir: Path):
    """Create GitTools instance for testing."""
    from circuit_agent.tools import GitTools
    from circuit_agent.errors import SmartError

    smart_error = SmartError(str(project_dir))
    return GitTools(str(project_dir), smart_error)


@pytest.fixture
def backup_manager(project_dir: Path):
    """Create BackupManager instance for testing."""
    from circuit_agent.tools import BackupManager
    return BackupManager(str(project_dir))


# ============================================================================
# Agent Fixtures
# ============================================================================

@pytest.fixture
def mock_agent(project_dir: Path, mock_credentials: Dict[str, str]):
    """Create a mock CircuitAgent for testing (without API calls)."""
    from circuit_agent import CircuitAgent

    with patch.object(CircuitAgent, 'get_token', new_callable=AsyncMock) as mock_token:
        mock_token.return_value = "mock_token"
        agent = CircuitAgent(
            client_id=mock_credentials["client_id"],
            client_secret=mock_credentials["client_secret"],
            app_key=mock_credentials["app_key"],
            working_dir=str(project_dir),
        )
        agent._token = "mock_token"
        agent._expiry = float('inf')  # Never expires
        yield agent


# ============================================================================
# Environment Fixtures
# ============================================================================

@pytest.fixture
def clean_env():
    """Temporarily clear Circuit-related environment variables."""
    env_vars = [
        "CIRCUIT_CLIENT_ID",
        "CIRCUIT_CLIENT_SECRET",
        "CIRCUIT_APP_KEY",
        "CIRCUIT_SSL_VERIFY",
        "CIRCUIT_CA_BUNDLE",
    ]
    original = {k: os.environ.pop(k, None) for k in env_vars}
    yield
    for k, v in original.items():
        if v is not None:
            os.environ[k] = v


@pytest.fixture
def mock_env(mock_credentials: Dict[str, str]):
    """Set mock environment variables."""
    env_vars = {
        "CIRCUIT_CLIENT_ID": mock_credentials["client_id"],
        "CIRCUIT_CLIENT_SECRET": mock_credentials["client_secret"],
        "CIRCUIT_APP_KEY": mock_credentials["app_key"],
    }
    original = {}
    for k, v in env_vars.items():
        original[k] = os.environ.get(k)
        os.environ[k] = v
    yield
    for k, v in original.items():
        if v is not None:
            os.environ[k] = v
        else:
            os.environ.pop(k, None)


# ============================================================================
# Async Test Support
# ============================================================================

@pytest.fixture
def event_loop():
    """Create an event loop for async tests."""
    import asyncio
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


# ============================================================================
# Markers
# ============================================================================

def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests as integration tests"
    )
    config.addinivalue_line(
        "markers", "requires_network: marks tests that require network access"
    )

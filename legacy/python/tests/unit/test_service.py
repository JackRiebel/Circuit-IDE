"""
Unit tests for the unified service layer.

Tests events, state management, and AgentService.
"""

import pytest
import asyncio
from datetime import datetime
from unittest.mock import MagicMock, AsyncMock, patch


class TestEventEmitter:
    """Tests for EventEmitter."""

    def test_emit_event(self):
        """Should emit events to handlers."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()
        received = []

        def handler(event):
            received.append(event)

        emitter.on(EventType.MESSAGE_CHUNK, handler)
        emitter.emit(EventType.MESSAGE_CHUNK, {"content": "Hello"})

        assert len(received) == 1
        assert received[0].data["content"] == "Hello"

    def test_multiple_handlers(self):
        """Should call multiple handlers for same event."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()
        results = []

        emitter.on(EventType.CONNECTED, lambda e: results.append("a"))
        emitter.on(EventType.CONNECTED, lambda e: results.append("b"))
        emitter.emit(EventType.CONNECTED)

        assert results == ["a", "b"]

    def test_unsubscribe(self):
        """Should stop calling handler after unsubscribe."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()
        count = [0]

        def handler(e):
            count[0] += 1

        emitter.on(EventType.MESSAGE_CHUNK, handler)
        emitter.emit(EventType.MESSAGE_CHUNK)
        assert count[0] == 1

        emitter.off(EventType.MESSAGE_CHUNK, handler)
        emitter.emit(EventType.MESSAGE_CHUNK)
        assert count[0] == 1  # Should not increase

    def test_on_all(self):
        """Should receive all events with on_all."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()
        events = []

        emitter.on_all(lambda e: events.append(e.type))
        emitter.emit(EventType.CONNECTED)
        emitter.emit(EventType.MESSAGE_CHUNK)
        emitter.emit(EventType.DISCONNECTED)

        assert EventType.CONNECTED in events
        assert EventType.MESSAGE_CHUNK in events
        assert EventType.DISCONNECTED in events

    def test_handler_error_doesnt_break_others(self):
        """Handler errors should not break other handlers."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()
        results = []

        def bad_handler(e):
            raise ValueError("Oops!")

        def good_handler(e):
            results.append("ok")

        emitter.on(EventType.CONNECTED, bad_handler)
        emitter.on(EventType.CONNECTED, good_handler)

        # Should not raise, and good_handler should still be called
        emitter.emit(EventType.CONNECTED)
        assert "ok" in results

    def test_handler_count(self):
        """Should count handlers correctly."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()

        assert emitter.handler_count() == 0

        emitter.on(EventType.CONNECTED, lambda e: None)
        assert emitter.handler_count(EventType.CONNECTED) == 1

        emitter.on(EventType.CONNECTED, lambda e: None)
        assert emitter.handler_count(EventType.CONNECTED) == 2

    def test_clear_handlers(self):
        """Should clear handlers."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()
        emitter.on(EventType.CONNECTED, lambda e: None)
        emitter.on(EventType.MESSAGE_CHUNK, lambda e: None)

        emitter.clear(EventType.CONNECTED)
        assert emitter.handler_count(EventType.CONNECTED) == 0
        assert emitter.handler_count(EventType.MESSAGE_CHUNK) == 1

        emitter.clear()
        assert emitter.handler_count() == 0

    @pytest.mark.asyncio
    async def test_async_emit(self):
        """Should handle async event emission."""
        from circuit_agent.service import EventEmitter, EventType

        emitter = EventEmitter()
        results = []

        async def async_handler(event):
            await asyncio.sleep(0.01)
            results.append("async")

        def sync_handler(event):
            results.append("sync")

        emitter.on(EventType.CONNECTED, sync_handler)
        emitter.on(EventType.CONNECTED, async_handler, is_async=True)

        await emitter.emit_async(EventType.CONNECTED)

        assert "sync" in results
        assert "async" in results


class TestEvent:
    """Tests for Event dataclass."""

    def test_event_creation(self):
        """Should create event with type and data."""
        from circuit_agent.service import Event, EventType

        event = Event(type=EventType.MESSAGE_CHUNK, data={"content": "Hello"})

        assert event.type == EventType.MESSAGE_CHUNK
        assert event.data["content"] == "Hello"
        assert event.timestamp is not None

    def test_event_default_data(self):
        """Should have empty dict as default data."""
        from circuit_agent.service import Event, EventType

        event = Event(type=EventType.CONNECTED)

        assert event.data == {}


class TestChatMessage:
    """Tests for ChatMessage."""

    def test_message_creation(self):
        """Should create message with required fields."""
        from circuit_agent.service import ChatMessage, MessageRole

        msg = ChatMessage(
            id="msg-1",
            role=MessageRole.USER,
            content="Hello",
        )

        assert msg.id == "msg-1"
        assert msg.role == MessageRole.USER
        assert msg.content == "Hello"
        assert msg.is_streaming is False

    def test_message_immutable(self):
        """ChatMessage should be immutable."""
        from circuit_agent.service import ChatMessage, MessageRole

        msg = ChatMessage(
            id="msg-1",
            role=MessageRole.USER,
            content="Hello",
        )

        with pytest.raises(Exception):  # frozen dataclass
            msg.content = "Changed"

    def test_with_content(self):
        """Should create new message with updated content."""
        from circuit_agent.service import ChatMessage, MessageRole

        msg1 = ChatMessage(
            id="msg-1",
            role=MessageRole.USER,
            content="Hello",
        )

        msg2 = msg1.with_content("Updated")

        assert msg1.content == "Hello"  # Original unchanged
        assert msg2.content == "Updated"
        assert msg2.id == msg1.id

    def test_with_streaming(self):
        """Should create new message with updated streaming status."""
        from circuit_agent.service import ChatMessage, MessageRole

        msg1 = ChatMessage(
            id="msg-1",
            role=MessageRole.ASSISTANT,
            content="",
            is_streaming=True,
        )

        msg2 = msg1.with_streaming(False)

        assert msg1.is_streaming is True
        assert msg2.is_streaming is False


class TestToolCallInfo:
    """Tests for ToolCallInfo."""

    def test_tool_call_creation(self):
        """Should create tool call info."""
        from circuit_agent.service import ToolCallInfo, ToolStatus

        tool = ToolCallInfo(
            id="tool-1",
            name="read_file",
            arguments={"path": "src/main.py"},
        )

        assert tool.id == "tool-1"
        assert tool.name == "read_file"
        assert tool.status == ToolStatus.PENDING

    def test_tool_detail(self):
        """Should generate appropriate detail string."""
        from circuit_agent.service import ToolCallInfo

        read_tool = ToolCallInfo(
            id="1", name="read_file",
            arguments={"path": "src/main.py"}
        )
        assert read_tool.detail == "src/main.py"

        cmd_tool = ToolCallInfo(
            id="2", name="run_command",
            arguments={"command": "pytest"}
        )
        assert "pytest" in cmd_tool.detail

    def test_with_status(self):
        """Should create new tool call with updated status."""
        from circuit_agent.service import ToolCallInfo, ToolStatus

        tool1 = ToolCallInfo(
            id="tool-1",
            name="read_file",
            arguments={"path": "test.py"},
            status=ToolStatus.PENDING,
        )

        tool2 = tool1.with_status(ToolStatus.SUCCESS, result="file content")

        assert tool1.status == ToolStatus.PENDING
        assert tool2.status == ToolStatus.SUCCESS
        assert tool2.result == "file content"


class TestAgentState:
    """Tests for AgentState."""

    def test_initial_state(self):
        """Should have correct initial state."""
        from circuit_agent.service import AgentState, ConnectionStatus

        state = AgentState()

        assert state.connection_status == ConnectionStatus.DISCONNECTED
        assert state.model == "gpt-4o"
        assert state.auto_approve is False
        assert state.is_processing is False
        assert state.messages == []

    def test_is_connected(self):
        """Should report connection status correctly."""
        from circuit_agent.service import AgentState, ConnectionStatus

        disconnected = AgentState(connection_status=ConnectionStatus.DISCONNECTED)
        assert disconnected.is_connected is False

        connected = AgentState(connection_status=ConnectionStatus.CONNECTED)
        assert connected.is_connected is True

    def test_can_send_message(self):
        """Should check if message can be sent."""
        from circuit_agent.service import AgentState, ConnectionStatus

        # Can send when connected and not processing
        state = AgentState(
            connection_status=ConnectionStatus.CONNECTED,
            is_processing=False,
        )
        assert state.can_send_message is True

        # Cannot send when disconnected
        state = AgentState(connection_status=ConnectionStatus.DISCONNECTED)
        assert state.can_send_message is False

        # Cannot send when processing
        state = AgentState(
            connection_status=ConnectionStatus.CONNECTED,
            is_processing=True,
        )
        assert state.can_send_message is False

    def test_add_message(self):
        """Should create new state with added message."""
        from circuit_agent.service import AgentState, ChatMessage, MessageRole

        state1 = AgentState()
        msg = ChatMessage(id="1", role=MessageRole.USER, content="Hi")

        state2 = state1.add_message(msg)

        assert len(state1.messages) == 0  # Original unchanged
        assert len(state2.messages) == 1
        assert state2.messages[0].content == "Hi"

    def test_clear_messages(self):
        """Should create new state with cleared messages."""
        from circuit_agent.service import AgentState, ChatMessage, MessageRole

        msg = ChatMessage(id="1", role=MessageRole.USER, content="Hi")
        state1 = AgentState(messages=[msg])

        state2 = state1.clear_messages()

        assert len(state1.messages) == 1  # Original unchanged
        assert len(state2.messages) == 0

    def test_total_tokens(self):
        """Should calculate total tokens."""
        from circuit_agent.service import AgentState, TokenUsage

        state = AgentState(
            session_tokens=TokenUsage(prompt_tokens=100, completion_tokens=50)
        )

        assert state.total_tokens == 150


class TestAgentService:
    """Tests for AgentService."""

    def test_service_creation(self, temp_dir):
        """Should create service with default settings."""
        from circuit_agent.service import AgentService, ConnectionStatus

        service = AgentService(working_dir=str(temp_dir))

        assert service.state.connection_status == ConnectionStatus.DISCONNECTED
        assert service.state.model == "gpt-4o"
        assert service.is_connected is False

    def test_service_event_subscription(self, temp_dir):
        """Should allow event subscription."""
        from circuit_agent.service import AgentService, EventType

        service = AgentService(working_dir=str(temp_dir))
        received = []

        service.on(EventType.STATUS_CHANGED, lambda e: received.append(e))
        service.set_auto_approve(True)

        assert len(received) == 1
        assert received[0].data["auto_approve"] is True

    def test_set_model(self, temp_dir):
        """Should update model setting."""
        from circuit_agent.service import AgentService, EventType

        service = AgentService(working_dir=str(temp_dir))
        events = []

        service.on(EventType.MODEL_CHANGED, lambda e: events.append(e))
        service.set_model("gpt-4o-mini")

        assert service.state.model == "gpt-4o-mini"
        assert len(events) == 1

    def test_set_auto_approve(self, temp_dir):
        """Should update auto-approve setting."""
        from circuit_agent.service import AgentService

        service = AgentService(working_dir=str(temp_dir))

        assert service.state.auto_approve is False

        service.set_auto_approve(True)
        assert service.state.auto_approve is True

        service.set_auto_approve(False)
        assert service.state.auto_approve is False

    def test_set_thinking_mode(self, temp_dir):
        """Should update thinking mode setting."""
        from circuit_agent.service import AgentService

        service = AgentService(working_dir=str(temp_dir))

        assert service.state.thinking_mode is False

        service.set_thinking_mode(True)
        assert service.state.thinking_mode is True

    def test_clear_history(self, temp_dir):
        """Should clear message history."""
        from circuit_agent.service import AgentService, EventType

        service = AgentService(working_dir=str(temp_dir))
        events = []

        service.on(EventType.HISTORY_CLEARED, lambda e: events.append(e))
        service.clear_history()

        assert service.state.messages == []
        assert len(events) == 1

    def test_get_token_stats(self, temp_dir):
        """Should return token statistics."""
        from circuit_agent.service import AgentService

        service = AgentService(working_dir=str(temp_dir))
        stats = service.get_token_stats()

        assert "session_total" in stats
        assert "last_total" in stats
        assert stats["session_total"] == 0

    def test_get_cost_stats(self, temp_dir):
        """Should return cost statistics."""
        from circuit_agent.service import AgentService

        service = AgentService(working_dir=str(temp_dir))
        stats = service.get_cost_stats()

        assert "total_cost_usd" in stats
        assert stats["total_cost_usd"] == 0

    @pytest.mark.asyncio
    async def test_connect_without_credentials(self, temp_dir):
        """Should fail connection without credentials."""
        from circuit_agent.service import AgentService, ConnectionStatus

        service = AgentService(working_dir=str(temp_dir))

        with patch("circuit_agent.config.load_credentials") as mock_creds:
            mock_creds.return_value = (None, None, None)
            result = await service.connect_with_saved_credentials()

        assert result is False
        assert service.state.connection_status == ConnectionStatus.ERROR

    @pytest.mark.asyncio
    async def test_disconnect(self, temp_dir):
        """Should disconnect properly."""
        from circuit_agent.service import AgentService, EventType, ConnectionStatus

        service = AgentService(working_dir=str(temp_dir))
        events = []

        service.on(EventType.DISCONNECTED, lambda e: events.append(e))
        service.disconnect()

        assert service.state.connection_status == ConnectionStatus.DISCONNECTED
        assert len(events) == 1

    @pytest.mark.asyncio
    async def test_send_message_when_not_connected(self, temp_dir):
        """Should fail to send message when not connected."""
        from circuit_agent.service import AgentService, EventType

        service = AgentService(working_dir=str(temp_dir))
        errors = []

        service.on(EventType.MESSAGE_ERROR, lambda e: errors.append(e))
        result = await service.send_message("Hello")

        assert result is None
        assert len(errors) == 1
        assert "Not connected" in errors[0].data["error"]


class TestConfirmationRequest:
    """Tests for ConfirmationRequest."""

    def test_confirmation_creation(self):
        """Should create confirmation request."""
        from circuit_agent.service import ConfirmationRequest, ToolCallInfo

        tool = ToolCallInfo(id="1", name="write_file", arguments={"path": "test.py"})
        request = ConfirmationRequest(
            id="confirm-1",
            tool_call=tool,
            message="Allow write_file?",
        )

        assert request.id == "confirm-1"
        assert request.tool_name == "write_file"
        assert request.timeout == 60.0

    def test_dangerous_flag(self):
        """Should track dangerous operations."""
        from circuit_agent.service import ConfirmationRequest, ToolCallInfo

        tool = ToolCallInfo(id="1", name="run_command", arguments={"command": "rm -rf /"})
        request = ConfirmationRequest(
            id="confirm-1",
            tool_call=tool,
            message="Allow dangerous command?",
            is_dangerous=True,
        )

        assert request.is_dangerous is True

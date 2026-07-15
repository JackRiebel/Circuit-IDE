import 'dart:async';
import 'dart:convert';

class SSEEvent {
  final String? event;
  final String data;
  final String? id;

  const SSEEvent({this.event, required this.data, this.id});
}

class SSEParser {
  final StreamController<SSEEvent> _controller = StreamController<SSEEvent>();
  String _buffer = '';
  String? _currentEvent;
  String _currentData = '';
  String? _currentId;

  Stream<SSEEvent> get stream => _controller.stream;

  void addData(String chunk) {
    _buffer += chunk;

    while (_buffer.contains('\n')) {
      final newlineIndex = _buffer.indexOf('\n');
      final line = _buffer.substring(0, newlineIndex).trimRight();
      _buffer = _buffer.substring(newlineIndex + 1);

      _processLine(line);
    }
  }

  void _processLine(String line) {
    if (line.isEmpty) {
      // Empty line = dispatch event
      if (_currentData.isNotEmpty) {
        _controller.add(
          SSEEvent(
            event: _currentEvent,
            data: _currentData.trimRight(),
            id: _currentId,
          ),
        );
      }
      _currentEvent = null;
      _currentData = '';
      _currentId = null;
      return;
    }

    if (line.startsWith(':')) return; // Comment

    if (line.startsWith('event:')) {
      _currentEvent = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      final value = line.substring(5).trim();
      if (_currentData.isNotEmpty) {
        _currentData += '\n';
      }
      _currentData += value;
    } else if (line.startsWith('id:')) {
      _currentId = line.substring(3).trim();
    }
  }

  void close() {
    // Flush any remaining data
    if (_currentData.isNotEmpty) {
      _controller.add(
        SSEEvent(
          event: _currentEvent,
          data: _currentData.trimRight(),
          id: _currentId,
        ),
      );
    }
    _controller.close();
  }
}

/// Parses OpenAI-compatible SSE stream chunks into structured data
class OpenAISSEParser {
  static Map<String, dynamic>? parseChunk(String data) {
    if (data == '[DONE]') return null;
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

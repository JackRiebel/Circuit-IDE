import 'dart:async';

import '../enums/event_type.dart';

class Event {
  final EventType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  Event({required this.type, Map<String, dynamic>? data, DateTime? timestamp})
    : data = data ?? {},
      timestamp = timestamp ?? DateTime.now();
}

typedef EventHandler = void Function(Event event);

class EventBus {
  final _handlers = <EventType, List<EventHandler>>{};
  final _controller = StreamController<Event>.broadcast();

  Stream<Event> get stream => _controller.stream;

  void on(EventType type, EventHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  void off(EventType type, EventHandler handler) {
    _handlers[type]?.remove(handler);
  }

  void emit(EventType type, [Map<String, dynamic>? data]) {
    final event = Event(type: type, data: data ?? {});

    // Notify specific handlers
    final handlers = _handlers[type];
    if (handlers != null) {
      for (final handler in List.of(handlers)) {
        handler(event);
      }
    }

    // Broadcast to stream
    _controller.add(event);
  }

  Stream<Event> where(EventType type) {
    return _controller.stream.where((e) => e.type == type);
  }

  void dispose() {
    _handlers.clear();
    _controller.close();
  }
}

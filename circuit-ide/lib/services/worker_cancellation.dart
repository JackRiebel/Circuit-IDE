import 'dart:async';
import 'dart:isolate';

/// Cancellation state shared by a caller and a worker-isolate request.
///
/// The token stays on the calling isolate. [CancellableWorker] observes it and
/// terminates the worker isolate immediately, so cancelled work cannot keep
/// consuming CPU after its UI owner has gone away.
class WorkerCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  String? _reason;
  String? get reason => _reason;

  void cancel([String reason = 'Worker task cancelled.']) {
    if (isCancelled) return;
    _reason = reason;
    _cancelled.complete();
  }
}

class WorkerCancelledException implements Exception {
  final String message;

  const WorkerCancelledException([this.message = 'Worker task cancelled.']);

  @override
  String toString() => message;
}

/// Runs a top-level worker entry point with a cancellation-aware lifecycle.
///
/// Worker entry points receive [arguments] plus a `replyPort`. They must send a
/// map containing either `result` or `error` to that port. Keeping the protocol
/// JSON-shaped makes the isolate boundary explicit and transferable.
typedef WorkerEntrypoint = void Function(Map<String, Object?> arguments);

class CancellableWorker {
  static Future<T> run<T>({
    required WorkerEntrypoint entryPoint,
    required Map<String, Object?> arguments,
    required T Function(Object? result) decodeResult,
    WorkerCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      throw WorkerCancelledException(
        cancellationToken!.reason ?? 'Worker task cancelled.',
      );
    }

    final replyPort = ReceivePort();
    Isolate? isolate;
    var receivedResponse = false;
    try {
      isolate = await Isolate.spawn<Map<String, Object?>>(entryPoint, {
        ...arguments,
        'replyPort': replyPort.sendPort,
      }, errorsAreFatal: true);
      final response = await _nextResponse(
        replyPort,
        cancellationToken: cancellationToken,
      );
      receivedResponse = true;
      final error = response['error']?.toString().trim();
      if (error != null && error.isNotEmpty) {
        throw StateError(error);
      }
      return decodeResult(response['result']);
    } finally {
      replyPort.close();
      if (!receivedResponse) {
        isolate?.kill(priority: Isolate.immediate);
      }
    }
  }

  static Future<Map<String, Object?>> _nextResponse(
    ReceivePort replyPort, {
    required WorkerCancellationToken? cancellationToken,
  }) async {
    final response = replyPort.first.then((message) {
      if (message is! Map) {
        throw StateError('Worker returned a malformed response.');
      }
      return Map<String, Object?>.from(message);
    });
    if (cancellationToken == null) return response;
    return Future.any<Map<String, Object?>>([
      response,
      cancellationToken.whenCancelled.then((_) {
        throw WorkerCancelledException(
          cancellationToken.reason ?? 'Worker task cancelled.',
        );
      }),
    ]);
  }
}

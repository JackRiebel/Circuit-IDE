import 'dart:convert';
import 'dart:typed_data';

import 'package:circuit_ide/agent/providers/cisco_stream_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stream support preserves split UTF-8 and reports nonempty byte chunks',
    () async {
      final bytes = utf8.encode('Ready ✓');
      var firstByteCount = 0;
      final text = await CiscoStreamSupport.decodeUtf8Stream(
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList(bytes.sublist(0, 7)),
          Uint8List.fromList(bytes.sublist(7)),
        ]),
        idleTimeout: const Duration(seconds: 1),
        onFirstByte: () => firstByteCount++,
      ).join();

      expect(text, 'Ready ✓');
      expect(firstByteCount, 2);
    },
  );

  test(
    'stream support keeps JSON/SSE classification and redacts SSE errors',
    () {
      expect(CiscoStreamSupport.isJsonContentType('application/json'), isTrue);
      expect(
        CiscoStreamSupport.isJsonContentType('text/event-stream'),
        isFalse,
      );
      expect(CiscoStreamSupport.looksLikeSsePayload('data: {}'), isTrue);
      expect(
        CiscoStreamSupport.looksLikeSsePayload('{"choices": []}'),
        isFalse,
      );
      final detail = CiscoStreamSupport.sseErrorEventMessage(
        '{"message":"provider-response-secret"}',
      );
      expect(detail, 'provider reported an SSE error.');
      expect(detail, isNot(contains('provider-response-secret')));
    },
  );
}

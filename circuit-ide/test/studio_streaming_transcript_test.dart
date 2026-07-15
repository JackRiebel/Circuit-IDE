import 'package:circuit_ide/ui/studio/studio_task_transcript_messages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';

void main() {
  Widget host({required String text, required bool streaming}) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 720,
            child: StudioTaskChatTranscriptLine(
              isUser: false,
              text: text,
              isStreaming: streaming,
            ),
          ),
        ),
      ),
    ),
  );

  String renderedStreamingText(WidgetTester tester) {
    final textWidgets = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('studio-streaming-assistant-text')),
        matching: find.byType(Text),
      ),
    );
    return textWidgets
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .join();
  }

  testWidgets(
    'streaming transcript freezes a bounded prefix and restores Markdown on completion',
    (tester) async {
      final first = List<String>.filled(1100, 'stream ').join();
      final complete = '$first${List<String>.filled(900, 'tail ').join()}';

      await tester.pumpWidget(host(text: first, streaming: true));
      expect(
        find.byKey(const ValueKey('studio-streaming-frozen-0')),
        findsOneWidget,
      );
      expect(renderedStreamingText(tester), first);

      await tester.pumpWidget(host(text: complete, streaming: true));
      expect(renderedStreamingText(tester), complete);
      expect(find.byType(MarkdownWidget), findsNothing);

      await tester.pumpWidget(host(text: complete, streaming: false));
      expect(find.byType(MarkdownWidget), findsOneWidget);
      expect(
        find.byKey(const ValueKey('studio-streaming-assistant-text')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}

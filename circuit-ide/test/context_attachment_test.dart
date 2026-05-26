import 'package:circuit_ide/models/context_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ContextAttachment serializes visible context into prompt blocks', () {
    final attachment = ContextAttachment(
      id: 'a1',
      type: ContextAttachmentType.file,
      label: 'main.dart',
      path: '/tmp/project/main.dart',
      content: 'class App {}',
      createdAt: DateTime(2026, 5, 25),
    );

    expect(attachment.promptHeader, contains('main.dart'));
    expect(attachment.promptHeader, contains('/tmp/project/main.dart'));
    expect(attachment.toPromptBlock(), contains('class App {}'));
  });

  test('ContextAttachment preserves preview metadata through JSON', () {
    final attachment = ContextAttachment(
      id: 'a2',
      type: ContextAttachmentType.file,
      label: 'big.dart',
      path: '/tmp/project/big.dart',
      content: 'void main() {}',
      resolutionStatus: ContextAttachmentResolutionStatus.tooLarge,
      estimatedTokens: 42,
      truncationMessage: '[Context truncated.]',
      createdAt: DateTime(2026, 5, 25),
    );

    final restored = ContextAttachment.fromJson(attachment.toJson());

    expect(restored, isNotNull);
    expect(
      restored!.resolutionStatus,
      ContextAttachmentResolutionStatus.tooLarge,
    );
    expect(restored.estimatedTokens, 42);
    expect(restored.toPromptBlock(), contains('[Context truncated.]'));
  });
}

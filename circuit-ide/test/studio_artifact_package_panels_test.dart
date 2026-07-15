import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/ui/studio/studio_artifact_package_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'package companion deliverables are named keyboard-operable actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var openedArtifactId = '';
      final artifact = GeneratedArtifact(
        id: 'companion-report',
        kind: GeneratedArtifactKind.pdf,
        status: GeneratedArtifactStatus.ready,
        fileName: 'customer-report.pdf',
        filePath: '/tmp/customer-report.pdf',
        summary: 'A customer-ready report.',
        byteSize: 1024,
        createdAt: DateTime(2026),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioArtifactPackageCompanionList(
                artifacts: [artifact],
                onOpen: (opened) => openedArtifactId = opened.id,
              ),
            ),
          ),
        ),
      );

      final action = find.bySemanticsLabel(
        'Open customer-report.pdf, PDF deliverable',
      );
      expect(action, findsOneWidget);
      await tester.tap(action);
      expect(openedArtifactId, artifact.id);

      openedArtifactId = '';
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(openedArtifactId, artifact.id);
      semantics.dispose();
    },
  );
}

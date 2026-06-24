import 'package:circuit_ide/ui/studio/studio_project_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Studio project view does not expose legacy task execution', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: StudioProjectView())),
      ),
    );
    await tester.pump();

    expect(find.text('Cisco Circuit project studio'), findsOneWidget);
    expect(find.text('Start task'), findsNothing);
    expect(find.text('Run checks'), findsNothing);
    expect(find.text('Active tasks'), findsNothing);
    expect(find.textContaining('Use the Studio composer'), findsOneWidget);
  });
}

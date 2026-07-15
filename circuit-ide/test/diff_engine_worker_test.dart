import 'package:circuit_ide/services/diff_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worker diff preserves line and change semantics', () async {
    const before = 'alpha\nbeta\ngamma\n';
    const after = 'alpha\nBETA\ngamma\ndelta\n';

    final inline = DiffEngine.diff(
      leftContent: before,
      rightContent: after,
      leftTitle: 'Before',
      rightTitle: 'After',
    );
    final worker = await DiffEngine.diffInWorker(
      leftContent: before,
      rightContent: after,
      leftTitle: 'Before',
      rightTitle: 'After',
    );

    expect(worker.leftTitle, inline.leftTitle);
    expect(worker.rightTitle, inline.rightTitle);
    expect(worker.additions, inline.additions);
    expect(worker.deletions, inline.deletions);
    expect(worker.modifications, inline.modifications);
    expect(worker.lines.length, inline.lines.length);
    for (var index = 0; index < inline.lines.length; index++) {
      final expected = inline.lines[index];
      final actual = worker.lines[index];
      expect(actual.type, expected.type);
      expect(actual.leftLineNum, expected.leftLineNum);
      expect(actual.rightLineNum, expected.rightLineNum);
      expect(actual.leftContent, expected.leftContent);
      expect(actual.rightContent, expected.rightContent);
    }
  });
}

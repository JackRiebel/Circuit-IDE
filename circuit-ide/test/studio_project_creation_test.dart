import 'dart:io';

import 'package:circuit_ide/state/studio_project_creator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'project creator sanitizes names and creates unique directories',
    () async {
      final parent = await Directory.systemTemp.createTemp('studio_projects_');
      addTearDown(() => parent.delete(recursive: true));

      final first = await StudioProjectCreator.createProject(
        name: '  My / New: Project!  ',
        parentPath: parent.path,
      );
      final second = await StudioProjectCreator.createProject(
        name: 'My / New: Project!',
        parentPath: parent.path,
      );

      expect(await Directory(first).exists(), isTrue);
      expect(await Directory(second).exists(), isTrue);
      expect(p.basename(first), 'My-New-Project');
      expect(p.basename(second), 'My-New-Project-2');
    },
  );

  test('project creator derives usable names from prompts', () {
    expect(
      StudioProjectCreator.projectNameFromPrompt(
        'Build me a topology diagram for a branch office',
      ),
      'Build-me-topology-diagram-for-branch-office',
    );
    expect(
      StudioProjectCreator.projectNameFromPrompt('@@@'),
      'Circuit-project',
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Studio uses the approved typography and icon vocabulary', () async {
    final studioDirectory = Directory('lib/ui/studio');
    final files = await studioDirectory
        .list(recursive: true)
        .where((entry) => entry is File && entry.path.endsWith('.dart'))
        .cast<File>()
        .toList();

    for (final file in files) {
      final source = await file.readAsString();
      expect(
        RegExp(r'(?<!Studio)Icons\.').hasMatch(source),
        isFalse,
        reason: '${file.path} bypasses StudioIcons.',
      );
      expect(
        RegExp(r'fontSize:\s*\d').hasMatch(source),
        isFalse,
        reason: '${file.path} bypasses FontSizes.',
      );
      if (source.contains('StudioIcons.')) {
        expect(
          source,
          contains('core/constants/design_tokens.dart'),
          reason: '${file.path} uses StudioIcons without its token import.',
        );
      }
      if (RegExp(r'Animated(?:Container|Align)').hasMatch(source)) {
        expect(
          source,
          contains('studio_motion.dart'),
          reason:
              '${file.path} has Studio motion without the accessibility helper.',
        );
        expect(
          RegExp(
            r'Animated(?:Container|Align)\([\s\S]{0,240}?duration:\s*(?:const\s+Duration|AnimationDurations)',
          ).hasMatch(source),
          isFalse,
          reason: '${file.path} bypasses the reduced-motion duration helper.',
        );
      }
      expect(
        RegExp(r'^\s*IconButton\(', multiLine: true).hasMatch(source),
        isFalse,
        reason:
            '${file.path} uses a direct IconButton instead of the shared accessible Studio chrome control.',
      );
      expect(
        RegExp(
          r'IconButton\([\s\S]{0,300}?visualDensity:\s*VisualDensity\.compact',
        ).hasMatch(source),
        isFalse,
        reason:
            '${file.path} uses a compact IconButton instead of the shared accessible Studio chrome control.',
      );
      if (!file.path.endsWith('studio_chrome.dart')) {
        expect(
          RegExp(r'^\s*InkWell\(', multiLine: true).hasMatch(source),
          isFalse,
          reason:
              '${file.path} uses a bare InkWell instead of a shared Studio focusable control.',
        );
      }
    }
  });
}

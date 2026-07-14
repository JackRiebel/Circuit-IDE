import 'dart:convert';

import 'zip_package_integrity.dart';

/// Ensures internal OOXML relationship targets resolve to package entries.
///
/// A syntactically complete DOCX, XLSX, or PPTX can still render with missing
/// styles, media, slides, or worksheets when a `.rels` target is absent. The
/// generated Office packages use stored entries, allowing this check to read
/// every relationship file after ZIP integrity validation.
class OfficePackageRelationshipInspection {
  final int internalRelationshipCount;
  final List<String> missingTargets;
  final List<String> unreadableRelationshipFiles;

  const OfficePackageRelationshipInspection({
    required this.internalRelationshipCount,
    required this.missingTargets,
    required this.unreadableRelationshipFiles,
  });

  bool get hasResolvableInternalTargets =>
      missingTargets.isEmpty && unreadableRelationshipFiles.isEmpty;
}

class OfficePackageRelationshipInspector {
  const OfficePackageRelationshipInspector();

  OfficePackageRelationshipInspection inspect(ZipPackageInspection package) {
    final missingTargets = <String>[];
    final unreadableRelationshipFiles = <String>[];
    final packageEntries = package.entryNames.toSet();
    var internalRelationshipCount = 0;

    for (final relationshipPath in package.entryNames.where(
      (entry) => entry.endsWith('.rels'),
    )) {
      final bytes = package.storedEntries[relationshipPath];
      if (bytes == null) {
        unreadableRelationshipFiles.add(relationshipPath);
        continue;
      }
      final contents = utf8.decode(bytes, allowMalformed: true);
      for (final match in RegExp(
        r'<Relationship\b[^>]*>',
        caseSensitive: false,
      ).allMatches(contents)) {
        final tag = match.group(0) ?? '';
        if (_attribute(tag, 'TargetMode')?.toLowerCase() == 'external') {
          continue;
        }
        final target = _attribute(tag, 'Target');
        if (target == null || target.trim().isEmpty) {
          missingTargets.add('$relationshipPath -> (missing target)');
          continue;
        }
        internalRelationshipCount++;
        final resolved = _resolveTarget(relationshipPath, target);
        if (resolved == null || !packageEntries.contains(resolved)) {
          missingTargets.add('$relationshipPath -> $target');
        }
      }
    }

    return OfficePackageRelationshipInspection(
      internalRelationshipCount: internalRelationshipCount,
      missingTargets: List.unmodifiable(missingTargets),
      unreadableRelationshipFiles: List.unmodifiable(
        unreadableRelationshipFiles,
      ),
    );
  }

  String? _attribute(String tag, String name) {
    final match = RegExp(
      '$name\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
  }

  String? _resolveTarget(String relationshipPath, String target) {
    if (target.startsWith('/')) return null;
    final sourcePath = _sourcePathForRelationship(relationshipPath);
    if (sourcePath == null) return null;
    final sourceSeparator = sourcePath.lastIndexOf('/');
    final components = <String>[
      if (sourceSeparator >= 0)
        ...sourcePath
            .substring(0, sourceSeparator)
            .split('/')
            .where((part) => part.isNotEmpty),
    ];
    for (final component in target.split('/')) {
      if (component.isEmpty || component == '.') continue;
      if (component == '..') {
        if (components.isEmpty) return null;
        components.removeLast();
      } else {
        components.add(component);
      }
    }
    return components.isEmpty ? null : components.join('/');
  }

  String? _sourcePathForRelationship(String relationshipPath) {
    if (relationshipPath == '_rels/.rels') return '';
    const marker = '/_rels/';
    final markerOffset = relationshipPath.indexOf(marker);
    if (markerOffset <= 0 || !relationshipPath.endsWith('.rels')) return null;
    final ownerDirectory = relationshipPath.substring(0, markerOffset);
    final sourceName = relationshipPath
        .substring(markerOffset + marker.length)
        .replaceFirst(RegExp(r'\.rels$'), '');
    if (sourceName.isEmpty) return null;
    return '$ownerDirectory/$sourceName';
  }
}

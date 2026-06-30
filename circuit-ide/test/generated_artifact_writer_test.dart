import 'dart:io';

import 'package:circuit_ide/models/generated_artifact.dart';
import 'package:circuit_ide/services/artifact_type_registry.dart';
import 'package:circuit_ide/services/generated_artifact_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PowerPoint prompt creates a real pptx artifact from structured markdown',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a PowerPoint deck for this customer proposal',
            content: '''
# Customer Architecture Proposal

Short executive summary for the customer.

## Current State
- Three branch sites
- Dual WAN at each site
- Centralized security policy

## Recommended Architecture
- Use resilient edge pairs
- Standardize access switching
- Validate PoE budgets
''',
            turnId: 'turn-pptx',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.powerPoint);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.pptx'));
      expect(artifact.sheetCount, greaterThanOrEqualTo(6));
      expect(artifact.summary, contains('PowerPoint deck'));
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('ppt/presentation.xml'));
      expect(packageText, contains('ppt/slides/slide1.xml'));
      expect(packageText, contains('Agenda'));
      expect(packageText, contains('Current State'));
      expect(packageText, contains('Recommended Architecture'));
    },
  );

  test(
    'Excel prompt creates a real xlsx artifact from markdown table',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create an Excel file from this',
            content: '''
Here is the data.

| Product | Count |
| --- | ---: |
| C9300 | 6 |
| CW9176 | 90 |
''',
            turnId: 'turn-1',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.excel);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.xlsx'));
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      expect(String.fromCharCodes(bytes), contains('xl/workbook.xml'));
      expect(artifact.previewRows.first, ['Product', 'Count']);
      expect(artifact.sheetCount, 1);
    },
  );

  test(
    'DOCX prompt creates a real Word artifact from structured markdown',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'create a DOCX architecture report',
            content: '''
# Branch Network Architecture Report

Executive summary for a customer handoff.

## Findings
- WAN redundancy is required.
- Access switching needs PoE validation.

## Recommendations
- Standardize branch edge design.
- Create validation checkpoints before deployment.

| Risk | Severity |
| --- | --- |
| PoE budget unknown | Medium |

## Assumptions
- Customer will confirm AP counts.

## Sources
- Customer inventory export
''',
            turnId: 'turn-docx',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.docx);
      expect(artifact.status, GeneratedArtifactStatus.ready);
      expect(artifact.fileName, endsWith('.docx'));
      expect(File(artifact.filePath).existsSync(), isTrue);
      final bytes = File(artifact.filePath).readAsBytesSync();
      expect(bytes.take(4), [0x50, 0x4b, 0x03, 0x04]);
      final packageText = String.fromCharCodes(bytes);
      expect(packageText, contains('word/document.xml'));
      expect(packageText, contains('word/styles.xml'));
      expect(packageText, contains('Branch Network Architecture Report'));
      expect(packageText, contains('WAN redundancy is required'));
      expect(packageText, contains('PoE budget unknown'));
    },
  );

  test('CSV prompt creates a CSV artifact from markdown table', () async {
    final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
    addTearDown(() => root.delete(recursive: true));
    final artifact = await const GeneratedArtifactWriter()
        .writeFromAssistantOutput(
          rootPath: root.path,
          prompt: 'create a CSV file from this',
          content: '''
| Product | Count |
| --- | ---: |
| C9300 | 6 |
| CW9176 | 90 |
''',
          turnId: 'turn-csv',
          threadId: 'thread-1',
          requestId: 'request-1',
        );

    expect(artifact, isNotNull);
    expect(artifact!.kind, GeneratedArtifactKind.csv);
    expect(artifact.status, GeneratedArtifactStatus.ready);
    expect(artifact.fileName, endsWith('.csv'));
    expect(File(artifact.filePath).readAsStringSync(), contains('C9300,6'));
  });

  test(
    'JSON prompt creates formatted JSON artifact when valid JSON is fenced',
    () async {
      final root = await Directory.systemTemp.createTemp('circuit-artifacts-');
      addTearDown(() => root.delete(recursive: true));
      final artifact = await const GeneratedArtifactWriter()
          .writeFromAssistantOutput(
            rootPath: root.path,
            prompt: 'generate a JSON file',
            content: '''
```json
{"name":"Circuit","count":2}
```
''',
            turnId: 'turn-json',
            threadId: 'thread-1',
            requestId: 'request-1',
          );

      expect(artifact, isNotNull);
      expect(artifact!.kind, GeneratedArtifactKind.json);
      expect(
        File(artifact.filePath).readAsStringSync(),
        contains('"name": "Circuit"'),
      );
    },
  );

  test('artifact registry exposes the 15 priority artifact descriptors', () {
    const registry = ArtifactTypeRegistry();

    expect(ArtifactTypeRegistry.descriptors, hasLength(15));
    expect(
      registry.descriptorForKind(GeneratedArtifactKind.powerPoint)?.id,
      'powerpoint_deck',
    );
    expect(
      registry.descriptorForPrompt('make a topology diagram')?.id,
      'network_topology_diagram',
    );
    expect(
      registry.descriptorForPrompt('create a business case for Acme')?.id,
      'business_use_case_brief',
    );
  });
}

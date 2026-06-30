import '../models/artifact_document.dart';
import 'workbook_table.dart';

class SolutionSizingWorkbookBuilder {
  const SolutionSizingWorkbookBuilder();

  bool matches(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r'\b(solution sizing|sizing workbook|sizing model|sizing matrix|size (?:a |the )?(?:solution|network|campus|branch|datacenter|data center)|poe budget|wan sizing|throughput sizing|client count|ap count)\b',
    ).hasMatch(normalized);
  }

  List<WorkbookTable> build({
    required String prompt,
    required String content,
    required ArtifactDocument document,
  }) {
    final requirements = _requirementRows('$prompt\n$content');
    final recommendations = _recommendationRows(document);
    final assumptions = _assumptionRows(document, content);
    final sourceTables = _sourceTables(document);
    return [
      WorkbookTable(
        name: 'Requirements',
        rows: [
          const ['Metric', 'Value', 'Notes'],
          ...requirements,
        ],
      ),
      WorkbookTable(
        name: 'Sizing Inputs',
        rows: [
          const ['Category', 'Input', 'Value', 'Notes'],
          ..._inputRows(requirements),
        ],
      ),
      WorkbookTable(
        name: 'Recommendations',
        rows: [
          const ['Area', 'Recommendation', 'Rationale', 'Status'],
          ...recommendations,
        ],
      ),
      const WorkbookTable(
        name: 'Validation',
        rows: [
          ['Check', 'Why it matters', 'Status'],
          [
            'PoE/UPOE budget',
            'Wi-Fi 6E/7 APs and cameras can exceed older access switch power budgets',
            'Needs validation',
          ],
          [
            'Multigig access ports',
            'Modern APs can require 2.5/5/10G access links',
            'Needs validation',
          ],
          [
            'WAN throughput',
            'Security services, SD-WAN, and inspection reduce usable throughput',
            'Needs validation',
          ],
          [
            'High availability',
            'Core, firewall, WAN, and power design must match outage tolerance',
            'Needs validation',
          ],
          [
            'Lifecycle / LDOS',
            'Recommended models should be checked against current lifecycle data',
            'Needs validation',
          ],
        ],
      ),
      WorkbookTable(
        name: 'Assumptions',
        rows: [
          const ['Assumption', 'Impact'],
          ...assumptions,
        ],
      ),
      if (sourceTables.isNotEmpty) ...sourceTables,
    ];
  }

  List<List<String>> _requirementRows(String content) {
    final rows = <List<String>>[];
    void add(String metric, String? value, String notes) {
      if (value == null || value.trim().isEmpty) return;
      rows.add([metric, value.trim(), notes]);
    }

    add(
      'Users / clients',
      _first(
        content,
        RegExp(
          r'(\d[\d,]*)\s+(?:users?|clients?|employees?|end users?)\b',
          caseSensitive: false,
        ),
      ),
      'Extracted from user/client count language.',
    );
    add(
      'Access points',
      _first(
        content,
        RegExp(r'(\d[\d,]*)\s+(?:aps?|access points?)\b', caseSensitive: false),
      ),
      'Validate model, Wi-Fi generation, port speed, and power draw.',
    );
    add(
      'Switches',
      _first(
        content,
        RegExp(
          r'(\d[\d,]*)\s+(?:switches?|access switches?|core switches?)\b',
          caseSensitive: false,
        ),
      ),
      'Validate stacking, uplinks, PoE, and lifecycle.',
    );
    add(
      'WAN speed',
      _first(
        content,
        RegExp(
          r'(\d+(?:\.\d+)?\s*(?:gbps|gigs?|g|mbps|m))\s*(?:wan|internet|circuit|link|links)?\b',
          caseSensitive: false,
        ),
      ),
      'Confirm committed rate, burst, HA links, and inspection throughput.',
    );
    add(
      'PoE / UPOE',
      _first(
        content,
        RegExp(
          r'\b(upoe\+?|poe\+?\+?|power budget|watts?)\b',
          caseSensitive: false,
        ),
      ),
      'Treat power class as a hard sizing constraint.',
    );
    add(
      'Growth',
      _first(
        content,
        RegExp(
          r'(\d+(?:\.\d+)?\s*%|\d+\s*(?:year|yr)s?)\s*(?:growth|headroom|forecast)?\b',
          caseSensitive: false,
        ),
      ),
      'Use as headroom for port, power, WAN, and licensing sizing.',
    );
    if (rows.isEmpty) {
      rows.addAll(const [
        [
          'Users / clients',
          'TBD',
          'Provide current and projected endpoint counts.',
        ],
        [
          'Access points',
          'TBD',
          'Provide AP model, quantity, Wi-Fi generation, and expected power draw.',
        ],
        [
          'WAN speed',
          'TBD',
          'Provide primary/secondary bandwidth and security service requirements.',
        ],
      ]);
    }
    return rows;
  }

  List<List<String>> _inputRows(List<List<String>> requirements) {
    return requirements
        .map((row) {
          final metric = row[0];
          final category = switch (metric.toLowerCase()) {
            String value when value.contains('wan') => 'WAN',
            String value
                when value.contains('poe') || value.contains('access') =>
              'Access',
            String value when value.contains('switch') => 'Switching',
            String value when value.contains('growth') => 'Planning',
            _ => 'Demand',
          };
          return [category, row[0], row[1], row[2]];
        })
        .toList(growable: false);
  }

  List<List<String>> _recommendationRows(ArtifactDocument document) {
    final rows = <List<String>>[];
    for (final section in document.sections) {
      final sectionName = section.title.toLowerCase();
      if (!sectionName.contains('recommend') &&
          !sectionName.contains('sizing') &&
          !sectionName.contains('architecture')) {
        continue;
      }
      for (final bullet in section.bullets) {
        rows.add([
          section.title,
          bullet,
          'Derived from assistant recommendation section.',
          'Review',
        ]);
      }
      if (section.bullets.isEmpty && section.body.trim().isNotEmpty) {
        rows.add([
          section.title,
          _shorten(section.body.trim(), 180),
          'Derived from assistant recommendation section.',
          'Review',
        ]);
      }
    }
    if (rows.isEmpty) {
      rows.addAll(const [
        [
          'Access',
          'Validate PoE/UPOE and multigig requirements before selecting access switches.',
          'Prevents undersized switch recommendations for Wi-Fi 6E/7 deployments.',
          'Review',
        ],
        [
          'WAN',
          'Size WAN/security throughput against enabled services and HA design.',
          'Nominal link speed is not equal to inspected throughput.',
          'Review',
        ],
      ]);
    }
    return rows.take(24).toList(growable: false);
  }

  List<List<String>> _assumptionRows(
    ArtifactDocument document,
    String content,
  ) {
    final assumptions = document.assumptions.isNotEmpty
        ? document.assumptions
        : _bulletsAfter(content, 'assumptions');
    if (assumptions.isEmpty) {
      return const [
        [
          'Lifecycle data and current portfolio fit must be verified before final model selection.',
          'Avoids treating migration hints as final recommendations.',
        ],
        [
          'Power draw, WAN service mix, and growth targets are placeholders until customer data is confirmed.',
          'Prevents false precision in sizing outputs.',
        ],
      ];
    }
    return assumptions
        .take(20)
        .map((assumption) => [assumption, 'Validate before final design.'])
        .toList(growable: false);
  }

  List<WorkbookTable> _sourceTables(ArtifactDocument document) {
    final tables = <WorkbookTable>[];
    for (var i = 0; i < document.tables.length && i < 4; i++) {
      final table = document.tables[i];
      if (table.rows.length < 2) continue;
      tables.add(WorkbookTable(name: 'Source ${i + 1}', rows: table.rows));
    }
    return tables;
  }

  List<String> _bulletsAfter(String content, String headingName) {
    final heading = RegExp(
      '^\\s{0,3}#{1,4}\\s+$headingName\\b.*\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(content);
    if (heading == null) return const [];
    final tail = content.substring(heading.end);
    final nextHeading = RegExp(
      r'^\s{0,3}#{1,4}\s+',
      multiLine: true,
    ).firstMatch(tail);
    final block = nextHeading == null
        ? tail
        : tail.substring(0, nextHeading.start);
    return block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- ') || line.startsWith('* '))
        .map((line) => line.substring(2).trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String? _first(String content, RegExp pattern) {
    final match = pattern.firstMatch(content);
    if (match == null) return null;
    return match.group(1) ?? match.group(0);
  }

  String _shorten(String value, int maxLength) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxLength) return singleLine;
    return '${singleLine.substring(0, maxLength - 1).trim()}...';
  }
}

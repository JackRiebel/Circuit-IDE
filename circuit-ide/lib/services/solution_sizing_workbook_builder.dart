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
    final profile = _SizingProfile.fromRequirements(
      requirements,
      '$prompt\n$content',
    );
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
        name: 'Capacity Model',
        rows: [
          const [
            'Demand Area',
            'Current Input',
            'Planning Headroom',
            'Planning Value',
            'Design Notes',
          ],
          ..._capacityRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'PoE Budget',
        rows: [
          const [
            'Load Type',
            'Quantity',
            'Watts Each',
            'Estimated Watts',
            'Minimum Budget',
            'Notes',
          ],
          ..._poeRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'WAN Throughput',
        rows: [
          const [
            'Traffic Class',
            'Required Mbps',
            'Design Headroom',
            'Recommended Mbps',
            'Notes',
          ],
          ..._wanRows(profile),
        ],
      ),
      WorkbookTable(
        name: 'HA Growth',
        rows: [
          const ['Constraint', 'Design Treatment', 'Status', 'Notes'],
          ..._haGrowthRows(profile),
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
      WorkbookTable(
        name: 'Decision Summary',
        rows: [
          const ['Area', 'Recommendation', 'Evidence Needed', 'Confidence'],
          ..._decisionRows(profile),
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

  List<List<String>> _capacityRows(_SizingProfile profile) {
    final growth = profile.growthMultiplier;
    return [
      [
        'Users / clients',
        profile.usersText,
        profile.growthText,
        profile.users == null
            ? 'TBD'
            : (profile.users! * growth).ceil().toString(),
        'Use for endpoint density, authentication, licensing, and support assumptions.',
      ],
      [
        'Access points',
        profile.accessPointsText,
        profile.growthText,
        profile.accessPoints == null
            ? 'TBD'
            : (profile.accessPoints! * growth).ceil().toString(),
        'Validate AP model, Wi-Fi generation, mGig need, and power class.',
      ],
      [
        'Switches',
        profile.switchesText,
        profile.growthText,
        profile.switches == null
            ? 'TBD'
            : (profile.switches! * growth).ceil().toString(),
        'Validate stack size, uplinks, redundancy, and lifecycle status.',
      ],
      [
        'Access ports',
        profile.accessPoints == null
            ? 'TBD'
            : (profile.accessPoints! + ((profile.users ?? 0) / 6))
                  .ceil()
                  .toString(),
        profile.growthText,
        profile.accessPoints == null
            ? 'TBD'
            : ((profile.accessPoints! + ((profile.users ?? 0) / 6)) * growth)
                  .ceil()
                  .toString(),
        'Directional port count for APs plus wired/client support; replace with inventory before final design.',
      ],
    ];
  }

  List<List<String>> _poeRows(_SizingProfile profile) {
    final apWatts = profile.requiresHighPowerAp ? 60 : 30;
    final apCount = profile.accessPoints;
    final apLoad = apCount == null ? null : apCount * apWatts;
    final minimumBudget = apLoad == null
        ? 'TBD'
        : (apLoad * profile.growthMultiplier * 1.2).ceil().toString();
    return [
      [
        'Wireless APs',
        profile.accessPointsText,
        apWatts.toString(),
        apLoad?.toString() ?? 'TBD',
        minimumBudget,
        profile.requiresHighPowerAp
            ? 'Wi-Fi 7/UPOE signal detected; validate switch power budget and mGig ports.'
            : 'Validate AP power class and reserve budget before final switch selection.',
      ],
      [
        'Phones / cameras / IoT',
        'TBD',
        'TBD',
        'TBD',
        'TBD',
        'Add non-AP PoE loads before customer handoff.',
      ],
      [
        'Power reserve',
        'N/A',
        '20%',
        'N/A',
        minimumBudget,
        'Minimum budget includes growth and reserve; confirm per-IDF distribution.',
      ],
    ];
  }

  List<List<String>> _wanRows(_SizingProfile profile) {
    final required = profile.wanMbps;
    final recommended = required == null
        ? 'TBD'
        : (required * profile.growthMultiplier * 1.25).ceil().toString();
    return [
      [
        'Internet / SD-WAN edge',
        required?.round().toString() ?? profile.wanText,
        profile.growthText,
        recommended,
        'Size against inspected throughput and enabled security services, not only carrier line rate.',
      ],
      [
        'Failover / secondary WAN',
        'TBD',
        profile.growthText,
        'TBD',
        'Confirm active/active or active/standby behavior and minimum outage tolerance.',
      ],
      [
        'Cloud / SaaS critical apps',
        'TBD',
        profile.growthText,
        'TBD',
        'Add app-specific requirements for voice, video, backups, and security inspection.',
      ],
    ];
  }

  List<List<String>> _haGrowthRows(_SizingProfile profile) {
    return [
      [
        'Growth headroom',
        profile.growthText,
        profile.growthPercent == null ? 'Needs input' : 'Captured',
        'Apply to users, APs, ports, power, WAN, licensing, and support contracts.',
      ],
      [
        'High availability',
        'Dual WAN, redundant core/firewall, power, and stack/chassis strategy',
        'Needs validation',
        'Confirm outage tolerance and which sites require warm spare or active/active design.',
      ],
      [
        'Lifecycle risk',
        'Validate LDOS/EoX and current portfolio fit before final model choice',
        'Needs validation',
        'EoX replacement PID is a migration clue only; verify against Wi-Fi 7, UPOE, mGig, and lifecycle needs.',
      ],
      [
        'Licensing',
        'Map selected architecture to licensing tiers and support coverage',
        'Needs validation',
        'Include DNA/Meraki/security licensing where applicable.',
      ],
    ];
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

  List<List<String>> _decisionRows(_SizingProfile profile) {
    return [
      [
        'Access switching',
        profile.requiresHighPowerAp
            ? 'Shortlist mGig UPOE/UPOE+ capable access switches.'
            : 'Shortlist access switches after AP power and port speed are confirmed.',
        'AP model, power draw, mGig need, uplink speed, stack/HA, lifecycle.',
        'Medium',
      ],
      [
        'Wireless',
        profile.accessPoints == null
            ? 'Collect AP count and Wi-Fi generation before sizing.'
            : 'Plan around ${profile.accessPointsText} APs with growth headroom.',
        'AP model, density, channel plan, PoE class, expected client mix.',
        profile.accessPoints == null ? 'Low' : 'Medium',
      ],
      [
        'WAN / security edge',
        profile.wanMbps == null
            ? 'Collect primary/secondary WAN and inspection requirements.'
            : 'Validate at least ${profile.wanText} plus security-service headroom.',
        'Firewall/SD-WAN throughput with services enabled, HA mode, circuits.',
        profile.wanMbps == null ? 'Low' : 'Medium',
      ],
      [
        'Customer follow-up',
        'Use this workbook as a requirements and validation artifact, not final bill of materials.',
        'Current datasheets, lifecycle, licensing, site inventory, and customer constraints.',
        'High',
      ],
    ];
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

class _SizingProfile {
  final int? users;
  final int? accessPoints;
  final int? switches;
  final double? wanMbps;
  final double? growthPercent;
  final bool requiresHighPowerAp;
  final String usersText;
  final String accessPointsText;
  final String switchesText;
  final String wanText;
  final String growthText;

  const _SizingProfile({
    required this.users,
    required this.accessPoints,
    required this.switches,
    required this.wanMbps,
    required this.growthPercent,
    required this.requiresHighPowerAp,
    required this.usersText,
    required this.accessPointsText,
    required this.switchesText,
    required this.wanText,
    required this.growthText,
  });

  double get growthMultiplier => 1 + ((growthPercent ?? 25) / 100);

  factory _SizingProfile.fromRequirements(
    List<List<String>> requirements,
    String content,
  ) {
    String valueFor(String metric) {
      final normalized = metric.toLowerCase();
      for (final row in requirements) {
        if (row.length < 2) continue;
        if (row.first.toLowerCase().contains(normalized)) return row[1];
      }
      return 'TBD';
    }

    final usersText = valueFor('users');
    final apText = valueFor('access points');
    final switchesText = valueFor('switches');
    final wanText = valueFor('wan');
    final growthText = valueFor('growth');
    final highPower = RegExp(
      r'\b(wi-?fi\s*7|upoe\+?|802\.3bt|class\s*6|class\s*8|60w|90w)\b',
      caseSensitive: false,
    ).hasMatch(content);
    return _SizingProfile(
      users: _firstInt(usersText),
      accessPoints: _firstInt(apText),
      switches: _firstInt(switchesText),
      wanMbps: _wanMbps(wanText),
      growthPercent: _growthPercent(growthText),
      requiresHighPowerAp: highPower,
      usersText: usersText,
      accessPointsText: apText,
      switchesText: switchesText,
      wanText: wanText,
      growthText: growthText == 'TBD' ? '25% default' : growthText,
    );
  }

  static int? _firstInt(String value) {
    final match = RegExp(r'\d[\d,]*').firstMatch(value);
    if (match == null) return null;
    return int.tryParse((match.group(0) ?? '').replaceAll(',', ''));
  }

  static double? _wanMbps(String value) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(gbps|gigs?|g|mbps|m)?',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) return null;
    final unit = (match.group(2) ?? 'mbps').toLowerCase();
    if (unit == 'g' || unit.startsWith('gig') || unit == 'gbps') {
      return number * 1000;
    }
    return number;
  }

  static double? _growthPercent(String value) {
    final percent = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(value);
    if (percent != null) return double.tryParse(percent.group(1) ?? '');
    return null;
  }
}

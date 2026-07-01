import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

class ChartRenderResult {
  final Uint8List bytes;
  final int chartCount;
  final List<String> signals;
  final List<List<String>> previewRows;
  final Map<String, Object?> metadata;

  const ChartRenderResult({
    required this.bytes,
    required this.chartCount,
    required this.signals,
    required this.previewRows,
    required this.metadata,
  });
}

class ChartArtifactRenderer {
  const ChartArtifactRenderer();

  ChartRenderResult render(ArtifactDocument document) {
    final charts = _chartsFor(document);
    final profile = _ChartPackProfile.fromCharts(charts);
    final svg = _svgFor(document, charts, profile);
    return ChartRenderResult(
      bytes: Uint8List.fromList(utf8.encode(svg)),
      chartCount: charts.length,
      signals: profile.signals,
      previewRows: _previewRows(charts),
      metadata: _metadataFor(charts, profile, document),
    );
  }

  Map<String, Object?> _metadataFor(
    List<_ChartData> charts,
    _ChartPackProfile profile,
    ArtifactDocument document,
  ) {
    final insights = _executiveInsights(profile);
    final gates = _validationGates(profile);
    final actions = _recommendedActions(profile);
    final validationGaps = _validationGapsFrom(gates);
    final dataQualityItems = _dataQualityItems(document, profile);
    final thresholdItems = _thresholdGuidanceItems(charts, profile);
    return {
      'generator': 'CircuitCode',
      'artifact': 'chart_pack',
      'chartPackType': _chartPackType(profile),
      'handoffStatus': _handoffStatus(profile, validationGaps),
      'decisionPurpose': _decisionPurpose(profile),
      'chartCount': charts.length,
      'pointCount': profile.pointCount,
      'highRiskCount': profile.highRiskCount,
      'mediumRiskCount': profile.mediumRiskCount,
      'lowRiskCount': profile.lowRiskCount,
      'hasPoe': profile.hasPoe,
      'hasWan': profile.hasWan,
      'hasLifecycle': profile.hasLifecycle,
      'hasComparison': profile.hasComparison,
      'hasCost': profile.hasCost,
      'hasRoadmap': profile.hasRoadmap,
      'signals': profile.signals,
      'chartFamilies': profile.chartFamilies,
      'readinessSignals': _readinessSignals(profile, gates),
      'validationGaps': validationGaps,
      'validationGapCount': validationGaps.length,
      'sourceTableCount': document.tables.length,
      'citationCount': document.citations.length,
      'assumptionCount': document.assumptions.length,
      'hasSourceEvidence': document.citations.isNotEmpty,
      'hasAssumptions': document.assumptions.isNotEmpty,
      'hasDataQualityPanel': dataQualityItems.isNotEmpty,
      'hasSourceProvenancePanel': true,
      'hasThresholdGuidance': thresholdItems.isNotEmpty,
      'hasCustomerReadyChartPack':
          validationGaps.isEmpty && profile.highRiskCount == 0,
      'kinds': charts.map((chart) => chart.kind.name).toList(growable: false),
      'insightCount': insights.length,
      'validationGateCount': gates.length,
      'recommendedActionCount': actions.length,
      'dataQualityItemCount': dataQualityItems.length,
      'thresholdGuidanceCount': thresholdItems.length,
    };
  }

  List<List<String>> _previewRows(List<_ChartData> charts) {
    if (charts.isEmpty) return const [];
    if (charts.length == 1) {
      return [
        ['Metric', charts.first.valueLabel],
        for (final point in charts.first.points.take(8))
          [point.label, _format(point.value)],
      ];
    }
    return [
      ['Chart', 'Signal', 'Data points'],
      for (final chart in charts.take(8))
        [chart.title, chart.kind.label, chart.points.length.toString()],
    ];
  }

  List<_ChartData> _chartsFor(ArtifactDocument document) {
    final charts = <_ChartData>[];
    for (final table in document.tables.take(6)) {
      final chart = _chartFromTable(table);
      if (chart != null) charts.add(chart);
    }
    if (charts.isNotEmpty) return charts;
    final points = <_ChartPoint>[];
    for (final section in document.sections.take(8)) {
      final count = math.max(
        section.bullets.length,
        section.body.length ~/ 140,
      );
      if (count > 0) {
        points.add(_ChartPoint(section.title, count.toDouble()));
      }
    }
    if (points.isEmpty) {
      points.add(const _ChartPoint('Summary', 1));
    }
    return [
      _ChartData(
        title: 'Content Weight',
        valueLabel: 'Items',
        kind: _ChartKind.summary,
        points: points,
      ),
    ];
  }

  _ChartData? _chartFromTable(ArtifactTable table) {
    if (table.rows.length < 2 || table.rows.first.length < 2) return null;
    final headers = table.rows.first;
    final kind = _kindFor(table);
    final lifecycle = _lifecycleChart(table, kind);
    if (lifecycle != null) return lifecycle;

    final numericColumns = <int>[];
    for (var column = 1; column < headers.length; column++) {
      final values = table.rows
          .skip(1)
          .map((row) => column < row.length ? _number(row[column]) : null)
          .whereType<double>()
          .toList();
      if (values.length >= math.min(2, table.rows.length - 1)) {
        numericColumns.add(column);
      }
    }
    if (numericColumns.isEmpty) return null;

    final numericColumn = _primaryNumericColumn(headers, numericColumns, kind);
    final secondaryColumn = _secondaryNumericColumn(
      headers,
      numericColumns,
      numericColumn,
      kind,
    );
    final points = <_ChartPoint>[];
    final secondaryPoints = <_ChartPoint>[];
    for (final row in table.rows.skip(1)) {
      if (row.isEmpty || numericColumn >= row.length) continue;
      final value = _number(row[numericColumn]);
      if (value == null) continue;
      points.add(_ChartPoint(row.first, value));
      if (secondaryColumn != null && secondaryColumn < row.length) {
        final secondary = _number(row[secondaryColumn]);
        if (secondary != null) {
          secondaryPoints.add(_ChartPoint(row.first, secondary));
        }
      }
    }
    if (points.isEmpty) return null;
    return _ChartData(
      title: _titleFor(table.title, kind),
      valueLabel: headers[numericColumn],
      secondaryLabel: secondaryColumn == null ? null : headers[secondaryColumn],
      kind: kind,
      points: points.take(12).toList(growable: false),
      secondaryPoints: secondaryPoints.take(12).toList(growable: false),
      notes: _notesFor(table, kind),
      riskProfile: _riskProfileFor(table),
    );
  }

  _ChartData? _lifecycleChart(ArtifactTable table, _ChartKind kind) {
    if (kind != _ChartKind.lifecycle && kind != _ChartKind.risk) return null;
    final headers = table.rows.first;
    final riskColumn = _columnIndex(headers, [
      'risk',
      'severity',
      'status',
      'lifecycle',
    ]);
    final dateColumn = _columnIndex(headers, [
      'ldos',
      'last date',
      'support',
      'end of',
      'eol',
      'eos',
    ]);
    if (riskColumn == null && dateColumn == null) return null;
    final points = <_ChartPoint>[];
    for (final row in table.rows.skip(1)) {
      if (row.isEmpty) continue;
      final value = riskColumn != null && riskColumn < row.length
          ? _riskScore(row[riskColumn])
          : null;
      final dateValue = dateColumn != null && dateColumn < row.length
          ? _yearScore(row[dateColumn])
          : null;
      final score = value ?? dateValue;
      if (score == null) continue;
      points.add(_ChartPoint(row.first, score));
    }
    if (points.isEmpty) return null;
    return _ChartData(
      title: kind == _ChartKind.lifecycle ? 'Lifecycle Risk' : table.title,
      valueLabel: riskColumn == null ? 'Timeline score' : 'Risk score',
      kind: kind,
      points: points.take(12).toList(growable: false),
      notes: [
        if (dateColumn != null) 'Uses lifecycle/date columns as risk signals.',
        if (riskColumn != null) 'High=3, Medium/Review=2, Low/Active=1.',
      ],
      riskProfile: _riskProfileFor(table),
    );
  }

  _ChartKind _kindFor(ArtifactTable table) {
    final text = '${table.title} ${table.rows.first.join(' ')}'.toLowerCase();
    if (RegExp(r'\b(poe|upoe|power|watt|watts)\b').hasMatch(text)) {
      return _ChartKind.poe;
    }
    if (RegExp(
      r'\b(wan|throughput|bandwidth|mbps|gbps|capacity)\b',
    ).hasMatch(text)) {
      return _ChartKind.wan;
    }
    if (RegExp(
      r'\b(ldos|eox|eol|eos|lifecycle|end of sale|support)\b',
    ).hasMatch(text)) {
      return _ChartKind.lifecycle;
    }
    if (RegExp(
      r'\b(model|product|comparison|fit score|recommendation)\b',
    ).hasMatch(text)) {
      return _ChartKind.comparison;
    }
    if (RegExp(
      r'\b(cost|price|pricing|license|licensing|opex|capex|tco)\b',
    ).hasMatch(text)) {
      return _ChartKind.cost;
    }
    if (RegExp(
      r'\b(roadmap|phase|phases|milestone|timeline|quarter|q[1-4])\b',
    ).hasMatch(text)) {
      return _ChartKind.roadmap;
    }
    if (RegExp(r'\b(risk|severity|priority)\b').hasMatch(text)) {
      return _ChartKind.risk;
    }
    return _ChartKind.generic;
  }

  int _primaryNumericColumn(
    List<String> headers,
    List<int> numericColumns,
    _ChartKind kind,
  ) {
    final preferred = switch (kind) {
      _ChartKind.poe => ['required', 'used', 'load', 'watts'],
      _ChartKind.wan => ['required', 'traffic', 'throughput', 'mbps', 'gbps'],
      _ChartKind.comparison => ['fit', 'score', 'rating'],
      _ChartKind.cost => ['cost', 'price', 'spend', 'tco', 'capex', 'opex'],
      _ChartKind.roadmap => ['priority', 'effort', 'score', 'duration'],
      _ChartKind.risk => ['risk', 'score', 'severity'],
      _ => <String>[],
    };
    for (final needle in preferred) {
      for (final column in numericColumns) {
        if (headers[column].toLowerCase().contains(needle)) return column;
      }
    }
    return numericColumns.first;
  }

  int? _secondaryNumericColumn(
    List<String> headers,
    List<int> numericColumns,
    int primaryColumn,
    _ChartKind kind,
  ) {
    final preferred = switch (kind) {
      _ChartKind.poe => ['budget', 'available', 'capacity'],
      _ChartKind.wan => ['capacity', 'available', 'link', 'wan'],
      _ => <String>[],
    };
    if (preferred.isEmpty) return null;
    for (final needle in preferred) {
      for (final column in numericColumns) {
        if (column == primaryColumn) continue;
        if (headers[column].toLowerCase().contains(needle)) return column;
      }
    }
    return null;
  }

  int? _columnIndex(List<String> headers, List<String> needles) {
    for (var index = 1; index < headers.length; index++) {
      final header = headers[index].toLowerCase();
      if (needles.any(header.contains)) return index;
    }
    return null;
  }

  double? _number(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(',', '')
        .replaceAll('%', '')
        .replaceAll('gbps', '000')
        .replaceAll('mbps', '')
        .replaceAll('watts', '')
        .replaceAll('w', '')
        .trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  double? _riskScore(String value) {
    final normalized = value.toLowerCase();
    if (RegExp(
      r'\b(high|critical|eol|eos|expired|unsupported)\b',
    ).hasMatch(normalized)) {
      return 3;
    }
    if (RegExp(
      r'\b(medium|moderate|review|warning|soon)\b',
    ).hasMatch(normalized)) {
      return 2;
    }
    if (RegExp(r'\b(low|active|ok|supported|current)\b').hasMatch(normalized)) {
      return 1;
    }
    return _number(value);
  }

  _RiskProfile _riskProfileFor(ArtifactTable table) {
    var high = 0;
    var medium = 0;
    var low = 0;
    for (final row in table.rows.skip(1)) {
      for (final cell in row) {
        switch (_riskLevel(cell)) {
          case _RiskLevel.high:
            high++;
          case _RiskLevel.medium:
            medium++;
          case _RiskLevel.low:
            low++;
          case null:
            break;
        }
      }
    }
    return _RiskProfile(high: high, medium: medium, low: low);
  }

  _RiskLevel? _riskLevel(String value) {
    final normalized = value.toLowerCase();
    if (RegExp(
      r'\b(high|critical|eol|eos|expired|unsupported)\b',
    ).hasMatch(normalized)) {
      return _RiskLevel.high;
    }
    if (RegExp(
      r'\b(medium|moderate|review|warning|soon)\b',
    ).hasMatch(normalized)) {
      return _RiskLevel.medium;
    }
    if (RegExp(r'\b(low|active|ok|supported|current)\b').hasMatch(normalized)) {
      return _RiskLevel.low;
    }
    return null;
  }

  double? _yearScore(String value) {
    final year = RegExp(r'\b(20\d{2})\b').firstMatch(value)?.group(1);
    if (year == null) return null;
    final parsed = int.tryParse(year);
    if (parsed == null) return null;
    if (parsed <= 2026) return 3;
    if (parsed <= 2028) return 2;
    return 1;
  }

  String _titleFor(String title, _ChartKind kind) {
    if (title.trim().isNotEmpty && title.toLowerCase() != 'data') {
      return title;
    }
    return kind.label;
  }

  List<String> _notesFor(ArtifactTable table, _ChartKind kind) {
    final rows = table.rows.length - 1;
    return [
      '${kind.label} from $rows source row${rows == 1 ? '' : 's'}.',
      if (kind == _ChartKind.poe)
        'Compare required load against available PoE/UPOE budget.',
      if (kind == _ChartKind.wan)
        'Compare demand against available WAN or inspection capacity.',
      if (kind == _ChartKind.comparison)
        'Use fit scores as directional ranking, not final recommendation.',
      if (kind == _ChartKind.cost)
        'Treat cost values as planning estimates until validated with current pricing.',
      if (kind == _ChartKind.roadmap)
        'Use roadmap values as sequencing signals, not committed delivery dates.',
    ];
  }

  String _svgFor(
    ArtifactDocument document,
    List<_ChartData> charts,
    _ChartPackProfile profile,
  ) {
    const chartHeight = 330;
    const chartTop = 330;
    final footerTop = chartTop + (charts.length * chartHeight);
    final height = math.max(720, footerTop + 330);
    const width = 1040;
    final insights = _executiveInsights(profile);
    final gates = _validationGates(profile);
    final actions = _recommendedActions(profile);
    final dataQualityItems = _dataQualityItems(document, profile);
    final thresholdItems = _thresholdGuidanceItems(charts, profile);
    final metadata = _metadataFor(charts, profile, document);
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img">',
      )
      ..writeln('<title>${_xml(document.title)}</title>')
      ..writeln(
        '<desc>Enterprise chart pack generated by CircuitCode. Review source data and assumptions before customer handoff.</desc>',
      )
      ..writeln('<metadata>${_xml(jsonEncode(metadata))}</metadata>')
      ..writeln('<rect width="100%" height="100%" rx="22" fill="#0f1010"/>')
      ..writeln('<rect x="0" y="0" width="7" height="$height" fill="#78aaa5"/>')
      ..writeln(
        '<text x="42" y="50" fill="#f2f2ef" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="24" font-weight="700">${_xml(document.title)}</text>',
      )
      ..writeln(
        '<text x="42" y="76" fill="#929a96" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">Generated chart pack • ${charts.length} chart${charts.length == 1 ? '' : 's'}</text>',
      );

    _writeSummary(buffer, profile, width: width);
    _writeExecutiveInsights(buffer, insights, width: width);
    buffer.writeln('<g id="chart-pack" data-chart-count="${charts.length}">');
    for (var chartIndex = 0; chartIndex < charts.length; chartIndex++) {
      _writeChart(
        buffer,
        charts[chartIndex],
        index: chartIndex + 1,
        top: chartTop + (chartIndex * chartHeight),
        width: width,
      );
    }
    buffer.writeln('</g>');
    _writeValidationGates(buffer, gates, top: footerTop + 10, width: width);
    _writeRecommendedActions(
      buffer,
      actions,
      top: footerTop + 88,
      width: width,
    );
    _writeDataQualityPanel(
      buffer,
      dataQualityItems,
      top: footerTop + 176,
      width: width,
    );
    _writeThresholdGuidance(
      buffer,
      thresholdItems,
      top: footerTop + 246,
      width: width,
    );
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  void _writeSummary(
    StringBuffer buffer,
    _ChartPackProfile profile, {
    required int width,
  }) {
    const left = 42.0;
    const cardWidth = 178.0;
    final metrics = [
      ('Charts', profile.chartCount.toString(), '#78aaa5'),
      ('Data points', profile.pointCount.toString(), '#84a7ff'),
      ('High risk', profile.highRiskCount.toString(), '#ec8f87'),
      ('Review', profile.mediumRiskCount.toString(), '#e1b96b'),
      ('Low/active', profile.lowRiskCount.toString(), '#7fc6a6'),
    ];
    buffer
      ..writeln(
        '<g id="chart-summary" data-chart-count="${profile.chartCount}" data-point-count="${profile.pointCount}" data-high-risk-count="${profile.highRiskCount}" data-medium-risk-count="${profile.mediumRiskCount}" data-low-risk-count="${profile.lowRiskCount}">',
      )
      ..writeln(
        '<rect x="34" y="92" width="${width - 68}" height="118" rx="16" fill="#151716" stroke="#29302d" stroke-width="1"/>',
      )
      ..writeln(
        '<text x="$left" y="122" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="15" font-weight="700">Chart pack summary</text>',
      )
      ..writeln(
        '<text x="$left" y="145" fill="#9da6a3" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">Review high-risk signals and validate source assumptions before customer handoff.</text>',
      );
    for (var i = 0; i < metrics.length; i++) {
      final metric = metrics[i];
      final x = left + (i * (cardWidth + 10));
      buffer
        ..writeln(
          '<rect class="chart-summary-card" x="$x" y="164" width="$cardWidth" height="34" rx="10" fill="#1d211f" stroke="#2b322f" stroke-width="1"/>',
        )
        ..writeln('<circle cx="${x + 16}" cy="181" r="5" fill="${metric.$3}"/>')
        ..writeln(
          '<text x="${x + 30}" y="185" fill="#f2f2ef" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12" font-weight="700">${_xml(metric.$2)}</text>',
        )
        ..writeln(
          '<text x="${x + 64}" y="185" fill="#929a96" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">${_xml(metric.$1)}</text>',
        );
    }
    buffer
      ..writeln(
        '<g id="chart-risk-legend" data-has-poe="${profile.hasPoe}" data-has-wan="${profile.hasWan}" data-has-lifecycle="${profile.hasLifecycle}" data-has-comparison="${profile.hasComparison}" data-has-cost="${profile.hasCost}" data-has-roadmap="${profile.hasRoadmap}">',
      )
      ..writeln(
        '<text x="${width - 300}" y="122" fill="#9da6a3" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">Signals: ${_xml(profile.signals.isEmpty ? 'general chart data' : profile.signals.join(' • '))}</text>',
      )
      ..writeln(
        '<text class="chart-note" x="${width - 300}" y="145" fill="#89928e" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">High/Critical/EoL = high risk • Review/Warning = medium.</text>',
      )
      ..writeln('</g>')
      ..writeln('</g>');
  }

  List<String> _executiveInsights(_ChartPackProfile profile) {
    final insights = <String>[
      profile.signals.isEmpty
          ? 'General chart data is available, but no enterprise signal family was detected.'
          : 'Signals covered: ${profile.signals.join(', ')}.',
      '${profile.pointCount} data point${profile.pointCount == 1 ? '' : 's'} across ${profile.chartCount} chart${profile.chartCount == 1 ? '' : 's'}.',
    ];
    if (profile.highRiskCount > 0) {
      insights.add(
        '${profile.highRiskCount} high-risk item${profile.highRiskCount == 1 ? '' : 's'} need owner review before handoff.',
      );
    } else if (profile.mediumRiskCount > 0) {
      insights.add('No high-risk item detected; review medium-risk signals.');
    } else {
      insights.add('No explicit high/medium risk labels detected.');
    }
    if (profile.hasPoe && profile.hasWan) {
      insights.add(
        'Validate both access-layer power and WAN headroom together.',
      );
    } else if (profile.hasPoe) {
      insights.add('Power budget is an explicit validation gate.');
    } else if (profile.hasWan) {
      insights.add('WAN capacity is an explicit validation gate.');
    }
    return insights.take(4).toList(growable: false);
  }

  List<({String gate, String status, bool ready})> _validationGates(
    _ChartPackProfile profile,
  ) {
    return [
      (
        gate: 'Source data',
        status: profile.pointCount > 0 ? 'Present' : 'Missing',
        ready: profile.pointCount > 0,
      ),
      (
        gate: 'Risk labels',
        status: profile.highRiskCount + profile.mediumRiskCount > 0
            ? 'Captured'
            : 'Needs review',
        ready: profile.highRiskCount + profile.mediumRiskCount > 0,
      ),
      (
        gate: 'Capacity signals',
        status: profile.hasPoe || profile.hasWan ? 'Captured' : 'Not detected',
        ready: profile.hasPoe || profile.hasWan,
      ),
      (
        gate: 'Decision context',
        status: profile.hasComparison || profile.hasCost || profile.hasRoadmap
            ? 'Captured'
            : 'Needs owner',
        ready: profile.hasComparison || profile.hasCost || profile.hasRoadmap,
      ),
    ];
  }

  List<String> _validationGapsFrom(
    List<({String gate, String status, bool ready})> gates,
  ) {
    return [
      for (final gate in gates)
        if (!gate.ready) '${gate.gate}: ${gate.status}',
    ];
  }

  List<String> _readinessSignals(
    _ChartPackProfile profile,
    List<({String gate, String status, bool ready})> gates,
  ) {
    final ready = <String>[
      for (final gate in gates)
        if (gate.ready) gate.gate,
    ];
    if (profile.highRiskCount > 0) {
      ready.add('High-risk review required');
    } else {
      ready.add('No high-risk labels detected');
    }
    return ready.take(6).toList(growable: false);
  }

  String _chartPackType(_ChartPackProfile profile) {
    if (profile.signals.length >= 4) return 'Enterprise readiness chart pack';
    if (profile.hasPoe || profile.hasWan) return 'Capacity planning chart pack';
    if (profile.hasLifecycle) return 'Lifecycle risk chart pack';
    if (profile.hasComparison) return 'Product comparison chart pack';
    if (profile.hasCost) return 'Cost planning chart pack';
    if (profile.hasRoadmap) return 'Roadmap chart pack';
    return 'General chart pack';
  }

  String _handoffStatus(
    _ChartPackProfile profile,
    List<String> validationGaps,
  ) {
    if (profile.highRiskCount > 0) return 'Review required - high risk signals';
    if (validationGaps.isNotEmpty) return 'Draft - validation gaps';
    return 'Ready for stakeholder review';
  }

  String _decisionPurpose(_ChartPackProfile profile) {
    if ((profile.hasPoe || profile.hasWan) && profile.hasLifecycle) {
      return 'Capacity and lifecycle decision support';
    }
    if (profile.hasPoe || profile.hasWan) {
      return 'Capacity validation and sizing support';
    }
    if (profile.hasComparison && profile.hasCost) {
      return 'Model fit and cost tradeoff support';
    }
    if (profile.hasRoadmap) return 'Implementation sequencing support';
    return 'Structured visual decision support';
  }

  List<String> _recommendedActions(_ChartPackProfile profile) {
    final actions = <String>[];
    if (profile.highRiskCount > 0) {
      actions.add('Assign owners for every high-risk chart row.');
    }
    if (profile.hasPoe) {
      actions.add('Validate PoE/UPOE reserve and AP draw before model choice.');
    }
    if (profile.hasWan) {
      actions.add(
        'Confirm WAN demand, inspection throughput, and failover SLA.',
      );
    }
    if (profile.hasLifecycle) {
      actions.add(
        'Check lifecycle dates against current replacement requirements.',
      );
    }
    if (profile.hasComparison) {
      actions.add(
        'Treat fit scores as directional until datasheet facts are verified.',
      );
    }
    if (profile.hasCost) {
      actions.add(
        'Refresh pricing/licensing assumptions before customer handoff.',
      );
    }
    if (profile.hasRoadmap) {
      actions.add('Convert roadmap scores into owner/date milestones.');
    }
    if (actions.isEmpty) {
      actions.add(
        'Review chart inputs and attach source evidence before handoff.',
      );
    }
    return actions.take(4).toList(growable: false);
  }

  List<({String label, String value, String guidance, bool ready})>
  _dataQualityItems(ArtifactDocument document, _ChartPackProfile profile) {
    return [
      (
        label: 'Source tables',
        value: document.tables.isEmpty
            ? 'None'
            : '${document.tables.length} table${document.tables.length == 1 ? '' : 's'}',
        guidance: document.tables.isEmpty
            ? 'Add source rows before treating charts as evidence.'
            : 'Source rows captured for chart generation.',
        ready: document.tables.isNotEmpty,
      ),
      (
        label: 'Citations',
        value: document.citations.isEmpty
            ? 'Missing'
            : '${document.citations.length} source${document.citations.length == 1 ? '' : 's'}',
        guidance: document.citations.isEmpty
            ? 'Attach checked source evidence before customer handoff.'
            : 'Review source authority and checked dates.',
        ready: document.citations.isNotEmpty,
      ),
      (
        label: 'Assumptions',
        value: document.assumptions.isEmpty
            ? 'Missing'
            : '${document.assumptions.length} listed',
        guidance: document.assumptions.isEmpty
            ? 'Document scope, units, and interpretation assumptions.'
            : 'Assumptions are visible for stakeholder review.',
        ready: document.assumptions.isNotEmpty,
      ),
      (
        label: 'Risk labeling',
        value: profile.highRiskCount + profile.mediumRiskCount > 0
            ? 'Captured'
            : 'Needs review',
        guidance: profile.highRiskCount + profile.mediumRiskCount > 0
            ? 'Risk labels can drive owner follow-up.'
            : 'Add High/Medium/Low or equivalent risk labels.',
        ready: profile.highRiskCount + profile.mediumRiskCount > 0,
      ),
    ];
  }

  List<({String topic, String guidance, bool critical})>
  _thresholdGuidanceItems(List<_ChartData> charts, _ChartPackProfile profile) {
    final items = <({String topic, String guidance, bool critical})>[];
    if (charts.any((chart) => chart.secondaryPoints.isNotEmpty)) {
      items.add((
        topic: 'Budget comparison',
        guidance:
            'Primary bars are overlaid against available budget/capacity where a secondary column exists.',
        critical: false,
      ));
    }
    if (profile.hasPoe) {
      items.add((
        topic: 'PoE/UPOE',
        guidance:
            'Validate AP draw, switch power supplies, UPOE reserve, and growth headroom.',
        critical: true,
      ));
    }
    if (profile.hasWan) {
      items.add((
        topic: 'WAN',
        guidance:
            'Compare demand against inspected throughput, failover path, and SLA requirements.',
        critical: true,
      ));
    }
    if (profile.hasLifecycle) {
      items.add((
        topic: 'Lifecycle',
        guidance:
            'Lifecycle dates are risk signals only; replacement choice still needs current portfolio validation.',
        critical: true,
      ));
    }
    if (profile.hasComparison) {
      items.add((
        topic: 'Model fit',
        guidance:
            'Fit scores are directional until datasheet facts and hard requirements are source-backed.',
        critical: true,
      ));
    }
    if (items.isEmpty) {
      items.add((
        topic: 'Thresholds',
        guidance:
            'Add target, budget, risk, or limit columns to make the chart decision-ready.',
        critical: false,
      ));
    }
    return items.take(4).toList(growable: false);
  }

  void _writeExecutiveInsights(
    StringBuffer buffer,
    List<String> insights, {
    required int width,
  }) {
    buffer
      ..writeln(
        '<g id="chart-executive-insights" data-insight-count="${insights.length}">',
      )
      ..writeln(
        '<rect x="34" y="222" width="${width - 68}" height="76" rx="16" fill="#131615" stroke="#29302d" stroke-width="1"/>',
      )
      ..writeln(
        '<text x="42" y="250" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="15" font-weight="700">Executive insights</text>',
      );
    final columnWidth = (width - 132) / 2;
    for (var i = 0; i < insights.length; i++) {
      final x = 42 + ((i % 2) * (columnWidth + 24));
      final y = 272 + ((i ~/ 2) * 18);
      buffer.writeln(
        '<text class="chart-insight" x="$x" y="$y" fill="#aeb6b2" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">• ${_xml(_shorten(insights[i], 74))}</text>',
      );
    }
    buffer.writeln('</g>');
  }

  void _writeValidationGates(
    StringBuffer buffer,
    List<({String gate, String status, bool ready})> gates, {
    required int top,
    required int width,
  }) {
    buffer
      ..writeln(
        '<g id="chart-validation-gates" data-validation-gate-count="${gates.length}">',
      )
      ..writeln(
        '<rect x="34" y="$top" width="${width - 68}" height="62" rx="16" fill="#151716" stroke="#29302d" stroke-width="1"/>',
      )
      ..writeln(
        '<text x="42" y="${top + 25}" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="14" font-weight="700">Validation gates</text>',
      );
    var x = 184.0;
    for (final gate in gates) {
      const widthForGate = 178.0;
      buffer
        ..writeln(
          '<rect x="${x.toStringAsFixed(1)}" y="${top + 15}" width="$widthForGate" height="30" rx="10" fill="${gate.ready ? '#1d342f' : '#302f21'}" stroke="${gate.ready ? '#315f55' : '#5c5530'}"/>',
        )
        ..writeln(
          '<text x="${(x + 10).toStringAsFixed(1)}" y="${top + 28}" fill="${gate.ready ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(gate.gate)}</text>',
        )
        ..writeln(
          '<text x="${(x + 10).toStringAsFixed(1)}" y="${top + 41}" fill="#cdd4d1" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9">${_xml(gate.status)}</text>',
        );
      x += widthForGate + 10;
    }
    buffer.writeln('</g>');
  }

  void _writeRecommendedActions(
    StringBuffer buffer,
    List<String> actions, {
    required int top,
    required int width,
  }) {
    buffer
      ..writeln(
        '<g id="chart-recommended-actions" data-recommended-action-count="${actions.length}">',
      )
      ..writeln(
        '<rect x="34" y="$top" width="${width - 68}" height="74" rx="16" fill="#111413" stroke="#26302d" stroke-width="1"/>',
      )
      ..writeln(
        '<text x="42" y="${top + 25}" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="14" font-weight="700">Recommended next actions</text>',
      );
    final columnWidth = (width - 132) / 2;
    for (var i = 0; i < actions.length; i++) {
      final x = 42 + ((i % 2) * (columnWidth + 24));
      final y = top + 48 + ((i ~/ 2) * 17);
      buffer.writeln(
        '<text class="chart-action" x="$x" y="$y" fill="#aeb6b2" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">• ${_xml(_shorten(actions[i], 72))}</text>',
      );
    }
    buffer.writeln('</g>');
  }

  void _writeDataQualityPanel(
    StringBuffer buffer,
    List<({String label, String value, String guidance, bool ready})> items, {
    required int top,
    required int width,
  }) {
    buffer
      ..writeln(
        '<g id="chart-data-quality" data-data-quality-item-count="${items.length}">',
      )
      ..writeln(
        '<rect x="34" y="$top" width="${width - 68}" height="58" rx="16" fill="#151716" stroke="#29302d" stroke-width="1"/>',
      )
      ..writeln(
        '<text x="42" y="${top + 24}" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="14" font-weight="700">Source and data quality</text>',
      );
    var x = 222.0;
    const cardWidth = 186.0;
    for (final item in items.take(4)) {
      buffer
        ..writeln(
          '<rect x="${x.toStringAsFixed(1)}" y="${top + 12}" width="$cardWidth" height="32" rx="10" fill="${item.ready ? '#1d342f' : '#302f21'}" stroke="${item.ready ? '#315f55' : '#5c5530'}"/>',
        )
        ..writeln(
          '<text x="${(x + 10).toStringAsFixed(1)}" y="${top + 25}" fill="${item.ready ? '#8dd3bd' : '#e1bb6d'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten('${item.label}: ${item.value}', 30))}</text>',
        )
        ..writeln(
          '<text x="${(x + 10).toStringAsFixed(1)}" y="${top + 39}" fill="#cdd4d1" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(item.guidance, 38))}</text>',
        );
      x += cardWidth + 8;
    }
    buffer.writeln('</g>');
  }

  void _writeThresholdGuidance(
    StringBuffer buffer,
    List<({String topic, String guidance, bool critical})> items, {
    required int top,
    required int width,
  }) {
    buffer
      ..writeln(
        '<g id="chart-threshold-guidance" data-threshold-guidance-count="${items.length}">',
      )
      ..writeln(
        '<rect x="34" y="$top" width="${width - 68}" height="58" rx="16" fill="#111413" stroke="#26302d" stroke-width="1"/>',
      )
      ..writeln(
        '<text x="42" y="${top + 24}" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="14" font-weight="700">Threshold guidance</text>',
      );
    var x = 204.0;
    const cardWidth = 194.0;
    for (final item in items.take(4)) {
      buffer
        ..writeln(
          '<rect x="${x.toStringAsFixed(1)}" y="${top + 12}" width="$cardWidth" height="32" rx="10" fill="${item.critical ? '#2a241b' : '#182621'}" stroke="${item.critical ? '#59482b' : '#2e5148'}"/>',
        )
        ..writeln(
          '<text x="${(x + 10).toStringAsFixed(1)}" y="${top + 25}" fill="${item.critical ? '#e1bb6d' : '#8dd3bd'}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="9" font-weight="700">${_xml(_shorten(item.topic, 28))}</text>',
        )
        ..writeln(
          '<text x="${(x + 10).toStringAsFixed(1)}" y="${top + 39}" fill="#cdd4d1" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="8">${_xml(_shorten(item.guidance, 40))}</text>',
        );
      x += cardWidth + 8;
    }
    buffer.writeln('</g>');
  }

  void _writeChart(
    StringBuffer buffer,
    _ChartData chart, {
    required int index,
    required int top,
    required int width,
  }) {
    const left = 56.0;
    final plotWidth = width - 332.0;
    const rowHeight = 28.0;
    final maxValue = chart.points.fold<double>(
      0,
      (max, point) => point.value > max ? point.value : max,
    );
    final secondaryMax = chart.secondaryPoints.fold<double>(
      0,
      (max, point) => point.value > max ? point.value : max,
    );
    final scaleMax = math.max(maxValue, secondaryMax);
    final accent = chart.kind.accent;
    buffer
      ..writeln(
        '<g class="chart-panel" data-chart-index="$index" data-chart-kind="${_xml(chart.kind.name)}" data-chart-title="${_xml(chart.title)}" data-point-count="${chart.points.length}">',
      )
      ..writeln(
        '<rect x="34" y="${top - 32}" width="${width - 68}" height="294" rx="16" fill="#151716" stroke="#29302d" stroke-width="1"/>',
      )
      ..writeln(
        '<text x="$left" y="$top" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="17" font-weight="700">${_xml(chart.title)}</text>',
      )
      ..writeln(
        '<rect x="${left + 1}" y="${top + 12}" width="${chart.kind.label.length * 7 + 18}" height="20" rx="10" fill="${chart.kind.badgeFill}"/>',
      )
      ..writeln(
        '<text x="${left + 10}" y="${top + 27}" fill="${chart.kind.badgeText}" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11" font-weight="700">${_xml(chart.kind.label)}</text>',
      )
      ..writeln(
        '<text x="${left + 190}" y="${top + 27}" fill="#9da6a3" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">${_xml(chart.valueLabel)}${chart.secondaryLabel == null ? '' : ' vs ${chart.secondaryLabel}'}</text>',
      );
    for (var i = 0; i < chart.points.length; i++) {
      final point = chart.points[i];
      final y = top + 58 + (i * rowHeight);
      final barWidth = scaleMax <= 0 ? 0 : (point.value / scaleMax) * plotWidth;
      final secondary = i < chart.secondaryPoints.length
          ? chart.secondaryPoints[i]
          : null;
      final secondaryWidth = secondary == null || scaleMax <= 0
          ? 0.0
          : (secondary.value / scaleMax) * plotWidth;
      final secondaryAttribute = secondary == null
          ? ''
          : ' data-secondary-value="${_format(secondary.value)}"';
      buffer
        ..writeln(
          '<g class="chart-point" data-label="${_xml(point.label)}" data-value="${_format(point.value)}"$secondaryAttribute>',
        )
        ..writeln(
          '<text x="$left" y="${y + 15}" fill="#d9dedb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">${_xml(_shorten(point.label, 25))}</text>',
        )
        ..writeln(
          '<rect x="${left + 210}" y="$y" width="$plotWidth" height="19" rx="5" fill="#222625"/>',
        );
      if (secondary != null) {
        buffer.writeln(
          '<rect x="${left + 210}" y="$y" width="$secondaryWidth" height="19" rx="5" fill="#3f4744"/>',
        );
      }
      buffer
        ..writeln(
          '<rect x="${left + 210}" y="$y" width="$barWidth" height="19" rx="5" fill="$accent"/>',
        )
        ..writeln(
          '<text x="${left + 222 + math.max(barWidth, secondaryWidth)}" y="${y + 15}" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12" font-weight="600">${_xml(_format(point.value))}</text>',
        )
        ..writeln('</g>');
    }
    var noteY = top + 236;
    for (final note in chart.notes.take(2)) {
      buffer.writeln(
        '<text class="chart-note" x="$left" y="$noteY" fill="#89928e" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">${_xml(note)}</text>',
      );
      noteY += 17;
    }
    buffer.writeln('</g>');
  }

  String _format(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  String _shorten(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1).trim()}…';
  }

  String _xml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

enum _ChartKind {
  poe('PoE Budget', '#7fc6a6', '#123126', '#bfead8'),
  wan('WAN Capacity', '#84a7ff', '#17254c', '#dbe5ff'),
  lifecycle('Lifecycle', '#e1b96b', '#3d2c10', '#f7e8bf'),
  comparison('Comparison', '#b79cff', '#2b214b', '#ebe3ff'),
  cost('Cost/TCO', '#f0a86b', '#432612', '#ffe4ca'),
  roadmap('Roadmap', '#8bc5ff', '#162c43', '#dceeff'),
  risk('Risk', '#ec8f87', '#471f1c', '#ffd9d5'),
  summary('Summary', '#78aaa5', '#183331', '#d8efec'),
  generic('Chart', '#78aaa5', '#183331', '#d8efec');

  final String label;
  final String accent;
  final String badgeFill;
  final String badgeText;

  const _ChartKind(this.label, this.accent, this.badgeFill, this.badgeText);
}

enum _RiskLevel { high, medium, low }

class _RiskProfile {
  final int high;
  final int medium;
  final int low;

  const _RiskProfile({this.high = 0, this.medium = 0, this.low = 0});

  static const empty = _RiskProfile();
}

class _ChartPackProfile {
  final int chartCount;
  final int pointCount;
  final int highRiskCount;
  final int mediumRiskCount;
  final int lowRiskCount;
  final bool hasPoe;
  final bool hasWan;
  final bool hasLifecycle;
  final bool hasComparison;
  final bool hasCost;
  final bool hasRoadmap;

  const _ChartPackProfile({
    required this.chartCount,
    required this.pointCount,
    required this.highRiskCount,
    required this.mediumRiskCount,
    required this.lowRiskCount,
    required this.hasPoe,
    required this.hasWan,
    required this.hasLifecycle,
    required this.hasComparison,
    required this.hasCost,
    required this.hasRoadmap,
  });

  List<String> get signals => [
    if (hasPoe) 'PoE/UPOE',
    if (hasWan) 'WAN capacity',
    if (hasLifecycle) 'Lifecycle',
    if (hasComparison) 'Model fit',
    if (hasCost) 'Cost/TCO',
    if (hasRoadmap) 'Roadmap',
  ];

  List<String> get chartFamilies => [
    if (hasPoe) 'PoE Budget',
    if (hasWan) 'WAN Capacity',
    if (hasLifecycle) 'Lifecycle Risk',
    if (hasComparison) 'Product Comparison',
    if (hasCost) 'Cost/TCO',
    if (hasRoadmap) 'Roadmap',
    if (highRiskCount + mediumRiskCount + lowRiskCount > 0) 'Risk Scorecard',
    if (chartCount > 0) 'Validation Gates',
  ];

  factory _ChartPackProfile.fromCharts(List<_ChartData> charts) {
    return _ChartPackProfile(
      chartCount: charts.length,
      pointCount: charts.fold<int>(
        0,
        (sum, chart) => sum + chart.points.length,
      ),
      highRiskCount: charts.fold<int>(
        0,
        (sum, chart) => sum + chart.riskProfile.high,
      ),
      mediumRiskCount: charts.fold<int>(
        0,
        (sum, chart) => sum + chart.riskProfile.medium,
      ),
      lowRiskCount: charts.fold<int>(
        0,
        (sum, chart) => sum + chart.riskProfile.low,
      ),
      hasPoe: charts.any((chart) => chart.kind == _ChartKind.poe),
      hasWan: charts.any((chart) => chart.kind == _ChartKind.wan),
      hasLifecycle: charts.any((chart) => chart.kind == _ChartKind.lifecycle),
      hasComparison: charts.any((chart) => chart.kind == _ChartKind.comparison),
      hasCost: charts.any((chart) => chart.kind == _ChartKind.cost),
      hasRoadmap: charts.any((chart) => chart.kind == _ChartKind.roadmap),
    );
  }
}

class _ChartData {
  final String title;
  final String valueLabel;
  final String? secondaryLabel;
  final _ChartKind kind;
  final List<_ChartPoint> points;
  final List<_ChartPoint> secondaryPoints;
  final List<String> notes;
  final _RiskProfile riskProfile;

  const _ChartData({
    required this.title,
    required this.valueLabel,
    required this.kind,
    required this.points,
    this.secondaryLabel,
    this.secondaryPoints = const [],
    this.notes = const [],
    this.riskProfile = _RiskProfile.empty,
  });
}

class _ChartPoint {
  final String label;
  final double value;

  const _ChartPoint(this.label, this.value);
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/artifact_document.dart';

class ChartRenderResult {
  final Uint8List bytes;
  final int chartCount;
  final List<List<String>> previewRows;

  const ChartRenderResult({
    required this.bytes,
    required this.chartCount,
    required this.previewRows,
  });
}

class ChartArtifactRenderer {
  const ChartArtifactRenderer();

  ChartRenderResult render(ArtifactDocument document) {
    final charts = _chartsFor(document);
    final svg = _svgFor(document.title, charts);
    return ChartRenderResult(
      bytes: Uint8List.fromList(utf8.encode(svg)),
      chartCount: charts.length,
      previewRows: charts.isEmpty
          ? const []
          : [
              ['Metric', charts.first.valueLabel],
              for (final point in charts.first.points.take(8))
                [point.label, _format(point.value)],
            ],
    );
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
    ];
  }

  String _svgFor(String title, List<_ChartData> charts) {
    const chartHeight = 330;
    final height = math.max(420, 132 + (charts.length * chartHeight));
    const width = 1040;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img">',
      )
      ..writeln('<title>${_xml(title)}</title>')
      ..writeln('<rect width="100%" height="100%" rx="22" fill="#0f1010"/>')
      ..writeln('<rect x="0" y="0" width="7" height="$height" fill="#78aaa5"/>')
      ..writeln(
        '<text x="42" y="50" fill="#f2f2ef" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="24" font-weight="700">${_xml(title)}</text>',
      )
      ..writeln(
        '<text x="42" y="76" fill="#929a96" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">Generated chart pack • ${charts.length} chart${charts.length == 1 ? '' : 's'}</text>',
      );

    for (var chartIndex = 0; chartIndex < charts.length; chartIndex++) {
      _writeChart(
        buffer,
        charts[chartIndex],
        top: 100 + (chartIndex * chartHeight),
        width: width,
      );
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  void _writeChart(
    StringBuffer buffer,
    _ChartData chart, {
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
      buffer
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
        );
    }
    var noteY = top + 236;
    for (final note in chart.notes.take(2)) {
      buffer.writeln(
        '<text x="$left" y="$noteY" fill="#89928e" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="11">${_xml(note)}</text>',
      );
      noteY += 17;
    }
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
  risk('Risk', '#ec8f87', '#471f1c', '#ffd9d5'),
  summary('Summary', '#78aaa5', '#183331', '#d8efec'),
  generic('Chart', '#78aaa5', '#183331', '#d8efec');

  final String label;
  final String accent;
  final String badgeFill;
  final String badgeText;

  const _ChartKind(this.label, this.accent, this.badgeFill, this.badgeText);
}

class _ChartData {
  final String title;
  final String valueLabel;
  final String? secondaryLabel;
  final _ChartKind kind;
  final List<_ChartPoint> points;
  final List<_ChartPoint> secondaryPoints;
  final List<String> notes;

  const _ChartData({
    required this.title,
    required this.valueLabel,
    required this.kind,
    required this.points,
    this.secondaryLabel,
    this.secondaryPoints = const [],
    this.notes = const [],
  });
}

class _ChartPoint {
  final String label;
  final double value;

  const _ChartPoint(this.label, this.value);
}

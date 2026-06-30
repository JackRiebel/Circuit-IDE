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
    for (final table in document.tables.take(4)) {
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
      _ChartData(title: 'Content Weight', valueLabel: 'Items', points: points),
    ];
  }

  _ChartData? _chartFromTable(ArtifactTable table) {
    if (table.rows.length < 2 || table.rows.first.length < 2) return null;
    final headers = table.rows.first;
    var numericColumn = -1;
    for (var column = 1; column < headers.length; column++) {
      final values = table.rows
          .skip(1)
          .map((row) => column < row.length ? _number(row[column]) : null)
          .whereType<double>()
          .toList();
      if (values.length >= math.min(2, table.rows.length - 1)) {
        numericColumn = column;
        break;
      }
    }
    if (numericColumn == -1) return null;
    final points = <_ChartPoint>[];
    for (final row in table.rows.skip(1)) {
      if (row.isEmpty || numericColumn >= row.length) continue;
      final value = _number(row[numericColumn]);
      if (value == null) continue;
      points.add(_ChartPoint(row.first, value));
    }
    if (points.isEmpty) return null;
    return _ChartData(
      title: table.title,
      valueLabel: headers[numericColumn],
      points: points.take(12).toList(growable: false),
    );
  }

  double? _number(String value) {
    final normalized = value.trim().replaceAll(',', '').replaceAll('%', '');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String _svgFor(String title, List<_ChartData> charts) {
    const chartHeight = 300;
    final height = math.max(420, 140 + (charts.length * chartHeight));
    const width = 980;
    final buffer = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height" role="img">',
      )
      ..writeln('<title>${_xml(title)}</title>')
      ..writeln('<rect width="100%" height="100%" rx="20" fill="#101111"/>')
      ..writeln('<rect x="0" y="0" width="8" height="$height" fill="#78aaa5"/>')
      ..writeln(
        '<text x="40" y="54" fill="#f2f2ef" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="25" font-weight="700">${_xml(title)}</text>',
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
    const left = 76.0;
    final plotWidth = width - 150.0;
    const rowHeight = 30.0;
    final maxValue = chart.points.fold<double>(
      0,
      (max, point) => point.value > max ? point.value : max,
    );
    buffer
      ..writeln(
        '<text x="$left" y="$top" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="17" font-weight="700">${_xml(chart.title)}</text>',
      )
      ..writeln(
        '<text x="$left" y="${top + 24}" fill="#9da6a3" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">${_xml(chart.valueLabel)}</text>',
      );
    for (var i = 0; i < chart.points.length; i++) {
      final point = chart.points[i];
      final y = top + 54 + (i * rowHeight);
      final barWidth = maxValue <= 0 ? 0 : (point.value / maxValue) * plotWidth;
      buffer
        ..writeln(
          '<text x="$left" y="${y + 15}" fill="#d9dedb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12">${_xml(_shorten(point.label, 28))}</text>',
        )
        ..writeln(
          '<rect x="${left + 220}" y="$y" width="$barWidth" height="19" rx="5" fill="#78aaa5"/>',
        )
        ..writeln(
          '<text x="${left + 230 + barWidth}" y="${y + 15}" fill="#f4f1eb" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" font-size="12" font-weight="600">${_xml(_format(point.value))}</text>',
        );
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

class _ChartData {
  final String title;
  final String valueLabel;
  final List<_ChartPoint> points;

  const _ChartData({
    required this.title,
    required this.valueLabel,
    required this.points,
  });
}

class _ChartPoint {
  final String label;
  final double value;

  const _ChartPoint(this.label, this.value);
}

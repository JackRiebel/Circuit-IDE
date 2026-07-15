import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/release_performance_series.dart';

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length.isEven) {
    stderr.writeln(
      'usage: dart run scripts/aggregate_release_performance.dart /path/to/samples.jsonl [--key value]...',
    );
    exitCode = 64;
    return;
  }
  try {
    final metadata = <String, String>{};
    for (var index = 1; index < arguments.length; index += 2) {
      final flag = arguments[index];
      final value = arguments[index + 1];
      final key = switch (flag) {
        '--build-version' => 'buildVersion',
        '--macos-version' => 'macosVersion',
        '--architecture' => 'architecture',
        '--hardware-model' => 'hardwareModel',
        '--fixture-revision' => 'fixtureRevision',
        _ => throw FormatException('Unsupported metadata flag: $flag'),
      };
      metadata[key] = value;
    }
    final lines = File(arguments.first).readAsLinesSync();
    final series = PackagedReleasePerformanceSeries.parseLines(lines);
    final output = series.toJson();
    if (metadata.isNotEmpty) output['metadata'] = metadata;
    stdout.writeln(jsonEncode(output));
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read release performance samples: $error');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln('Invalid release performance samples: ${error.message}');
    exitCode = 65;
  }
}

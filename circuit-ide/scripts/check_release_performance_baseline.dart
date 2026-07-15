import 'dart:convert';
import 'dart:io';

import 'package:circuit_ide/services/release_performance_baseline.dart';

void main(List<String> arguments) {
  if (arguments.length < 2 || arguments.length > 3) {
    stderr.writeln(
      'usage: dart run scripts/check_release_performance_baseline.dart baseline.json series.json [--require-match]',
    );
    exitCode = 64;
    return;
  }
  final requireMatch = arguments.length == 3;
  if (requireMatch && arguments.last != '--require-match') {
    stderr.writeln('Unsupported release performance baseline option.');
    exitCode = 64;
    return;
  }
  try {
    final baseline = PackagedReleasePerformanceBaseline.fromJson(
      jsonDecode(File(arguments[0]).readAsStringSync()),
    );
    final series = jsonDecode(File(arguments[1]).readAsStringSync());
    if (series is! Map) {
      throw const FormatException('Release performance series must be a map.');
    }
    final result = baseline.evaluate(Map<String, Object?>.from(series));
    stdout.writeln(jsonEncode(result.toJson()));
    if (!result.passed || (requireMatch && !result.applicable)) {
      exitCode = 1;
    }
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read release performance baseline: $error');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln('Invalid release performance baseline: ${error.message}');
    exitCode = 65;
  }
}

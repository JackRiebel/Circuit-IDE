import 'flow_analyzer.dart';

class FlowContextBuilder {
  static const _maxTokenBudget = 2000;

  /// Format flow context for system prompt injection.
  static String format(FlowContext ctx) {
    if (ctx.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('## Connected Code Context');
    buffer.writeln();

    int tokenEstimate = 30; // header overhead

    // Direct imports (highest priority)
    if (ctx.dependencies.isNotEmpty) {
      buffer.writeln('### Dependencies (imported by active file)');
      for (final sig in ctx.dependencies) {
        final section = _formatSignature(sig);
        final sectionTokens = (section.length / 4).ceil();
        if (tokenEstimate + sectionTokens > _maxTokenBudget) break;
        buffer.writeln(section);
        tokenEstimate += sectionTokens;
      }
      buffer.writeln();
    }

    // Dependents (lower priority)
    if (ctx.dependents.isNotEmpty && tokenEstimate < _maxTokenBudget) {
      buffer.writeln('### Dependents (files that import active file)');
      for (final sig in ctx.dependents) {
        final section = _formatSignature(sig);
        final sectionTokens = (section.length / 4).ceil();
        if (tokenEstimate + sectionTokens > _maxTokenBudget) break;
        buffer.writeln(section);
        tokenEstimate += sectionTokens;
      }
    }

    return buffer.toString().trim();
  }

  static String _formatSignature(FileSignature sig) {
    final buffer = StringBuffer();
    buffer.writeln('**${sig.relativePath}**');

    if (sig.classNames.isNotEmpty) {
      buffer.writeln('- Classes: ${sig.classNames.join(', ')}');
    }
    if (sig.functionSignatures.isNotEmpty) {
      for (final fn in sig.functionSignatures.take(10)) {
        buffer.writeln('- `$fn`');
      }
      if (sig.functionSignatures.length > 10) {
        buffer.writeln('- ... and ${sig.functionSignatures.length - 10} more');
      }
    }
    if (sig.exportedConstants.isNotEmpty) {
      buffer.writeln('- Constants: ${sig.exportedConstants.join(', ')}');
    }
    return buffer.toString();
  }
}

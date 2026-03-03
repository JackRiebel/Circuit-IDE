import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/security/vulnerability_scanner.dart';
import '../core/utils/logger.dart';
import '../models/security_scan_models.dart';
import 'connection_provider.dart';
import 'file_tree_provider.dart';

class SecurityScanState {
  final ScanResult? lastResult;
  final bool isScanning;
  final Set<String> activeSeverityFilters;
  final String? aiAnalysis;
  final bool isAnalyzing;

  const SecurityScanState({
    this.lastResult,
    this.isScanning = false,
    this.activeSeverityFilters = const {'critical', 'high', 'medium', 'low'},
    this.aiAnalysis,
    this.isAnalyzing = false,
  });

  SecurityScanState copyWith({
    ScanResult? lastResult,
    bool? isScanning,
    Set<String>? activeSeverityFilters,
    String? aiAnalysis,
    bool? isAnalyzing,
  }) {
    return SecurityScanState(
      lastResult: lastResult ?? this.lastResult,
      isScanning: isScanning ?? this.isScanning,
      activeSeverityFilters:
          activeSeverityFilters ?? this.activeSeverityFilters,
      aiAnalysis: aiAnalysis ?? this.aiAnalysis,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
    );
  }

  List<SecurityFinding> get filteredFindings {
    if (lastResult == null) return [];
    return lastResult!.findings
        .where((f) => activeSeverityFilters.contains(f.severity))
        .toList();
  }
}

class SecurityScanNotifier extends Notifier<SecurityScanState> {
  final _scanner = VulnerabilityScanner();

  @override
  SecurityScanState build() => const SecurityScanState();

  Future<void> scanProject() async {
    final rootPath = ref.read(fileTreeProvider).rootPath;
    if (rootPath == null) return;

    state = state.copyWith(isScanning: true);

    try {
      final result = await _scanner.scanProject(rootPath);
      state = SecurityScanState(
        lastResult: result,
        isScanning: false,
        activeSeverityFilters: state.activeSeverityFilters,
      );
    } catch (e) {
      Logger.error('Security scan failed', e);
      state = state.copyWith(isScanning: false);
    }
  }

  void toggleSeverityFilter(String severity) {
    final filters = Set<String>.from(state.activeSeverityFilters);
    if (filters.contains(severity)) {
      filters.remove(severity);
    } else {
      filters.add(severity);
    }
    state = state.copyWith(activeSeverityFilters: filters);
  }

  Future<void> aiAnalyzeFinding(SecurityFinding finding) async {
    final service = ref.read(agentServiceProvider);
    if (!service.isConnected) return;

    state = state.copyWith(isAnalyzing: true, aiAnalysis: null);

    try {
      final prompt = '''Analyze this security vulnerability and provide a detailed fix:

**Type**: ${finding.type.displayName}
**Severity**: ${finding.severity.toUpperCase()}
**File**: ${finding.filePath}:${finding.line}
**Code**: `${finding.preview}`
**Description**: ${finding.description}

Please provide:
1. A detailed explanation of why this is vulnerable
2. The exact code fix needed
3. Any additional security recommendations''';

      final result = await service.sendOneShot(prompt);
      state = state.copyWith(
        aiAnalysis: result ?? 'Unable to generate analysis.',
        isAnalyzing: false,
      );
    } catch (e) {
      Logger.error('AI analysis failed', e);
      state = state.copyWith(
        aiAnalysis: 'Analysis failed: $e',
        isAnalyzing: false,
      );
    }
  }

  void clearAnalysis() {
    state = state.copyWith(aiAnalysis: null);
  }
}

final securityScanProvider =
    NotifierProvider<SecurityScanNotifier, SecurityScanState>(
  SecurityScanNotifier.new,
);

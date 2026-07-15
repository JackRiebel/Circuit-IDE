import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/artifact_document.dart';
import '../models/artifact_template.dart';
import '../models/generated_artifact.dart';
import 'architecture_review_pack_builder.dart';
import 'artifact_accessibility_evaluator.dart';
import 'artifact_readiness_evaluator.dart';
import 'artifact_quality_matrix_evaluator.dart';
import 'artifact_type_registry.dart';
import 'artifact_visual_preview_renderer.dart';
import 'artifact_workbook_layout.dart';
import 'business_use_case_brief_builder.dart';
import 'change_summary_diff_report_builder.dart';
import 'chart_artifact_renderer.dart';
import 'diagram_artifact_renderer.dart';
import 'docx_artifact_inspector.dart';
import 'docx_artifact_renderer.dart';
import 'evidence_pack_builder.dart';
import 'html_artifact_renderer.dart';
import 'implementation_plan_artifact_builder.dart';
import 'lifecycle_eox_workbook_builder.dart';
import 'network_topology_brief_builder.dart';
import 'pdf_artifact_inspector.dart';
import 'pdf_artifact_renderer.dart';
import 'powerpoint_artifact_inspector.dart';
import 'powerpoint_artifact_renderer.dart';
import 'powerpoint_visual_preview_renderer.dart';
import 'product_comparison_workbook_builder.dart';
import 'solution_sizing_workbook_builder.dart';
import 'workbook_artifact_inspector.dart';
import 'worker_cancellation.dart';

// ADR-0005: this is the sole generated-artifact output-routing boundary.
class GeneratedArtifactWriter {
  static const _maximumWorkbookSheets = 48;
  static int _stagedFileSequence = 0;

  final ArtifactComposer composer;
  final PowerPointArtifactRenderer powerPointRenderer;
  final PowerPointVisualPreviewRenderer powerPointVisualPreviewRenderer;
  final DocxArtifactRenderer docxRenderer;
  final PdfArtifactRenderer pdfRenderer;
  final PdfArtifactInspector pdfInspector;
  final PowerPointArtifactInspector powerPointInspector;
  final DocxArtifactInspector docxInspector;
  final WorkbookArtifactInspector workbookInspector;
  final DiagramArtifactRenderer diagramRenderer;
  final ChartArtifactRenderer chartRenderer;
  final HtmlArtifactRenderer htmlRenderer;
  final LifecycleEoxWorkbookBuilder lifecycleEoxBuilder;
  final NetworkTopologyBriefBuilder networkTopologyBuilder;
  final ProductComparisonWorkbookBuilder productComparisonBuilder;
  final SolutionSizingWorkbookBuilder solutionSizingBuilder;
  final ArchitectureReviewPackBuilder architectureReviewBuilder;
  final BusinessUseCaseBriefBuilder businessUseCaseBuilder;
  final EvidencePackBuilder evidencePackBuilder;
  final ImplementationPlanArtifactBuilder implementationPlanBuilder;
  final ChangeSummaryDiffReportBuilder changeSummaryBuilder;
  final ArtifactReadinessEvaluator readinessEvaluator;
  final ArtifactQualityMatrixEvaluator artifactQualityMatrixEvaluator;
  final ArtifactAccessibilityEvaluator accessibilityEvaluator;
  final ArtifactVisualPreviewRenderer artifactVisualPreviewRenderer;
  final ArtifactTypeRegistry artifactTypeRegistry;
  final ArtifactTemplateRegistry artifactTemplateRegistry;

  const GeneratedArtifactWriter({
    this.composer = const ArtifactComposer(),
    this.powerPointRenderer = const PowerPointArtifactRenderer(),
    this.powerPointVisualPreviewRenderer =
        const PowerPointVisualPreviewRenderer(),
    this.docxRenderer = const DocxArtifactRenderer(),
    this.pdfRenderer = const PdfArtifactRenderer(),
    this.pdfInspector = const PdfArtifactInspector(),
    this.powerPointInspector = const PowerPointArtifactInspector(),
    this.docxInspector = const DocxArtifactInspector(),
    this.workbookInspector = const WorkbookArtifactInspector(),
    this.diagramRenderer = const DiagramArtifactRenderer(),
    this.chartRenderer = const ChartArtifactRenderer(),
    this.htmlRenderer = const HtmlArtifactRenderer(),
    this.lifecycleEoxBuilder = const LifecycleEoxWorkbookBuilder(),
    this.networkTopologyBuilder = const NetworkTopologyBriefBuilder(),
    this.productComparisonBuilder = const ProductComparisonWorkbookBuilder(),
    this.solutionSizingBuilder = const SolutionSizingWorkbookBuilder(),
    this.architectureReviewBuilder = const ArchitectureReviewPackBuilder(),
    this.businessUseCaseBuilder = const BusinessUseCaseBriefBuilder(),
    this.evidencePackBuilder = const EvidencePackBuilder(),
    this.implementationPlanBuilder = const ImplementationPlanArtifactBuilder(),
    this.changeSummaryBuilder = const ChangeSummaryDiffReportBuilder(),
    this.readinessEvaluator = const ArtifactReadinessEvaluator(),
    this.artifactQualityMatrixEvaluator =
        const ArtifactQualityMatrixEvaluator(),
    this.accessibilityEvaluator = const ArtifactAccessibilityEvaluator(),
    this.artifactVisualPreviewRenderer = const ArtifactVisualPreviewRenderer(),
    this.artifactTypeRegistry = const ArtifactTypeRegistry(),
    this.artifactTemplateRegistry = const ArtifactTemplateRegistry(),
  });

  Future<GeneratedArtifact?> writeFromAssistantOutput({
    required String rootPath,
    required String prompt,
    required String content,
    required String turnId,
    required String? threadId,
    required String? requestId,
    int artifactVersion = 1,
    String? parentArtifactId,
    String? templateId,
    WorkerCancellationToken? cancellationToken,
  }) async {
    final route = artifactTypeRegistry.routeForPrompt(prompt);
    final requestedKind = route.primaryKind;
    if (requestedKind == null || content.trim().isEmpty) return null;
    final root = p.normalize(rootPath);
    final outputDir = Directory(p.join(root, 'outputs'));
    if (!p.isWithin(root, outputDir.path) && outputDir.path != root) {
      return null;
    }
    await outputDir.create(recursive: true);

    final baseName = _safeBaseName(prompt);
    final now = DateTime.now();
    final template = artifactTemplateRegistry.resolve(templateId);
    final document = template.apply(
      composer.fromAssistantOutput(prompt: prompt, content: content),
    );
    final resolved = await _resolveOutput(
      requestedKind: requestedKind,
      prompt: prompt,
      content: content,
      document: document,
      cancellationToken: cancellationToken,
    );
    if (resolved == null) return null;

    final fileName =
        '${_versionedBaseName(baseName, artifactVersion)}.${resolved.extension}';
    final filePath = p.join(outputDir.path, fileName);
    final normalizedFilePath = p.normalize(filePath);
    if (!p.isWithin(root, normalizedFilePath)) return null;
    final persistedOutput = await _persistArtifactOutput(
      artifactFilePath: normalizedFilePath,
      resolved: resolved,
      document: document,
    );
    final size = persistedOutput.byteSize;
    final visualPreview = persistedOutput.visualPreview;
    final metadataWithoutMatrix = {
      ..._metadataWithReadiness(
        resolved: resolved,
        document: document,
        byteSize: size,
        route: route,
        persistedVisualPreviewMetadata: visualPreview.metadata,
      ),
      ...{
        'visualPreviewPath': visualPreview.path,
        'visualPreviewFormat': visualPreview.extension,
        'visualPreviewSha256': visualPreview.sha256,
        'visualPreviewByteSize': visualPreview.byteSize,
        'visualPreviewPersistence': 'atomic-sidecar-v1',
      },
    };
    final metadata = {
      ...metadataWithoutMatrix,
      ...artifactQualityMatrixEvaluator.metadataFor(
        kind: resolved.kind,
        document: document,
        bytes: resolved.bytes,
        extension: resolved.extension,
        previewRows: resolved.previewRows,
        metadata: metadataWithoutMatrix,
        visualPreviewPersisted: true,
      ),
    };
    return GeneratedArtifact(
      id: turnId,
      kind: resolved.kind,
      status: resolved.status,
      fileName: fileName,
      filePath: normalizedFilePath,
      summary: resolved.summary,
      byteSize: size,
      previewRows: resolved.previewRows,
      sheetCount: resolved.sheetCount,
      metadata: metadata,
      threadId: threadId,
      requestId: requestId,
      createdAt: now,
      version: artifactVersion,
      parentArtifactId: parentArtifactId,
      outputHash: sha256.convert(resolved.bytes).toString(),
      generationRecipe: _generationRecipe(
        prompt: prompt,
        content: content,
        template: template,
      ),
    );
  }

  Future<GeneratedArtifact?> writeStructuredArtifact({
    required String rootPath,
    required String prompt,
    required String content,
    required GeneratedArtifactKind targetKind,
    required String turnId,
    required String? threadId,
    required String? requestId,
    int artifactVersion = 1,
    String? parentArtifactId,
    String? templateId,
    WorkerCancellationToken? cancellationToken,
  }) async {
    if (content.trim().isEmpty) return null;
    final root = p.normalize(rootPath);
    final outputDir = Directory(p.join(root, 'outputs'));
    if (!p.isWithin(root, outputDir.path) && outputDir.path != root) {
      return null;
    }
    await outputDir.create(recursive: true);

    final template = artifactTemplateRegistry.resolve(templateId);
    final document = template.apply(
      composer.fromAssistantOutput(prompt: prompt, content: content),
    );
    final resolved = await _resolveOutput(
      requestedKind: targetKind,
      prompt: prompt,
      content: content,
      document: document,
      cancellationToken: cancellationToken,
    );
    if (resolved == null) return null;

    final baseName = _safeBaseName(prompt);
    final fileName =
        '${_versionedBaseName(baseName, artifactVersion)}.${resolved.extension}';
    final filePath = p.join(outputDir.path, fileName);
    final normalizedFilePath = p.normalize(filePath);
    if (!p.isWithin(root, normalizedFilePath)) return null;
    final persistedOutput = await _persistArtifactOutput(
      artifactFilePath: normalizedFilePath,
      resolved: resolved,
      document: document,
    );
    final size = persistedOutput.byteSize;
    final visualPreview = persistedOutput.visualPreview;
    final metadataWithoutMatrix = {
      ..._metadataWithReadiness(
        resolved: resolved,
        document: document,
        byteSize: size,
        route: artifactTypeRegistry.routeForPrompt(prompt),
        persistedVisualPreviewMetadata: visualPreview.metadata,
      ),
      ...{
        'visualPreviewPath': visualPreview.path,
        'visualPreviewFormat': visualPreview.extension,
        'visualPreviewSha256': visualPreview.sha256,
        'visualPreviewByteSize': visualPreview.byteSize,
        'visualPreviewPersistence': 'atomic-sidecar-v1',
      },
    };
    final metadata = {
      ...metadataWithoutMatrix,
      ...artifactQualityMatrixEvaluator.metadataFor(
        kind: resolved.kind,
        document: document,
        bytes: resolved.bytes,
        extension: resolved.extension,
        previewRows: resolved.previewRows,
        metadata: metadataWithoutMatrix,
        visualPreviewPersisted: true,
      ),
    };
    return GeneratedArtifact(
      id: turnId,
      kind: resolved.kind,
      status: resolved.status,
      fileName: fileName,
      filePath: normalizedFilePath,
      summary: resolved.summary,
      byteSize: size,
      previewRows: resolved.previewRows,
      sheetCount: resolved.sheetCount,
      metadata: metadata,
      threadId: threadId,
      requestId: requestId,
      createdAt: DateTime.now(),
      version: artifactVersion,
      parentArtifactId: parentArtifactId,
      outputHash: sha256.convert(resolved.bytes).toString(),
      generationRecipe: _generationRecipe(
        prompt: prompt,
        content: content,
        template: template,
      ),
    );
  }

  Map<String, Object?> _metadataWithReadiness({
    required _ResolvedArtifact resolved,
    required ArtifactDocument document,
    required int byteSize,
    required ArtifactRouteDecision route,
    Map<String, Object?> persistedVisualPreviewMetadata = const {},
  }) {
    final descriptor = _descriptorForRoute(route, resolved.kind);
    final resolvedMetadata = {
      ...resolved.metadata,
      ...persistedVisualPreviewMetadata,
    };
    final quality = readinessEvaluator.metadataFor(
      kind: resolved.kind,
      status: resolved.status,
      document: document,
      previewRows: resolved.previewRows,
      count: resolved.sheetCount,
      byteSize: byteSize,
      metadata: resolvedMetadata,
      contractFields: descriptor.contractFields,
    );
    final accessibility = accessibilityEvaluator.metadataFor(
      kind: resolved.kind,
      document: document,
      previewRows: resolved.previewRows,
      metadata: resolvedMetadata,
    );
    return {
      ...document.metadata,
      ...resolvedMetadata,
      ..._documentStructureMetadata(document),
      ..._descriptorMetadata(
        descriptor: descriptor,
        route: route,
        kind: resolved.kind,
      ),
      ..._artifactSpecializationMetadata(resolvedMetadata),
      ...accessibility,
      ...quality,
    };
  }

  Map<String, Object?> _documentStructureMetadata(ArtifactDocument document) {
    return {
      'artifactSectionCount': document.sections.length,
      'artifactTableCount': document.tables.length,
      'artifactChartCount': document.charts.length,
      'artifactDiagramCount': document.diagrams.length,
      'artifactAppendixCount': document.appendices.length,
      'artifactSourceDataCount': document.sourceData.length,
      'artifactCitationCount': document.citations.length,
      'artifactHasSources': document.citations.isNotEmpty,
      if (document.exportMetadata.hasData)
        'artifactExportMetadata': {
          'requestedFormats': document.exportMetadata.requestedFormats,
          if (document.exportMetadata.audience != null)
            'audience': document.exportMetadata.audience,
          if (document.exportMetadata.checkedDate != null)
            'checkedDate': document.exportMetadata.checkedDate,
          ...document.exportMetadata.fields,
        },
    };
  }

  ArtifactTypeDescriptor _descriptorForRoute(
    ArtifactRouteDecision route,
    GeneratedArtifactKind kind,
  ) {
    final descriptor = route.descriptor;
    if (descriptor != null &&
        (descriptor.supportedKinds.contains(kind) ||
            descriptor.packageKinds.contains(kind))) {
      return descriptor;
    }
    return artifactTypeRegistry.descriptorForKind(kind) ??
        ArtifactTypeDescriptor(
          id: kind.name,
          label: _generatedArtifactKindLabel(kind),
          supportedKinds: [kind],
        );
  }

  Map<String, Object?> _descriptorMetadata({
    required ArtifactTypeDescriptor descriptor,
    required ArtifactRouteDecision route,
    required GeneratedArtifactKind kind,
  }) {
    return {
      'artifactDescriptorId': descriptor.id,
      'artifactDescriptorLabel': descriptor.label,
      'artifactPreviewSurface': descriptor.previewSurface,
      'artifactUseCases': descriptor.useCases,
      'artifactRequiredInputs': descriptor.requiredInputs,
      'artifactDrawerActions': descriptor.drawerActions,
      'artifactVerificationChecks': descriptor.verificationChecks,
      'artifactSupportedKinds': descriptor.supportedKinds
          .map((kind) => kind.name)
          .toList(growable: false),
      'artifactPackageKinds': descriptor.packageKinds
          .map((kind) => kind.name)
          .toList(growable: false),
      'artifactRouteTargets': route.targetKinds
          .map((kind) => kind.name)
          .toList(growable: false),
      'artifactRouteLabel': route.label,
      'artifactContractLabel': route.contractLabel,
      'artifactContractFields': descriptor.contractFields
          .map((field) => field.label)
          .toList(growable: false),
      'artifactRequestedKind': route.requestedKind?.name,
      'artifactProducedKind': kind.name,
    };
  }

  Map<String, Object?> _artifactSpecializationMetadata(
    Map<String, Object?> metadata,
  ) {
    if (metadata['artifactTemplate'] == 'evidence_pack' &&
        metadata['hasVisualEvidenceRegister'] == true &&
        _metadataIntFrom(metadata['visualEvidenceCount']) > 0) {
      final reliability =
          metadata['visualEvidenceReliability']?.toString().trim() ?? '';
      final requiresVisionReview =
          metadata['visualEvidenceRequiresVisionReview'] == true ||
          reliability == 'metadata_only_until_vision_or_user_description';
      return {
        'artifactPreviewSurface': 'Visual evidence review',
        'artifactSpecialization': 'visual_evidence',
        'artifactTrustBoundary': requiresVisionReview
            ? 'Metadata-only screenshots: add OCR, vision analysis, or a user description before relying on pixel-level visual claims.'
            : 'OCR or user-provided visual text is attached; validate it before customer-facing handoff.',
        'artifactPrimaryAction': metadata['visualEvidenceReviewAction'],
        'artifactEvidenceReadiness': requiresVisionReview
            ? 'Needs OCR/vision/user description'
            : 'Visual text attached - validate',
      };
    }
    return const {};
  }

  int _metadataIntFrom(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _generatedArtifactKindLabel(GeneratedArtifactKind kind) {
    return switch (kind) {
      GeneratedArtifactKind.excel => 'Excel Workbook',
      GeneratedArtifactKind.csv => 'CSV Dataset',
      GeneratedArtifactKind.markdown => 'Markdown Document',
      GeneratedArtifactKind.html => 'HTML Document',
      GeneratedArtifactKind.json => 'JSON Artifact',
      GeneratedArtifactKind.pdf => 'PDF Report',
      GeneratedArtifactKind.powerPoint => 'PowerPoint Deck',
      GeneratedArtifactKind.docx => 'Word / DOCX Report',
      GeneratedArtifactKind.diagram => 'Network Topology Diagram',
      GeneratedArtifactKind.chart => 'Chart Pack',
      GeneratedArtifactKind.report => 'Report',
    };
  }

  Future<_ResolvedArtifact?> _resolveOutput({
    required GeneratedArtifactKind requestedKind,
    required String prompt,
    required String content,
    required ArtifactDocument document,
    WorkerCancellationToken? cancellationToken,
  }) async {
    var documentForOutput = document;
    if (businessUseCaseBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint)) {
      documentForOutput = businessUseCaseBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }
    if (architectureReviewBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint)) {
      documentForOutput = architectureReviewBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }
    if (evidencePackBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint ||
            requestedKind == GeneratedArtifactKind.json)) {
      documentForOutput = evidencePackBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }
    if (implementationPlanBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint ||
            requestedKind == GeneratedArtifactKind.markdown)) {
      documentForOutput = implementationPlanBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }
    if (changeSummaryBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint ||
            requestedKind == GeneratedArtifactKind.markdown)) {
      documentForOutput = changeSummaryBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }
    if (networkTopologyBuilder.matches(prompt) &&
        (requestedKind == GeneratedArtifactKind.docx ||
            requestedKind == GeneratedArtifactKind.pdf ||
            requestedKind == GeneratedArtifactKind.powerPoint ||
            requestedKind == GeneratedArtifactKind.markdown)) {
      documentForOutput = networkTopologyBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
    }

    if (requestedKind == GeneratedArtifactKind.powerPoint) {
      final slideCount = powerPointRenderer.slideCountFor(documentForOutput);
      final bytes = await powerPointRenderer.renderInWorker(
        documentForOutput,
        cancellationToken: cancellationToken,
      );
      final inspectionMetadata = await powerPointInspector
          .inspectMetadataInWorker(
            bytes,
            expectedSlideCount: slideCount,
            cancellationToken: cancellationToken,
          );
      if (inspectionMetadata['pptxStructuralValid'] != true) {
        throw StateError(
          'Generated PowerPoint failed structural inspection: ${inspectionMetadata['pptxInspectionFailedChecks']}',
        );
      }
      final architectureReview = architectureReviewBuilder.matches(prompt);
      final implementationPlan = implementationPlanBuilder.matches(prompt);
      final changeSummary = changeSummaryBuilder.matches(prompt);
      final topologyBrief = networkTopologyBuilder.matches(prompt);
      final evidencePack = evidencePackBuilder.matches(prompt);
      final visualPreview = powerPointVisualPreviewRenderer.renderDeck(
        documentForOutput,
      );
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.powerPoint,
        status: GeneratedArtifactStatus.ready,
        extension: 'pptx',
        bytes: bytes,
        summary: architectureReview
            ? 'Created an architecture review PowerPoint deck with $slideCount slides, findings, risks, recommendations, validation, assumptions, and sources.'
            : implementationPlan
            ? 'Created an implementation plan PowerPoint deck with $slideCount slides, phases, workstreams, dependencies, verification, rollback, approval gates, and sources.'
            : changeSummary
            ? 'Created a change summary PowerPoint deck with $slideCount slides, edited files, verification results, command log, checkpoints, risks, and next steps.'
            : topologyBrief
            ? 'Created a topology PowerPoint deck with $slideCount slides, inventory, validated links, capacity checks, failure domains, assumptions, and sources.'
            : evidencePack
            ? 'Created an evidence readout PowerPoint deck with $slideCount slides, claim/source matrix, checked-date register, confidence gates, unsupported-claim triage, assumptions, and follow-up actions.'
            : 'Created a PowerPoint deck with $slideCount slides from the response structure.',
        previewRows: powerPointRenderer.previewRowsFor(documentForOutput),
        sheetCount: slideCount,
        metadata: {
          ...documentForOutput.metadata,
          ...powerPointRenderer.metadataFor(documentForOutput),
          ...inspectionMetadata,
          ...visualPreview.metadata,
        },
        visualPreviewBytes: visualPreview.bytes,
        visualPreviewExtension: 'svg',
      );
    }

    if (requestedKind == GeneratedArtifactKind.docx) {
      final bytes = await docxRenderer.renderInWorker(
        documentForOutput,
        cancellationToken: cancellationToken,
      );
      final inspectionMetadata = await docxInspector.inspectMetadataInWorker(
        bytes,
        cancellationToken: cancellationToken,
      );
      if (inspectionMetadata['docxStructuralValid'] != true) {
        throw StateError(
          'Generated DOCX failed structural inspection: ${inspectionMetadata['docxInspectionFailedChecks']}',
        );
      }
      final businessUseCase = businessUseCaseBuilder.matches(prompt);
      final architectureReview = architectureReviewBuilder.matches(prompt);
      final evidencePack = evidencePackBuilder.matches(prompt);
      final implementationPlan = implementationPlanBuilder.matches(prompt);
      final changeSummary = changeSummaryBuilder.matches(prompt);
      final topologyBrief = networkTopologyBuilder.matches(prompt);
      final previewRows = docxRenderer.previewRowsFor(documentForOutput);
      final visualPreview = artifactVisualPreviewRenderer.render(
        kind: GeneratedArtifactKind.docx,
        document: documentForOutput,
        previewRows: previewRows,
        unitCount: documentForOutput.sections.length,
      );
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.docx,
        status: GeneratedArtifactStatus.ready,
        extension: 'docx',
        bytes: bytes,
        summary: businessUseCase
            ? 'Created a business use case brief with executive decision snapshot, readiness scorecard, prioritized use cases, value metrics, solution mapping, account motion, objection handling, next steps, assumptions, and sources.'
            : architectureReview
            ? 'Created an architecture review pack with findings matrix, risk register, recommendation roadmap, validation checklist, decisions, assumptions, and sources.'
            : evidencePack
            ? 'Created an evidence pack with claim-to-source matrix, source freshness register, unsupported-claim triage, confidence scorecard, assumptions, and follow-up checklist.'
            : implementationPlan
            ? 'Created an implementation plan with scope, workstreams, phases, dependencies, verification, rollback, approval gates, assumptions, and sources.'
            : changeSummary
            ? 'Created a change summary / diff report with edited files, verification results, command log, checkpoints, risks, and next steps.'
            : topologyBrief
            ? 'Created a topology report with inventory, validated links, capacity checks, failure-domain review, assumptions, and sources.'
            : 'Created a Word report with ${documentForOutput.sections.length} sections from the response structure.',
        previewRows: previewRows,
        sheetCount: documentForOutput.sections.length,
        metadata: {
          ...documentForOutput.metadata,
          ...docxRenderer.metadataFor(documentForOutput),
          ...inspectionMetadata,
          ...visualPreview.metadata,
        },
        visualPreviewBytes: visualPreview.bytes,
        visualPreviewExtension: 'svg',
      );
    }

    if (requestedKind == GeneratedArtifactKind.pdf) {
      final bytes = await pdfRenderer.renderInWorker(
        documentForOutput,
        cancellationToken: cancellationToken,
      );
      final inspectionResult = await pdfInspector.inspectForArtifactInWorker(
        bytes,
        cancellationToken: cancellationToken,
      );
      final inspectedPageCount = inspectionResult['pageCount'] as int? ?? 0;
      final inspectionMetadata = Map<String, Object?>.from(
        inspectionResult['metadata'] as Map,
      );
      final pageCount = inspectedPageCount > 0
          ? inspectedPageCount
          : _pdfPageCount(bytes);
      final architectureReview = architectureReviewBuilder.matches(prompt);
      final implementationPlan = implementationPlanBuilder.matches(prompt);
      final changeSummary = changeSummaryBuilder.matches(prompt);
      final topologyBrief = networkTopologyBuilder.matches(prompt);
      final previewRows = pdfRenderer.previewRowsFor(
        documentForOutput,
        pageCount: pageCount,
      );
      final visualPreview = artifactVisualPreviewRenderer.render(
        kind: GeneratedArtifactKind.pdf,
        document: documentForOutput,
        previewRows: previewRows,
        unitCount: pageCount,
      );
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.pdf,
        status: GeneratedArtifactStatus.ready,
        extension: 'pdf',
        bytes: bytes,
        summary: architectureReview
            ? 'Created an architecture review PDF with findings, risks, recommendations, validation, assumptions, and sources.'
            : implementationPlan
            ? 'Created an implementation plan PDF with phases, dependencies, verification, rollback, approval gates, assumptions, and sources.'
            : changeSummary
            ? 'Created a change summary / diff report PDF with edited files, verification results, command log, checkpoints, risks, and next steps.'
            : topologyBrief
            ? 'Created a topology PDF report with inventory, validated links, capacity checks, failure-domain review, assumptions, and sources.'
            : 'Created a PDF report with ${documentForOutput.sections.length} sections from the response structure.',
        previewRows: previewRows,
        sheetCount: pageCount,
        metadata: {
          ...documentForOutput.metadata,
          ...pdfRenderer.metadataFor(documentForOutput),
          ...inspectionMetadata,
          ...visualPreview.metadata,
        },
        visualPreviewBytes: visualPreview.bytes,
        visualPreviewExtension: 'svg',
      );
    }

    if (requestedKind == GeneratedArtifactKind.diagram) {
      final diagram = diagramRenderer.render(
        document: document,
        content: content,
      );
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.diagram,
        status: GeneratedArtifactStatus.ready,
        extension: 'svg',
        bytes: diagram.bytes,
        summary:
            'Created an SVG topology diagram with ${diagram.nodeCount} nodes and ${diagram.edgeCount} links.',
        previewRows: diagram.previewRows,
        metadata: {
          ...diagram.metadata,
          'editableDiagramSourceFormat': 'Mermaid',
          'editableDiagramSourceLineCount': const LineSplitter()
              .convert(diagram.mermaidSource)
              .length,
        },
      );
    }

    if (requestedKind == GeneratedArtifactKind.chart) {
      final chart = chartRenderer.render(document);
      final signalSummary = chart.signals.isEmpty
          ? ''
          : ' covering ${chart.signals.join(', ')}';
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.chart,
        status: GeneratedArtifactStatus.ready,
        extension: 'svg',
        bytes: chart.bytes,
        summary: chart.chartCount == 1
            ? 'Created an SVG chart artifact from the response data.'
            : 'Created an SVG chart pack with ${chart.chartCount} charts$signalSummary.',
        previewRows: chart.previewRows,
        sheetCount: chart.chartCount,
        metadata: chart.metadata,
      );
    }

    if (requestedKind == GeneratedArtifactKind.excel ||
        requestedKind == GeneratedArtifactKind.csv) {
      final lifecycleEox =
          requestedKind == GeneratedArtifactKind.excel &&
          lifecycleEoxBuilder.matches(prompt);
      final productComparison =
          requestedKind == GeneratedArtifactKind.excel &&
          productComparisonBuilder.matches(prompt);
      final sizingWorkbook =
          requestedKind == GeneratedArtifactKind.excel &&
          solutionSizingBuilder.matches(prompt);
      final List<_TableData> tables;
      Map<String, Object?> workbookMetadata = const {};
      if (lifecycleEox) {
        final workbookTables = lifecycleEoxBuilder.build(
          prompt: prompt,
          content: content,
          document: document,
        );
        workbookMetadata = lifecycleEoxBuilder.metadataFor(workbookTables);
        tables = workbookTables
            .map((table) => _TableData(name: table.name, rows: table.rows))
            .toList(growable: false);
      } else if (productComparison) {
        final workbookTables = productComparisonBuilder.build(
          prompt: prompt,
          content: content,
          document: document,
        );
        workbookMetadata = productComparisonBuilder.metadataFor(workbookTables);
        tables = workbookTables
            .map((table) => _TableData(name: table.name, rows: table.rows))
            .toList(growable: false);
      } else if (sizingWorkbook) {
        final workbookTables = solutionSizingBuilder.build(
          prompt: prompt,
          content: content,
          document: document,
        );
        workbookMetadata = solutionSizingBuilder.metadataFor(workbookTables);
        tables = workbookTables
            .map((table) => _TableData(name: table.name, rows: table.rows))
            .toList(growable: false);
      } else {
        tables = _extractTables(content);
      }
      if (tables.isNotEmpty && requestedKind == GeneratedArtifactKind.excel) {
        final workbookTables = tables
            .take(_maximumWorkbookSheets)
            .toList(growable: false);
        final workbook = _xlsxBytes(
          workbookTables,
          template: artifactTemplateRegistry.fromDocument(documentForOutput),
        );
        final workbookInspectionMetadata = await workbookInspector
            .inspectMetadataInWorker(
              workbook,
              cancellationToken: cancellationToken,
            );
        if (workbookInspectionMetadata['workbookStructuralValid'] != true) {
          throw StateError(
            'Generated workbook failed structural inspection: ${workbookInspectionMetadata['workbookInspectionFailedChecks']}',
          );
        }
        final visualPreview = artifactVisualPreviewRenderer.render(
          kind: GeneratedArtifactKind.excel,
          document: documentForOutput,
          previewRows: workbookTables.first.rows,
          unitCount: workbookTables.length,
          workbookSheets: workbookTables
              .map(
                (table) => ArtifactVisualPreviewSheet(
                  name: table.name,
                  rows: table.rows,
                ),
              )
              .toList(growable: false),
        );
        return _ResolvedArtifact(
          kind: GeneratedArtifactKind.excel,
          status: GeneratedArtifactStatus.ready,
          extension: 'xlsx',
          bytes: workbook,
          summary: lifecycleEox
              ? 'Created a Lifecycle / EoX workbook with executive risk, date authority, support runway, migration decision, replacement readiness, customer actions, and source sheets.'
              : productComparison
              ? 'Created a product comparison matrix with executive decision, hard gates, source confidence, migration suitability, lifecycle runway, implementation impact, and source sheets.'
              : sizingWorkbook
              ? 'Created a solution sizing workbook with executive summary, site distribution, PoE/closet power, WAN, licensing, risks, recommendations, validation, and source sheets.'
              : workbookTables.length == 1
              ? 'Created an Excel workbook with formatted headers and frozen first row.'
              : 'Created an Excel workbook with ${workbookTables.length} sheets, formatted headers, and frozen first rows.',
          previewRows: workbookTables.first.rows
              .take(6)
              .toList(growable: false),
          sheetCount: workbookTables.length,
          visualPreviewBytes: visualPreview.bytes,
          visualPreviewExtension: 'svg',
          metadata: {
            ...workbookMetadata,
            ...workbookInspectionMetadata,
            ...visualPreview.metadata,
            'workbookInputSheetCount': tables.length,
            'workbookPackagedSheetCount': workbookTables.length,
            'workbookSheetLimit': _maximumWorkbookSheets,
            'workbookSheetsTruncated': tables.length > workbookTables.length,
            'workbookWrapTextEnabled': true,
            'workbookRowHeightsAdjusted': true,
          },
        );
      }
      if (tables.isNotEmpty) {
        final csv = _tableToCsv(tables.first);
        return _ResolvedArtifact(
          kind: GeneratedArtifactKind.csv,
          status: requestedKind == GeneratedArtifactKind.excel
              ? GeneratedArtifactStatus.fallback
              : GeneratedArtifactStatus.ready,
          extension: 'csv',
          bytes: utf8.encode(csv),
          summary: requestedKind == GeneratedArtifactKind.excel
              ? 'Excel workbook creation was unavailable, so a CSV artifact was created.'
              : 'Created a CSV artifact.',
          previewRows: tables.first.rows.take(6).toList(growable: false),
          sheetCount: 1,
        );
      }
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.markdown,
        status: GeneratedArtifactStatus.fallback,
        extension: 'md',
        bytes: utf8.encode(content.trim()),
        summary:
            'Could not find a clean table, so the response was saved as Markdown.',
      );
    }

    if (requestedKind == GeneratedArtifactKind.json) {
      final lifecycleEvidence = lifecycleEoxBuilder.matches(prompt);
      if (evidencePackBuilder.matches(prompt) || lifecycleEvidence) {
        final evidenceDocument = evidencePackBuilder.build(
          prompt: evidencePackBuilder.matches(prompt)
              ? prompt
              : 'create an evidence pack for lifecycle and EoX recommendations: $prompt',
          content: content,
          document: documentForOutput,
        );
        final jsonText = evidencePackBuilder.toJsonString(evidenceDocument);
        return _ResolvedArtifact(
          kind: GeneratedArtifactKind.json,
          status: GeneratedArtifactStatus.ready,
          extension: 'json',
          bytes: utf8.encode(jsonText),
          summary: lifecycleEvidence
              ? 'Created a structured JSON lifecycle evidence register with sources, assumptions, claims, confidence, and follow-up sections.'
              : 'Created a structured JSON evidence pack with sources, assumptions, claims, confidence, and follow-up sections.',
          previewRows: _jsonPreviewRows(evidenceDocument),
          sheetCount: evidenceDocument.tables.length,
          metadata: {
            ...evidenceDocument.metadata,
            'artifact': lifecycleEvidence
                ? 'lifecycle_evidence_register'
                : 'json_evidence_pack',
            'evidenceRegisterKind': lifecycleEvidence
                ? 'Lifecycle / EoX evidence'
                : 'Evidence pack',
            'sourceCount': evidenceDocument.citations.length,
            'assumptionCount': evidenceDocument.assumptions.length,
            'evidenceSectionCount': evidenceDocument.sections.length,
            'evidenceTableCount': evidenceDocument.tables.length,
            'hasCheckedDateRegister': evidenceDocument.sections.any(
              (section) => section.title.toLowerCase().contains('checked'),
            ),
            'hasClaimDispositionRegister': true,
            'qualityStatus': evidenceDocument.citations.isEmpty
                ? 'Evidence needs sources'
                : 'Evidence register ready',
            'qualityScore': evidenceDocument.citations.isEmpty ? 72 : 92,
            'qualityGates': [
              'Source inventory captured',
              'Claim disposition register included',
              'Checked-date review included',
            ],
            if (evidenceDocument.citations.isEmpty)
              'qualityGaps': [
                'Attach official source URLs or checked-date evidence.',
              ],
            'readinessSignals': [
              'Evidence JSON parseable',
              'Claim/source matrix included',
              if (lifecycleEvidence)
                'Lifecycle recommendation caveats captured',
            ],
          },
        );
      }
      final jsonText = _extractJson(content);
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.json,
        status: jsonText == null
            ? GeneratedArtifactStatus.fallback
            : GeneratedArtifactStatus.ready,
        extension: jsonText == null ? 'md' : 'json',
        bytes: utf8.encode(jsonText ?? content.trim()),
        summary: jsonText == null
            ? 'Could not isolate valid JSON, so the response was saved as Markdown.'
            : 'Created a JSON artifact.',
      );
    }

    if (requestedKind == GeneratedArtifactKind.html) {
      final rendered = htmlRenderer.render(documentForOutput);
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.html,
        status: GeneratedArtifactStatus.ready,
        extension: 'html',
        bytes: rendered.bytes,
        summary:
            'Created a semantic HTML document from the shared artifact composition.',
        previewRows: documentForOutput.previewRows,
        sheetCount: documentForOutput.sections.length,
        metadata: rendered.metadata,
      );
    }

    if (requestedKind == GeneratedArtifactKind.markdown &&
        networkTopologyBuilder.matches(prompt)) {
      final topologyDocument = networkTopologyBuilder.build(
        prompt: prompt,
        content: content,
        document: documentForOutput,
      );
      final diagram = diagramRenderer.render(
        document: topologyDocument,
        content: content,
      );
      final markdown = _topologyMermaidMarkdown(
        document: topologyDocument,
        diagram: diagram,
      );
      return _ResolvedArtifact(
        kind: GeneratedArtifactKind.markdown,
        status: GeneratedArtifactStatus.ready,
        extension: 'md',
        bytes: utf8.encode(markdown),
        summary:
            'Created an editable Mermaid topology source companion with ${diagram.nodeCount} nodes and ${diagram.edgeCount} links.',
        previewRows: [
          const ['Source', 'Value'],
          ['Format', 'Mermaid'],
          ['Nodes', '${diagram.nodeCount}'],
          ['Links', '${diagram.edgeCount}'],
          ['Sections', '${topologyDocument.sections.length}'],
        ],
        sheetCount: diagram.nodeCount,
        metadata: {
          ...topologyDocument.metadata,
          ...diagram.metadata,
          'artifact': 'network_topology_mermaid_source',
          'artifactTemplate': 'network_topology_brief',
          'editableSourceFormat': 'Mermaid',
          'hasEditableDiagramSource': true,
          'editableDiagramSourceLineCount': const LineSplitter()
              .convert(diagram.mermaidSource)
              .length,
          'qualityGates': [
            'Mermaid source generated from topology graph',
            'Rendered SVG companion should match source topology',
            'Review labels and link annotations before handoff',
          ],
          'readinessSignals': [
            'Editable topology source packaged',
            'Topology graph metadata preserved',
          ],
        },
      );
    }

    return _ResolvedArtifact(
      kind: requestedKind,
      status: GeneratedArtifactStatus.ready,
      extension: 'md',
      bytes: utf8.encode(_templatedMarkdown(documentForOutput, content)),
      summary: 'Created a Markdown artifact.',
      metadata: documentForOutput.metadata,
    );
  }

  String _templatedMarkdown(ArtifactDocument document, String content) {
    final template = artifactTemplateRegistry.fromDocument(document);
    final body = content.trim();
    return [
      '<!-- CircuitCode template: ${template.id} v${template.version} -->',
      '',
      '**${template.logoText} · ${template.confidentialityLabel}**',
      '',
      body,
      '',
      '---',
      template.footerText,
    ].join('\n').trim();
  }

  String _topologyMermaidMarkdown({
    required ArtifactDocument document,
    required DiagramRenderResult diagram,
  }) {
    final buffer = StringBuffer()
      ..writeln('# ${document.title} - Editable Topology Source')
      ..writeln()
      ..writeln(
        document.summary.trim().isEmpty
            ? 'Editable Mermaid source generated from the resolved CircuitCode topology graph.'
            : document.summary.trim(),
      )
      ..writeln()
      ..writeln('## Mermaid Source')
      ..writeln()
      ..writeln('```mermaid')
      ..writeln(diagram.mermaidSource)
      ..writeln('```')
      ..writeln()
      ..writeln('## Diagram Metadata')
      ..writeln()
      ..writeln('| Signal | Value |')
      ..writeln('| --- | --- |')
      ..writeln('| Nodes | ${diagram.nodeCount} |')
      ..writeln('| Links | ${diagram.edgeCount} |')
      ..writeln(
        '| Topology type | ${_markdownCell(diagram.metadata['topologyType']?.toString() ?? 'Topology')} |',
      )
      ..writeln(
        '| Readiness | ${_markdownCell(diagram.metadata['topologyReadinessLevel']?.toString() ?? 'Needs review')} |',
      )
      ..writeln(
        '| Editable source | ${diagram.metadata['editableSourceFormat'] ?? 'Mermaid'} |',
      )
      ..writeln()
      ..writeln('## Handoff Checklist')
      ..writeln()
      ..writeln(
        '- Confirm the Mermaid source matches the rendered SVG diagram.',
      )
      ..writeln(
        '- Validate node labels, redundancy, WAN links, and site counts.',
      )
      ..writeln(
        '- Keep this source file with the deck/PDF so the topology can be revised without regenerating from scratch.',
      );
    if (document.assumptions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Assumptions')
        ..writeln();
      for (final assumption in document.assumptions) {
        buffer.writeln('- $assumption');
      }
    }
    return buffer.toString().trimRight();
  }

  String _markdownCell(String value) {
    return value.replaceAll('|', '\\|').replaceAll('\n', ' ').trim();
  }

  List<_TableData> _extractTables(String content) {
    final tables = _markdownTables(content);
    if (tables.isEmpty) return const [];
    final parsed = <_TableData>[];
    for (var i = 0; i < tables.length; i++) {
      final rows = <List<String>>[];
      for (final line in tables[i]) {
        final cells = _tableCells(line);
        if (cells.isEmpty) continue;
        if (cells.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
          continue;
        }
        rows.add(cells);
      }
      if (rows.length >= 2) {
        parsed.add(_TableData(name: 'Sheet ${i + 1}', rows: rows));
      }
    }
    parsed.sort((a, b) => b.rows.length.compareTo(a.rows.length));
    return parsed;
  }

  String _tableToCsv(_TableData table) {
    return table.rows.map((row) => row.map(_csvCell).join(',')).join('\n');
  }

  List<List<String>> _jsonPreviewRows(ArtifactDocument document) {
    final rows = <List<String>>[
      ['Register', 'Count', 'Status'],
      [
        'Sections',
        '${document.sections.length}',
        document.sections.isEmpty ? 'Needs structure' : 'Ready',
      ],
      [
        'Tables',
        '${document.tables.length}',
        document.tables.isEmpty ? 'Needs evidence matrix' : 'Ready',
      ],
      [
        'Sources',
        '${document.citations.length}',
        document.citations.isEmpty ? 'Needs sources' : 'Ready',
      ],
      [
        'Assumptions',
        '${document.assumptions.length}',
        document.assumptions.isEmpty ? 'None captured' : 'Ready',
      ],
    ];
    return rows;
  }

  List<List<String>> _markdownTables(String content) {
    final tables = <List<String>>[];
    var current = <String>[];
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      final looksLikeRow = line.contains('|') && _tableCells(line).length >= 2;
      if (looksLikeRow) {
        current.add(line);
        continue;
      }
      if (current.length >= 2) tables.add(current);
      current = <String>[];
    }
    if (current.length >= 2) tables.add(current);
    return tables;
  }

  List<String> _tableCells(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed
        .split('|')
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty)
        .toList();
  }

  String _csvCell(String value) {
    final normalized = value.replaceAll('\n', ' ').trim();
    final escaped = normalized.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('|')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Uint8List _xlsxBytes(
    List<_TableData> tables, {
    required ArtifactTemplate template,
  }) {
    final workbookTables = tables
        .take(_maximumWorkbookSheets)
        .toList(growable: false);
    final files = <_ZipFileEntry>[
      _ZipFileEntry(
        '[Content_Types].xml',
        _utf8Bytes(_contentTypesXml(workbookTables.length)),
      ),
      _ZipFileEntry('_rels/.rels', _utf8Bytes(_rootRelsXml())),
      _ZipFileEntry('docProps/app.xml', _utf8Bytes(_appXml(template))),
      _ZipFileEntry('docProps/core.xml', _utf8Bytes(_coreXml(template))),
      _ZipFileEntry(
        'xl/workbook.xml',
        _utf8Bytes(_workbookXml(workbookTables)),
      ),
      _ZipFileEntry(
        'xl/_rels/workbook.xml.rels',
        _utf8Bytes(_workbookRelsXml(workbookTables.length)),
      ),
      _ZipFileEntry('xl/styles.xml', _utf8Bytes(_stylesXml(template))),
      for (var i = 0; i < workbookTables.length; i++)
        _ZipFileEntry(
          'xl/worksheets/sheet${i + 1}.xml',
          _utf8Bytes(_worksheetXml(workbookTables[i])),
        ),
    ];
    return _zip(files);
  }

  Uint8List _utf8Bytes(String value) => Uint8List.fromList(utf8.encode(value));

  String _contentTypesXml(int sheetCount) {
    final sheets = List.generate(
      sheetCount,
      (index) =>
          '<Override PartName="/xl/worksheets/sheet${index + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '$sheets</Types>';
  }

  String _rootRelsXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>';
  }

  String _appXml(ArtifactTemplate template) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '<Application>${_xmlText(template.logoText)}</Application>'
        '<Company>${_xmlText(template.organizationName)}</Company>'
        '</Properties>';
  }

  String _coreXml(ArtifactTemplate template) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:creator>CircuitCode</dc:creator>'
        '<cp:lastModifiedBy>CircuitCode</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>'
        '</cp:coreProperties>';
  }

  String _workbookXml(List<_TableData> tables) {
    final sheets = [
      for (var i = 0; i < tables.length; i++)
        '<sheet name="${_xmlAttr(_sheetName(tables[i].name, i))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$sheets</sheets></workbook>';
  }

  String _workbookRelsXml(int sheetCount) {
    final buffer = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    for (var i = 0; i < sheetCount; i++) {
      buffer.write(
        '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
      );
    }
    buffer.write(
      '<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
    buffer.write('</Relationships>');
    return buffer.toString();
  }

  String _stylesXml(ArtifactTemplate template) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="${_xmlAttr(template.fontFamily)}"/></font><font><b/><sz val="11"/><name val="${_xmlAttr(template.fontFamily)}"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF${template.primaryColor}"/><bgColor indexed="64"/></patternFill></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';
  }

  String _worksheetXml(_TableData table) {
    final maxColumns = table.rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    final columns = [
      for (var i = 0; i < maxColumns; i++)
        '<col min="${i + 1}" max="${i + 1}" width="${_columnWidth(table, i).toStringAsFixed(1)}" customWidth="1"/>',
    ].join();
    final rows = <String>[];
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      final cells = <String>[];
      for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
        cells.add(
          _cellXml(
            row[columnIndex],
            rowIndex: rowIndex,
            columnIndex: columnIndex,
            header: rowIndex == 0,
          ),
        );
      }
      final lineCount = _requiredRowLineCount(table, row);
      final height = lineCount > 1
          ? ' ht="${ArtifactWorkbookLayout.emittedRowHeightPoints(lineCount).toStringAsFixed(1)}" customHeight="1"'
          : '';
      rows.add('<row r="${rowIndex + 1}"$height>${cells.join()}</row>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        '<cols>$columns</cols><sheetData>${rows.join()}</sheetData>'
        '<autoFilter ref="A1:${_columnName(maxColumns - 1)}${table.rows.length}"/>'
        '</worksheet>';
  }

  String _cellXml(
    String value, {
    required int rowIndex,
    required int columnIndex,
    required bool header,
  }) {
    final ref = '${_columnName(columnIndex)}${rowIndex + 1}';
    final styleIndex = header
        ? _requiresWrap(value)
              ? 3
              : 1
        : _requiresWrap(value)
        ? 2
        : null;
    final style = styleIndex == null ? '' : ' s="$styleIndex"';
    final numeric = _numericValue(value);
    if (!header && numeric != null) {
      return '<c r="$ref"$style><v>$numeric</v></c>';
    }
    return '<c r="$ref" t="inlineStr"$style><is><t>${_xmlText(value)}</t></is></c>';
  }

  bool _requiresWrap(String value) =>
      ArtifactWorkbookLayout.requiresWrap(value);

  int _requiredRowLineCount(_TableData table, List<String> row) =>
      ArtifactWorkbookLayout.requiredRowLineCount(table.rows, row);

  String? _numericValue(String value) {
    final normalized = value.trim().replaceAll(',', '');
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^-?\d+(\.\d+)?%?$').hasMatch(normalized)) return null;
    if (normalized.endsWith('%')) {
      final parsed = double.tryParse(
        normalized.substring(0, normalized.length - 1),
      );
      if (parsed == null) return null;
      return (parsed / 100).toString();
    }
    return double.tryParse(normalized)?.toString();
  }

  double _columnWidth(_TableData table, int columnIndex) =>
      ArtifactWorkbookLayout.columnWidth(table.rows, columnIndex);

  String _columnName(int zeroBasedIndex) {
    var index = zeroBasedIndex;
    final chars = <String>[];
    do {
      chars.insert(0, String.fromCharCode(65 + (index % 26)));
      index = (index ~/ 26) - 1;
    } while (index >= 0);
    return chars.join();
  }

  String _sheetName(String raw, int index) {
    final sanitized = raw
        .replaceAll(RegExp(r'[\[\]\*:/\\?]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fallback = 'Sheet ${index + 1}';
    final name = sanitized.isEmpty ? fallback : sanitized;
    return name.length > 31 ? name.substring(0, 31) : name;
  }

  String _xmlText(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _xmlAttr(String value) {
    return _xmlText(value).replaceAll('"', '&quot;');
  }

  String? _extractJson(String content) {
    final fenced = RegExp(
      r'```json\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(content);
    final candidate = fenced?.group(1)?.trim() ?? content.trim();
    try {
      final decoded = jsonDecode(candidate);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return null;
    }
  }

  String _safeBaseName(String prompt) {
    final words = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s_-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .take(6)
        .toList();
    final base = words.isEmpty ? 'generated-artifact' : words.join('-');
    return base.length > 48 ? base.substring(0, 48) : base;
  }

  String _versionedBaseName(String baseName, int artifactVersion) {
    final normalizedVersion = artifactVersion < 1 ? 1 : artifactVersion;
    return normalizedVersion == 1 ? baseName : '$baseName-v$normalizedVersion';
  }

  Future<_PersistedArtifactOutput> _persistArtifactOutput({
    required String artifactFilePath,
    required _ResolvedArtifact resolved,
    required ArtifactDocument document,
  }) async {
    // Publish immutable review evidence before the customer file. A failed
    // file commit can leave only an unreferenced sidecar; it can never expose
    // a new artifact that lacks its corresponding review snapshot.
    final visualPreview = await _writeVisualPreview(
      artifactFilePath,
      resolved,
      document: document,
    );
    try {
      await _writeBytesAtomically(File(artifactFilePath), resolved.bytes);
    } catch (_) {
      if (visualPreview.createdByThisWrite &&
          await File(visualPreview.path).exists()) {
        await File(visualPreview.path).delete();
      }
      rethrow;
    }
    return _PersistedArtifactOutput(
      byteSize: resolved.bytes.length,
      visualPreview: visualPreview,
    );
  }

  Future<_PersistedVisualPreview> _writeVisualPreview(
    String artifactFilePath,
    _ResolvedArtifact resolved, {
    required ArtifactDocument document,
  }) async {
    final generatedPreview =
        resolved.visualPreviewBytes == null ||
            resolved.visualPreviewExtension == null ||
            resolved.visualPreviewExtension!.trim().isEmpty
        ? artifactVisualPreviewRenderer.render(
            kind: resolved.kind,
            document: document,
            previewRows: resolved.previewRows,
            unitCount: resolved.sheetCount > 0
                ? resolved.sheetCount
                : document.sections.length,
          )
        : null;
    final bytes = resolved.visualPreviewBytes ?? generatedPreview!.bytes;
    final extension = resolved.visualPreviewExtension ?? 'svg';
    final digest = sha256.convert(bytes).toString();
    // Snapshot paths are content-addressed, so regeneration cannot replace
    // the review evidence recorded for a previous artifact version.
    final preview = File(
      '$artifactFilePath.preview-${digest.substring(0, 16)}.$extension',
    );
    var createdByThisWrite = false;
    if (!await preview.exists()) {
      await _writeBytesAtomically(preview, bytes);
      createdByThisWrite = true;
    }
    return _PersistedVisualPreview(
      path: preview.path,
      extension: extension,
      sha256: digest,
      byteSize: bytes.length,
      createdByThisWrite: createdByThisWrite,
      metadata: generatedPreview?.metadata ?? const {},
    );
  }

  Future<void> _writeBytesAtomically(File target, List<int> bytes) async {
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    final staged = File(
      '${target.path}.staging-${DateTime.now().microsecondsSinceEpoch}-$pid-${_stagedFileSequence++}',
    );
    try {
      await staged.writeAsBytes(bytes, flush: true);
      // Both paths are siblings, so macOS replaces the file in one rename
      // rather than exposing a partial customer artifact or preview.
      await staged.rename(target.path);
    } finally {
      if (await staged.exists()) await staged.delete();
    }
  }

  ArtifactGenerationRecipe _generationRecipe({
    required String prompt,
    required String content,
    required ArtifactTemplate template,
  }) {
    final composition = '$prompt\n\n$content';
    return ArtifactGenerationRecipe(
      prompt: prompt,
      sourceContent: content,
      compositionHash: sha256.convert(utf8.encode(composition)).toString(),
      templateId: template.id,
      templateVersion: template.version,
    );
  }

  int _pdfPageCount(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final count = RegExp(r'/Type /Page\b').allMatches(text).length;
    return count <= 0 ? 1 : count;
  }
}

class _ResolvedArtifact {
  final GeneratedArtifactKind kind;
  final GeneratedArtifactStatus status;
  final String extension;
  final List<int> bytes;
  final String summary;
  final List<List<String>> previewRows;
  final int sheetCount;
  final Map<String, Object?> metadata;
  final List<int>? visualPreviewBytes;
  final String? visualPreviewExtension;

  const _ResolvedArtifact({
    required this.kind,
    required this.status,
    required this.extension,
    required this.bytes,
    required this.summary,
    this.previewRows = const [],
    this.sheetCount = 0,
    this.metadata = const {},
    this.visualPreviewBytes,
    this.visualPreviewExtension,
  });
}

class _PersistedVisualPreview {
  final String path;
  final String extension;
  final String sha256;
  final int byteSize;
  final bool createdByThisWrite;
  final Map<String, Object?> metadata;

  const _PersistedVisualPreview({
    required this.path,
    required this.extension,
    required this.sha256,
    required this.byteSize,
    required this.createdByThisWrite,
    this.metadata = const {},
  });
}

class _PersistedArtifactOutput {
  final int byteSize;
  final _PersistedVisualPreview visualPreview;

  const _PersistedArtifactOutput({
    required this.byteSize,
    required this.visualPreview,
  });
}

class _TableData {
  final String name;
  final List<List<String>> rows;

  const _TableData({required this.name, required this.rows});
}

class _ZipFileEntry {
  final String path;
  final Uint8List bytes;

  const _ZipFileEntry(this.path, this.bytes);
}

Uint8List _zip(List<_ZipFileEntry> files) {
  final output = BytesBuilder(copy: false);
  final centralDirectory = BytesBuilder(copy: false);
  var offset = 0;

  for (final file in files) {
    final nameBytes = utf8.encode(file.path);
    final crc = _crc32(file.bytes);
    final local = BytesBuilder(copy: false)
      ..add(_uint32(0x04034b50))
      ..add(_uint16(20))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(crc))
      ..add(_uint32(file.bytes.length))
      ..add(_uint32(file.bytes.length))
      ..add(_uint16(nameBytes.length))
      ..add(_uint16(0))
      ..add(nameBytes);
    final localBytes = local.toBytes();
    output
      ..add(localBytes)
      ..add(file.bytes);

    centralDirectory
      ..add(_uint32(0x02014b50))
      ..add(_uint16(20))
      ..add(_uint16(20))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(crc))
      ..add(_uint32(file.bytes.length))
      ..add(_uint32(file.bytes.length))
      ..add(_uint16(nameBytes.length))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint16(0))
      ..add(_uint32(0))
      ..add(_uint32(offset))
      ..add(nameBytes);
    offset += localBytes.length + file.bytes.length;
  }

  final centralBytes = centralDirectory.toBytes();
  output
    ..add(centralBytes)
    ..add(_uint32(0x06054b50))
    ..add(_uint16(0))
    ..add(_uint16(0))
    ..add(_uint16(files.length))
    ..add(_uint16(files.length))
    ..add(_uint32(centralBytes.length))
    ..add(_uint32(offset))
    ..add(_uint16(0));
  return output.toBytes();
}

List<int> _uint16(int value) => [value & 0xff, (value >> 8) & 0xff];

List<int> _uint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) == 1) {
        crc = (crc >> 1) ^ 0xedb88320;
      } else {
        crc >>= 1;
      }
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

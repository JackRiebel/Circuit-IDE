import 'artifact_document.dart';

/// A durable visual contract for every generated artifact format. The logo is
/// intentionally a text mark for the first-party renderers: no untrusted
/// external asset is fetched while creating a customer deliverable.
class ArtifactTemplate {
  final String id;
  final String version;
  final String label;
  final String description;
  final String organizationName;
  final String logoText;
  final String primaryColor;
  final String accentColor;
  final String fontFamily;
  final String footerText;
  final String confidentialityLabel;
  final String layout;

  const ArtifactTemplate({
    required this.id,
    required this.version,
    required this.label,
    required this.description,
    required this.organizationName,
    required this.logoText,
    required this.primaryColor,
    required this.accentColor,
    required this.fontFamily,
    required this.footerText,
    required this.confidentialityLabel,
    required this.layout,
  });

  ArtifactDocument apply(ArtifactDocument document) {
    return document.copyWith(
      metadata: {
        ...document.metadata,
        'artifactBrandTemplate': toMetadata(),
        // Preserve legacy deck theme selection for the standard template.
        if (id != ArtifactTemplateRegistry.standard.id)
          'theme': layout == 'executive-light' ? 'light' : 'dark',
      },
    );
  }

  Map<String, Object?> toMetadata() => {
    'id': id,
    'version': version,
    'label': label,
    'organizationName': organizationName,
    'logoText': logoText,
    'primaryColor': primaryColor,
    'accentColor': accentColor,
    'fontFamily': fontFamily,
    'footerText': footerText,
    'confidentialityLabel': confidentialityLabel,
    'layout': layout,
  };

  static ArtifactTemplate? fromMetadata(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    final version = value['version']?.toString().trim() ?? '';
    final label = value['label']?.toString().trim() ?? '';
    final organizationName = value['organizationName']?.toString().trim() ?? '';
    final logoText = value['logoText']?.toString().trim() ?? '';
    final primaryColor = _hexColor(value['primaryColor']);
    final accentColor = _hexColor(value['accentColor']);
    final fontFamily = value['fontFamily']?.toString().trim() ?? '';
    final footerText = value['footerText']?.toString().trim() ?? '';
    final confidentialityLabel =
        value['confidentialityLabel']?.toString().trim() ?? '';
    final layout = value['layout']?.toString().trim() ?? '';
    if (id.isEmpty ||
        version.isEmpty ||
        label.isEmpty ||
        organizationName.isEmpty ||
        logoText.isEmpty ||
        primaryColor == null ||
        accentColor == null ||
        fontFamily.isEmpty ||
        footerText.isEmpty ||
        confidentialityLabel.isEmpty ||
        layout.isEmpty) {
      return null;
    }
    return ArtifactTemplate(
      id: id,
      version: version,
      label: label,
      description: value['description']?.toString().trim() ?? label,
      organizationName: organizationName,
      logoText: logoText,
      primaryColor: primaryColor,
      accentColor: accentColor,
      fontFamily: fontFamily,
      footerText: footerText,
      confidentialityLabel: confidentialityLabel,
      layout: layout,
    );
  }

  static String? _hexColor(Object? value) {
    final normalized = value?.toString().trim().replaceFirst('#', '') ?? '';
    return RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)
        ? normalized.toUpperCase()
        : null;
  }
}

class ArtifactTemplateRegistry {
  static const standard = ArtifactTemplate(
    id: 'circuit-standard',
    version: '1.0',
    label: 'Circuit standard',
    description:
        'Calm, neutral delivery format for internal and customer work.',
    organizationName: 'CircuitCode',
    logoText: 'CircuitCode',
    primaryColor: '172033',
    accentColor: '3B82F6',
    fontFamily: 'Aptos',
    footerText: 'CircuitCode - Generated artifact',
    confidentialityLabel: 'INTERNAL',
    layout: 'executive-dark',
  );

  static const customerBriefing = ArtifactTemplate(
    id: 'customer-briefing',
    version: '1.0',
    label: 'Customer briefing',
    description: 'A light executive layout for a polished customer readout.',
    organizationName: 'Customer briefing',
    logoText: 'CUSTOMER BRIEFING',
    primaryColor: '0F3D56',
    accentColor: '0E7490',
    fontFamily: 'Aptos Display',
    footerText: 'Customer briefing · Prepared by CircuitCode',
    confidentialityLabel: 'CONFIDENTIAL',
    layout: 'executive-light',
  );

  static const executiveReview = ArtifactTemplate(
    id: 'executive-review',
    version: '1.0',
    label: 'Executive review',
    description:
        'A high-contrast dark layout for decision, risk, and review packs.',
    organizationName: 'Executive review',
    logoText: 'EXECUTIVE REVIEW',
    primaryColor: '111827',
    accentColor: 'C78A3B',
    fontFamily: 'Aptos Display',
    footerText: 'Executive review · Decision material',
    confidentialityLabel: 'RESTRICTED',
    layout: 'executive-dark',
  );

  const ArtifactTemplateRegistry();

  List<ArtifactTemplate> get templates => const [
    standard,
    customerBriefing,
    executiveReview,
  ];

  ArtifactTemplate resolve(String? id) {
    final normalized = id?.trim().toLowerCase();
    return templates.firstWhere(
      (template) => template.id == normalized,
      orElse: () => standard,
    );
  }

  ArtifactTemplate fromDocument(ArtifactDocument document) {
    return ArtifactTemplate.fromMetadata(
          document.metadata['artifactBrandTemplate'],
        ) ??
        standard;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/design_tokens.dart';
import '../../models/artifact_template.dart';
import 'studio_motion.dart';

/// A deliberate selection point before producing a new immutable artifact
/// version. The miniature document preview exposes visual decisions without
/// asking users to infer a template from an opaque name.
Future<ArtifactTemplate?> showArtifactTemplateSelector(
  BuildContext context, {
  required String selectedTemplateId,
}) {
  return showDialog<ArtifactTemplate>(
    context: context,
    builder: (_) =>
        _ArtifactTemplateSelectorDialog(selectedTemplateId: selectedTemplateId),
  );
}

class _ArtifactTemplateSelectorDialog extends StatefulWidget {
  final String selectedTemplateId;

  const _ArtifactTemplateSelectorDialog({required this.selectedTemplateId});

  @override
  State<_ArtifactTemplateSelectorDialog> createState() =>
      _ArtifactTemplateSelectorDialogState();
}

class _ArtifactTemplateSelectorDialogState
    extends State<_ArtifactTemplateSelectorDialog> {
  final _registry = const ArtifactTemplateRegistry();
  late String _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _selectedTemplateId = _registry.resolve(widget.selectedTemplateId).id;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _registry.resolve(_selectedTemplateId);
    return AlertDialog(
      title: const Text('Choose artifact template'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choosing a template creates a new artifact version. The same logo mark, colors, typeface, footer, confidentiality label, and layout are retained when you export another supported format.',
              ),
              const SizedBox(height: 16),
              for (final template in _registry.templates) ...[
                _TemplatePreviewCard(
                  template: template,
                  selected: template.id == _selectedTemplateId,
                  onTap: () =>
                      setState(() => _selectedTemplateId = template.id),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              Text(
                '${selected.label}: ${selected.description}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(selected),
          child: const Text('Create styled version'),
        ),
      ],
    );
  }
}

class _TemplatePreviewCard extends StatefulWidget {
  final ArtifactTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const _TemplatePreviewCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_TemplatePreviewCard> createState() => _TemplatePreviewCardState();
}

class _TemplatePreviewCardState extends State<_TemplatePreviewCard> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'artifact-template-${widget.template.id}',
    )..addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _activate() {
    _focusNode.requestFocus();
    widget.onTap();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    _activate();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final primary = _color(template.primaryColor);
    final accent = _color(template.accentColor);
    final isDark = template.layout == 'executive-dark';
    final canvas = isDark ? const Color(0xFF15181F) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF172033);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${template.label} template',
      onTap: _activate,
      child: ExcludeSemantics(
        child: Focus(
          key: ValueKey('artifact-template-card-${template.id}'),
          focusNode: _focusNode,
          onKeyEvent: _handleKey,
          child: InkWell(
            canRequestFocus: false,
            onTap: _activate,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: studioMotionDuration(
                context,
                const Duration(milliseconds: 150),
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? Theme.of(context).colorScheme.primary
                      : widget.selected
                      ? accent
                      : primary.withValues(alpha: 0.25),
                  width: _focusNode.hasFocus
                      ? 1.5
                      : widget.selected
                      ? 2
                      : 1,
                ),
              ),
              child: _PreviewContents(
                template: template,
                text: text,
                primary: primary,
                accent: accent,
                isDark: isDark,
                selected: widget.selected,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _color(String hex) {
    final value = int.tryParse(hex, radix: 16) ?? 0;
    return Color(0xff000000 | value);
  }
}

class _PreviewContents extends StatelessWidget {
  final ArtifactTemplate template;
  final Color text;
  final Color primary;
  final Color accent;
  final bool isDark;
  final bool selected;

  const _PreviewContents({
    required this.template,
    required this.text,
    required this.primary,
    required this.accent,
    required this.isDark,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                template.label,
                style: TextStyle(color: text, fontWeight: FontWeight.w700),
              ),
            ),
            if (selected) Icon(StudioIcons.checkCircle, color: accent),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 4, color: primary),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              template.logoText,
              style: TextStyle(
                color: primary,
                fontFamily: template.fontFamily,
                fontSize: FontSizes.xs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const Spacer(),
            Text(
              template.confidentialityLabel,
              style: TextStyle(
                color: accent,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 9,
          width: 260,
          color: text.withValues(alpha: isDark ? 0.24 : 0.12),
        ),
        const SizedBox(height: 5),
        Container(
          height: 7,
          width: 190,
          color: text.withValues(alpha: isDark ? 0.16 : 0.08),
        ),
        const SizedBox(height: 14),
        Text(
          template.footerText,
          style: TextStyle(
            color: text.withValues(alpha: 0.64),
            fontSize: FontSizes.xxs,
          ),
        ),
      ],
    );
  }
}

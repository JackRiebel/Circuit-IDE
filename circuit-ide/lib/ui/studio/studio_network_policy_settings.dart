import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../models/agent_workspace.dart';
import '../../state/agent_workspace_provider.dart';
import '../../state/file_tree_provider.dart';
import '../../state/theme_provider.dart';
import 'studio_chrome.dart';

/// Project-scoped network rules. The default is intentionally deny: a user
/// must make each public domain visible here before a Studio tool can reach it.
class ProjectNetworkPolicyPanel extends ConsumerWidget {
  const ProjectNetworkPolicyPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(
      fileTreeProvider.select((state) => state.rootPath),
    );
    final policy = ref.watch(
      agentWorkspaceProvider.select((state) => state.projectPolicy),
    );
    if (rootPath == null || rootPath.trim().isEmpty) {
      return const _NetworkPolicyMessage(
        message: 'Open a project folder to manage its network boundary.',
      );
    }
    final projectName = p.basename(rootPath);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network access for $projectName',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: FontSizes.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Unlisted domains are blocked. Localhost, private networks, metadata services, uploads, redirects, and credentials stay blocked unless an explicit public-domain rule permits the operation.',
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: FontSizes.xs,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            OutlinedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _ProjectNetworkPolicyDialog(
                  projectName: projectName,
                  policy: policy,
                ),
              ),
              child: const Text('Configure'),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        if (policy.networkRules.isEmpty)
          const _NetworkPolicyMessage(
            message: 'No public domains are approved for this project.',
          )
        else
          ...policy.networkRules.map((rule) => _NetworkRuleSummary(rule: rule)),
      ],
    );
  }
}

class _NetworkPolicyMessage extends ConsumerWidget {
  final String message;

  const _NetworkPolicyMessage({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceHover,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: tokens.textMuted, fontSize: FontSizes.xs),
      ),
    );
  }
}

class _NetworkRuleSummary extends ConsumerWidget {
  final WorkspaceNetworkRule rule;

  const _NetworkRuleSummary({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final operationDetails = [
      rule.methods.join(', '),
      if (rule.allowUpload) 'uploads',
      if (rule.allowRedirects) 'redirects',
      if (rule.allowCredentials) 'credentials',
    ].join(' · ');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.outlineSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.domain,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: FontSizes.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  operationDetails,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: FontSizes.xs,
                  ),
                ),
              ],
            ),
          ),
          StudioMiniChip(label: _dispositionLabel(rule.disposition)),
        ],
      ),
    );
  }
}

class _ProjectNetworkPolicyDialog extends ConsumerStatefulWidget {
  final String projectName;
  final WorkspacePermissionConfiguration policy;

  const _ProjectNetworkPolicyDialog({
    required this.projectName,
    required this.policy,
  });

  @override
  ConsumerState<_ProjectNetworkPolicyDialog> createState() =>
      _ProjectNetworkPolicyDialogState();
}

class _ProjectNetworkPolicyDialogState
    extends ConsumerState<_ProjectNetworkPolicyDialog> {
  final _domainController = TextEditingController();
  late List<WorkspaceNetworkRule> _rules;
  WorkspaceNetworkRuleDisposition _disposition =
      WorkspaceNetworkRuleDisposition.allow;
  final Set<String> _methods = {'GET'};
  bool _allowUploads = false;
  bool _allowRedirects = false;
  bool _allowCredentials = false;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rules = [...widget.policy.networkRules];
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  void _addRule() {
    final domain = WorkspaceNetworkRule.normalizePublicDomain(
      _domainController.text,
    );
    if (domain == null) {
      setState(() {
        _error =
            'Enter a public domain such as api.example.com or *.example.com. URLs, IP addresses, localhost, and private names are not allowed.';
      });
      return;
    }
    if (_methods.isEmpty) {
      setState(() => _error = 'Select at least one HTTP method.');
      return;
    }
    final rule = WorkspaceNetworkRule(
      domain: domain,
      disposition: _disposition,
      methods: _methods.toList()..sort(),
      allowUpload: _allowUploads,
      allowRedirects: _allowRedirects,
      allowCredentials: _allowCredentials,
    );
    setState(() {
      _rules = [
        rule,
        ..._rules.where((candidate) => candidate.domain != domain),
      ];
      _domainController.clear();
      _disposition = WorkspaceNetworkRuleDisposition.allow;
      _methods
        ..clear()
        ..add('GET');
      _allowUploads = false;
      _allowRedirects = false;
      _allowCredentials = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final policy = widget.policy.copyWith(
      externalNetwork: WorkspacePermissionDisposition.block,
      networkRules: List.unmodifiable(_rules),
    );
    await ref
        .read(agentWorkspaceProvider.notifier)
        .setProjectNetworkPolicy(policy);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Network rules · ${widget.projectName}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Network is blocked by default. Add a public domain rule only when this project needs it. A rule applies to existing and future tasks in this project.',
              ),
              const SizedBox(height: Spacing.lg),
              TextField(
                controller: _domainController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Public domain',
                  hintText: 'api.example.com or *.example.com',
                ),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<WorkspaceNetworkRuleDisposition>(
                initialValue: _disposition,
                decoration: const InputDecoration(labelText: 'Rule action'),
                items: WorkspaceNetworkRuleDisposition.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_dispositionLabel(value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _disposition = value);
                },
              ),
              const SizedBox(height: Spacing.md),
              const Text('Allowed methods'),
              Wrap(
                spacing: Spacing.sm,
                children:
                    const ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE']
                        .map((method) => _NetworkMethodChip(method: method))
                        .toList(growable: false),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow uploads'),
                subtitle: const Text(
                  'Permit request bodies that may contain workspace data.',
                ),
                value: _allowUploads,
                onChanged: (value) => setState(() => _allowUploads = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow redirects'),
                subtitle: const Text(
                  'Every redirected target still needs to pass policy checks.',
                ),
                value: _allowRedirects,
                onChanged: (value) => setState(() => _allowRedirects = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow credentials'),
                subtitle: const Text(
                  'Permit authenticated requests only for this domain rule.',
                ),
                value: _allowCredentials,
                onChanged: (value) => setState(() => _allowCredentials = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _addRule,
                  icon: const Icon(StudioIcons.add),
                  label: const Text('Add rule'),
                ),
              ),
              const Divider(),
              if (_rules.isEmpty)
                const Text('No domain rules yet.')
              else
                ..._rules.map(
                  (rule) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(rule.domain),
                    subtitle: Text(
                      '${_dispositionLabel(rule.disposition)} · ${rule.methods.join(', ')}${rule.allowUpload ? ' · uploads' : ''}${rule.allowRedirects ? ' · redirects' : ''}${rule.allowCredentials ? ' · credentials' : ''}',
                    ),
                    trailing: StudioChromeIconButton(
                      tooltip: 'Remove ${rule.domain}',
                      onTap: () => setState(
                        () => _rules.removeWhere(
                          (candidate) => candidate.domain == rule.domain,
                        ),
                      ),
                      icon: StudioIcons.deleteOutline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save rules'),
        ),
      ],
    );
  }
}

class _NetworkMethodChip extends StatefulWidget {
  final String method;

  const _NetworkMethodChip({required this.method});

  @override
  State<_NetworkMethodChip> createState() => _NetworkMethodChipState();
}

class _NetworkMethodChipState extends State<_NetworkMethodChip> {
  @override
  Widget build(BuildContext context) {
    final owner = context
        .findAncestorStateOfType<_ProjectNetworkPolicyDialogState>();
    final selected = owner?._methods.contains(widget.method) ?? false;
    return FilterChip(
      label: Text(widget.method),
      selected: selected,
      onSelected: (value) {
        owner?.setState(() {
          if (value) {
            owner._methods.add(widget.method);
          } else {
            owner._methods.remove(widget.method);
          }
        });
      },
    );
  }
}

String _dispositionLabel(WorkspaceNetworkRuleDisposition disposition) {
  return switch (disposition) {
    WorkspaceNetworkRuleDisposition.allow => 'Allow',
    WorkspaceNetworkRuleDisposition.ask => 'Require review',
    WorkspaceNetworkRuleDisposition.deny => 'Block',
  };
}

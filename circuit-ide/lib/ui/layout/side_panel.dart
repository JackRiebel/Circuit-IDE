import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import 'activity_bar.dart';
import '../agents/agent_manager_panel.dart';
import '../checkpoints/checkpoint_panel.dart';
import '../codebase_map/codebase_map_panel.dart';
import '../file_explorer/file_explorer.dart';
import '../memories/memories_panel.dart';
import '../notebook/notebook_panel.dart';
import '../rules/rules_panel.dart';
import '../search/search_panel.dart';
import '../git/git_panel.dart';
import '../mcp/mcp_hub_panel.dart';
import '../security/security_scan_panel.dart';
import '../testing/test_generation_panel.dart';
import '../vericoding/vericoding_panel.dart';

class SidePanel extends ConsumerWidget {
  const SidePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final activeItem = ref.watch(activeActivityItemProvider);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgMain,
        border: Border(
          right: BorderSide(
            color: tokens.border.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Container(
            height: LayoutDimensions.tabBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: tokens.border.withValues(alpha: 0.3),
                ),
              ),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              activeItem.tooltip.toUpperCase(),
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: FontSizes.xxs,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Panel content
          Expanded(
            child: switch (activeItem) {
              ActivityBarItem.explorer => const FileExplorer(),
              ActivityBarItem.search => const SearchPanel(),
              ActivityBarItem.git => const GitPanel(),
              ActivityBarItem.codebaseMap => const CodebaseMapPanel(),
              ActivityBarItem.notebook => const NotebookPanel(),
              ActivityBarItem.testing => const TestGenerationPanel(),
              ActivityBarItem.security => const SecurityScanPanel(),
              ActivityBarItem.mcp => const McpHubPanel(),
              ActivityBarItem.vericoding => const VericodingPanel(),
              ActivityBarItem.memories => const MemoriesPanel(),
              ActivityBarItem.checkpoints => const CheckpointPanel(),
              ActivityBarItem.rules => const RulesPanel(),
              ActivityBarItem.agents => const AgentManagerPanel(),
            },
          ),
        ],
      ),
    );
  }
}

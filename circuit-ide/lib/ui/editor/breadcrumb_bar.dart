import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';
import '../../state/file_tree_provider.dart';

class BreadcrumbBar extends ConsumerWidget {
  final String filePath;

  const BreadcrumbBar({super.key, required this.filePath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);
    final rootPath = ref.watch(fileTreeProvider).rootPath ?? '';
    final relativePath = rootPath.isNotEmpty
        ? p.relative(filePath, from: rootPath)
        : filePath;
    final parts = relativePath.split(p.separator);

    return Container(
      height: LayoutDimensions.breadcrumbHeight,
      color: tokens.editorBg,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Row(
        children: [
          for (int i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 12,
                  color: tokens.textMuted.withValues(alpha: 0.5),
                ),
              ),
            Text(
              parts[i],
              style: TextStyle(
                color: i == parts.length - 1
                    ? tokens.textPrimary
                    : tokens.textMuted,
                fontSize: FontSizes.xxs,
                fontWeight: i == parts.length - 1
                    ? FontWeight.w500
                    : FontWeight.w400,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

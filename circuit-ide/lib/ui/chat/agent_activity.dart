import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/design_tokens.dart';
import '../../state/theme_provider.dart';

enum FileEditStatus { pending, editing, done, error }

class FileActivity {
  final String filePath;
  final FileEditStatus status;
  final String? description;

  const FileActivity({
    required this.filePath,
    required this.status,
    this.description,
  });
}

class AgentActivityWidget extends ConsumerWidget {
  final List<FileActivity> files;
  final VoidCallback? onCancel;

  const AgentActivityWidget({
    super.key,
    required this.files,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeProvider);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.bgLighter,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Agent Working',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: FontSizes.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (onCancel != null)
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.error,
                    textStyle: const TextStyle(fontSize: FontSizes.xs),
                  ),
                  child: const Text('Cancel'),
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          ...files.map((file) {
            final statusIcon = switch (file.status) {
              FileEditStatus.pending => Icons.schedule,
              FileEditStatus.editing => Icons.edit,
              FileEditStatus.done => Icons.check_circle,
              FileEditStatus.error => Icons.error,
            };
            final statusColor = switch (file.status) {
              FileEditStatus.pending => tokens.textMuted,
              FileEditStatus.editing => tokens.warning,
              FileEditStatus.done => tokens.success,
              FileEditStatus.error => tokens.error,
            };

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  file.status == FileEditStatus.editing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          ),
                        )
                      : Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.filePath.split('/').last,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: FontSizes.xs,
                      ),
                    ),
                  ),
                  if (file.description != null)
                    Text(
                      file.description!,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

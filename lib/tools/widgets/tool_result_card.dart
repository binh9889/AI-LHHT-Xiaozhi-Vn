import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ai_assistant/tools/models/tool_models.dart';

class ToolResultCard extends StatelessWidget {
  const ToolResultCard({
    super.key,
    required this.result,
    this.onSpeak,
    this.onRefresh,
  });

  final ToolResult result;
  final VoidCallback? onSpeak;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: result.success
                      ? colors.primaryContainer
                      : colors.errorContainer,
                  child: Icon(
                    result.success ? Icons.bolt_rounded : Icons.error_outline_rounded,
                    color: result.success
                        ? colors.onPrimaryContainer
                        : colors.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.summary,
                        style: TextStyle(color: colors.onSurfaceVariant, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (result.details.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              ...result.details.entries.take(10).map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              entry.key,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 6,
                            child: Text(
                              entry.value,
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FreshnessChip(result: result),
                Chip(
                  avatar: const Icon(Icons.schedule_rounded, size: 16),
                  label: Text(DateFormat('HH:mm dd/MM').format(result.timestamp)),
                  visualDensity: VisualDensity.compact,
                ),
                if (result.source.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.source_rounded, size: 16),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(result.source, overflow: TextOverflow.ellipsis),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (onSpeak != null || onRefresh != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onSpeak != null)
                    TextButton.icon(
                      onPressed: onSpeak,
                      icon: const Icon(Icons.volume_up_rounded),
                      label: const Text('Đọc kết quả'),
                    ),
                  const Spacer(),
                  if (onRefresh != null)
                    IconButton(
                      tooltip: 'Làm mới',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({required this.result});
  final ToolResult result;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (result.freshness) {
      ToolResultFreshness.live => ('Vừa cập nhật', Icons.circle),
      ToolResultFreshness.recent => ('Dữ liệu gần nhất', Icons.history_rounded),
      ToolResultFreshness.cached => ('Cache', Icons.cached_rounded),
      ToolResultFreshness.staticData => ('Dữ liệu cục bộ', Icons.offline_bolt_rounded),
    };
    return Chip(
      avatar: Icon(icon, size: 14),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

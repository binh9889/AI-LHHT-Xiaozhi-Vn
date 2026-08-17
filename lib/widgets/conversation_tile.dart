import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/providers/config_provider.dart';

class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ConversationTile({
    super.key,
    required this.conversation,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _avatar(context),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(conversation.lastMessageTime),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Flexible(child: _typeChip(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            conversation.lastMessage.isEmpty
                                ? 'Chưa có tin nhắn'
                                : conversation.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final color = switch (conversation.type) {
      ConversationType.dify => Colors.blue,
      ConversationType.minimax => Colors.teal,
      ConversationType.xiaozhi => Colors.deepPurple,
    };
    final icon = switch (conversation.type) {
      ConversationType.dify => Icons.chat_bubble_outline_rounded,
      ConversationType.minimax => Icons.auto_awesome_rounded,
      ConversationType.xiaozhi => Icons.mic_rounded,
    };
    return CircleAvatar(
      radius: 24,
      backgroundColor: color.withOpacity(.12),
      child: Icon(icon, color: color),
    );
  }

  Widget _typeChip(BuildContext context) {
    final provider = Provider.of<ConfigProvider>(context, listen: false);
    var label = switch (conversation.type) {
      ConversationType.dify => 'Dify',
      ConversationType.minimax => 'MiniMax',
      ConversationType.xiaozhi => 'Xiaozhi',
    };

    if (conversation.configId.isNotEmpty) {
      if (conversation.type == ConversationType.dify) {
        for (final item in provider.difyConfigs) {
          if (item.id == conversation.configId) label = item.name;
        }
      } else if (conversation.type == ConversationType.minimax) {
        for (final item in provider.minimaxConfigs) {
          if (item.id == conversation.configId) label = item.name;
        }
      } else {
        for (final item in provider.xiaozhiConfigs) {
          if (item.id == conversation.configId) label = item.name;
        }
      }
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final delta = startToday.difference(day).inDays;
    if (delta == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    if (delta == 1) return 'Hôm qua';
    if (delta < 7) {
      const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      return days[dateTime.weekday - 1];
    }
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}';
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_assistant/models/conversation.dart';
import 'package:ai_assistant/providers/conversation_provider.dart';
import 'package:ai_assistant/screens/chat_screen.dart';
import 'package:ai_assistant/screens/conversation_type_screen.dart';
import 'package:ai_assistant/screens/settings_screen.dart';
import 'package:ai_assistant/widgets/conversation_tile.dart';
import 'package:ai_assistant/widgets/discovery_screen.dart';
import 'package:ai_assistant/widgets/slidable_delete_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _index == 0
          ? AppBar(
              title: const Text('Tin nhắn'),
              actions: [
                IconButton(
                  tooltip: 'Cài đặt',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            )
          : null,
      body: _index == 0 ? _messagesTab() : const DiscoveryScreen(),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConversationTypeScreen()),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Cuộc trò chuyện'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Tin nhắn',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Khám phá',
          ),
        ],
      ),
    );
  }

  Widget _messagesTab() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _searchController,
              leading: const Icon(Icons.search_rounded),
              hintText: 'Tìm cuộc trò chuyện',
              trailing: _query.isEmpty
                  ? null
                  : [
                      IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
              onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: Consumer<ConversationProvider>(
              builder: (context, provider, _) {
                final filtered = provider.conversations.where((item) {
                  if (_query.isEmpty) return true;
                  return item.title.toLowerCase().contains(_query) ||
                      item.lastMessage.toLowerCase().contains(_query);
                }).toList()
                  ..sort((a, b) {
                    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
                    return b.lastMessageTime.compareTo(a.lastMessageTime);
                  });

                if (filtered.isEmpty) return _emptyState(provider.conversations.isEmpty);

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 110),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _conversationItem(filtered[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool trulyEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                trulyEmpty ? Icons.chat_bubble_outline_rounded : Icons.search_off_rounded,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              trulyEmpty ? 'Chưa có cuộc trò chuyện' : 'Không tìm thấy kết quả',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              trulyEmpty
                  ? 'Tạo cuộc trò chuyện với Xiaozhi, Dify hoặc MiniMax.'
                  : 'Thử một từ khóa khác.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationItem(Conversation conversation) {
    return SlidableDeleteTile(
      key: ValueKey(conversation.id),
      onDelete: () {
        context.read<ConversationProvider>().deleteConversation(conversation.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa ${conversation.title}'),
            action: SnackBarAction(
              label: 'Hoàn tác',
              onPressed: () => context.read<ConversationProvider>().restoreLastDeletedConversation(),
            ),
          ),
        );
      },
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: conversation)),
      ),
      onLongPress: () => _showOptions(conversation),
      child: ConversationTile(conversation: conversation),
    );
  }

  void _showOptions(Conversation conversation) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(conversation.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(conversation.isPinned ? 'Bỏ ghim' : 'Ghim cuộc trò chuyện'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.read<ConversationProvider>().togglePinConversation(conversation.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('Xóa', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                context.read<ConversationProvider>().deleteConversation(conversation.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/screens/tool_detail_screen.dart';
import 'package:ai_assistant/screens/tool_provider_settings_screen.dart';
import 'package:ai_assistant/tools/models/tool_models.dart';
import 'package:ai_assistant/tools/services/realtime_tool_engine.dart';
import 'package:ai_assistant/tools/services/tool_intent_router.dart';
import 'package:ai_assistant/tools/tool_registry.dart';

class RealtimeToolsScreen extends StatefulWidget {
  const RealtimeToolsScreen({super.key});

  @override
  State<RealtimeToolsScreen> createState() => _RealtimeToolsScreenState();
}

class _RealtimeToolsScreenState extends State<RealtimeToolsScreen> {
  final TextEditingController _search = TextEditingController();
  final RealtimeToolEngine _engine = RealtimeToolEngine();
  ToolCategory? _category;
  Set<String> _favorites = <String>{};
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadLocalState();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('v4_tool_favorites') ?? <String>[];
    final history = await _engine.history();
    if (!mounted) return;
    setState(() {
      _favorites = favorites.toSet();
      _history = history.take(6).toList();
    });
  }

  Future<void> _toggleFavorite(String id) async {
    final next = Set<String>.from(_favorites);
    if (!next.add(id)) next.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('v4_tool_favorites', next.toList()..sort());
    if (mounted) setState(() => _favorites = next);
  }

  List<ToolDefinition> get _visibleTools {
    final searched = ToolIntentRouter.searchDefinitions(_search.text);
    return searched.where((tool) => _category == null || tool.category == _category).toList();
  }

  void _open(ToolDefinition tool, {String? query}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ToolDetailScreen(tool: tool, initialQuery: query)),
    );
    _loadLocalState();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 4 : width >= 720 ? 3 : 2;
    final theme = Theme.of(context);
    final favoriteTools = ToolRegistry.all.where((tool) => _favorites.contains(tool.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime & Tra cứu'),
        actions: [
          IconButton(
            tooltip: 'Nguồn dữ liệu',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ToolProviderSettingsScreen()),
            ),
            icon: const Icon(Icons.hub_outlined),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bộ công cụ realtime & tra cứu',
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '21 công cụ trong một router: nói hoặc nhập yêu cầu, app chọn đúng nguồn trước khi gọi Agent.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  SearchBar(
                    controller: _search,
                    hintText: 'Tìm công cụ hoặc nhập từ khóa…',
                    leading: const Icon(Icons.search_rounded),
                    trailing: _search.text.isEmpty
                        ? null
                        : [
                            IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Tất cả'),
                          selected: _category == null,
                          onSelected: (_) => setState(() => _category = null),
                        ),
                        const SizedBox(width: 8),
                        ...ToolCategory.values.expand((category) sync* {
                          yield ChoiceChip(
                            label: Text(category.label),
                            selected: _category == category,
                            onSelected: (_) => setState(() => _category = category),
                          );
                          yield const SizedBox(width: 8);
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (favoriteTools.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              sliver: SliverToBoxAdapter(
                child: _HorizontalToolStrip(
                  title: 'Đã ghim',
                  tools: favoriteTools,
                  onTap: (tool) => _open(tool),
                ),
              ),
            ),
          if (_history.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dùng gần đây', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _history.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final item = _history[index];
                          final id = '${item['toolId'] ?? ''}';
                          final tool = ToolRegistry.all.where((t) => t.id == id).firstOrNull;
                          if (tool == null) return const SizedBox.shrink();
                          return SizedBox(
                            width: 230,
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _open(tool, query: '${item['query'] ?? ''}'),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(child: Icon(tool.icon, size: 20)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(tool.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                                            const SizedBox(height: 4),
                                            Text('${item['query'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: width < 380 ? .86 : .96,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final tool = _visibleTools[index];
                  return _ToolCard(
                    tool: tool,
                    favorite: _favorites.contains(tool.id),
                    onFavorite: () => _toggleFavorite(tool.id),
                    onTap: () => _open(tool),
                  );
                },
                childCount: _visibleTools.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalToolStrip extends StatelessWidget {
  const _HorizontalToolStrip({required this.title, required this.tools, required this.onTap});
  final String title;
  final List<ToolDefinition> tools;
  final ValueChanged<ToolDefinition> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tools.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final tool = tools[index];
              return ActionChip(
                avatar: Icon(tool.icon, size: 20),
                label: Text(tool.name),
                onPressed: () => onTap(tool),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.favorite,
    required this.onFavorite,
    required this.onTap,
  });

  final ToolDefinition tool;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(tool.icon, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: favorite ? 'Bỏ ghim' : 'Ghim',
                    onPressed: onFavorite,
                    icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tool.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  tool.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, height: 1.3),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _SmallChip(label: tool.category.label),
                  _SmallChip(label: tool.availability.label),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

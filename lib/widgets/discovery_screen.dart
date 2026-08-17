import 'package:flutter/material.dart';
import 'package:ai_assistant/screens/interpreter_screen.dart';
import 'package:ai_assistant/screens/diagnostics_screen.dart';
import 'package:ai_assistant/screens/realtime_tools_screen.dart';

class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;
    return CustomScrollView(
      slivers: [
        const SliverAppBar(
          pinned: true,
          title: Text('Khám phá'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI-LHHT Voice Pro',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Giọng nói, phiên dịch, tài liệu và chẩn đoán trong một nơi.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: width < 380 ? 1.0 : 1.12,
            ),
            delegate: SliverChildListDelegate([
              _FeatureCard(
                title: 'Phiên dịch AI',
                subtitle: 'Dịch văn bản và giọng nói đa ngôn ngữ',
                icon: Icons.translate_rounded,
                gradient: const [Color(0xFF2563EB), Color(0xFF4F46E5)],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InterpreterScreen()),
                ),
              ),
              _FeatureCard(
                title: 'Trợ lý giọng nói',
                subtitle: 'Hội thoại thời gian thực với Xiaozhi',
                icon: Icons.graphic_eq_rounded,
                gradient: const [Color(0xFF7C3AED), Color(0xFFDB2777)],
                onTap: () => _showTip(context, 'Mở một cuộc trò chuyện Xiaozhi ở tab Tin nhắn.'),
              ),
              _FeatureCard(
                title: 'Phân tích tài liệu',
                subtitle: 'Đọc, tóm tắt và hỏi đáp theo tài liệu',
                icon: Icons.description_rounded,
                gradient: const [Color(0xFF059669), Color(0xFF0D9488)],
                onTap: () => _showTip(context, 'Kết nối Dify Knowledge Base để dùng tài liệu chuyên sâu.'),
              ),
              _FeatureCard(
                title: 'Chẩn đoán Voice',
                subtitle: 'MIC → ASR → Agent → Tool → TTS',
                icon: Icons.monitor_heart_outlined,
                gradient: const [Color(0xFFEA580C), Color(0xFFDC2626)],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                ),
              ),
              _FeatureCard(
                title: 'Knowledge Base',
                subtitle: 'Kho tri thức cho Agent và tài liệu nội bộ',
                icon: Icons.menu_book_rounded,
                gradient: const [Color(0xFF0891B2), Color(0xFF0284C7)],
                onTap: () => _showTip(context, 'Quản lý Knowledge Base trên Xiaozhi/Dify rồi gắn cho Agent.'),
              ),
              _FeatureCard(
                title: 'Tool / MCP',
                subtitle: '21 công cụ realtime: tài chính, thời tiết, crypto, tin tức, thể thao…',
                icon: Icons.extension_rounded,
                gradient: const [Color(0xFF475569), Color(0xFF111827)],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RealtimeToolsScreen()),
                ),
              ),
            ]),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Thiết kế cho AI Box',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _SimpleTile(
                icon: Icons.hotel_rounded,
                title: 'Khách sạn',
                subtitle: 'Sẵn sàng tích hợp phòng trống, dọn phòng, doanh thu qua Tool/API.',
              ),
              _SimpleTile(
                icon: Icons.confirmation_number_outlined,
                title: 'Xổ số realtime',
                subtitle: 'Đã chuyển vào Realtime Tool Engine v4 với router, cache, retry và bridge dự phòng.',
              ),
              _SimpleTile(
                icon: Icons.music_note_rounded,
                title: 'Nhạc trực tuyến',
                subtitle: 'Lệnh “bật nhạc” tìm catalog online và mở nguồn phát YouTube Music thay vì kho cục bộ 5 bài.',
              ),
              _SimpleTile(
                icon: Icons.security_rounded,
                title: 'Bảo mật cấu hình',
                subtitle: 'Không hiển thị token đầy đủ trên giao diện chẩn đoán.',
              ),
            ]),
          ),
        ),
      ],
    );
  }

  static void _showTip(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: constraints.maxHeight < 150 ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.84),
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SimpleTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

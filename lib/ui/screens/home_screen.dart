/// صفحهٔ اصلی: ایجاد بازی، پیوستن به بازی، پروفایل و راهنما.
library;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../domain/models.dart';
import '../../domain/room_record.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';
import 'guide_screen.dart';
import 'join_screen.dart';
import 'lobby_screen.dart';
import 'play_screen.dart';
import 'profile_screen.dart';
import 'results_screen.dart';
import 'settings_screen.dart';
import 'judging_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  Future<void> _createGame() async {
    final controller = GameScope.read(context);
    if (controller.profile.displayName.trim().isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProfileScreen(firstRun: true),
        ),
      );
      if (!mounted) return;
      if (controller.profile.displayName.trim().isEmpty) return;
    }
    setState(() => _busy = true);
    final ok = await controller.createGame();
    if (!mounted) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _busy = false);
    if (!ok) {
      final error = controller.lastError;
      if (error != null) showMessage(context, error);
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const LobbyScreen()));
  }

  Future<void> _joinGame() async {
    final controller = GameScope.read(context);
    if (controller.profile.displayName.trim().isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProfileScreen(firstRun: true),
        ),
      );
      if (!mounted) return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const JoinScreen()));
  }

  /// ادامهٔ یک اتاق ذخیره‌شده (میزبان یا بازیکن).
  Future<void> _resumeRoom(RoomRecord room) async {
    final controller = GameScope.read(context);
    setState(() => _busy = true);
    final ok = await controller.resumeRoom(room);
    if (!mounted) {
      setState(() => _busy = false);
      return;
    }
    setState(() => _busy = false);
    if (!ok) {
      final error = controller.lastError;
      if (error != null) showMessage(context, error);
      return;
    }
    final phase = controller.session.phase;
    final route = switch (phase) {
      GamePhase.judging => const JudgingScreen(),
      GamePhase.roundResults => const ResultsScreen(),
      GamePhase.lobby => const LobbyScreen(),
      _ => const PlayScreen(),
    };
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => route));
  }

  /// خروج صریح از یک اتاق ذخیره‌شده (با تأیید).
  Future<void> _leaveSavedRoom(RoomRecord room) async {
    final controller = GameScope.read(context);
    final ok = await confirmDialog(
      context,
      title: 'خروج از اتاق',
      message:
          'از اتاق «${room.roomName}» خارج می‌شوید؟ اطلاعات این اتاق از این '
          'دستگاه حذف می‌شود و برای بازگشت باید دوباره عضو شوید. '
          '(بازگشت به صفحهٔ اصلی به معنی خروج از اتاق نیست.)',
      confirmLabel: 'خروج از اتاق',
      destructive: true,
    );
    if (!ok) return;
    await controller.leaveRoom(room);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _discardSavedGame() async {
    final controller = GameScope.read(context);
    final ok = await confirmDialog(
      context,
      title: 'شروع بازی جدید',
      message:
          'همهٔ اتاق‌های ذخیره‌شدهٔ این دستگاه پاک می‌شوند. ادامه می‌دهید؟',
      confirmLabel: 'بله، حذف و بازی جدید',
      destructive: true,
    );
    if (!ok) return;
    await controller.discardSavedGame();
    if (!mounted) return;
    await _createGame();
  }

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    final rooms = controller.savedRooms;
    final resumable = rooms.where((room) => room.resumable).toList();
    final displayName = controller.profile.displayName.trim();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'شتر مرغ',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'اسم فامیل گروهی — چند گوشی، یک بازی',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ActionTile(
              icon: Icons.person_outline_rounded,
              title: displayName.isEmpty ? 'تعیین نام نمایشی' : displayName,
              subtitle: displayName.isEmpty
                  ? 'برای بازی چندنفره، نام نمایشی خود را وارد کنید'
                  : 'پروفایل و نام نمایشی',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
            ),
            if (controller.lastError != null) ...[
              const SizedBox(height: 8),
              _ErrorBanner(message: controller.lastError!),
            ],
            if (resumable.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: resumable.length == 1
                    ? 'اتاق ذخیره‌شده'
                    : 'اتاق‌های ذخیره‌شده',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'اتاق ذخیره‌شده روی این دستگاه پیدا شد. با «ادامه بازی» '
                      'به همان اتاق و همان وضعیت قبلی برمی‌گردید.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    ...resumable.map((room) {
                      final status = switch (room.linkStatus) {
                        RoomLinkStatus.online => 'آخرین اتصال: متصل',
                        RoomLinkStatus.connecting => 'آخرین اتصال: در حال اتصال',
                        RoomLinkStatus.offline => 'آخرین اتصال: قطع',
                      };
                      final roleLabel = room.isHost ? 'میزبان' : 'بازیکن';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      room.hostName.isEmpty
                                          ? room.roomName
                                          : 'میزبان: ${room.hostName}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  PillLabel(
                                    text: roleLabel,
                                    color: room.isHost
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$status • ${_roomPhaseLabel(room)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _resumeRoom(room),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 20,
                                ),
                                label: const Text('ادامه بازی'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _leaveSavedRoom(room),
                                child: const Text('خروج از اتاق'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _discardSavedGame,
                      child: const Text('حذف همهٔ بازی‌های ذخیره‌شده'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SectionCard(
              title: 'شروع بازی چندنفره',
              child: Column(
                children: [
                  _BigAction(
                    icon: Icons.wifi_tethering_rounded,
                    title: 'ایجاد بازی',
                    subtitle: 'میزبان شوید و بقیه را به بازی دعوت کنید',
                    onTap: _busy ? null : _createGame,
                    primary: true,
                  ),
                  const SizedBox(height: 10),
                  _BigAction(
                    icon: Icons.login_rounded,
                    title: 'پیوستن به بازی',
                    subtitle: 'به بازی میزبان در شبکهٔ محلی وصل شوید',
                    onTap: _busy ? null : _joinGame,
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ActionTile(
                    icon: Icons.menu_book_rounded,
                    title: 'راهنمای بازی',
                    subtitle: 'قوانین، امتیازدهی و روش اتصال',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GuideScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ActionTile(
                    icon: Icons.settings_outlined,
                    title: 'تنظیمات',
                    subtitle: 'نام نمایشی، پاک‌سازی داده‌ها و گزارش فنی',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'نسخهٔ ${faNum('4.1.0')} — بدون اینترنت و بدون سرور بیرونی',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// برچسب فارسی وضعیت ذخیره‌شدهٔ اتاق.
String _roomPhaseLabel(RoomRecord room) {
  final phase = switch (room.phase) {
    GamePhase.lobby => 'لابی',
    GamePhase.playing => 'در حال بازی',
    GamePhase.paused => 'متوقف شده',
    GamePhase.collecting => 'دریافت پاسخ‌ها',
    GamePhase.judging => 'داوری',
    GamePhase.roundResults => 'نتایج دست',
    GamePhase.finished => 'پایان‌یافته',
  };
  if (room.roundIndex <= 0) return phase;
  return '$phase • دست ${faNum(room.roundIndex)}';
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.primarySoft : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: primary ? AppColors.primary : AppColors.outline,
              width: primary ? 1.1 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: primary ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left,
                color: primary ? AppColors.primary : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rejected.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.rejected.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.rejected, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Lobby: player list, join code, network state and start (host only).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../domain/categories.dart';
import '../../domain/game_session.dart';
import '../../domain/models.dart';
import '../../state/game_controller.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';
import '../widgets/exit_guard.dart';
import 'play_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _navigating = false;
  GameController? _listening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GameScope.read(context);
    if (!identical(_listening, controller)) {
      _listening?.removeListener(_onChanged);
      _listening = controller..addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _listening?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final controller = _listening;
    if (controller == null || _navigating) return;
    if (controller.session.phase != GamePhase.lobby) {
      // The host started the game, or the player synced with a running session.
      _goToGame();
    } else if (controller.session.rounds.isNotEmpty) {
      // The game ended formally; go back Home.
      _goToHome();
    }
  }

  Future<void> _goToHome() async {
    if (_navigating) return;
    _navigating = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _navigating = false;
  }

  Future<void> _goToGame() async {
    if (_navigating) return;
    _navigating = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PlayScreen()),
    );
  }

  Future<void> _startGame() async {
    final controller = GameScope.read(context);
    if (controller.session.activePlayerCount < GameSession.minPlayers) {
      showMessage(context, 'برای شروع بازی حداقل یک بازیکن لازم است.');
      return;
    }
    controller.startGame();
  }

  Future<void> _leaveRoom() async {
    final controller = GameScope.read(context);
    await confirmLeaveRoom(
      context,
      roomName: controller.gameName,
      isHostRole: controller.isHost,
    );
  }

  Future<void> _editCategories() async {
    final controller = GameScope.read(context);
    final selected = <int>{...controller.session.config.activeCategoryIds};
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('دسته‌های بازی', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'دسته‌هایی که در این بازی پرسیده می‌شوند را انتخاب کنید.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: orderedCategories().map((category) {
                  final isOn = selected.contains(category.id);
                  return FilterChip(
                    selected: isOn,
                    label: Text(category.title),
                    onSelected: (value) => setSheetState(() {
                      if (value) {
                        selected.add(category.id);
                      } else if (selected.length > 1) {
                        selected.remove(category.id);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(selected),
                child: const Text('ذخیره'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || result.isEmpty) return;
    controller.setActiveCategories(
      kCategoryDisplayOrder.where(result.contains).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    final session = controller.session;
    final isHost = controller.isHost;
    final players = session.players;
    final canStart = session.activePlayerCount >= GameSession.minPlayers;

    return ExitGuard(
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(isHost ? 'لابی بازی' : 'در انتظار شروع'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'گزینه‌های اتاق',
              onSelected: (value) {
                if (value == 'leave') _leaveRoom();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'leave',
                  child: Text(isHost ? 'بستن اتاق' : 'خروج از اتاق'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            controller.gameName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        PillLabel(
                          text: isHost
                              ? (controller.netStatus == NetStatus.hosting
                                    ? 'میزبان آنلاین'
                                    : 'میزبان')
                              : (controller.netStatus == NetStatus.connected
                                    ? 'متصل'
                                    : 'در حال اتصال'),
                          color: controller.netStatus == NetStatus.disconnected
                              ? AppColors.rejected
                              : AppColors.confirmed,
                          icon: Icons.wifi_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.key_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'کد اتصال: ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          controller.joinToken,
                          style: const TextStyle(
                            fontFamily: 'Vazirmatn',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                            color: AppColors.primary,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                    if (isHost && controller.localAddresses.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'آدرس میزبان: ${faNum(controller.localAddresses.first)}'
                        ' • پورت ${faNum(controller.hostPort)}',
                        style: Theme.of(context).textTheme.bodySmall,
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                    if (isHost) ...[
                      const SizedBox(height: 10),
                      SectionCard(
                        title: 'QR Code اتصال به بازی',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'بازیکنان می‌توانند این QR را اسکن کرده و به سرعت به بازی وصل شوند.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            QrCodePanel(
                              data: jsonEncode(
                                controller.qrConnectionPayload(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'در جزئیات اتصال (اینگم، آدرس، پورت و توکن) '
                              'به‌صورت پویا تولید شده و بعد از پایان رسمی بازی '
                              'نامعتبر می‌شود.',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'کد اتصال: ${controller.joinToken}',
                                    style: const TextStyle(
                                      fontFamily: 'Vazirmatn',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                      color: AppColors.primary,
                                    ),
                                    textDirection: TextDirection.ltr,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'کپی کد اتصال',
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(
                                        text: controller.joinToken,
                                      ),
                                    );
                                    showMessage(
                                      context,
                                      'کد اتصال کپی شد.',
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isHost) ...[
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: controller.openJoin,
                        onChanged: controller.setOpenJoin,
                        title: Text(
                          'ورود سریع بدون کد',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          'بازیکنان شبکهٔ محلی بدون وارد کردن کد به بازی وصل می‌شوند.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'بازیکنان (${faNum(players.length)})',
                trailing: isHost
                    ? TextButton.icon(
                        onPressed: _editCategories,
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('دسته‌ها'),
                      )
                    : null,
                child: Column(
                  children: [
                    ...players.map((player) {
                      final connected = session.isConnected(player.id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppColors.surfaceHigh,
                          child: Text(
                            player.name.characters.first,
                            style: const TextStyle(
                              fontFamily: 'Vazirmatn',
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(player.name)),
                            if (player.isHost) ...[
                              const SizedBox(width: 6),
                              const PillLabel(
                                text: 'میزبان',
                                color: AppColors.primary,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          connected ? 'متصل' : 'قطع شده',
                          style: TextStyle(
                            fontFamily: 'Vazirmatn',
                            fontSize: 12,
                            color: connected
                                ? AppColors.confirmed
                                : AppColors.rejected,
                          ),
                        ),
                        trailing: isHost && !player.isHost
                            ? IconButton(
                                onPressed: () async {
                                  final ok = await confirmDialog(
                                    context,
                                    title: 'حذف بازیکن',
                                    message: '${player.name} از بازی حذف شود؟',
                                    confirmLabel: 'حذف',
                                    destructive: true,
                                  );
                                  if (ok) {
                                    await controller.removePlayer(player.id);
                                  }
                                },
                                icon: const Icon(
                                  Icons.person_remove_outlined,
                                  size: 20,
                                  color: AppColors.rejected,
                                ),
                              )
                            : null,
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (isHost) ...[
                FilledButton.icon(
                  onPressed: canStart ? _startGame : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(
                    canStart ? 'شروع بازی' : 'حداقل یک بازیکن لازم است',
                  ),
                ),
                if (session.activePlayerCount == 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    'می‌توانید به‌تنهایی برای تمرین بازی را شروع کنید.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'زمان هر دست ۷ دقیقه است و قابل تغییر نیست. هیچ کلمه یا حرفی '
                  'برای دست‌ها تعیین نمی‌شود؛ دست با دکمهٔ «استپ» یا پایان زمان '
                  'به داوری می‌رسد.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else ...[
                const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(height: 10),
                Text(
                  'منتظر شروع بازی توسط میزبان باشید…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

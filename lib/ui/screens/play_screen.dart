/// صفحهٔ بازی (دست جاری): حرف، زمان‌سنج همگام، پاسخ‌ها و دکمهٔ «استپ».
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../domain/answer_rules.dart';
import '../../domain/models.dart';
import '../../state/game_controller.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';
import '../widgets/exit_guard.dart';
import 'judging_screen.dart';
import 'results_screen.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final Map<int, TextEditingController> _controllers =
      <int, TextEditingController>{};
  bool _navigating = false;
  String? _lastErrorShown;
  GameController? _listening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GameScope.read(context);
    if (!identical(_listening, controller)) {
      _listening?.removeListener(_onGameChanged);
      _lastErrorShown = controller.lastError;
      _listening = controller..addListener(_onGameChanged);
    }
  }

  @override
  void dispose() {
    _listening?.removeListener(_onGameChanged);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(
    GameController controller,
    int categoryId,
  ) {
    return _controllers.putIfAbsent(
      categoryId,
      () => TextEditingController(text: controller.myAnswer(categoryId)),
    );
  }

  void _onGameChanged() {
    final controller = _listening;
    if (controller == null || _navigating) return;
    final error = controller.lastError;
    if (error != null && error != _lastErrorShown) {
      _lastErrorShown = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
      });
    }
    final phase = controller.session.phase;
    if (phase == GamePhase.lobby || phase == GamePhase.finished) {
      // بازی به پایان رسمی رسید یا نشست خالی است — بازگشت به صفحه اصلی.
      _goToHome();
      return;
    }
    if (phase == GamePhase.judging && controller.isHost) {
      _goTo(const JudgingScreen());
      return;
    }
    if (phase == GamePhase.roundResults) {
      _goTo(const ResultsScreen());
    }
  }

  Future<void> _goToHome() async {
    if (_navigating) return;
    _navigating = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _navigating = false;
  }

  Future<void> _goTo(Widget screen) async {
    if (_navigating) return;
    _navigating = true;
    await Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => screen));
    _navigating = false;
  }

  /// نمایش QR اتصال (میزبان) — مفید پس از بازیابی جلسه.
  Future<void> _showQrDialog() async {
    final controller = GameScope.read(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR اتصال به بازی'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrCodePanel(data: jsonEncode(controller.qrConnectionPayload())),
              const SizedBox(height: 10),
              Text(
                'کد اتصال: ${controller.joinToken}',
                style: const TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 6),
              Text(
                'بازیکنان می‌توانند با اسکن این QR به همین جلسه وصل شوند.',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  Future<void> _stop() async {
    final controller = GameScope.read(context);
    final ok = await confirmDialog(
      context,
      title: 'استپ',
      message:
          'با استپ، دست برای همهٔ بازیکنان تمام می‌شود و پاسخ‌های فعلی شما ثبت '
          'می‌شوند. ادامه می‌دهید؟',
      confirmLabel: 'استپ',
    );
    if (!ok) return;
    await controller.requestStop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    final session = controller.session;
    final round = session.currentRound;
    final phase = session.phase;
    final stopped = controller.iAmStopped;
    final canType = phase == GamePhase.playing && !stopped;
    // شرط فعال بودن دکمهٔ استپ (نسخهٔ ۱.۰.۰).
    final canStop = controller.iCanStop;

    return ExitGuard(
      child: Scaffold(
        appBar: AppBar(
          leading: const HomeIconButton(),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  'assets/images/app_icon_display.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              Text(round == null ? 'بازی' : 'دست ${faNum(round.index)}'),
            ],
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _ConnectionPill(controller: controller),
              ),
            ),
            if (controller.isHost)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  switch (value) {
                    case 'pause':
                      phase == GamePhase.paused
                          ? controller.resumeGame()
                          : controller.pauseGame();
                    case 'end':
                      final ok = await confirmDialog(
                        context,
                        title: 'پایان دست',
                        message: 'دست برای همهٔ بازیکنان تمام شود و به مرحلهٔ دریافت پاسخ‌ها برود؟',
                        confirmLabel: 'پایان دست',
                      );
                      if (ok) controller.forceEndRound();
                    case 'qr':
                      await _showQrDialog();
                    case 'leave':
                      await confirmLeaveRoom(
                        context,
                        roomName: controller.gameName,
                        isHostRole: true,
                      );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'pause',
                    child: Text(
                      phase == GamePhase.paused ? 'ادامهٔ زمان' : 'توقف موقت',
                    ),
                  ),
                  const PopupMenuItem(value: 'end', child: Text('پایان دست')),
                  const PopupMenuItem(
                    value: 'qr',
                    child: Text('نمایش QR اتصال'),
                  ),
                  const PopupMenuItem(
                    value: 'leave',
                    child: Text('خروج از اتاق'),
                  ),
                ],
              ),
          ],
        ),
        body: SafeArea(
          child: phase == GamePhase.paused
              ? _PausedView(controller: controller)
              : phase == GamePhase.collecting
              ? _CollectingView(controller: controller)
              : Column(
                  children: [
                    _RoundHeader(controller: controller),
                    // تگ‌های وضعیت بازیکنان در بالای صفحه (بند ۳).
                    _PlayersStrip(controller: controller),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: controller.activeCategories.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final categories = controller.activeCategories;
                          if (index == categories.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                stopped
                                    ? 'پاسخ‌های شما قفل شده است و به میزبان ارسال شد.'
                                    : 'پاسخ‌ها بلافاصله برای میزبان ارسال می‌شوند.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            );
                          }
                          final category = categories[index];
                          return Row(
                            children: [
                              SizedBox(
                                width: 92,
                                child: Text(
                                  category.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _controllerFor(
                                    controller,
                                    category.id,
                                  ),
                                  enabled: canType,
                                  textInputAction: TextInputAction.next,
                                  maxLength: kMaxAnswerLength,
                                  maxLengthEnforcement:
                                      MaxLengthEnforcement.enforced,
                                  decoration: InputDecoration(
                                    hintText: 'پاسخ خود را بنویسید',
                                    helperText: 'حداکثر ۸۰ نویسه',
                                    isDense: true,
                                  ),
                                  onChanged: (value) =>
                                      controller.setAnswer(category.id, value),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 54,
                            child: FilledButton.icon(
                              // نسخهٔ ۱.۰.۰: دکمهٔ استپ تنها وقتی فعال است که
                              // همهٔ پاسخ‌های همین بازیکن حداقل ۲ کاراکتر
                              // معتبر داشته باشند.
                              onPressed: canStop ? _stop : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: stopped
                                    ? AppColors.surfaceHigh
                                    : AppColors.rejected,
                                // حالت غیرفعال باید کاملاً از فعال تشخیص داده
                                // شود (خاکستری کم‌رنگ + متن محو).
                                disabledBackgroundColor: AppColors.surfaceHigh,
                                disabledForegroundColor: AppColors.textMuted,
                                disabledIconColor: AppColors.textMuted,
                                side: stopped || canStop
                                    ? null
                                    : const BorderSide(
                                        color: AppColors.outline,
                                      ),
                              ),
                              icon: Icon(
                                stopped
                                    ? Icons.check_circle_outline
                                    : canStop
                                    ? Icons.stop_circle_outlined
                                    : Icons.lock_outline_rounded,
                                size: 22,
                              ),
                              label: Text(
                                stopped
                                    ? 'استپ ثبت شد؛ منتظر بقیهٔ بازیکنان'
                                    : 'استپ',
                              ),
                            ),
                          ),
                          if (!stopped &&
                              phase == GamePhase.playing &&
                              !canStop) ...[
                            const SizedBox(height: 6),
                            Text(
                              controller.stopHintText,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.warning),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.netStatus;
    final (label, color) = switch (status) {
      NetStatus.hosting => ('میزبان', AppColors.confirmed),
      NetStatus.connected => ('متصل', AppColors.confirmed),
      NetStatus.reconnecting => ('اتصال مجدد…', AppColors.warning),
      NetStatus.disconnected => ('قطع', AppColors.rejected),
      NetStatus.offline => ('آفلاین', AppColors.textMuted),
    };
    return PillLabel(text: label, color: color, icon: Icons.wifi_rounded);
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final round = controller.session.currentRound;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline, width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary, width: 1.1),
              ),
              child: Text(
                faNum(round?.index ?? 0),
                style: const TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.profile.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.isHost ? 'میزبان' : 'بازیکن',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TimerPill(
              remainingMs: controller.remainingMs,
              paused: controller.session.phase == GamePhase.paused,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayersStrip extends StatelessWidget {
  const _PlayersStrip({required this.controller});

  final GameController controller;

  /// برچسب وضعیت یک بازیکن بر اساس فاز بازی و اتصال.
  (String, Color) _statusOf(BuildContext context, Player player) {
    final session = controller.session;
    final connected = session.isConnected(player.id);
    final submission = controller.submissionOf(player.id);
    final phase = session.phase;

    if (session.hasPlayerLeft(player.id)) {
      return ('از بازی خارج شد', AppColors.textMuted);
    }
    if (!connected) {
      return ('قطع ارتباط', AppColors.rejected);
    }
    if (phase == GamePhase.judging || phase == GamePhase.roundResults) {
      return ('منتظر نتیجه', AppColors.warning);
    }
    return switch (submission) {
      SubmissionState.received => ('دریافت شد', AppColors.confirmed),
      SubmissionState.stopped => ('استپ کرده', AppColors.duplicate),
      SubmissionState.typing => ('در حال بازی', AppColors.textSecondary),
      SubmissionState.offline => ('قطع ارتباط', AppColors.rejected),
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final children = <Widget>[];
    for (final player in session.players) {
      final isMe = player.id == controller.myPlayerId;
      final (label, color) = _statusOf(context, player);
      final hostBadge = player.isHost ? '  • میزبان' : '';
      children.add(
        Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: PillLabel(
            text: '${player.name}$hostBadge  •  $label',
            color: isMe ? AppColors.primary : color,
            icon: isMe ? Icons.person_rounded : null,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectingView extends StatelessWidget {
  const _CollectingView({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final pending = session.pendingSnapshotPlayerIds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        SectionCard(
          title: 'پایان دست',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'زمان دست تمام شد. پاسخ‌های همهٔ بازیکنان در حال دریافت است…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              ...session.players.map((player) {
                final submission = controller.submissionOf(player.id);
                final received = submission == SubmissionState.received;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    received
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_bottom_rounded,
                    color: received ? AppColors.confirmed : AppColors.warning,
                  ),
                  title: Text(player.name),
                  subtitle: Text(
                    received ? 'پاسخ‌ها دریافت شد' : 'در انتظار پاسخ‌ها',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing:
                      controller.isHost &&
                          !received &&
                          !session.isConnected(player.id)
                      ? TextButton(
                          onPressed: () =>
                              controller.resolveOfflinePlayer(player.id),
                          child: const Text('کنار گذاشتن'),
                        )
                      : null,
                );
              }),
              const SizedBox(height: 8),
              if (!controller.isHost)
                Text(
                  'پس از دریافت پاسخ‌ها، داوری روی دستگاه میزبان انجام می‌شود.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (controller.isHost && pending.isNotEmpty)
                Text(
                  'تا دریافت پاسخ بازیکنان باقی‌مانده، داوری آغاز نمی‌شود. اگر بازیکنی '
                  'قطع شده باشد می‌توانید او را از این دست کنار بگذارید؛ پاسخ‌های '
                  'دریافت‌شدهٔ قبلی حفظ می‌شوند.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PausedView extends StatelessWidget {
  const _PausedView({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.pause_circle_filled_rounded,
              size: 64,
              color: AppColors.warning,
            ),
            const SizedBox(height: 14),
            Text(
              'بازی متوقف شده است',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              controller.isHost
                  ? 'زمان‌سنج متوقف است و با «ادامه» از همان زمان قبلی ادامه می‌یابد.'
                  : 'میزبان بازی را موقتاً متوقف کرده است.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            TimerPill(remainingMs: controller.remainingMs, paused: true),
            if (controller.isHost) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  onPressed: controller.resumeGame,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('ادامه'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

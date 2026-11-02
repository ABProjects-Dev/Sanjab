/// نتایج دست و مجموع امتیازها.
///
/// روی دستگاه میزبان، دکمه‌های «دست جدید» و «پایان بازی» فعال است؛ دستگاه
/// بازیکنان فقط نتیجهٔ اعلام‌شده توسط میزبان را می‌بینند.
library;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../domain/models.dart';
import '../../state/game_controller.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';
import '../widgets/exit_guard.dart';
import 'play_screen.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _navigating = false;
  GameController? _listening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GameScope.read(context);
    if (!identical(_listening, controller)) {
      _listening?.removeListener(_onGameChanged);
      _listening = controller..addListener(_onGameChanged);
    }
  }

  @override
  void dispose() {
    _listening?.removeListener(_onGameChanged);
    super.dispose();
  }

  void _onGameChanged() {
    final controller = _listening;
    if (controller == null || _navigating) return;
    if (controller.session.phase == GamePhase.playing) {
      _goPlay();
    }
  }

  Future<void> _goPlay() async {
    if (_navigating) return;
    _navigating = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PlayScreen()),
    );
    _navigating = false;
  }

  Future<void> _nextRound() async {
    final controller = GameScope.read(context);
    controller.startNextRound();
  }

  Future<void> _finishGame() async {
    final controller = GameScope.read(context);
    final ok = await confirmDialog(
      context,
      title: 'پایان بازی',
      message:
          'بازی برای همهٔ بازیکنان پایان می‌یابد و همه به صفحهٔ اصلی منتقل '
          'می‌شوند. پس از پایان رسمی، «ادامه بازی» برای این جلسه وجود ندارد.',
      confirmLabel: 'پایان بازی',
      destructive: true,
    );
    if (!ok) return;
    await controller.finishGame();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    final session = controller.session;
    final round = session.currentRound;
    final standings = session.standings();
    final isHost = controller.isHost;

    return ExitGuard(
      child: Scaffold(
        appBar: AppBar(
          leading: const HomeIconButton(),
          title: Text('نتایج دست ${faNum(round?.index ?? 0)}'),
          actions: [
            if (!isHost)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: PillLabel(
                    text: 'منتظر میزبان',
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              SectionCard(
                title: 'امتیاز این دست',
                child: Column(
                  children: session.players.map((player) {
                    final score = round?.scores[player.id] ?? 0;
                    final total = session.totals[player.id] ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(player.name),
                      subtitle: Text(
                        'مجموع: ${faNum(total)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: PillLabel(
                        text: '${faNum(score)} امتیاز',
                        color: score > 0
                            ? AppColors.confirmed
                            : AppColors.textMuted,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'رتبه‌بندی کل',
                child: Column(
                  children: standings.map((standing) {
                    final isMe = standing.playerId == controller.myPlayerId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: standing.rank == 1
                            ? AppColors.duplicate.withValues(alpha: 0.25)
                            : AppColors.surfaceHigh,
                        child: Text(
                          faNum(standing.rank),
                          style: const TextStyle(
                            fontFamily: 'Vazirmatn',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        isMe
                            ? '${standing.playerName} (شما)'
                            : standing.playerName,
                      ),
                      trailing: Text(
                        faNum(standing.totalScore),
                        style: const TextStyle(
                          fontFamily: 'Vazirmatn',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              if (isHost) ...[
                FilledButton.icon(
                  onPressed: _nextRound,
                  icon: const Icon(Icons.autorenew_rounded, size: 20),
                  label: const Text('دست جدید'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _finishGame,
                  icon: const Icon(Icons.flag_rounded, size: 20),
                  label: const Text('پایان بازی'),
                ),
              ] else
                Text(
                  'برای دست بعدی منتظر میزبان بمانید…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صفحهٔ داوری — فقط روی دستگاه میزبان.
///
/// جابه‌جایی بین دسته‌ها تنها با کشیدن افقی (Swipe) انجام می‌شود؛ هیچ دکمهٔ
/// بعدی/قبلی وجود ندارد و در دو سر فهرست، حرکت متوقف می‌شود (بند ۹.۴ سند ۱.۰.۰
/// که در ۲.۰.۰ هم حفظ شده است).
library;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../domain/models.dart';
import '../../domain/scoring.dart';
import '../../state/game_controller.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';
import '../widgets/exit_guard.dart';
import 'results_screen.dart';

class JudgingScreen extends StatefulWidget {
  const JudgingScreen({super.key});

  @override
  State<JudgingScreen> createState() => _JudgingScreenState();
}

class _JudgingScreenState extends State<JudgingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;
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
    _pageController.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    final controller = _listening;
    if (controller == null || _navigating) return;
    if (controller.session.phase == GamePhase.roundResults) {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_navigating) return;
    _navigating = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ResultsScreen()),
    );
    _navigating = false;
  }

  Future<void> _finalize() async {
    final controller = GameScope.read(context);
    final ok = await confirmDialog(
      context,
      title: 'ثبت نهایی داوری',
      message: 'امتیازهای این دست محاسبه و به مجموع امتیازها اضافه می‌شود. ادامه می‌دهید؟',
      confirmLabel: 'ثبت نهایی',
    );
    if (!ok) return;
    try {
      controller.finalizeJudging();
    } on Object catch (error) {
      if (!mounted) return;
      showMessage(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    if (!controller.isHost) {
      return Scaffold(
        appBar: AppBar(title: const Text('داوری')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'داوری فقط روی دستگاه میزبان انجام می‌شود. منتظر نتایج باشید.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      );
    }
    final categories = controller.activeCategories;
    final round = controller.session.currentRound;
    final unchecked = controller.session.uncheckedCount;

    return ExitGuard(
      child: Scaffold(
        appBar: AppBar(
          leading: const HomeIconButton(),
          title: Text('داوری دست ${faNum(round?.index ?? 0)}'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: PillLabel(
                  text: unchecked == 0
                      ? 'آمادهٔ ثبت'
                      : '${faNum(unchecked)} پاسخ بررسی‌نشده',
                  color: unchecked == 0
                      ? AppColors.confirmed
                      : AppColors.warning,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Text(
                      'دستهٔ ${faNum(_index + 1)} از ${faNum(categories.length)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text(
                      'برای دستهٔ بعد، افقی بکشید',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const ClampingScrollPhysics(),
                  itemCount: categories.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _CategoryPage(
                      controller: controller,
                      categoryId: category.id,
                      title: category.title,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: unchecked == 0 ? _finalize : null,
                    icon: const Icon(Icons.done_all_rounded, size: 20),
                    label: Text(
                      unchecked == 0
                          ? 'ثبت نهایی و محاسبهٔ امتیازها'
                          : 'همهٔ پاسخ‌ها را داوری کنید',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPage extends StatelessWidget {
  const _CategoryPage({
    required this.controller,
    required this.categoryId,
    required this.title,
  });

  final GameController controller;
  final int categoryId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final answers = session.answersOfCategory(categoryId);
    final tally = tallyCategory(answers);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (tally.uniqueConfirmed)
              PillLabel(
                text: tally.hasDuplicate
                    ? 'یکتا — ۱۵ امتیاز'
                    : 'یکتا — ۲۰ امتیاز',
                color: AppColors.confirmed,
                icon: Icons.star_rounded,
              )
            else if (tally.confirmedCount > 1)
              const PillLabel(
                text: 'چند پاسخ معتبر — ۱۰ امتیاز',
                color: AppColors.textSecondary,
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...answers.map((answer) {
          final blank = answer.isBlank;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: blank
                      ? AppColors.outline
                      : judgementColor(answer.status).withValues(alpha: 0.55),
                  width: 0.9,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.nameOf(answer.playerId),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      PillLabel(
                        text: blank ? 'خالی' : judgementLabel(answer.status),
                        color: judgementColor(answer.status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    blank ? '—' : answer.text.trim(),
                    style: TextStyle(
                      fontFamily: 'Vazirmatn',
                      fontSize: 15,
                      color: blank
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (!blank) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _JudgeButton(
                          label: 'تأیید',
                          color: AppColors.confirmed,
                          selected: answer.status == JudgementStatus.confirmed,
                          onTap: () => controller.setJudgement(
                            answer.playerId,
                            categoryId,
                            answer.status == JudgementStatus.confirmed
                                ? null
                                : JudgementStatus.confirmed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _JudgeButton(
                          label: 'تکراری',
                          color: AppColors.duplicate,
                          selected: answer.status == JudgementStatus.duplicate,
                          onTap: () => controller.setJudgement(
                            answer.playerId,
                            categoryId,
                            answer.status == JudgementStatus.duplicate
                                ? null
                                : JudgementStatus.duplicate,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _JudgeButton(
                          label: 'رد',
                          color: AppColors.rejected,
                          selected: answer.status == JudgementStatus.rejected,
                          onTap: () => controller.setJudgement(
                            answer.playerId,
                            categoryId,
                            answer.status == JudgementStatus.rejected
                                ? null
                                : JudgementStatus.rejected,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _JudgeButton extends StatelessWidget {
  const _JudgeButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? color.withValues(alpha: 0.22) : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : AppColors.outline,
                width: selected ? 1.2 : 0.8,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Vazirmatn',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? color : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

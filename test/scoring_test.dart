/// Scoring engine tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/domain/models.dart';
import 'package:sanjab/domain/scoring.dart';

AnswerEntry entry(
  String playerId,
  JudgementStatus status, {
  String text = 'تهران',
  int categoryId = 0,
}) => AnswerEntry(
  playerId: playerId,
  categoryId: categoryId,
  text: status == JudgementStatus.empty ? '' : text,
  status: status,
);

void main() {
  group('امتیاز پایه', () {
    test('پاسخ خالی صفر امتیاز دارد', () {
      expect(baseScoreOf(entry('p1', JudgementStatus.empty)), 0);
      expect(
        baseScoreOf(
          const AnswerEntry(
            playerId: 'p1',
            categoryId: 0,
            text: '   ',
            status: JudgementStatus.confirmed,
          ),
        ),
        0,
      );
    });

    test('پاسخ ردشده صفر امتیاز دارد', () {
      expect(baseScoreOf(entry('p1', JudgementStatus.rejected)), 0);
    });

    test('پاسخ تکراری ۵ امتیاز دارد', () {
      expect(baseScoreOf(entry('p1', JudgementStatus.duplicate)), 5);
    });

    test('پاسخ تأییدشدهٔ عادی ۱۰ امتیاز دارد', () {
      expect(baseScoreOf(entry('p1', JudgementStatus.confirmed)), 10);
    });
  });

  group('قانون یکتایی ۱۵ امتیاز', () {
    test('تنها پاسخ تأییدشده با وجود پاسخ تکراری دیگران ۱۵ می‌گیرد', () {
      final scored = scoreCategory([
        entry('p1', JudgementStatus.confirmed, text: 'تهران'),
        entry('p2', JudgementStatus.duplicate, text: 'تهران'),
        entry('p3', JudgementStatus.empty),
      ]);
      expect(scored.firstWhere((a) => a.playerId == 'p1').score, 15);
      expect(scored.firstWhere((a) => a.playerId == 'p1').uniqueBonus, isTrue);
      expect(scored.firstWhere((a) => a.playerId == 'p2').score, 5);
      expect(scored.firstWhere((a) => a.playerId == 'p3').score, 0);
    });

    test('امتیاز ویژه با امتیاز عادی جمع نمی‌شود (۱۵ نه ۲۵)', () {
      final scored = scoreCategory([
        entry('p1', JudgementStatus.confirmed),
        entry('p2', JudgementStatus.duplicate),
      ]);
      expect(scored.firstWhere((a) => a.playerId == 'p1').score, 15);
    });

    test('پاسخ‌های خالی و ردشده در کنار یک تکراری، مانع ۱۵ نیستند', () {
      final scored = scoreCategory([
        entry('p1', JudgementStatus.confirmed),
        entry('p2', JudgementStatus.rejected),
        entry('p3', JudgementStatus.duplicate),
        entry('p4', JudgementStatus.empty),
      ]);
      expect(scored.firstWhere((a) => a.playerId == 'p1').score, 15);
    });
  });

  group('قانون یکتایی ۲۰ امتیاز', () {
    test('تنها پاسخ تأییدشده و بقیه خالی/ردشده ۲۰ می‌گیرد', () {
      final scored = scoreCategory([
        entry('p1', JudgementStatus.confirmed),
        entry('p2', JudgementStatus.empty),
        entry('p3', JudgementStatus.rejected),
      ]);
      expect(scored.firstWhere((a) => a.playerId == 'p1').score, 20);
      expect(scored.firstWhere((a) => a.playerId == 'p1').uniqueBonus, isTrue);
    });

    test('در حضور هر پاسخ تکراری، قانون ۲۰ اعمال نمی‌شود و ۱۵ می‌شود', () {
      final scored = scoreCategory([
        entry('p1', JudgementStatus.confirmed),
        entry('p2', JudgementStatus.duplicate),
      ]);
      expect(scored.firstWhere((a) => a.playerId == 'p1').score, 15);
    });
  });

  group('نبود شرط یکتایی', () {
    test('دو پاسخ تأییدشده هر دو ۱۰ می‌گیرند', () {
      final scored = scoreCategory([
        entry('p1', JudgementStatus.confirmed, text: 'تهران'),
        entry('p2', JudgementStatus.confirmed, text: 'تبریز'),
        entry('p3', JudgementStatus.duplicate),
      ]);
      expect(scored.firstWhere((a) => a.playerId == 'p1').score, 10);
      expect(scored.firstWhere((a) => a.playerId == 'p2').score, 10);
      expect(scored.firstWhere((a) => a.playerId == 'p3').score, 5);
      expect(scored.any((a) => a.uniqueBonus), isFalse);
    });

    test('بدون پاسخ تأییدشده هیچ امتیاز ویژه‌ای داده نمی‌شود', () {
      final scored = scoreCategory([
        entry('p1', JudgementStatus.duplicate),
        entry('p2', JudgementStatus.rejected),
        entry('p3', JudgementStatus.empty),
      ]);
      expect(scored.where((a) => a.uniqueBonus), isEmpty);
      expect(scored.firstWhere((a) => a.playerId == 'p1').score, 5);
    });
  });

  group('امتیازدهی کل دست', () {
    test('جمع امتیاز هر بازیکن در همهٔ دسته‌ها درست است', () {
      final answers = <AnswerEntry>[
        // Category 0: p1 is unique and the rest are empty, so 20.
        entry('p1', JudgementStatus.confirmed, categoryId: 0),
        entry('p2', JudgementStatus.empty, categoryId: 0),
        // Category 1: p1 and p2 confirmed, so 10 and 10.
        entry('p1', JudgementStatus.confirmed, categoryId: 1),
        entry('p2', JudgementStatus.confirmed, categoryId: 1),
        // Category 2: p2 is a duplicate, so 5.
        entry('p2', JudgementStatus.duplicate, categoryId: 2),
        entry('p1', JudgementStatus.rejected, categoryId: 2),
      ];
      final result = scoreRound(answers, playerIds: ['p1', 'p2']);
      expect(result.perPlayer['p1'], 30);
      expect(result.perPlayer['p2'], 15);
    });

    test('بازیکن بدون پاسخ در جدول امتیاز صفر می‌گیرد', () {
      final result = scoreRound(
        [entry('p1', JudgementStatus.confirmed)],
        playerIds: ['p1', 'p2'],
      );
      expect(result.perPlayer['p2'], 0);
    });
  });

  group('رتبه‌بندی', () {
    test('بیشترین مجموع رتبهٔ اول و تساوی رتبهٔ مشترک می‌گیرد', () {
      final standings = buildStandings(
        players: const [
          Player(id: 'p1', name: 'الف'),
          Player(id: 'p2', name: 'ب'),
          Player(id: 'p3', name: 'پ'),
        ],
        totals: const {'p1': 40, 'p2': 40, 'p3': 10},
      );
      expect(standings.first.rank, 1);
      expect(standings[1].rank, 1);
      expect(standings.last.rank, 3);
    });
  });
}

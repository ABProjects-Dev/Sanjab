/// Shared routing between the game screens.
library;

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../state/game_scope.dart';
import 'screens/judging_screen.dart';
import 'screens/play_screen.dart';
import 'screens/results_screen.dart';

/// Persian label of a game phase.
String phaseLabel(GamePhase phase) {
  switch (phase) {
    case GamePhase.lobby:
      return 'لابی';
    case GamePhase.playing:
      return 'در حال بازی';
    case GamePhase.paused:
      return 'متوقف شده';
    case GamePhase.collecting:
      return 'دریافت پاسخ‌ها';
    case GamePhase.judging:
      return 'در حال داوری';
    case GamePhase.roundResults:
      return 'نتایج دست';
    case GamePhase.finished:
      return 'پایان‌یافته';
  }
}

/// Open the screen that matches the current phase.
void openGameScreen(BuildContext context) {
  final controller = GameScope.read(context);
  final route = switch (controller.session.phase) {
    GamePhase.judging => const JudgingScreen(),
    GamePhase.roundResults => const ResultsScreen(),
    GamePhase.finished => const PlayScreen(),
    _ => const PlayScreen(),
  };
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => route));
}

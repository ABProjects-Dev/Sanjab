/// Access to the game controller from the widget tree.
library;

import 'package:flutter/widgets.dart';

import 'game_controller.dart';

/// Inherited widget used for state sharing, with no external dependency.
class GameScope extends InheritedNotifier<GameController> {
  const GameScope({
    super.key,
    required GameController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Read the controller and subscribe, so the widget rebuilds on change.
  static GameController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope در درخت ویجت‌ها یافت نشد.');
    return scope!.notifier!;
  }

  /// Read the controller without subscribing, for event handlers.
  static GameController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope در درخت ویجت‌ها یافت نشد.');
    return scope!.notifier!;
  }
}

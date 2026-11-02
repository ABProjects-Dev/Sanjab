/// دسترسی به کنترلر بازی در درخت ویجت‌ها.
library;

import 'package:flutter/widgets.dart';

import 'game_controller.dart';

/// ارث‌بر ویجت برای مدیریت وضعیت (بدون وابستگی بیرونی).
class GameScope extends InheritedNotifier<GameController> {
  const GameScope({
    super.key,
    required GameController controller,
    required super.child,
  }) : super(notifier: controller);

  /// خواندن کنترلر همراه با ثبت وابستگی (برای بازسازی ویجت پس از تغییر).
  static GameController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope در درخت ویجت‌ها یافت نشد.');
    return scope!.notifier!;
  }

  /// خواندن کنترلر بدون ثبت وابستگی (برای رویدادها).
  static GameController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope در درخت ویجت‌ها یافت نشد.');
    return scope!.notifier!;
  }
}

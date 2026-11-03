/// ریشهٔ برنامه: تم، زبان فارسی، جهت RTL و مدیریت وضعیت.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_logger.dart';
import 'core/app_theme.dart';
import 'state/game_controller.dart';
import 'state/game_scope.dart';
import 'ui/screens/home_screen.dart';

class SanjabApp extends StatefulWidget {
  const SanjabApp({
    super.key,
    required this.controller,
    this.initialScreen,
  });

  final GameController controller;

  /// صفحهٔ آغازین (پیش‌فرض صفحهٔ اصلی)؛ برای آزمون ویجت استفاده می‌شود.
  final Widget? initialScreen;

  @override
  State<SanjabApp> createState() => _SanjabAppState();
}

class _SanjabAppState extends State<SanjabApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lifecycle callbacks cannot be awaited by the OS. Start the best-effort
    // write promptly and observe failures rather than leaking an async error.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(
        widget.controller.flush().catchError((Object error, StackTrace stack) {
          AppLogger.instance.error('lifecycle.flush', error, stack);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScope(
      controller: widget.controller,
      child: MaterialApp(
        title: 'سنجاب',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        locale: const Locale('fa'),
        supportedLocales: const <Locale>[Locale('fa')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: widget.initialScreen ?? const HomeScreen(),
      ),
    );
  }
}

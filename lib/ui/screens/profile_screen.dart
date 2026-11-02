/// پروفایل: نمایش و ویرایش نام نمایشی.
library;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../domain/profile.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.firstRun = false});

  /// اگر اولین اجرا باشد، بازگشت پس از ذخیره انجام می‌شود.
  final bool firstRun;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: GameScope.read(context).profile.displayName,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = GameScope.read(context);
    final value = _controller.text;
    final error = validateDisplayName(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await controller.saveDisplayName(value);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      setState(
        () => _error = controller.lastError ?? 'ذخیره نام نمایشی انجام نشد.',
      );
      return;
    }
    showMessage(context, 'نام نمایشی ذخیره شد.');
    if (widget.firstRun) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('پروفایل')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            SectionCard(
              title: 'نام نمایشی',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    maxLength: kMaxDisplayNameLength,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      hintText: 'مثلاً: سارا',
                      errorText: _error,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'این نام به بقیهٔ بازیکنان نمایش داده می‌شود. تغییر نام، هویت شما در بازی '
                    'را عوض نمی‌کند و امتیازهایتان حفظ می‌شود.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_rounded, size: 20),
                    label: const Text('ذخیره'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'شناسهٔ این دستگاه',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    faNum(controller.profile.playerId),
                    style: const TextStyle(
                      fontFamily: 'Vazirmatn',
                      fontSize: 13,
                      letterSpacing: 1.1,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'این شناسه برای شناسایی شما در نشست بازی استفاده می‌شود و به کسی نشان '
                    'داده نمی‌شود. با تغییر نام نمایشی تغییر نمی‌کند.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

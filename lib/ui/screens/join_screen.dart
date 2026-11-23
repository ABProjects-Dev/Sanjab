/// Join a game: automatic discovery, QR scan or manual entry.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../net/discovery.dart';
import '../../state/game_controller.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';
import 'lobby_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  List<DiscoveredHost> _hosts = const <DiscoveredHost>[];
  bool _scanning = false;
  bool _connecting = false;
  bool _scanned = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _addressController.dispose();
    _codeController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final controller = GameScope.read(context);
    setState(() {
      _scanning = true;
      _error = null;
    });
    final hosts = await controller.scanHosts();
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      _scanning = false;
      _scanned = true;
      if (hosts.isEmpty) {
        _error = controller.lastError;
      }
    });
  }

  /// Connect with address, port, token and game ID.
  Future<void> _connect({
    required String address,
    required int port,
    required String gameId,
    required String token,
    String hostName = '',
  }) async {
    final controller = GameScope.read(context);
    setState(() {
      _connecting = true;
      _error = null;
    });
    final ok = await controller.joinGame(
      address: address,
      port: port,
      gameId: gameId,
      token: token,
      hostName: hostName,
    );
    if (!mounted) return;
    setState(() => _connecting = false);
    if (!ok) {
      setState(() => _error = controller.lastError ?? 'اتصال برقرار نشد.');
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LobbyScreen()),
    );
  }

  /// Scan the host QR code with the camera.
  Future<void> _scanQrCode() async {
    final controller = GameScope.read(context);
    if (controller.profile.displayName.trim().isEmpty) {
      setState(() =>
          _error = 'پیش از پیوستن به بازی، نام نمایشی خود را در پروفایل وارد کنید.');
      return;
    }

    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => QrScannerPage(
          onManualEntry: () => Navigator.of(context).pop(),
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || raw == null || raw.isEmpty) return;

    _handleScannedQr(raw);
  }

  /// Handle scanned text: parse, validate and ask for confirmation.
  void _handleScannedQr(String raw) {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      setState(() => _error = 'QR Code نامعتبر است؛ ساختار دادهٔ آن قابل تجزیه نیست.');
      return;
    }

    final controller = GameScope.read(context);
    if (!controller.qrPayloadValid(payload)) {
      String reason = 'QR Code نامعتبر است.';
      if (controller.sessionFinished) {
        reason = 'این نشست بازی به‌صورت رسمی تمام شده است و QR آن نامعتبر است.';
      } else {
        final gameId = payload['gameId'] as String?;
        final token = payload['token'] as String?;
        if (gameId == null || gameId.isEmpty) {
          reason = 'شناسه بازی در QR معتبر نیست.';
        } else if (token == null || token.isEmpty) {
          reason = 'توکن اتصال در QR معتبر نیست.';
        } else if (gameId != controller.gameId ||
            token != controller.joinToken) {
          reason = 'این QR مربوط به نشست بازی دیگری است یا منقضی شده است.';
        }
      }
      setState(() => _error = reason);
      return;
    }

    // Show the game and host details before connecting; the user must confirm.
    final hostName = payload['hostName'] as String? ?? 'میزبان';
    final host = payload['host'] as String? ?? '';
    final port =
        (payload['port'] as num?)?.toInt() ??
        GameController.defaultHostPort;
    final gameId = payload['gameId'] as String?;
    final token = payload['token'] as String?;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تایید اتصال به بازی'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('بازی: $hostName', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('میزبان: $host', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('پورت: $port', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            Text(
              'آیا از اتصال به این بازی اطمینان دارید؟',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('اتصال'),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (!mounted || confirmed != true) return;
      await _connectFromScannedQr(
        address: host,
        port: port,
        gameId: gameId ?? '*',
        token: token ?? '',
        hostName: hostName,
      );
    });
  }

  /// Connect using the QR data, with the fields pre-filled.
  Future<void> _connectFromScannedQr({
    required String address,
    required int port,
    required String gameId,
    required String token,
    String hostName = '',
  }) async {
    final controller = GameScope.read(context);
    setState(() {
      _connecting = true;
      _error = null;
    });
    // Pre-fill the manual fields so the user can review and edit them.
    _addressController.text = address;
    _portController.text = port.toString();
    _codeController.text = token;

    final ok = await controller.joinGame(
      address: address,
      port: port,
      gameId: gameId,
      token: token,
      hostName: hostName,
    );
    if (!mounted) return;
    setState(() => _connecting = false);
    if (!ok) {
      setState(() => _error = controller.lastError ?? 'اتصال برقرار نشد.');
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LobbyScreen()),
    );
  }

  Future<void> _connectManual() async {
    final address = _addressController.text.trim();
    final code = _codeController.text.trim().toUpperCase();
    final portText = _portController.text.trim();
    final port = portText.isEmpty
        ? 0
        : int.tryParse(faToEnDigits(portText)) ?? 0;
    if (address.isEmpty || code.isEmpty) {
      setState(() => _error = 'آدرس میزبان و کد اتصال را وارد کنید.');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'کد اتصال ۶ نویسه است.');
      return;
    }
    await _connect(
      address: address,
      port: port == 0 ? GameController.defaultHostPort : port,
      gameId: '*',
      token: code,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پیوستن به بازی')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.rejected.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.rejected.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
            ],
            SectionCard(
              title: 'بازی‌های پیدا‌شده',
              trailing: IconButton(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'جست‌وجوی دوباره',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_scanning)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'در حال جست‌وجوی میزبان در شبکهٔ محلی…',
                            style: TextStyle(
                              fontFamily: 'Vazirmatn',
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_hosts.isEmpty)
                    Text(
                      _scanned
                          ? 'بازی‌ای پیدا نشد. مطمئن شوید هر دو گوشی به یک Hotspot یا Wi-Fi '
                              'وصل‌اند و میزبان بازی را ساخته است. می‌توانید با آدرس و کد، '
                              'دستی وصل شوید یا QR را اسکن کنید.'
                          : 'برای جست‌وجو، دکمهٔ بالا را بزنید.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ..._hosts.map(
                      (host) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            title: Text(host.gameName),
                            subtitle: Text(
                              'میزبان: ${host.hostName} • '
                              '${faNum(host.playerCount)} بازیکن • '
                              '${faNum(host.address)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: _connecting
                                ? null
                                : () async {
                                    if (host.token == null) {
                                      setState(() {
                                        _addressController.text = host.address;
                                        _portController.text = host.port
                                            .toString();
                                        _error = 'این میزبان ورود سریع را خاموش کرده است؛ کد اتصال را از او بگیرید.';
                                      });
                                      return;
                                    }
                                    await _connect(
                                      address: host.address,
                                      port: host.port,
                                      gameId: host.gameId,
                                      token: host.token!,
                                      hostName: host.hostName,
                                    );
                                  },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'اسکن QR Code',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'دوربین را روی QR کد میزبان قرار دهید. پس از اسکن موفق، '
                    'اطلاعات اتصال به‌صورت خودکار تکمیل شده و قبل از اتصال '
                    'اطلاعات بازی و میزبان به شما نمایش داده می‌شود.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _connecting ? null : _scanQrCode,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 22),
                      label: const Text('اسکن QR Code'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اگر مجوز دوربین رد شود یا دوربین در دسترس نباشد، '
                    'می‌توانید از روش ورود دستی استفاده کنید.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'ورود دستی',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _addressController,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'آدرس میزبان (مثلاً ۱۹۲.۱۶۸.۴۳.۱)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textDirection: TextDirection.ltr,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'کد اتصال (۶ نویسه)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 108,
                        child: TextField(
                          controller: _portController,
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'پورت',
                            hintText: '۵۰۵۰۱',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _connecting ? null : _connectManual,
                    icon: const Icon(Icons.link_rounded, size: 20),
                    label: const Text('اتصال'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'برای بازی، یک نفر Hotspot گوشی خود را روشن می‌کند و بقیه به آن وصل می‌شوند؛ '
              'یا همه به یک Wi-Fi مشترک وصل می‌شوند. برنامه خودش میزبان را در همان شبکه '
              'پیدا می‌کند و درخواست مجوز اینترنت به معنی ارتباط با اینترنت نیست.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_connecting) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ],
        ),
      ),
    );
  }
}

/// Scanner failure states that need a Persian fallback UI.
@visibleForTesting
enum ScannerFailure { none, permissionDenied, unsupported }

/// Classify a scanner error: a denied camera permission is recoverable through
/// the system settings, anything else means the camera is unusable here.
@visibleForTesting
ScannerFailure scannerFailureFrom(Object error) {
  final text = error.toString().toLowerCase();
  final denied =
      text.contains('permission') ||
      text.contains('denied') ||
      text.contains('notauthorized') ||
      text.contains('not authorized');
  return denied ? ScannerFailure.permissionDenied : ScannerFailure.unsupported;
}

/// Persian explanation for a scanner failure, paired with the manual-entry
/// fallback that must always stay available.
@visibleForTesting
String scannerFailureMessage(ScannerFailure failure) {
  switch (failure) {
    case ScannerFailure.permissionDenied:
      return 'مجوز دوربین داده نشده است. برای اسکن QR، مجوز دوربین را از '
          'تنظیمات برنامه فعال کنید.';
    case ScannerFailure.unsupported:
      return 'دوربین در این دستگاه در دسترس نیست.';
    case ScannerFailure.none:
      return 'دوربین را روی QR کد قرار دهید';
  }
}

/// Camera-based QR scan screen.
///
/// A denied camera permission or an unavailable camera does not surface a raw
/// plugin error: the page switches to a Persian explanation with a
/// "manual entry" action, so QR stays an optional joining path.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key, this.onManualEntry});

  /// Called when the user chooses manual address/code entry instead.
  final VoidCallback? onManualEntry;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  MobileScannerController? _scannerController;
  bool _hasResult = false;
  ScannerFailure _failure = ScannerFailure.none;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(autoStart: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScanner());
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  /// Starts the camera and turns permission/availability errors into a
  /// user-facing Persian state instead of an unhandled plugin error.
  Future<void> _startScanner() async {
    final controller = _scannerController;
    if (controller == null || !mounted) return;
    try {
      await controller.start();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _failure = scannerFailureFrom(error));
    }
  }

  Widget _failureView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 44,
              color: AppColors.warning,
            ),
            const SizedBox(height: 10),
            Text(
              scannerFailureMessage(_failure),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                final fallback = widget.onManualEntry;
                if (fallback != null) fallback();
                if (mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.keyboard_rounded, size: 20),
              label: const Text('ورود دستی با آدرس و کد'),
            ),
          ],
        ),
      ),
    );
  }

  void _onBarcode(BarcodeCapture capture) {
    if (_hasResult) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _hasResult = true;
    _scannerController?.stop();
    if (mounted) Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اسکن QR Code'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: _failure == ScannerFailure.none
                ? MobileScanner(
                    controller: _scannerController,
                    onDetect: _onBarcode,
                  )
                : _failureView(context),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'دوربین را روی QR کد قرار دهید',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'اگر مجوز دوربین رد شده است، از ورود دستی استفاده کنید.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

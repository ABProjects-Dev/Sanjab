/// شناسایی خودکار میزبان در شبکهٔ محلی (UDP broadcast).
///
/// چرا Broadcast و نه mDNS؟ هر دو در اندروید کار می‌کنند، اما mDNS/NSD به سرویس
/// سیستمی و مجوزهای اضافی و پیاده‌سازی بومی نیاز دارد. روش UDP broadcast تنها با
/// مجوز INTERNET (که برای Socket لازم است) کار می‌کند، در Hotspot و Wi-Fi مشترک
/// یکسان عمل می‌کند و وابستگی بیرونی ندارد. اگر شبکه Broadcast را مسدود کند
/// (برخی روترها)، ورود دستی با آدرس IP و کد اتصال همیشه در دسترس است.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// پورت ثابت شناسایی (UDP).
const int kDiscoveryPort = 50507;

/// متن پروب شناسایی.
const String kProbeText = 'SANJAB_DISCOVER_V2';

/// یک میزبان شناسایی‌شده در شبکه.
class DiscoveredHost {
  const DiscoveredHost({
    required this.gameId,
    required this.gameName,
    required this.hostName,
    required this.address,
    required this.port,
    required this.openJoin,
    this.token,
    this.playerCount = 0,
  });

  final String gameId;
  final String gameName;
  final String hostName;
  final String address;
  final int port;

  /// آیا ورود بدون کد (فقط از شبکهٔ محلی) مجاز است.
  final bool openJoin;

  /// توکن اتصال؛ تنها در حالت [openJoin] ارسال می‌شود.
  final String? token;

  final int playerCount;

  Map<String, dynamic> toJson() => {
    'k': 'SM_HOST',
    'gid': gameId,
    'gn': gameName,
    'hn': hostName,
    'port': port,
    'open': openJoin,
    if (token != null) 'token': token,
    'pc': playerCount,
  };

  /// ساخت از پیام JSON؛ در صورت نامعتبر بودن null برمی‌گرداند.
  static DiscoveredHost? tryParse(String raw, {required String address}) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['k'] != 'SM_HOST') return null;
    final gameId = decoded['gid'];
    final port = decoded['port'];
    if (gameId is! String || gameId.isEmpty) return null;
    if (port is! int || port <= 0 || port > 65535) return null;
    final token = decoded['token'];
    return DiscoveredHost(
      gameId: gameId,
      gameName: decoded['gn'] as String? ?? 'بازی سنجاب',
      hostName: decoded['hn'] as String? ?? 'میزبان',
      address: address,
      port: port,
      openJoin: decoded['open'] == true,
      token: token is String && token.isNotEmpty ? token : null,
      playerCount: (decoded['pc'] as num?)?.toInt() ?? 0,
    );
  }
}

/// پاسخ‌دهندهٔ شناسایی روی دستگاه میزبان.
class DiscoveryBeacon {
  DiscoveryBeacon({
    required this.gameId,
    required this.gameName,
    required this.hostName,
    required this.port,
    required this.openJoin,
    this.token,
    this.playerCount = 0,
  });

  final String gameId;
  final String gameName;
  final String hostName;
  final int port;
  final bool openJoin;
  final String? token;
  int playerCount;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;

  bool get isRunning => _socket != null;

  /// شروع پاسخ‌دهی به پروب‌ها + ارسال دوره‌ای اعلان.
  Future<bool> start() async {
    if (_socket != null) return true;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kDiscoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _socket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true).trim();
        if (text != kProbeText) return;
        final payload = utf8.encode(_json());
        try {
          socket.send(payload, datagram.address, datagram.port);
        } catch (_) {}
      });
      _beaconTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _sendBeacon();
      });
      return true;
    } catch (_) {
      // اگر پورت شناسایی در دسترس نبود، بازی با ورود دستی ادامه می‌یابد.
      _socket = null;
      return false;
    }
  }

  String _json() => jsonEncode(
    DiscoveredHost(
      gameId: gameId,
      gameName: gameName,
      hostName: hostName,
      address: '',
      port: port,
      openJoin: openJoin,
      token: openJoin ? token : null,
      playerCount: playerCount,
    ).toJson(),
  );

  void _sendBeacon() {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(
        utf8.encode(_json()),
        InternetAddress('255.255.255.255'),
        kDiscoveryPort,
      );
    } catch (_) {}
  }

  /// به‌روزرسانی تعداد بازیکنان (برای نمایش در فهرست اتصال).
  void updatePlayerCount(int count) => playerCount = count;

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _socket?.close();
    _socket = null;
  }
}

/// جست‌وجوی میزبان‌های فعال در شبکهٔ محلی.
Future<List<DiscoveredHost>> discoverHosts({
  Duration timeout = const Duration(milliseconds: 2500),
}) async {
  final found = <String, DiscoveredHost>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket!.receive();
      if (datagram == null) return;
      final host = DiscoveredHost.tryParse(
        utf8.decode(datagram.data, allowMalformed: true),
        address: datagram.address.address,
      );
      if (host != null) found[host.gameId] = host;
    });
    final probe = utf8.encode(kProbeText);
    try {
      socket.send(probe, InternetAddress('255.255.255.255'), kDiscoveryPort);
    } catch (_) {}
    // ارسال به آدرس Broadcast هر رابط شبکه (برای شبکه‌هایی که 255.255.255.255 را رد می‌کنند).
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final address in iface.addresses) {
          try {
            socket.send(probe, address, kDiscoveryPort);
          } catch (_) {}
        }
      }
    } catch (_) {}
    await Future<void>.delayed(timeout);
  } catch (_) {
    // در صورت خطا فهرست خالی برمی‌گردد و ورود دستی پیشنهاد می‌شود.
  } finally {
    socket?.close();
  }
  final list = found.values.toList(growable: false)
    ..sort((a, b) => a.gameName.compareTo(b.gameName));
  return list;
}

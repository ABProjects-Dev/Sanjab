/// Automatic host discovery on the local network (UDP broadcast).
///
/// Why broadcast instead of mDNS? mDNS/NSD needs a system service, extra
/// permissions and native code. UDP broadcast needs only INTERNET, behaves the
/// same on a hotspot and shared Wi-Fi, and adds no dependency. On networks that
/// block broadcast, manual address entry and QR codes remain available.
///
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fixed discovery port (UDP).
const int kDiscoveryPort = 50507;

/// Discovery probe text.
const String kProbeText = 'SANJAB_DISCOVER_V2';

/// A host discovered on the network.
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

  /// Whether open join (no code) is allowed on this network.
  final bool openJoin;

  /// Join token; only published when [openJoin] is enabled.
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

  /// Parse a JSON payload; returns null when it is not valid.
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

/// Discovery responder on the host device.
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

  /// Answer probes and send a periodic beacon.
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
      // If the discovery port is taken, the game continues with manual join.
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

  /// Update the player count shown in the join list.
  void updatePlayerCount(int count) => playerCount = count;

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Search for active hosts on the local network.
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
    // Dart exposes interface addresses but not IPv4 subnet masks, so a correct
    // per-interface directed-broadcast address cannot be derived here. Keep the
    // limited-broadcast probe above; QR/manual join remains the reliable fallback.
    await Future<void>.delayed(timeout);
  } catch (_) {
    // On error an empty list is returned and manual join is offered.
  } finally {
    socket?.close();
  }
  final list = found.values.toList(growable: false)
    ..sort((a, b) => a.gameName.compareTo(b.gameName));
  return list;
}

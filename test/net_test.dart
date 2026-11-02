/// آزمون شبکهٔ واقعی روی لوکال‌هاست (اتصال TCP، احراز دسترسی، تحویل پیام‌ها،
/// جلوگیری از پیام تکراری و اتصال مجدد).
///
/// این آزمون‌ها روی همان کدی اجرا می‌شوند که روی گوشی‌ها اجرا می‌شود؛ تنها
/// تفاوت، آدرس ۱۲۷.۰.۰.۱ به‌جای آدرس شبکهٔ محلی است.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/net/game_client.dart';
import 'package:sanjab/net/host_server.dart';
import 'package:sanjab/net/protocol.dart';

Future<bool> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return condition();
}

class RecordedHost {
  RecordedHost() {
    network = HostNetwork(
      gameId: 'g1',
      token: 'ABC123',
      callbacks: HostCallbacks(
        onHello: (request) async {
          hellos.add(request);
          if (request.playerId == 'blocked') {
            return const HelloDecision.reject('این بازیکن اجازهٔ ورود ندارد.');
          }
          return HelloDecision.accept(resumed: request.playerId == 'resume-me');
        },
        onAnswer: (playerId, round, category, text) =>
            answers.add('$playerId|$round|$category|$text'),
        onStop: (playerId, round) => stops.add('$playerId|$round'),
        onSnapshot: (playerId, round, answersMap) =>
            snapshots.add('$playerId|$round|${answersMap.length}'),
        onDisconnected: (playerId) => disconnects.add(playerId),
      ),
    );
  }

  late final HostNetwork network;
  final List<HelloRequest> hellos = <HelloRequest>[];
  final List<String> answers = <String>[];
  final List<String> stops = <String>[];
  final List<String> snapshots = <String>[];
  final List<String> disconnects = <String>[];

  Future<int> start() async {
    await network.start();
    return network.port;
  }
}

void main() {
  group('اتصال و احراز هویت', () {
    test('بازیکن با کد درست وصل می‌شود و پیام خوش‌آمد می‌گیرد', () async {
      final host = RecordedHost();
      final port = await host.start();
      final client = GameClient(
        hostAddress: '127.0.0.1',
        port: port,
        gameId: 'g1',
        token: 'ABC123',
        playerId: 'u1',
        displayName: 'سارا',
        autoReconnect: false,
      );
      final ok = await client.connect();
      expect(ok, isTrue);
      expect(client.isConnected, isTrue);
      expect(await waitUntil(() => host.hellos.isNotEmpty), isTrue);
      expect(host.hellos.single.playerId, 'u1');
      expect(host.hellos.single.displayName, 'سارا');
      await client.close();
      await host.network.stop();
    });

    test('کد اتصال نادرست پذیرفته نمی‌شود', () async {
      final host = RecordedHost();
      final port = await host.start();
      final client = GameClient(
        hostAddress: '127.0.0.1',
        port: port,
        gameId: 'g1',
        token: 'WRONG1',
        playerId: 'u1',
        displayName: 'سارا',
        autoReconnect: false,
      );
      final ok = await client.connect();
      expect(ok, isFalse);
      expect(client.lastError, contains('کد اتصال'));
      expect(host.network.rejectedConnections, greaterThan(0));
      await client.close();
      await host.network.stop();
    });

    test('میزبان می‌تواند بازیکن را رد کند', () async {
      final host = RecordedHost();
      final port = await host.start();
      final client = GameClient(
        hostAddress: '127.0.0.1',
        port: port,
        gameId: 'g1',
        token: 'ABC123',
        playerId: 'blocked',
        displayName: 'ناشناس',
        autoReconnect: false,
      );
      expect(await client.connect(), isFalse);
      expect(client.lastError, contains('اجازه'));
      await client.close();
      await host.network.stop();
    });

    test(
      'شناسهٔ بازی نامشخص (ورود دستی) با توکن درست پذیرفته می‌شود',
      () async {
        final host = RecordedHost();
        final port = await host.start();
        final client = GameClient(
          hostAddress: '127.0.0.1',
          port: port,
          gameId: '*',
          token: 'ABC123',
          playerId: 'u9',
          displayName: 'مینا',
          autoReconnect: false,
        );
        expect(await client.connect(), isTrue);
        await client.close();
        await host.network.stop();
      },
    );

    test('پیام بدون احراز هویت رد می‌شود', () async {
      final host = RecordedHost();
      final port = await host.start();
      final socket = await Socket.connect('127.0.0.1', port);
      socket.write(
        NetMessage(
          type: MsgType.answer,
          id: 'x1',
          seq: 1,
          payload: {'r': 1, 'c': 0, 't': 'تهران'},
        ).encode(),
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.answers, isEmpty);
      expect(host.network.connectedCount, 0);
      socket.destroy();
      await host.network.stop();
    });
  });

  group('تبادل پیام', () {
    test('وضعیت میزبان به بازیکن می‌رسد', () async {
      final host = RecordedHost();
      final port = await host.start();
      final client = GameClient(
        hostAddress: '127.0.0.1',
        port: port,
        gameId: 'g1',
        token: 'ABC123',
        playerId: 'u1',
        displayName: 'سارا',
        autoReconnect: false,
      );
      final states = <Map<String, dynamic>>[];
      client.messages.listen((message) {
        if (message.type == MsgType.state) states.add(message.payload);
      });
      expect(await client.connect(), isTrue);
      expect(
        host.network.sendState('u1', {
          'phase': 'playing',
          'round': 1,
          'letter': 'ب',
          'endEpochMs': DateTime.now().millisecondsSinceEpoch + 420000,
          'serverNow': DateTime.now().millisecondsSinceEpoch,
          'my': {'0': 'تهران'},
        }),
        isTrue,
      );
      expect(await waitUntil(() => states.isNotEmpty), isTrue);
      expect(states.first['letter'], 'ب');
      expect((states.first['my'] as Map)['0'], 'تهران');
      await client.close();
      await host.network.stop();
    });

    test('پاسخ، استپ و Snapshot بازیکن به میزبان می‌رسد', () async {
      final host = RecordedHost();
      final port = await host.start();
      final client = GameClient(
        hostAddress: '127.0.0.1',
        port: port,
        gameId: 'g1',
        token: 'ABC123',
        playerId: 'u1',
        displayName: 'سارا',
        autoReconnect: false,
      );
      expect(await client.connect(), isTrue);
      expect(client.sendAnswer(1, 2, 'تهران'), isTrue);
      expect(client.sendStop(1), isTrue);
      expect(client.sendSnapshot(1, {0: 'تهران', 1: 'رضایی'}), isTrue);
      expect(await waitUntil(() => host.answers.length == 1), isTrue);
      expect(await waitUntil(() => host.stops.length == 1), isTrue);
      expect(await waitUntil(() => host.snapshots.length == 1), isTrue);
      expect(host.answers.single, 'u1|1|2|تهران');
      expect(host.stops.single, 'u1|1');
      expect(host.snapshots.single, 'u1|1|2');
      await client.close();
      await host.network.stop();
    });

    test('پیام تکراری با همان شناسه فقط یک‌بار پردازش می‌شود', () async {
      final host = RecordedHost();
      final port = await host.start();
      final socket = await Socket.connect('127.0.0.1', port);
      final lines = <String>[
        NetMessage(
          type: MsgType.hello,
          id: 'h1',
          seq: 1,
          payload: {
            'gid': 'g1',
            'token': 'ABC123',
            'pid': 'u1',
            'name': 'سارا',
          },
        ).encode(),
        // همان پیام پاسخ با شناسهٔ یکسان، دو بار:
        NetMessage(
          type: MsgType.answer,
          id: 'dup',
          seq: 2,
          payload: {'r': 1, 'c': 0, 't': 'تهران'},
        ).encode(),
        NetMessage(
          type: MsgType.answer,
          id: 'dup',
          seq: 3,
          payload: {'r': 1, 'c': 0, 't': 'مشهد'},
        ).encode(),
      ];
      for (final line in lines) {
        socket.write(line);
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(await waitUntil(() => host.answers.isNotEmpty), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.answers, ['u1|1|0|تهران']);
      socket.destroy();
      await host.network.stop();
    });

    test('پیام نامعتبر اتصال را قطع نمی‌کند', () async {
      final host = RecordedHost();
      final port = await host.start();
      final socket = await Socket.connect('127.0.0.1', port);
      socket.write('این یک پیام نامعتبر است\n');
      await socket.flush();
      socket.write(
        NetMessage(
          type: MsgType.hello,
          id: 'h1',
          seq: 1,
          payload: {
            'gid': 'g1',
            'token': 'ABC123',
            'pid': 'u2',
            'name': 'مینا',
          },
        ).encode(),
      );
      await socket.flush();
      expect(await waitUntil(() => host.hellos.length == 1), isTrue);
      socket.destroy();
      await host.network.stop();
    });

    test('پیام‌های فقط-میزبان از بازیکن پذیرفته نمی‌شوند', () async {
      final host = RecordedHost();
      final port = await host.start();
      final socket = await Socket.connect('127.0.0.1', port);
      socket.write(
        NetMessage(
          type: MsgType.hello,
          id: 'h1',
          seq: 1,
          payload: {
            'gid': 'g1',
            'token': 'ABC123',
            'pid': 'u3',
            'name': 'لیلا',
          },
        ).encode(),
      );
      await socket.flush();
      await waitUntil(() => host.hellos.length == 1);
      // تلاش برای جعل پیام «وضعیت» و «نتیجهٔ داوری» از سمت بازیکن.
      socket.write(
        NetMessage(
          type: MsgType.state,
          id: 's1',
          seq: 2,
          payload: {'phase': 'roundResults'},
        ).encode(),
      );
      socket.write(
        NetMessage(
          type: MsgType.results,
          id: 's2',
          seq: 3,
          payload: {
            'totals': {'u3': 999},
          },
        ).encode(),
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.answers, isEmpty);
      expect(host.stops, isEmpty);
      expect(host.snapshots, isEmpty);
      socket.destroy();
      await host.network.stop();
    });
  });

  group('قطع و اتصال مجدد', () {
    test('قطع اتصال بازیکن به میزبان اعلام می‌شود', () async {
      final host = RecordedHost();
      final port = await host.start();
      final client = GameClient(
        hostAddress: '127.0.0.1',
        port: port,
        gameId: 'g1',
        token: 'ABC123',
        playerId: 'u1',
        displayName: 'سارا',
        autoReconnect: false,
      );
      expect(await client.connect(), isTrue);
      await waitUntil(() => host.network.connectedCount == 1);
      await client.close();
      expect(await waitUntil(() => host.disconnects.contains('u1')), isTrue);
      expect(host.network.connectedCount, 0);
      await host.network.stop();
    });

    test(
      'اتصال مجدد همان بازیکن به‌عنوان ادامهٔ نشست پذیرفته می‌شود',
      () async {
        final host = RecordedHost();
        final port = await host.start();
        Future<GameClient> connectAsResumed() async {
          final client = GameClient(
            hostAddress: '127.0.0.1',
            port: port,
            gameId: 'g1',
            token: 'ABC123',
            playerId: 'resume-me',
            displayName: 'سارا',
            autoReconnect: false,
          );
          expect(await client.connect(), isTrue);
          return client;
        }

        final first = await connectAsResumed();
        await first.close();
        await waitUntil(() => host.network.connectedCount == 0);
        final second = await connectAsResumed();
        expect(await waitUntil(() => host.hellos.length == 2), isTrue);
        expect(host.network.connectedCount, 1);
        await second.close();
        await host.network.stop();
      },
    );

    test('سه بازیکن هم‌زمان می‌توانند وصل شوند', () async {
      final host = RecordedHost();
      final port = await host.start();
      final clients = <GameClient>[];
      for (var i = 1; i <= 3; i++) {
        final client = GameClient(
          hostAddress: '127.0.0.1',
          port: port,
          gameId: 'g1',
          token: 'ABC123',
          playerId: 'u$i',
          displayName: 'بازیکن $i',
          autoReconnect: false,
        );
        expect(await client.connect(), isTrue);
        clients.add(client);
      }
      expect(await waitUntil(() => host.network.connectedCount == 3), isTrue);
      for (final client in clients) {
        client.sendSnapshot(1, {0: 'تهران'});
      }
      expect(await waitUntil(() => host.snapshots.length == 3), isTrue);
      for (final client in clients) {
        await client.close();
      }
      await host.network.stop();
    });
  });
}

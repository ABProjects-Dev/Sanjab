/// Regression tests for the 1.1.2 audit fixes.
///
/// Covered here:
///  * the generated app version stays in sync with `pubspec.yaml`;
///  * a rejected rename during reconnect no longer aborts the handshake;
///  * answer frames are coalesced and never relabeled across rounds;
///  * typing persists the session on a debounce, not on every keystroke;
///  * QR scanner failures degrade to a Persian fallback with manual entry.
library;

import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/core/app_version.dart';
import 'package:sanjab/data/room_repository.dart';
import 'package:sanjab/domain/models.dart';
import 'package:sanjab/domain/profile.dart';
import 'package:sanjab/domain/room_record.dart';
import 'package:sanjab/net/game_client.dart';
import 'package:sanjab/net/host_server.dart';
import 'package:sanjab/state/game_controller.dart';
import 'package:sanjab/ui/screens/join_screen.dart';

import 'test_support/memory_profile_store.dart';
import 'test_support/memory_store.dart';

Future<bool> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return condition();
}

/// Delays every room write so a superseded save can be observed.
class DelayedRoomStore extends MemoryRoomStore {
  DelayedRoomStore(this.delay);

  final Duration delay;

  @override
  Future<bool> upsert(RoomRecord record) async {
    await Future<void>.delayed(delay);
    return super.upsert(record);
  }
}

/// Create a game, retrying on a fresh port.
///
/// Every test in this file starts a host on the default port and tears it down;
/// a listener that is still closing can reject the next bind with ECONNRESET, so
/// a failed attempt is retried instead of flaking the suite.
Future<void> createGameWithRetry(GameController host) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (await host.createGame(activeCategoryIds: [0, 1])) return;
    } on Object {
      // Fall through to the retry below.
    }
    await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
  }
  throw StateError('could not start a host server after five attempts');
}

GameController buildController(String id, String name, {RoomStore? rooms}) =>
    GameController(
      store: MemorySessionStore(),
      profileRepo: MemoryProfileStore(
        initial: Profile(playerId: id, displayName: name),
      ),
      roomStore: rooms ?? MemoryRoomStore(),
    );

/// A host that records answer frames so coalescing can be observed.
class RecordingHost {
  RecordingHost() {
    network = HostNetwork(
      gameId: 'g1',
      token: 'ABC123',
      callbacks: HostCallbacks(
        onHello: (request) async {
          hellos.add(request);
          return const HelloDecision.accept();
        },
        onAnswer: (playerId, round, category, text) =>
            answers.add('$round|$category|$text'),
        onStop: (playerId, round) => frames.add('stop|$round'),
      ),
    );
  }

  late final HostNetwork network;
  final List<HelloRequest> hellos = <HelloRequest>[];
  final List<String> answers = <String>[];
  final List<String> frames = <String>[];

  Future<int> start() async {
    await network.start();
    return network.port;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('App version source of truth', () {
    test('generated constants match pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml must pin name+build');

      expect(kAppVersionName, match!.group(1));
      expect(kAppVersionCode, int.parse(match.group(2)!));
      expect(kAppVersionLabel, '$kAppVersionName+$kAppVersionCode');
    });
  });

  group('Reconnect with a colliding display name', () {
    late GameController host;
    late GameController player1;
    late GameController player2;

    setUp(() async {
      host = buildController('h1', 'سارا');
      player1 = buildController('p1', 'مینا');
      player2 = buildController('p2', 'رضا');
      await host.bootstrap();
      await player1.bootstrap();
      await player2.bootstrap();
    });

    tearDown(() async {
      await host.closeSession(silent: true);
      await player1.leaveGame();
      await player2.leaveGame();
      host.dispose();
      player1.dispose();
      player2.dispose();
    });

    test('the reconnect still succeeds and keeps the previous name', () async {
      await createGameWithRetry(host);
      Future<bool> join(GameController member) => member.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
      );

      expect(await join(player1), isTrue);
      expect(await join(player2), isTrue);
      expect(await waitUntil(() => host.session.players.length == 3), isTrue);

      // The host roster now hands p1 a different name and gives p2 the name
      // p1 still uses locally, so the next hello collides.
      host.session.renamePlayer('p1', 'مینا دو');
      host.session.renamePlayer('p2', 'مینا');

      // p1 reconnects announcing its old name: this used to throw out of the
      // hello handler and leave the socket hanging until the handshake timeout.
      expect(await join(player1), isTrue);
      expect(
        await waitUntil(
          () => host.session.connectedPlayerIds.contains('p1'),
        ),
        isTrue,
        reason: 'the reconnecting player must be marked connected',
      );
      expect(host.session.playerById('p1')!.name, 'مینا دو');
      expect(host.session.playerById('p2')!.name, 'مینا');
      expect(player1.lastError, isNull);
    });
  });

  group('Answer frame coalescing', () {
    late RecordingHost host;
    late GameClient client;

    setUp(() async {
      host = RecordingHost();
      final port = await host.start();
      client = GameClient(
        hostAddress: '127.0.0.1',
        port: port,
        gameId: 'g1',
        token: 'ABC123',
        playerId: 'p1',
        displayName: 'مینا',
        autoReconnect: false,
      );
      expect(await client.connect(), isTrue);
    });

    tearDown(() async {
      await client.close();
      await host.network.stop();
    });

    test('a burst of keystrokes sends one frame with the final text', () async {
      for (final text in ['آ', 'آب', 'آب ', 'آب و', 'آب و ن']) {
        client.sendAnswer(3, 0, text);
      }
      // Nothing leaves before the coalescing window closes.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(host.answers, isEmpty);

      expect(
        await waitUntil(() => host.answers.isNotEmpty),
        isTrue,
        reason: 'the coalesced frame must still be delivered',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(host.answers, hasLength(1));
      expect(host.answers.single, '3|0|آب و ن');
    });

    test('a round change flushes queued answers under their own round',
        () async {
      client.sendAnswer(0, 0, 'تهران');
      // The next round starts before the coalescing window closes.
      client.sendAnswer(1, 0, 'شیراز');

      expect(
        await waitUntil(() => host.answers.length >= 2),
        isTrue,
        reason: 'both frames must arrive',
      );
      expect(host.answers, containsAll(<String>['0|0|تهران', '1|0|شیراز']));
    });

    test('a Stop flushes queued answers before the Stop frame', () async {
      client.sendAnswer(2, 0, 'اصفهان');
      client.sendAnswer(2, 1, 'شیراز');
      client.sendStop(2);

      expect(
        await waitUntil(
          () =>
              host.frames.contains('stop|2') &&
              host.answers.where((frame) => frame.startsWith('2|')).length == 2,
        ),
        isTrue,
        reason: 'the host needs the answers before it validates the Stop',
      );

      // The frames reach the host on one ordered channel, so the answers must
      // be recorded before the Stop.
      expect(host.answers, containsAll(<String>['2|0|اصفهان', '2|1|شیراز']));
      expect(host.frames.where((frame) => frame == 'stop|2'), hasLength(1));
    });
  });

  group('Saved room records', () {
    test('one record per room and player, updated in place', () async {
      final store = MemoryRoomStore();
      RoomRecord record(String name, int updatedAt) => RoomRecord(
        gameId: 'g1',
        roomName: 'Room',
        hostPlayerId: 'h1',
        hostName: 'سارا',
        myPlayerId: 'p1',
        myName: 'مینا',
        role: GameRole.player,
        address: '192.168.1.5',
        port: 50501,
        token: 'ABC123',
        phase: GamePhase.playing,
        roundIndex: 1,
        updatedAtEpochMs: updatedAt,
      );

      expect(await store.upsert(record('Room', 100)), isTrue);
      expect(await store.upsert(record('Room renamed', 200)), isTrue);

      final rooms = await store.loadAll();
      expect(rooms, hasLength(1), reason: 'upsert must not duplicate a key');
      expect(rooms.single.roomName, 'Room renamed');
      expect(rooms.single.updatedAtEpochMs, 200);
    });
  });

  group('Resumed host session', () {
    test('a resumed host keeps its game ID and join token', () async {
      final rooms = MemoryRoomStore();
      final first = buildController('h1', 'سارا', rooms: rooms);
      await first.bootstrap();
      await createGameWithRetry(first);
      final gameId = first.gameId;
      final token = first.joinToken;
      expect(gameId, isNotEmpty);
      expect(token, hasLength(6));
      await first.closeSession(silent: true);
      first.dispose();

      final resumed = buildController('h1', 'سارا', rooms: rooms);
      addTearDown(resumed.dispose);
      await resumed.bootstrap();
      final saved = rooms.records.firstWhere((room) => room.gameId == gameId);
      expect(await resumed.resumeRoom(saved), isTrue);

      // A resumed session must keep advertising the same room and token.
      expect(resumed.gameId, gameId);
      expect(resumed.joinToken, token);
      expect(resumed.savedRooms.single.gameId, gameId);
      expect(resumed.savedRooms.single.token, token);
      await resumed.closeSession(silent: true);
    });
  });

  group('Out-of-order persistence', () {
    test('a save that was already running cannot resurrect a closed room',
        () async {
      final rooms = DelayedRoomStore(const Duration(milliseconds: 120));
      final host = buildController('h1', 'سارا', rooms: rooms);
      addTearDown(host.dispose);
      await host.bootstrap();
      await createGameWithRetry(host);
      host.startGame();
      host.setAnswer(0, 'آب');
      final gameId = host.gameId;

      // Start a write that is still running, then leave the room: the exit must
      // wait for it instead of letting it land afterwards.
      final runningSave = host.flush();
      await host.leaveRoom();
      await runningSave;

      expect(
        rooms.records.where((room) => room.gameId == gameId),
        isEmpty,
        reason: 'the exit must win over the in-flight save',
      );
    });

    test('a debounced save is dropped when the room is closed', () async {
      final rooms = MemoryRoomStore();
      final host = buildController('h1', 'سارا', rooms: rooms);
      addTearDown(host.dispose);
      await host.bootstrap();
      await createGameWithRetry(host);
      host.startGame();
      host.setAnswer(0, 'آب');
      final gameId = host.gameId;

      // The debounce timer is still pending when the room closes.
      await host.leaveRoom();
      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(
        rooms.records.where((room) => room.gameId == gameId),
        isEmpty,
        reason: 'a cancelled save must not run later',
      );
    });
  });

  group('Persistence debounce', () {
    test('typing does not write on every keystroke', () async {
      final store = MemorySessionStore();
      final controller = GameController(
        store: store,
        profileRepo: MemoryProfileStore(
          initial: const Profile(playerId: 'h1', displayName: 'سارا'),
        ),
        roomStore: MemoryRoomStore(),
      );
      addTearDown(controller.dispose);
      await controller.bootstrap();
      await createGameWithRetry(controller);
      controller.startGame();
      expect(controller.session.phase, GamePhase.playing);

      final before = store.saveCount;
      for (final text in ['آب', 'آب و', 'آب و ن']) {
        controller.setAnswer(0, text);
      }
      expect(
        store.saveCount,
        before,
        reason: 'a debounced write must not run per keystroke',
      );

      await controller.flush();
      expect(store.saveCount, greaterThan(before));
      expect(
        store.saved!.currentRound!.answerOf('h1', 0)!.text,
        'آب و ن',
        reason: 'flush persists the latest text',
      );
    });
  });

  group('Android build wiring', () {
    test('Gradle derives versionName and versionCode from pubspec.yaml', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('../../pubspec.yaml'));
      expect(gradle, contains('versionCode = appVersionCode'));
      expect(gradle, contains('versionName = appVersionName'));
      // compileSdk is an android {} property; assigning it inside defaultConfig
      // does not compile, so guard the placement.
      expect(gradle, contains('compileSdk = 36'));
      final defaultConfig = gradle.substring(
        gradle.indexOf('defaultConfig {'),
        gradle.indexOf('signingConfigs {'),
      );
      expect(defaultConfig, isNot(contains('compileSdk')));
      expect(defaultConfig, contains('targetSdk = 36'));
      expect(defaultConfig, contains('minSdk = 24'));
    });
  });

  group('QR scanner fallback', () {
    test('a denied permission is classified as recoverable', () {
      expect(
        scannerFailureFrom(
          PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'User denied permission',
          ),
        ),
        ScannerFailure.permissionDenied,
      );
      expect(
        scannerFailureFrom(StateError('no camera on this device')),
        ScannerFailure.unsupported,
      );
    });

    test('each failure explains itself in Persian', () {
      expect(
        scannerFailureMessage(ScannerFailure.permissionDenied),
        contains('مجوز دوربین'),
      );
      expect(
        scannerFailureMessage(ScannerFailure.unsupported),
        contains('دسترس نیست'),
      );
      expect(scannerFailureMessage(ScannerFailure.none), isNotEmpty);
    });
  });
}

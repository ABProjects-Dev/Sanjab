import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/data/room_repository.dart';
import 'package:sanjab/data/session_repository.dart';
import 'package:sanjab/domain/game_session.dart';
import 'package:sanjab/domain/models.dart';
import 'package:sanjab/domain/room_record.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sanjab_storage_queue');
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  GameSession sessionWithPlayers(List<String> names) {
    final session = GameSession.fresh(nowMs: 1000);
    for (final name in names) {
      session.addPlayer(name);
    }
    session.startNewRound(nowMs: 2000);
    return session;
  }

  RoomRecord room(String gameId, int updatedAt) => RoomRecord(
    gameId: gameId,
    roomName: 'Room $gameId',
    hostPlayerId: 'host-$gameId',
    hostName: 'Host',
    myPlayerId: 'player-$gameId',
    myName: 'Player',
    role: GameRole.player,
    address: '192.168.1.2',
    port: 50501,
    token: 'TOK123',
    phase: GamePhase.playing,
    roundIndex: 1,
    updatedAtEpochMs: updatedAt,
  );

  test('concurrent session saves preserve the latest requested snapshot', () async {
    final repository = SessionRepository(directory);
    final older = sessionWithPlayers(['First']);
    final newer = sessionWithPlayers(['First', 'Second']);

    final results = await Future.wait([
      repository.save(older, nowMs: 10),
      repository.save(newer, nowMs: 20),
    ]);

    expect(results, everyElement(isTrue));
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.players.map((player) => player.name), ['First', 'Second']);
    expect(loaded.savedAtEpochMs, 20);
  });

  test('concurrent room mutations do not overwrite one another', () async {
    final repository = RoomRepository(directory);

    final results = await Future.wait([
      repository.upsert(room('room-a', 10)),
      repository.upsert(room('room-b', 20)),
    ]);

    expect(results, everyElement(isTrue));
    final loaded = await RoomRepository(directory).loadAll();
    expect(loaded.map((record) => record.gameId).toSet(), {'room-a', 'room-b'});
  });
}

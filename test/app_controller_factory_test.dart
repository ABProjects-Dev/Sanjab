import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/app_controller_factory.dart';
import 'package:sanjab/domain/models.dart';
import 'package:sanjab/domain/room_record.dart';

void main() {
  test('production composition restores a saved player room after restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sanjab_controller_restart',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    final firstRun = createProductionGameController(directory);
    await firstRun.bootstrap();
    await firstRun.roomStore.upsert(
      RoomRecord(
        gameId: 'saved-game',
        roomName: 'Saved room',
        hostPlayerId: 'host-1',
        hostName: 'Host',
        myPlayerId: 'player-1',
        myName: 'Player',
        role: GameRole.player,
        address: '192.168.1.2',
        port: 50501,
        token: 'TOK123',
        phase: GamePhase.playing,
        roundIndex: 2,
        updatedAtEpochMs: 100,
      ),
    );
    firstRun.dispose();

    final afterRestart = createProductionGameController(directory);
    addTearDown(afterRestart.dispose);
    await afterRestart.bootstrap();

    expect(afterRestart.savedRooms, hasLength(1));
    expect(afterRestart.savedRooms.single.gameId, 'saved-game');
    expect(afterRestart.hasResumableRoom, isTrue);
  });
}

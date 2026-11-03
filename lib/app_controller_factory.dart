/// Creates the production controller and its file-backed repositories.
library;

import 'dart:io';

import 'data/profile_repository.dart';
import 'data/room_repository.dart';
import 'data/session_repository.dart';
import 'state/game_controller.dart';

GameController createProductionGameController(Directory dataDirectory) {
  return GameController(
    store: SessionRepository(dataDirectory),
    profileRepo: ProfileRepository(dataDirectory),
    roomStore: RoomRepository(dataDirectory),
  );
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/core/serial_task_queue.dart';

void main() {
  test('does not start a second task before the first one finishes', () async {
    final queue = SerialTaskQueue();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final events = <String>[];

    final first = queue.run(() async {
      events.add('first-start');
      firstStarted.complete();
      await releaseFirst.future;
      events.add('first-end');
      return 1;
    });
    await firstStarted.future;

    final second = queue.run(() async {
      events.add('second');
      return 2;
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);

    releaseFirst.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(events, ['first-start', 'first-end', 'second']);
  });

  test('a failed task does not block the next task', () async {
    final queue = SerialTaskQueue();
    final failed = queue.run<int>(() async => throw StateError('expected'));
    final next = queue.run(() async => 'completed');

    await expectLater(failed, throwsA(isA<StateError>()));
    expect(await next, 'completed');
  });
}

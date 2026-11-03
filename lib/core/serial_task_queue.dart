/// Runs asynchronous tasks one at a time while allowing each task's result to
/// be observed independently. A failed task does not prevent later tasks.
library;

import 'dart:async';

class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then<T>((_) => task());
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

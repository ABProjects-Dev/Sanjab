/// آزمون پروتکل پیام‌ها: ساخت، اعتبارسنجی، جلوگیری از تکرار و ترتیب.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shotormorgh/net/discovery.dart';
import 'package:shotormorgh/net/protocol.dart';

void main() {
  group('ساخت و خواندن پیام', () {
    test('پیام ساخته‌شده با همان محتوا خوانده می‌شود', () {
      final message = NetMessage(
        type: MsgType.answer,
        id: 'm1',
        seq: 3,
        payload: {'r': 1, 'c': 2, 't': 'تهران'},
      );
      final parsed = NetMessage.parse(message.encode().trim());
      expect(parsed.type, MsgType.answer);
      expect(parsed.id, 'm1');
      expect(parsed.seq, 3);
      expect(parsed.payload['t'], 'تهران');
    });

    test('نسخهٔ ناسازگار رد می‌شود', () {
      final json = jsonEncode({
        'v': 99,
        't': 'answer',
        'id': 'a',
        'q': 1,
        'p': <String, dynamic>{},
      });
      expect(
        () => NetMessage.parse(json),
        throwsA(
          isA<ProtocolException>().having(
            (e) => e.message,
            'message',
            contains('سازگار نیست'),
          ),
        ),
      );
    });

    test('نوع ناشناخته و JSON خراب رد می‌شوند', () {
      expect(
        () => NetMessage.parse('{"v":2,"t":"hack","id":"a","q":1}'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => NetMessage.parse('not-json'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => NetMessage.parse('{"v":2}'),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('شناسهٔ خالی و شمارهٔ ترتیب نامعتبر رد می‌شوند', () {
      expect(
        () => NetMessage.parse('{"v":2,"t":"ping","id":"","q":1}'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => NetMessage.parse('{"v":2,"t":"ping","id":"x","q":-1}'),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('پیام بزرگ‌تر از حد مجاز رد می‌شود', () {
      final huge = 'x' * (kMaxMessageBytes + 10);
      expect(() => NetMessage.parse(huge), throwsA(isA<ProtocolException>()));
    });
  });

  group('جلوگیری از پردازش تکراری', () {
    test('پیام تکراری تنها یک‌بار پذیرفته می‌شود', () {
      final deduper = MessageDeduper(capacity: 4);
      expect(deduper.accept('a'), isTrue);
      expect(deduper.accept('a'), isFalse);
      expect(deduper.accept('b'), isTrue);
    });

    test('ظرفیت محدود، قدیمی‌ها را دور می‌ریزد', () {
      final deduper = MessageDeduper(capacity: 2);
      deduper.accept('a');
      deduper.accept('b');
      deduper.accept('c');
      expect(deduper.length, 2);
      expect(deduper.accept('a'), isTrue);
    });

    test('شمارهٔ ترتیب قدیمی یا تکراری پذیرفته نمی‌شود', () {
      final guard = SequenceGuard();
      expect(guard.accept(5), isTrue);
      expect(guard.accept(5), isFalse);
      expect(guard.accept(4), isFalse);
      expect(guard.accept(6), isTrue);
    });
  });

  group('پیام شناسایی میزبان', () {
    test('پیام معتبر شناسایی خوانده می‌شود', () {
      final host = DiscoveredHost.tryParse(
        jsonEncode({
          'k': 'SM_HOST',
          'gid': 'g1',
          'gn': 'بازی سارا',
          'hn': 'سارا',
          'port': 50501,
          'open': true,
          'token': 'ABC123',
          'pc': 3,
        }),
        address: '192.168.43.1',
      );
      expect(host, isNotNull);
      expect(host!.port, 50501);
      expect(host.openJoin, isTrue);
      expect(host.token, 'ABC123');
      expect(host.address, '192.168.43.1');
    });

    test('پیام نامعتبر یا پورت غیرمجاز نادیده گرفته می‌شود', () {
      expect(DiscoveredHost.tryParse('{}', address: 'x'), isNull);
      expect(
        DiscoveredHost.tryParse(
          jsonEncode({'k': 'SM_HOST', 'gid': 'g1', 'port': 0}),
          address: 'x',
        ),
        isNull,
      );
      expect(DiscoveredHost.tryParse('hello', address: 'x'), isNull);
    });

    test('در حالت ورود با کد، توکن در پیام شناسایی منتشر نمی‌شود', () {
      final host = DiscoveredHost.tryParse(
        jsonEncode({
          'k': 'SM_HOST',
          'gid': 'g1',
          'gn': 'بازی',
          'hn': 'سارا',
          'port': 50501,
          'open': false,
        }),
        address: 'x',
      );
      expect(host!.token, isNull);
      expect(host.openJoin, isFalse);
    });
  });
}

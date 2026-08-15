import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/common/face_login.dart';

void main() {
  group('passcodeHashOf / passcodeMatches', () {
    test('same code produces same hash, different codes differ', () {
      final h1 = passcodeHashOf('1234');
      final h2 = passcodeHashOf('1234');
      final h3 = passcodeHashOf('12345');
      expect(h1, h2);
      expect(h1, isNot(h3));
      expect(h1.length, 64); // SHA-256 hex
    });

    test('matches only when stored hash non-empty and code equals', () {
      final stored = passcodeHashOf('abcd1234');
      expect(passcodeMatches(stored, 'abcd1234'), isTrue);
      expect(passcodeMatches(stored, 'abcd123'), isFalse);
      expect(passcodeMatches('', 'abcd1234'), isFalse); // 未设置密令
      expect(passcodeMatches(stored, ''), isFalse);
      expect(passcodeMatches('   ', 'abcd1234'), isFalse);
    });

    test('trims surrounding whitespace of code and stored hash', () {
      final stored = '  ${passcodeHashOf('hello')}  ';
      expect(passcodeMatches(stored, '  hello  '), isTrue);
    });
  });

  group('faceLoginInGraceWindowOf', () {
    const int now = 1700000000; // epoch 秒

    test('disabled when grace <= 0', () {
      expect(faceLoginInGraceWindowOf(0, now - 10, now), isFalse);
      expect(faceLoginInGraceWindowOf(-5, now - 10, now), isFalse);
    });

    test('disabled when last ok missing', () {
      expect(faceLoginInGraceWindowOf(5, 0, now), isFalse);
    });

    test('inside window within configured minutes', () {
      expect(faceLoginInGraceWindowOf(5, now - 60, now), isTrue); // 1 分钟内
      expect(faceLoginInGraceWindowOf(5, now - 299, now), isTrue); // 即将到期
    });

    test('outside window after grace expires', () {
      expect(faceLoginInGraceWindowOf(5, now - 300, now), isFalse); // 刚好 5 分钟
      expect(faceLoginInGraceWindowOf(5, now - 301, now), isFalse); // 超过 5 分钟
    });

    test('boundary at exactly grace*60 seconds', () {
      expect(faceLoginInGraceWindowOf(5, now - 300, now), isFalse);
      expect(faceLoginInGraceWindowOf(5, now - 299, now), isTrue);
    });
  });
}

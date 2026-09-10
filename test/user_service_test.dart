import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/services/user_service.dart';

void main() {
  group('validateName', () {
    test('rejects empty names', () {
      expect(UserService.validateName(''), isNotNull);
      expect(UserService.validateName('   '), isNotNull);
      expect(UserService.validateName(null), isNotNull);
    });

    test('rejects names longer than 100 characters', () {
      expect(UserService.validateName('a' * 101), isNotNull);
    });

    test('accepts a normal name', () {
      expect(UserService.validateName('Asha Rao'), isNull);
    });
  });

  group('validateEmail', () {
    test('rejects malformed addresses', () {
      for (final email in ['', 'asha', 'asha@', 'asha@cafe', 'a b@cafe.com']) {
        expect(UserService.validateEmail(email), isNotNull, reason: email);
      }
    });

    test('accepts a well-formed address', () {
      expect(UserService.validateEmail('asha@cafe.com'), isNull);
    });
  });

  group('validatePassword', () {
    test('rejects short passwords', () {
      expect(UserService.validatePassword('ab1'), isNotNull);
    });

    test('requires letters and numbers', () {
      expect(UserService.validatePassword('onlyletters'), isNotNull);
      expect(UserService.validatePassword('12345678'), isNotNull);
    });

    test('accepts a compliant password', () {
      expect(UserService.validatePassword('cafe1234'), isNull);
    });
  });
}

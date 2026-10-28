import 'package:flutter_test/flutter_test.dart';
import 'package:suki/services/account_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps common sign up errors to Chinese hints', () {
    expect(
      signUpErrorMessage(const AuthException('User already registered')),
      '该邮箱已注册，请直接登录',
    );
    expect(
      signUpErrorMessage(
        const AuthException('Password should be at least 6 characters.'),
      ),
      '密码至少 6 位',
    );
    expect(
      signUpErrorMessage(
        const AuthException(
          'Password is known to be weak and easy to guess, '
          'please pick a stronger password.',
        ),
      ),
      '密码强度不足，请换一个更复杂的密码',
    );
    expect(
      signUpErrorMessage(
        const AuthException('Unable to validate email address: invalid format'),
      ),
      '邮箱格式不正确',
    );
    expect(
      signUpErrorMessage(const AuthException('Email rate limit exceeded')),
      '操作太频繁，请稍后再试',
    );
    expect(
      signUpErrorMessage(
        const AuthException(
          'For security purposes, you can only request '
          'this after 60 seconds.',
        ),
      ),
      '操作太频繁，请稍后再试',
    );
    expect(
      signUpErrorMessage(
        const AuthException('Signups not allowed for this instance'),
      ),
      '当前未开放注册',
    );
  });

  test('falls back to the raw message for unknown errors', () {
    expect(
      signUpErrorMessage(const AuthException('Something odd')),
      'Something odd',
    );
    expect(signUpErrorMessage(Exception('boom')), 'Exception: boom');
  });
}

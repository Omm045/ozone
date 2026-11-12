// Regression: OzoneAuthProvider subscribed to authStateChanges without ever
// cancelling, so an auth event after dispose() called notifyListeners() on a
// disposed ChangeNotifier (seen on Android after sign-out in QA runs).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/auth/auth_provider.dart';
import 'package:ozone/core/auth/auth_service.dart';
import 'package:ozone/models/user_model.dart';

class _StreamAuth extends MockAuthService {
  final controller = StreamController<UserModel?>.broadcast();
  @override
  Stream<UserModel?> get authStateChanges => controller.stream;
}

void main() {
  test('auth events after dispose are ignored (subscription cancelled)', () async {
    final auth = _StreamAuth();
    final provider = OzoneAuthProvider(authService: auth);
    expect(auth.controller.hasListener, isTrue);
    provider.dispose();
    expect(auth.controller.hasListener, isFalse);
    auth.controller.add(null); // would throw "used after being disposed" before the fix
    await Future<void>.delayed(Duration.zero);
  });
}

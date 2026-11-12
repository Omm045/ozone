import 'package:flutter/foundation.dart';
import '../../models/user_model.dart';
import '../database/chat_repository.dart';
import 'auth_service.dart';

enum AuthStatus {
  unauthenticated,
  authenticated,
  awaitingVerification,
  loading,
  error,
}

class OzoneAuthProvider extends ChangeNotifier {
  final AuthService _authService;
  UserModel? _currentUser;
  AuthStatus _status = AuthStatus.loading;
  String? _errorMessage;

  OzoneAuthProvider({required AuthService authService})
      // ignore: prefer_initializing_formals
      : _authService = authService {
    _init();
  }

  UserModel? get currentUser => _currentUser;
  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAwaitingVerification => _status == AuthStatus.awaitingVerification;

  void _init() {
    _currentUser = _authService.currentUser;
    if (_currentUser == null) {
      _status = AuthStatus.unauthenticated;
    } else if (!_currentUser!.isEmailVerified) {
      _status = AuthStatus.awaitingVerification;
    } else {
      _status = AuthStatus.authenticated;
    }
    notifyListeners();

    _authService.authStateChanges.listen((user) {
      _currentUser = user;
      if (user == null) {
        _status = AuthStatus.unauthenticated;
      } else if (!user.isEmailVerified) {
        _status = AuthStatus.awaitingVerification;
      } else {
        _status = AuthStatus.authenticated;
      }
      notifyListeners();
    });
  }

  Future<bool> signUp({
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signUp(
        email: email,
        password: password,
      );
      _currentUser = user;
      _status = AuthStatus.awaitingVerification;
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signIn(
        email: email,
        password: password,
      );
      _currentUser = user;
      if (!user.isEmailVerified) {
        _status = AuthStatus.awaitingVerification;
      } else {
        _status = AuthStatus.authenticated;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      _currentUser = user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendPasswordResetEmail({required String email}) async {
    try {
      await _authService.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<void> sendEmailVerification() async {
    try {
      await _authService.sendEmailVerification();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<bool> checkEmailVerification() async {
    try {
      final verified = await _authService.checkEmailVerification();
      if (verified && _currentUser != null) {
        _currentUser = _currentUser!.copyWith(isEmailVerified: true);
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> deleteAccount({
    String? password,
    required ChatRepository chatRepository,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.deleteAccount(
        password: password,
        chatRepository: chatRepository,
      );
      _currentUser = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.error;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    if (_status == AuthStatus.error) {
      _status = _currentUser == null
          ? AuthStatus.unauthenticated
          : (_currentUser!.isEmailVerified
              ? AuthStatus.authenticated
              : AuthStatus.awaitingVerification);
    }
    notifyListeners();
  }
}

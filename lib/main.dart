import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/auth_provider.dart';
import 'core/database/chat_repository.dart';
import 'design_system/ozone_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/email_verification_screen.dart';
import 'features/chats/chat_list_screen.dart';
import 'features/call/incoming_call_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AuthService authService;
  ChatRepository chatRepository;

  try {
    // Attempt Firebase initialization (ozone-fc7f)
    await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
    authService = FirebaseAuthService();
    chatRepository = FirestoreChatRepository();
  } catch (e) {
    // Graceful fallback to Mock mode if Firebase configuration is pending
    debugPrint('Firebase not configured or initialized: $e. Running in mock provider mode.');
    authService = MockAuthService();
    chatRepository = MockChatRepository();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => OzoneAuthProvider(authService: authService),
        ),
        Provider<ChatRepository>.value(value: chatRepository),
      ],
      child: const OzoneApp(),
    ),
  );
}

class OzoneApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const OzoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Ozone',
      debugShowCheckedModeBanner: false,
      theme: OzoneTheme.darkTheme,
      home: const RootGate(),
      builder: (context, child) {
        return IncomingCallOverlayManager(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<OzoneAuthProvider>();
    final chatRepository = context.read<ChatRepository>();

    switch (auth.status) {
      case AuthStatus.loading:
        // While signed out, loading means a sign-in/sign-up/Google request is
        // in flight: keep the same AuthScreen element (it shows its own
        // progress) so the typed email, password and mode survive an error.
        if (auth.currentUser == null) {
          return const AuthScreen();
        }
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: OzoneTheme.cyan),
          ),
        );
      case AuthStatus.unauthenticated:
      case AuthStatus.error:
        return const AuthScreen();
      case AuthStatus.awaitingVerification:
        return const EmailVerificationScreen();
      case AuthStatus.authenticated:
        return ChatListScreen(chatRepository: chatRepository);
    }
  }
}

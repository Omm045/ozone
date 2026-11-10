import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_provider.dart';
import '../../design_system/ozone_theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _resendCooldown = false;

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);
    final auth = context.read<OzoneAuthProvider>();
    final verified = await auth.checkEmailVerification();
    if (mounted) {
      setState(() => _isChecking = false);
      if (!verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email not yet verified. Please check your inbox.'),
          ),
        );
      }
    }
  }

  Future<void> _resendVerification() async {
    final auth = context.read<OzoneAuthProvider>();
    await auth.sendEmailVerification();
    if (mounted) {
      setState(() => _resendCooldown = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification link sent.')),
      );
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted) setState(() => _resendCooldown = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<OzoneAuthProvider>();
    final email = auth.currentUser?.email ?? 'your email';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OzoneTheme.surfaceCard,
                        border: Border.all(color: OzoneTheme.amber, width: 2),
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        color: OzoneTheme.amber,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Verify your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: OzoneTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We sent a verification link to:\n$email\n\nPlease tap the link in your email to activate your account.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: OzoneTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Check Verification Button
                  ElevatedButton(
                    onPressed: _isChecking ? null : _checkVerification,
                    child: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text("I've Verified My Email"),
                  ),
                  const SizedBox(height: 12),

                  // Resend Button
                  TextButton(
                    onPressed: _resendCooldown ? null : _resendVerification,
                    child: Text(
                      _resendCooldown
                          ? 'Please wait 30s to resend'
                          : 'Resend Verification Email',
                      style: TextStyle(
                        color: _resendCooldown
                            ? OzoneTheme.textSecondary
                            : OzoneTheme.cyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

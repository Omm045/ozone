import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/database/chat_repository.dart';
import '../../core/webrtc/adaptive_quality_controller.dart';
import '../../core/webrtc/quality_preferences.dart';
import '../../core/utils/update_checker.dart';
import '../../design_system/ozone_theme.dart';

class SettingsScreen extends StatefulWidget {
  final ChatRepository chatRepository;

  const SettingsScreen({super.key, required this.chatRepository});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ResolutionTier? _preferredTier;
  bool _isLoadingPreference = true;
  String _appVersionDisplay = 'Loading...';
  String _currentSemver = '1.1.0';
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadAppVersion();
  }

  Future<void> _loadPreferences() async {
    final saved = await QualityPreferences.getSavedPreference();
    if (mounted) {
      setState(() {
        _preferredTier = saved;
        _isLoadingPreference = false;
      });
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentSemver = UpdateChecker.normalizeVersion(info.version);
          _appVersionDisplay = 'v${info.version} (${info.buildNumber})';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentSemver = '1.1.0';
          _appVersionDisplay = 'v1.1.0 (3)';
        });
      }
    }
  }

  Future<void> _onQualityChanged(ResolutionTier? tier) async {
    setState(() => _preferredTier = tier);
    await QualityPreferences.savePreference(tier);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tier == null
                ? 'Call quality set to Auto (adaptive)'
                : 'Call quality set to ${tier.name}',
          ),
          backgroundColor: OzoneTheme.surfaceCard,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _isCheckingUpdate = true);

    try {
      final result = await UpdateChecker.checkForUpdates(
        explicitCurrentVersion: _currentSemver,
      );

      if (!mounted) return;

      switch (result.status) {
        case UpdateStatus.updateAvailable:
          _showUpdateAvailableDialog(
            latestVersion: result.latestVersion!,
            releaseNotes: result.releaseNotes ?? 'Performance improvements and bug fixes.',
            releaseUrl: result.downloadUrl ?? 'https://github.com/Omm045/ozone/releases/latest',
          );
          break;
        case UpdateStatus.upToDate:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You are on the latest version (${result.currentVersion}).'),
              backgroundColor: OzoneTheme.surfaceCard,
            ),
          );
          break;
        case UpdateStatus.noReleases:
          _showUpdateDialog(
            title: 'No Releases Found',
            message: result.errorMessage ?? 'No release has been published yet.',
          );
          break;
        case UpdateStatus.rateLimited:
          _showUpdateDialog(
            title: 'Rate Limit Reached',
            message: result.errorMessage ?? 'GitHub API rate limit reached. Please try again in a few minutes.',
          );
          break;
        case UpdateStatus.error:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Could not check for updates.'),
              backgroundColor: OzoneTheme.ruby,
            ),
          );
          break;
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  void _showUpdateDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OzoneTheme.surfaceCard,
        title: Text(title, style: const TextStyle(color: OzoneTheme.textPrimary)),
        content: Text(message, style: const TextStyle(color: OzoneTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: OzoneTheme.cyan)),
          ),
        ],
      ),
    );
  }

  void _showUpdateAvailableDialog({
    required String latestVersion,
    required String releaseNotes,
    required String releaseUrl,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OzoneTheme.surfaceCard,
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: OzoneTheme.cyan),
            const SizedBox(width: 8),
            Text(
              'Update Available (v$latestVersion)',
              style: const TextStyle(color: OzoneTheme.textPrimary, fontSize: 18),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: SingleChildScrollView(
            child: Text(
              releaseNotes,
              style: const TextStyle(color: OzoneTheme.textSecondary, fontSize: 14, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later', style: TextStyle(color: OzoneTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri.parse(releaseUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: OzoneTheme.cyan,
              foregroundColor: Colors.black,
            ),
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteAccountConfirmation(BuildContext context) async {
    final confirmController = TextEditingController();
    final passwordController = TextEditingController();
    final auth = context.read<OzoneAuthProvider>();

    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isConfirmed = confirmController.text.trim() == 'DELETE';

            return AlertDialog(
              backgroundColor: OzoneTheme.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: OzoneTheme.ruby.withValues(alpha: 0.3)),
              ),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: OzoneTheme.ruby, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delete Account?',
                      style: TextStyle(
                        color: OzoneTheme.ruby,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This action is irreversible and permanent.\n\n'
                      '• Your profile and auth record will be permanently deleted.\n'
                      '• Your chats will be removed from your view, while conversation history is preserved for other participants.\n\n'
                      'To confirm, type DELETE below:',
                      style: TextStyle(
                        color: OzoneTheme.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('deleteConfirmTextField'),
                      controller: confirmController,
                      style: const TextStyle(color: OzoneTheme.textPrimary, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'Type DELETE',
                        hintStyle: TextStyle(color: OzoneTheme.textSecondary.withValues(alpha: 0.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: OzoneTheme.textSecondary.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: OzoneTheme.ruby),
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('deletePasswordTextField'),
                      controller: passwordController,
                      obscureText: true,
                      style: const TextStyle(color: OzoneTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Password (if re-auth required)',
                        hintStyle: TextStyle(color: OzoneTheme.textSecondary.withValues(alpha: 0.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: OzoneTheme.textSecondary.withValues(alpha: 0.3)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Cancel', style: TextStyle(color: OzoneTheme.textSecondary)),
                ),
                ElevatedButton(
                  key: const Key('confirmDeleteAccountBtn'),
                  onPressed: isConfirmed ? () => Navigator.of(dialogCtx).pop(true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OzoneTheme.ruby,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: OzoneTheme.ruby.withValues(alpha: 0.2),
                    disabledForegroundColor: Colors.white38,
                  ),
                  child: const Text('Delete Forever', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldDelete == true) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: OzoneTheme.ruby),
        ),
      );

      final success = await auth.deleteAccount(
        password: passwordController.text.trim().isEmpty ? null : passwordController.text.trim(),
        chatRepository: widget.chatRepository,
      );

      if (context.mounted) {
        // Pop loading dialog
        Navigator.of(context, rootNavigator: true).pop();

        if (success) {
          // Pop settings screen
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(auth.errorMessage ?? 'Failed to delete account. Please verify your password.'),
              backgroundColor: OzoneTheme.ruby,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<OzoneAuthProvider>();
    final currentUser = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // 1. Account Section
          _buildSectionHeader('ACCOUNT'),
          Card(
            color: OzoneTheme.surfaceCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined, color: OzoneTheme.cyan),
                  title: const Text(
                    'Signed in as',
                    style: TextStyle(fontSize: 12, color: OzoneTheme.textSecondary),
                  ),
                  subtitle: Text(
                    currentUser?.email ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: OzoneTheme.textPrimary,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                ListTile(
                  leading: const Icon(Icons.logout, color: OzoneTheme.amber),
                  title: const Text('Sign Out', style: TextStyle(color: OzoneTheme.amber)),
                  onTap: () async {
                    await auth.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const Divider(height: 1, color: Colors.white12),
                ListTile(
                  key: const Key('deleteAccountButton'),
                  leading: const Icon(Icons.delete_forever_rounded, color: OzoneTheme.ruby),
                  title: const Text(
                    'Delete Account',
                    style: TextStyle(color: OzoneTheme.ruby, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Permanently delete account and remove profile',
                    style: TextStyle(fontSize: 12, color: OzoneTheme.textSecondary),
                  ),
                  onTap: () => _showDeleteAccountConfirmation(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Call Quality Section
          _buildSectionHeader('CALL QUALITY'),
          Card(
            color: OzoneTheme.surfaceCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call-Start Quality',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: OzoneTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose default resolution for outgoing calls. Max native camera FPS (up to 60fps) is probed automatically.',
                    style: TextStyle(fontSize: 12, color: OzoneTheme.textSecondary, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingPreference)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ))
                  else
                    DropdownButtonFormField<ResolutionTier?>(
                      initialValue: _preferredTier,
                      dropdownColor: OzoneTheme.surfaceCard,
                      style: const TextStyle(color: OzoneTheme.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<ResolutionTier?>(
                          value: null,
                          child: Text('Auto (Adaptive)'),
                        ),
                        ...ResolutionTier.values.where((tier) {
                          if (!kIsWeb && Platform.isIOS) {
                            return tier == ResolutionTier.p720;
                          }
                          return true;
                        }).map(
                          (tier) => DropdownMenuItem<ResolutionTier?>(
                            value: tier,
                            child: Text(
                              tier == ResolutionTier.p4k
                                  ? '4K (${tier.width}x${tier.height} - Desktop Only)'
                                  : '${tier.name} (${tier.width}x${tier.height})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: _onQualityChanged,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 3. App Section
          _buildSectionHeader('APP'),
          Card(
            color: OzoneTheme.surfaceCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: OzoneTheme.cyan),
                  title: const Text('App Version', style: TextStyle(color: OzoneTheme.textPrimary)),
                  trailing: Text(
                    _appVersionDisplay,
                    style: const TextStyle(
                      color: OzoneTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                ListTile(
                  leading: _isCheckingUpdate
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: OzoneTheme.cyan),
                        )
                      : const Icon(Icons.system_update_rounded, color: OzoneTheme.cyan),
                  title: const Text('Check for Updates', style: TextStyle(color: OzoneTheme.cyan)),
                  onTap: _isCheckingUpdate ? null : _checkForUpdates,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: OzoneTheme.cyan,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Login screen — server URL + email + password.
///
/// The server URL field shows `https://demo.immich.app` as a
/// placeholder hint only. No credentials are prefilled anywhere and
/// no password is ever hard-coded. Flow: probe the server (ping +
/// version, blocks v2 and older), then log in.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/exceptions.dart';
import '../../providers/providers.dart';
import '../../services/auth_service.dart';
import 'server_settings_screen.dart';
import '../widgets/nova_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialError});

  final String? initialError;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _serverController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;
  ServerProbe? _probe;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _probeServer() async {
    if (_serverController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a server URL first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _probe = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final probe = await auth.probeServer(_serverController.text);
      setState(() {
        _probe = probe;
        if (probe.isTooOld) {
          _error =
              'This server runs Immich ${probe.version.major}.${probe.version.minor}.${probe.version.patch}. '
              'NOVA PHOTOS needs Immich 3.0 or newer — ask the server admin to upgrade.';
        }
      });
    } on ImmichApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      // Probe first when the URL changed since the last probe.
      final needsProbe = _probe == null ||
          _probe!.serverUrl != normalizeServerUrl(_serverController.text);
      if (needsProbe) {
        final probe = await auth.probeServer(_serverController.text);
        if (probe.isTooOld) {
          setState(() {
            _error =
                'This server runs Immich ${probe.version.major}.${probe.version.minor}.${probe.version.patch}. '
                'NOVA PHOTOS needs Immich 3.0 or newer.';
          });
          return;
        }
        _probe = probe;
      }
      final notifier = ref.read(authStateProvider.notifier);
      await notifier.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // On success the auth gate in NovaApp swaps in the HomeScreen.
    } on ImmichUnauthorizedException {
      setState(() => _error = 'Wrong email or password. Try again.');
    } on ImmichApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Center(child: NovaLogo(size: 96)),
                  const SizedBox(height: 16),
                  Text(
                    'NOVA PHOTOS',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your photos, on your server.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _serverController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://demo.immich.app',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your Immich server URL.'
                        : null,
                    onFieldSubmitted: (_) => _probeServer(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _probeServer,
                      icon: const Icon(Icons.radar_outlined, size: 18),
                      label: const Text('Check server'),
                    ),
                  ),
                  if (_probe != null && !_probe!.isTooOld)
                    _ProbeCard(probe: _probe!),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outlined),
                    ),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Enter an email.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Enter your password.'
                        : null,
                    onFieldSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sign in'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ServerSettingsScreen(),
                      ),
                    ),
                    child: const Text('Server settings'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProbeCard extends StatelessWidget {
  const _ProbeCard({required this.probe});

  final ServerProbe probe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = probe.version;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              probe.isNewerMajor ? Icons.warning_amber_outlined : Icons.check_circle_outlined,
              color: probe.isNewerMajor
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Immich ${version.major}.${version.minor}.${version.patch}'
                    ' (feature level ${version.featureLevel})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (probe.isNewerMajor)
                    Text(
                      'Built for Immich v3 — some features may not work.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    Text(
                      'Server reachable and supported.',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

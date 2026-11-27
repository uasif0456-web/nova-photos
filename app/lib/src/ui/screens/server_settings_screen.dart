/// Server settings screen — change the server URL, see the server
/// version + feature flags, sign out.
///
/// Changing the server signs the user out first (a session belongs to
/// exactly one server), then probes the new URL.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/exceptions.dart';
import '../../providers/providers.dart';
import '../../services/auth_service.dart';

class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState
    extends ConsumerState<ServerSettingsScreen> {
  final _serverController = TextEditingController();
  bool _busy = false;
  String? _error;
  ServerProbe? _probe;

  @override
  void dispose() {
    _serverController.dispose();
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
    });
    try {
      final auth = ref.read(authServiceProvider);
      final probe = await auth.probeServer(_serverController.text);
      setState(() => _probe = probe);
    } on ImmichApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyAndSignOut() async {
    // A session belongs to one server: switching servers signs out.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch server?'),
        content: const Text(
          'Changing the server signs you out of the current one. '
          'You will need to sign in again on the new server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch server'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(authStateProvider);
    final session = sessionAsync.value;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (session != null) ...[
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    session.user.name.isEmpty
                        ? '?'
                        : session.user.name[0].toUpperCase(),
                  ),
                ),
                title: Text(session.user.name),
                subtitle: Text(
                  '${session.user.email}\n${session.serverUrl}',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Immich ${session.version.major}.${session.version.minor}.${session.version.patch} '
                      '(feature level ${session.version.featureLevel})',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _FeatureChip(
                          label: 'Smart search',
                          on: session.features.smartSearch,
                        ),
                        _FeatureChip(
                          label: 'Faces',
                          on: session.features.facialRecognition,
                        ),
                        _FeatureChip(
                          label: 'Map',
                          on: session.features.map,
                        ),
                        _FeatureChip(
                          label: 'Trash',
                          on: session.features.trash,
                        ),
                        _FeatureChip(
                          label: 'OCR',
                          on: session.features.ocr,
                        ),
                        _FeatureChip(
                          label: 'Duplicates',
                          on: session.features.duplicateDetection,
                        ),
                      ],
                    ),
                    if (session.version.isNewerMajor) ...[
                      const SizedBox(height: 8),
                      Text(
                        'This server is newer than NOVA was built for '
                        '(Immich v3). Some features may not work.',
                        style: TextStyle(color: theme.colorScheme.tertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Switch server',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _serverController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'New server URL',
              hintText: 'https://demo.immich.app',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _probeServer,
                icon: const Icon(Icons.radar_outlined, size: 18),
                label: const Text('Check server'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed:
                    (_busy || _probe == null || _probe!.isTooOld) ? null : _applyAndSignOut,
                child: const Text('Switch & sign out'),
              ),
            ],
          ),
          if (_probe != null) ...[
            const SizedBox(height: 12),
            Text(
              _probe!.isTooOld
                  ? 'Server too old — NOVA needs Immich 3.0 or newer.'
                  : 'Immich ${normalizeServerUrl(_serverController.text)} '
                      'answers: version ${_probe!.version.major}.${_probe!.version.minor}.${_probe!.version.patch}.',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (session != null) ...[
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await ref.read(authStateProvider.notifier).logout();
                      if (context.mounted) Navigator.of(context).pop();
                    },
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Sign out'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      avatar: Icon(
        on ? Icons.check_circle_outline : Icons.remove_circle_outline,
        size: 18,
      ),
    );
  }
}

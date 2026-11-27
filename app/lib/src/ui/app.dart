/// App entry — [NovaApp] wires the theme, the auth gate, and the
/// home shell. Edge-to-edge is enabled in main.dart via SystemChrome.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

class NovaApp extends ConsumerWidget {
  const NovaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return MaterialApp(
      title: 'NOVA PHOTOS',
      debugShowCheckedModeBanner: false,
      theme: novaLightTheme(),
      darkTheme: novaDarkTheme(),
      themeMode: ThemeMode.system,
      home: authState.when(
        data: (session) =>
            session == null ? const LoginScreen() : const HomeScreen(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => LoginScreen(initialError: error.toString()),
      ),
    );
  }
}

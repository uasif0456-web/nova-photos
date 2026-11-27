/// Home shell — bottom navigation with five tabs:
/// Photos, Collections, Search, Memories, Library.
/// The app bar carries the backup status indicator (live Track C
/// engine state) and a shortcut to server settings.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/token_store.dart';
import '../widgets/backup_status_chip.dart';
import 'collections_page.dart';
import 'library_page.dart';
import 'memories_page.dart';
import 'photos_page.dart';
import 'search_page.dart';
import 'server_settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Track C: start the sync engine once per signed-in session —
    // socket as invalidation trigger, sync stream as source of truth,
    // then replay any offline operations queued while away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSync());
  }

  Future<void> _startSync() async {
    final api = ref.read(novaApiProvider);
    final sync = ref.read(syncServiceProvider);
    if (api == null || sync == null) return;
    final token = await ref
        .read(tokenStoreProvider)
        .read(TokenStoreKeys.accessToken);
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      api.socket.connect(accessToken: token);
    }
    sync.watchSocket();
    await sync.syncNow();
    if (!mounted) return;
    final pending = ref.read(pendingOpsServiceProvider);
    if (pending != null) await pending.replayAll();
  }

  static const _pages = [
    PhotosPage(),
    CollectionsPage(),
    SearchPage(),
    MemoriesPage(),
    LibraryPage(),
  ];

  static const _titles = [
    'Photos',
    'Collections',
    'Search',
    'Memories',
    'Library',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: BackupStatusChip(),
          ),
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: 'Server settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ServerSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library_outlined),
            activeIcon: Icon(Icons.photo_library),
            label: 'Photos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.collections_bookmark_outlined),
            activeIcon: Icon(Icons.collections_bookmark),
            label: 'Collections',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Memories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_outlined),
            activeIcon: Icon(Icons.folder),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}

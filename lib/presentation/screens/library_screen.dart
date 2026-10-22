// ============================================================================
//  library_screen.dart — main "Browse music" screen
//  Tabs: All tracks / Albums / Artists / Playlists
//  FAB: Scan (calls LibraryNotifier.scan)
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../domain/models/album.dart';
import '../providers/providers.dart';
import '../widgets/track_list_tile.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);
  bool _autoScanTriggered = false;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(libraryStateProvider);
    final playback = ref.watch(playbackServiceProvider);

    // Auto-scan once on first build (when state is still loading).
    if (!_autoScanTriggered && state.isLoading) {
      _autoScanTriggered = true;
      // Defer to next frame to avoid build-phase side effects.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(libraryStateProvider.notifier).scan();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navLibrary),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: l.libraryAllTracks),
            Tab(text: l.libraryAlbums),
            Tab(text: l.libraryArtists),
            Tab(text: l.libraryPlaylists),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              final mediaStore = ref.read(mediaStoreSourceProvider);
              final tracks = await mediaStore.pickAudioFiles();
              if (tracks.isEmpty) return;
              // Replace library with picked files
              ref.read(libraryStateProvider.notifier).setPickedTracks(tracks);
            },
            tooltip: 'Выбрать файлы',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {/* TODO: search filter */},
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${l.commonError}: $e')),
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.libraryEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          return TabBarView(
            controller: _tab,
            children: [
              // All tracks
              ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  return TrackListTile(
                    track: t,
                    index: i,
                    onTap: () {
                      playback.playQueue(tracks: tracks, startIndex: i);
                      Navigator.of(context).pushNamed('/now-playing');
                    },
                  );
                },
              ),
              // Albums
              _AlbumGrid(),
              // Artists
              _ArtistsList(),
              // Playlists
              _PlaylistsList(),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ref.read(libraryStateProvider.notifier).scan(),
        icon: const Icon(Icons.refresh),
        label: Text(l.libraryScan),
        backgroundColor: TubeColors.amber,
        foregroundColor: TubeColors.background,
      ),
    );
  }
}

class _AlbumGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      padding: const EdgeInsets.all(12),
      itemCount: albums.length,
      itemBuilder: (_, i) {
        final a = albums[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: TubeColors.surfaceVariant,
                      border: Border.all(color: TubeColors.brass),
                    ),
                    child: a.artUri.isEmpty
                        ? const Icon(Icons.album, size: 56, color: TubeColors.brass)
                        : Image.network(a.artUri, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  a.albumArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArtistsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    final artists = <String, List<Album>>{};
    for (final a in albums) {
      artists.putIfAbsent(a.albumArtist, () => []).add(a);
    }
    return ListView(
      children: artists.entries.map((e) {
        return ListTile(
          title: Text(e.key),
          subtitle: Text('${e.value.length} albums'),
          leading: const Icon(Icons.person, color: TubeColors.brass),
          onTap: () {/* TODO: drill in */},
        );
      }).toList(),
    );
  }
}

class _PlaylistsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(child: Text('No playlists yet'));
  }
}

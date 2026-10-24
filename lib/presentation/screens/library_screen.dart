import "package:flutter/foundation.dart" show debugPrint;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/l10n/generated/app_localizations.dart";
import "../../core/theme/tube_colors.dart";
import "../../domain/models/album.dart";
import "../../domain/models/track.dart";
import "../providers/providers.dart";
import "../widgets/track_list_tile.dart";

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);
  // NO _autoScanTriggered - library starts empty, user picks files/folder.

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Pick files/folder -> set as library -> immediately start playing first track.
  Future<void> _pickAndPlay(Future<List<Track>> Function() picker) async {
    debugPrint("[pathephon] _pickAndPlay: starting");
    final playback = ref.read(playbackServiceProvider);
    try {
      final tracks = await picker();
      debugPrint("[pathephon] _pickAndPlay: picked ${tracks.length} tracks");
      if (tracks.isEmpty) {
        debugPrint("[pathephon] _pickAndPlay: no tracks picked, aborting");
        return;
      }
      ref.read(libraryStateProvider.notifier).setPickedTracks(tracks);
      debugPrint("[pathephon] _pickAndPlay: setPickedTracks done, calling playQueue");
      await playback.playQueue(tracks: tracks, startIndex: 0);
      ref.read(isPlayingProvider.notifier).state = true;
      debugPrint("[pathephon] _pickAndPlay: playQueue started");
    } catch (e, st) {
      debugPrint("[pathephon] _pickAndPlay FAILED: $e\n$st");
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(libraryStateProvider);
    final playback = ref.watch(playbackServiceProvider);

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
            onPressed: () => _pickAndPlay(() =>
                ref.read(mediaStoreSourceProvider).pickDirectory()),
            tooltip: "\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u043F\u0430\u043F\u043A\u0443",
          ),
          IconButton(
            icon: const Icon(Icons.audio_file),
            onPressed: () => _pickAndPlay(() =>
                ref.read(mediaStoreSourceProvider).pickAudioFiles()),
            tooltip: "\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u0444\u0430\u0439\u043B\u044B",
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("${l.commonError}: $e")),
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.library_music, size: 80, color: TubeColors.brass),
                    const SizedBox(height: 16),
                    Text(
                      "\u0424\u0430\u0439\u043B\u044B \u043D\u0435 \u0432\u044B\u0431\u0440\u0430\u043D\u044B",
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: TubeColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "\u041D\u0430\u0436\u043C\u0438\u0442\u0435 \u043A\u043D\u043E\u043F\u043A\u0443 \u043F\u0430\u043F\u043A\u0438 \u0438\u043B\u0438 \u0444\u0430\u0439\u043B\u043E\u0432 \u0432\u0432\u0435\u0440\u0445\u0443",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TubeColors.textMuted,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return TabBarView(
            controller: _tab,
            children: [
              ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  return TrackListTile(
                    track: t,
                    index: i,
                    onTap: () {
                      playback.playQueue(tracks: tracks, startIndex: i);
                      ref.read(isPlayingProvider.notifier).state = true;
                    },
                  );
                },
              ),
              _AlbumGrid(),
              _ArtistsList(),
              const Center(child: Text("No playlists yet")),
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
    final playback = ref.watch(playbackServiceProvider);

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
          child: InkWell(
            onTap: () {
              if (a.tracks.isEmpty) return;
              playback.playQueue(tracks: a.tracks, startIndex: 0);
              ref.read(isPlayingProvider.notifier).state = true;
            },
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
                      child: _AlbumArt(album: a),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                  Text(a.albumArtist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Album artwork with fallbacks.
class _AlbumArt extends ConsumerWidget {
  const _AlbumArt({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (album.artUri.isNotEmpty) {
      return Image.network(
        album.artUri,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallbackIcon(),
      );
    }
    String? trackArtUri;
    for (final t in album.tracks) {
      if (t.artUri.isNotEmpty) {
        trackArtUri = t.artUri;
        break;
      }
    }
    if (trackArtUri != null) {
      return Image.network(
        trackArtUri,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallbackIcon(),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return const Center(
      child: Icon(Icons.album, size: 56, color: TubeColors.brass),
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
          subtitle: Text("${e.value.length} albums"),
          leading: const Icon(Icons.person, color: TubeColors.brass),
          onTap: () {},
        );
      }).toList(),
    );
  }
}
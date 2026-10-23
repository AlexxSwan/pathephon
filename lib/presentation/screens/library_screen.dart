import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/l10n/generated/app_localizations.dart";
import "../../core/theme/tube_colors.dart";
import "../../domain/models/album.dart";
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

    if (!_autoScanTriggered && state.isLoading) {
      _autoScanTriggered = true;
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
              final tracks = await mediaStore.pickDirectory();
              if (tracks.isEmpty) return;
              ref.read(libraryStateProvider.notifier).setPickedTracks(tracks);
            },
             param($m) 
    $val = $m.Value
    if ($val -match "\u0412\u044B\u0431\u0440\u0430\u0442\u044C") { $val }
    elseif ($val -match "folder") { 'tooltip: "\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u043F\u0430\u043F\u043A\u0443"' }
    elseif ($val -match "audio") { 'tooltip: "\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u0444\u0430\u0439\u043B\u044B"' }
    else { $val }
,
          ),
          IconButton(
            icon: const Icon(Icons.audio_file),
            onPressed: () async {
              final mediaStore = ref.read(mediaStoreSourceProvider);
              final tracks = await mediaStore.pickAudioFiles();
              if (tracks.isEmpty) return;
              ref.read(libraryStateProvider.notifier).setPickedTracks(tracks);
            },
             param($m) 
    $val = $m.Value
    if ($val -match "\u0412\u044B\u0431\u0440\u0430\u0442\u044C") { $val }
    elseif ($val -match "folder") { 'tooltip: "\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u043F\u0430\u043F\u043A\u0443"' }
    elseif ($val -match "audio") { 'tooltip: "\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u0444\u0430\u0439\u043B\u044B"' }
    else { $val }
,
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
              ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) {
                  final t = tracks[i];
                  return TrackListTile(
                    track: t,
                    index: i,
                    onTap: () {
                      playback.playQueue(tracks: tracks, startIndex: i); ref.read(isPlayingProvider.notifier).state = true;
                      Navigator.of(context).pushNamed("/now-playing");
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
              playback.playQueue(tracks: a.tracks, startIndex: 0); ref.read(isPlayingProvider.notifier).state = true;
              Navigator.of(context).pushNamed("/now-playing");
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
                      child: a.artUri.isEmpty
                          ? const Icon(Icons.album, size: 56, color: TubeColors.brass)
                          : Image.network(a.artUri, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.album, size: 56, color: TubeColors.brass)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  Text(a.albumArtist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
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
          subtitle: Text("${e.value.length} albums"),
          leading: const Icon(Icons.person, color: TubeColors.brass),
          onTap: () {},
        );
      }).toList(),
    );
  }
}
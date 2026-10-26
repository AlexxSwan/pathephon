import "package:flutter/foundation.dart" show debugPrint;
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "dart:io";
import "package:file_picker/file_picker.dart";
import "dart:typed_data";
import "dart:convert";

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

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _pickAndPlayFiles() async {
    final playback = ref.read(playbackServiceProvider);
    try {
      final tracks = await ref.read(mediaStoreSourceProvider).pickAudioFiles();
      if (tracks.isEmpty) return;
      ref.read(libraryStateProvider.notifier).setPickedTracks(tracks);
      await playback.playQueue(tracks: tracks, startIndex: 0);
      ref.read(isPlayingProvider.notifier).state = true;
    } catch (e) { debugPrint("[pathephon] _pickAndPlayFiles FAILED: $e"); }
  }

  /// Выбирает папку и ДОБАВЛЯЕТ её треки в текущую очередь (не заменяет).
  Future<void> _addFolderToQueue() async {
    try {
      final result = await ref.read(mediaStoreSourceProvider).pickDirectoryWithDiagnostic();
      if (result.tracks.isEmpty) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1410),
              title: const Text("Папка пуста", style: TextStyle(color: Color(0xFFF4E9D2))),
              content: Text(result.diagnostic, style: const TextStyle(color: Color(0xFFF4E9D2), fontSize: 12, fontFamily: 'monospace')),
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("OK", style: TextStyle(color: Color(0xFFFF6B1A))))],
            ),
          );
        }
        return;
      }
      await ref.read(libraryStateProvider.notifier).addToCurrentQueue(result.tracks, ProviderScope.containerOf(context));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено треков: ${result.tracks.length}')),
        );
      }
    } catch (e) { debugPrint("[pathephon] _addFolderToQueue FAILED: $e"); }
  }

  Future<void> _pickAndPlayFolder() async {
    final playback = ref.read(playbackServiceProvider);
    try {
      final result = await ref.read(mediaStoreSourceProvider).pickDirectoryWithDiagnostic();
      if (result.tracks.isEmpty) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1410),
              title: const Text("\u0414\u0438\u0430\u0433\u043D\u043E\u0441\u0442\u0438\u043A\u0430", style: TextStyle(color: Color(0xFFF4E9D2))),
              content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(
                child: Text(result.diagnostic, style: const TextStyle(color: Color(0xFFF4E9D2), fontSize: 12, fontFamily: 'monospace')),
              )),
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("OK", style: TextStyle(color: Color(0xFFFF6B1A))))],
            ),
          );
        }
        return;
      }
      ref.read(libraryStateProvider.notifier).setPickedTracks(result.tracks);
      await playback.playQueue(tracks: result.tracks, startIndex: 0);
      ref.read(isPlayingProvider.notifier).state = true;
    } catch (e) { debugPrint("[pathephon] _pickAndPlayFolder FAILED: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(libraryStateProvider);
    final playback = ref.watch(playbackServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navLibrary),
        bottom: TabBar(controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: l.libraryAllTracks), Tab(text: l.libraryAlbums),
          Tab(text: l.libraryArtists), Tab(text: l.libraryPlaylists),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickAndPlayFolder, tooltip: "Выбрать папку"),
          IconButton(icon: const Icon(Icons.playlist_add), onPressed: _addFolderToQueue, tooltip: "Добавить папку в очередь"),
          IconButton(icon: const Icon(Icons.audio_file), onPressed: _pickAndPlayFiles, tooltip: "\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u0444\u0430\u0439\u043B\u044B"),
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("${l.commonError}: $e")),
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.library_music, size: 80, color: TubeColors.brass),
              const SizedBox(height: 16),
              Text("\u0424\u0430\u0439\u043B\u044B \u043D\u0435 \u0432\u044B\u0431\u0440\u0430\u043D\u044B",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: TubeColors.textSecondary)),
            ]));
          }
          return TabBarView(controller: _tab, children: [
            ListView.builder(itemCount: tracks.length, itemBuilder: (_, i) {
              final t = tracks[i];
              return TrackListTile(track: t, index: i, onTap: () {
                playback.playQueue(tracks: tracks, startIndex: i);
                ref.read(isPlayingProvider.notifier).state = true;
              });
            }),
            _AlbumGrid(),
            _ArtistsList(),
            _PlaylistsTab(),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ref.read(libraryStateProvider.notifier).scan(),
        icon: const Icon(Icons.refresh), label: Text(l.libraryScan),
        backgroundColor: TubeColors.amber, foregroundColor: TubeColors.background,
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
        crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.85),
      padding: const EdgeInsets.all(12),
      itemCount: albums.length,
      itemBuilder: (_, i) {
        final a = albums[i];
        return Card(child: InkWell(
          onTap: () {
            if (a.tracks.isEmpty) return;
            playback.playQueue(tracks: a.tracks, startIndex: 0);
            ref.read(isPlayingProvider.notifier).state = true;
          },
          child: Padding(padding: const EdgeInsets.all(10), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 1, child: Container(
                decoration: BoxDecoration(color: TubeColors.surfaceVariant, border: Border.all(color: TubeColors.brass)),
                child: _AlbumArt(album: a),
              )),
              const SizedBox(height: 8),
              Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              Text(a.albumArtist, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
        ));
      },
    );
  }
}

class _AlbumArt extends ConsumerWidget {
  const _AlbumArt({required this.album});
  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? artUri = album.artUri;
    if (artUri.isEmpty) {
      for (final t in album.tracks) {
        if (t.artUri.isNotEmpty) { artUri = t.artUri; break; }
      }
    }
    if (artUri != null && artUri.isNotEmpty) {
      final ms = ref.read(mediaStoreSourceProvider);
      final cachedBytes = ms.getCoverBytes(artUri);
      if (cachedBytes != null) {
        return Image.memory(cachedBytes, fit: BoxFit.cover, errorBuilder: (_, e, __) => _fallback());
      }
      if (artUri.startsWith('file://')) {
        return Image.file(File(Uri.parse(artUri).toFilePath()), fit: BoxFit.cover, errorBuilder: (_, e, __) => _fallback());
      }
      return Image.network(artUri, fit: BoxFit.cover, errorBuilder: (_, e, __) => _fallback());
    }
    return _fallback();
  }
  Widget _fallback() => const Center(child: Icon(Icons.album, size: 56, color: TubeColors.brass));
}

class _ArtistsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider);
    final artists = <String, List<Album>>{};
    for (final a in albums) { artists.putIfAbsent(a.albumArtist, () => []).add(a); }
    return ListView(children: artists.entries.map((e) => ListTile(
      title: Text(e.key), subtitle: Text("${e.value.length} albums"),
      leading: const Icon(Icons.person, color: TubeColors.brass), onTap: () {},
    )).toList());
  }
}

// ============================================================================
//  Вкладка "Плейлисты" — список сохранённых плейлистов + кнопка "Сохранить текущий"
// ============================================================================
class _PlaylistsTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<_PlaylistsTab> {
  List<Map<String, dynamic>> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString('pathephon.playlists');
    if (raw == null) {
      setState(() { _playlists = []; _loading = false; });
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      setState(() { _playlists = list.cast<Map<String, dynamic>>(); _loading = false; });
    } catch (_) {
      setState(() { _playlists = []; _loading = false; });
    }
  }

  Future<void> _saveCurrentPlaylist() async {
    final snap = ref.read(playbackSnapshotProvider).valueOrNull;
    if (snap == null || snap.queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Очередь воспроизведения пуста')),
      );
      return;
    }
    // Диалог — спрашиваем имя плейлиста
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(
          text: 'Плейлист ${_playlists.length + 1}',
        );
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1410),
          title: const Text('Сохранить плейлист', style: TextStyle(color: Color(0xFFF4E9D2))),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Color(0xFFF4E9D2)),
            decoration: const InputDecoration(
              hintText: 'Название плейлиста',
              hintStyle: TextStyle(color: Color(0xFF8A7F6A)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена', style: TextStyle(color: Color(0xFF8A7F6A))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Сохранить', style: TextStyle(color: Color(0xFFFF6B1A))),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;

    // Сохраняем
    final prefs = ref.read(sharedPreferencesProvider);
    final newPlaylist = {
      'id': 'playlist_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
      'tracks': snap.queue.map((t) => t.toJson()).toList(),
    };
    _playlists.insert(0, newPlaylist);
    await prefs.setString('pathephon.playlists', jsonEncode(_playlists));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Плейлист "$name" сохранён (${snap.queue.length} треков)')),
    );
  }

  /// Экспорт выбранного плейлиста в .m3u файл.
  Future<void> _exportToM3u() async {
    if (_playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет плейлистов для экспорта')),
      );
      return;
    }
    // Диалог выбора плейлиста
    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1A1410),
        title: const Text('Выберите плейлист для экспорта', style: TextStyle(color: Color(0xFFF4E9D2))),
        children: _playlists.asMap().entries.map((e) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(e.key),
            child: Text(e.value['name'] as String, style: const TextStyle(color: Color(0xFFF4E9D2))),
          );
        }).toList(),
      ),
    );
    if (selectedIndex == null) return;
    final pl = _playlists[selectedIndex];
    final tracksJson = pl['tracks'] as List<dynamic>;
    final tracks = tracksJson.map((j) => Track.fromJson(j as Map<String, dynamic>)).toList();

    // Выбор папки через file_picker
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;
      final name = pl['name'] as String? ?? 'playlist';
      final file = File('$result/$name.m3u');
      final buf = StringBuffer();
      buf.writeln('#EXTM3U');
      for (final t in tracks) {
        buf.writeln('#EXTINF:${t.durationMs ~/ 1000},${t.artist.isNotEmpty ? "${t.artist} - " : ""}${t.title}');
        // Путь: если uri — file:// или content://, берём filePath, иначе uri
        final path = t.filePath.isNotEmpty ? t.filePath : t.uri;
        buf.writeln(path);
      }
      await file.writeAsString(buf.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Экспортировано: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  /// Импорт плейлиста из .m3u файла.
  Future<void> _importFromM3u() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      final file = File(path);
      final content = await file.readAsString();
      final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      final tracks = <Track>[];
      String? pendingTitle;
      String? pendingArtist;
      int? pendingDuration;

      for (final line in lines) {
        if (line.startsWith('#EXTM3U')) continue;
        if (line.startsWith('#EXTINF:')) {
          // #EXTINF:duration,artist - title
          final rest = line.substring(8);
          final commaIdx = rest.indexOf(',');
          if (commaIdx > 0) {
            final durStr = rest.substring(0, commaIdx);
            pendingDuration = int.tryParse(durStr);
            final info = rest.substring(commaIdx + 1);
            final dashIdx = info.indexOf(' - ');
            if (dashIdx > 0) {
              pendingArtist = info.substring(0, dashIdx);
              pendingTitle = info.substring(dashIdx + 3);
            } else {
              pendingTitle = info;
            }
          }
          continue;
        }
        if (line.startsWith('#')) continue;
        // Это путь к файлу
        final uri = line.startsWith('file://') || line.startsWith('content://')
            ? line
            : Uri.file(line).toString();
        tracks.add(Track(
          id: uri,
          uri: uri,
          filePath: line.startsWith('file://') ? Uri.parse(line).toFilePath() : line,
          title: pendingTitle ?? line.split('/').last.replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), ''),
          artist: pendingArtist ?? '',
          durationMs: (pendingDuration ?? 0) * 1000,
        ));
        pendingTitle = null;
        pendingArtist = null;
        pendingDuration = null;
      }

      if (tracks.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('В .m3u не найдено треков')),
          );
        }
        return;
      }

      // Сохраняем как новый плейлист
      final prefs = ref.read(sharedPreferencesProvider);
      final name = path.split('/').last.replaceAll(RegExp(r'\.(m3u|m3u8)$'), '');
      final newPlaylist = {
        'id': 'playlist_${DateTime.now().millisecondsSinceEpoch}',
        'name': name,
        'createdAt': DateTime.now().toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };
      _playlists.insert(0, newPlaylist);
      await prefs.setString('pathephon.playlists', jsonEncode(_playlists));
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Импортировано: $name (${tracks.length} треков)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта: $e')),
        );
      }
    }
  }

  Future<void> _loadPlaylist(int index) async {
    final pl = _playlists[index];
    final tracksJson = pl['tracks'] as List<dynamic>;
    final tracks = tracksJson
        .map((j) => Track.fromJson(j as Map<String, dynamic>))
        .toList(growable: false);
    ref.read(libraryStateProvider.notifier).setPickedTracks(tracks);
    await ref.read(playbackServiceProvider).playQueue(tracks: tracks, startIndex: 0);
    ref.read(isPlayingProvider.notifier).state = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Загружен плейлист "${pl['name']}" (${tracks.length} треков)')),
    );
  }

  Future<void> _deletePlaylist(int index) async {
    final pl = _playlists[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1410),
        title: const Text('Удалить плейлист?', style: TextStyle(color: Color(0xFFF4E9D2))),
        content: Text('"${pl['name']}"', style: const TextStyle(color: Color(0xFFF4E9D2))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена', style: TextStyle(color: Color(0xFF8A7F6A)))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Удалить', style: TextStyle(color: Color(0xFFFF6B1A)))),
        ],
      ),
    );
    if (confirmed != true) return;
    _playlists.removeAt(index);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('pathephon.playlists', jsonEncode(_playlists));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveCurrentPlaylist,
              icon: const Icon(Icons.save),
              label: const Text('Сохранить текущий'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TubeColors.amber,
                foregroundColor: TubeColors.background,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _exportToM3u,
                icon: const Icon(Icons.file_download),
                label: const Text('Экспорт .m3u'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TubeColors.brass,
                  foregroundColor: TubeColors.background,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _importFromM3u,
                icon: const Icon(Icons.file_upload),
                label: const Text('Импорт .m3u'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TubeColors.brass,
                  foregroundColor: TubeColors.background,
                ),
              ),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: _playlists.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.playlist_add, size: 80, color: TubeColors.brass),
                  const SizedBox(height: 16),
                  Text(
                    'Нет сохранённых плейлистов',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: TubeColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Нажмите «Сохранить текущий» чтобы\nдобавить текущую очередь воспроизведения',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: TubeColors.textMuted, fontSize: 12),
                  ),
                ]),
              )
            : ListView.builder(
                itemCount: _playlists.length,
                itemBuilder: (_, i) {
                  final pl = _playlists[i];
                  final tracksCount = (pl['tracks'] as List).length;
                  final createdAt = DateTime.tryParse(pl['createdAt'] as String? ?? '');
                  final dateStr = createdAt != null
                      ? '${createdAt.day}.${createdAt.month}.${createdAt.year}'
                      : '';
                  return ListTile(
                    leading: const Icon(Icons.playlist_play, color: TubeColors.brass, size: 40),
                    title: Text(pl['name'] as String? ?? 'Без названия'),
                    subtitle: Text('$tracksCount треков  •  $dateStr'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: TubeColors.textMuted),
                      onPressed: () => _deletePlaylist(i),
                    ),
                    onTap: () => _loadPlaylist(i),
                  );
                },
              ),
      ),
    ]);
  }
}
// ============================================================================
//  library_winamp.dart — Легенда-styled Library screen
//  Replaces the retro LibraryScreen when skin == 'winamp'.
//
//  Features:
//    - WinampTitleBar with "ПАТЕФОН БИБЛИОТЕКА" title + НАЗАД button
//    - Tab strip: ТРЕКИ | ПЛЕЙЛИСТЫ (Winamp-styled toggle buttons)
//    - Action bar: ADD DIR | ADD FILES | SAVE | EXP | IMP | SEARCH
//    - LCD background for track list / playlist list
//    - Winamp-styled list rows (24px tall, monospace)
//    - Skin-aware dialogs (uses LegendaDialog from winamp_theme.dart)
// ============================================================================
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/winamp_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/track.dart';
import '../../services/playback_service.dart';
import '../providers/providers.dart';
import '../providers/skin_provider.dart';

class LibraryWinamp extends ConsumerStatefulWidget {
  const LibraryWinamp({super.key, this.onBack});

  /// Tap НАЗАД button -> back to Now Playing
  final VoidCallback? onBack;

  @override
  ConsumerState<LibraryWinamp> createState() => _LibraryWinampState();
}

class _LibraryWinampState extends ConsumerState<LibraryWinamp> {
  bool _showPlaylists = false;
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _playlists = [];
  bool _playlistsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists() async {
    if (!mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString('pathephon.playlists');
    if (raw == null) {
      if (mounted) setState(() { _playlists = []; _playlistsLoaded = true; });
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      if (mounted) {
        setState(() {
          _playlists = list.cast<Map<String, dynamic>>();
          _playlistsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _playlists = []; _playlistsLoaded = true; });
    }
  }

  // === File / folder pickers ===
  Future<void> _pickAndPlayFiles() async {
    final playback = ref.read(playbackServiceProvider);
    try {
      final tracks = await ref.read(mediaStoreSourceProvider).pickAudioFiles();
      if (tracks.isEmpty) return;
      ref.read(libraryStateProvider.notifier).setPickedTracks(tracks);
      await playback.playQueue(tracks: tracks, startIndex: 0);
      ref.read(isPlayingProvider.notifier).state = true;
      // Switch back to Now Playing after adding
      if (mounted) widget.onBack?.call();
    } catch (_) {}
  }

  Future<void> _addFolderToQueue() async {
    try {
      final result =
          await ref.read(mediaStoreSourceProvider).pickDirectoryWithDiagnostic();
      if (result.tracks.isEmpty) {
        if (result.diagnostic.contains('null')) return;
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => LegendaDialog(
              title: '\u041F\u0410\u041F\u041A\u0410 \u041F\u0423\u0421\u0422\u0410',
              child: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.diagnostic,
                    style: TextStyle(
                        color: WinampColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.3),
                  ),
                ),
              ),
              primaryActions: [
                LegendaActionButton(
                    label: 'OK', onTap: () => Navigator.of(ctx).pop()),
              ],
            ),
          );
        }
        return;
      }
      await ref.read(libraryStateProvider.notifier).addToCurrentQueue(
          result.tracks, ProviderScope.containerOf(context));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u0414\u043E\u0431\u0430\u0432\u043B\u0435\u043D\u043E \u0442\u0440\u0435\u043A\u043E\u0432: ${result.tracks.length}')),
        );
      }
    } catch (_) {}
  }

  Future<void> _pickAndPlayFolder() async {
    final playback = ref.read(playbackServiceProvider);
    try {
      final result =
          await ref.read(mediaStoreSourceProvider).pickDirectoryWithDiagnostic();
      if (result.tracks.isEmpty) {
        if (result.diagnostic.contains('null')) return;
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => LegendaDialog(
              title: '\u0414\u0418\u0410\u0413\u041D\u041E\u0421\u0422\u0418\u041A\u0410',
              child: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.diagnostic,
                    style: TextStyle(
                        color: WinampColors.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.3),
                  ),
                ),
              ),
              primaryActions: [
                LegendaActionButton(
                    label: 'OK', onTap: () => Navigator.of(ctx).pop()),
              ],
            ),
          );
        }
        return;
      }
      ref.read(libraryStateProvider.notifier).setPickedTracks(result.tracks);
      await playback.playQueue(tracks: result.tracks, startIndex: 0);
      ref.read(isPlayingProvider.notifier).state = true;
      if (mounted) widget.onBack?.call();
    } catch (_) {}
  }

  // === Playlist actions ===
  Future<void> _saveCurrentPlaylist() async {
    final snap = ref.read(playbackSnapshotProvider).valueOrNull;
    if (snap == null || snap.queue.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u041E\u0447\u0435\u0440\u0435\u0434\u044C \u043F\u0443\u0441\u0442\u0430')),
        );
      }
      return;
    }
    String name = '\u041F\u043B\u0435\u0439\u043B\u0438\u0441\u0442 ${_playlists.length + 1}';
    if (!mounted) return;
    final controller = TextEditingController(text: name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => LegendaDialog(
        title: '\u0421\u041E\u0425\u0420\u0410\u041D\u0418\u0422\u042C \u041F\u041B\u0415\u0419\u041B\u0418\u0421\u0422',
        child: TextField(
          controller: controller,
          autofocus: true,
          style: lcdStyle(size: 12),
          decoration: InputDecoration(
            hintText: '\u041D\u0430\u0437\u0432\u0430\u043D\u0438\u0435',
            hintStyle: lcdStyle(size: 12, color: WinampColors.textMuted),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: WinampColors.metalMid)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: WinampColors.lcdText)),
          ),
        ),
        primaryActions: [
          LegendaActionButton(
              label: '\u041E\u0422\u041C\u0415\u041D\u0410',
              onTap: () => Navigator.of(ctx).pop()),
          LegendaActionButton(
              label: '\u0421\u041E\u0425\u0420\u0410\u041D\u0418\u0422\u042C',
              onTap: () => Navigator.of(ctx).pop(controller.text.trim())),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    name = result;

    final prefs = ref.read(sharedPreferencesProvider);
    final newPlaylist = {
      'id': 'playlist_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
      'tracks': snap.queue.map((t) => t.toJson()).toList(),
    };
    _playlists.insert(0, newPlaylist);
    await prefs.setString('pathephon.playlists', jsonEncode(_playlists));
    if (mounted) setState(() {});
  }

  Future<void> _loadPlaylist(int index) async {
    if (!mounted) return;
    final pl = _playlists[index];
    final tracksJson = pl['tracks'] as List<dynamic>;
    final tracks = tracksJson
        .map((j) => Track.fromJson(j as Map<String, dynamic>))
        .toList(growable: false);
    final libraryNotifier = ref.read(libraryStateProvider.notifier);
    final playback = ref.read(playbackServiceProvider);
    libraryNotifier.setPickedTracks(tracks);
    await playback.playQueue(tracks: tracks, startIndex: 0);
    if (!mounted) return;
    ref.read(isPlayingProvider.notifier).state = true;
    if (mounted) widget.onBack?.call();
  }

  Future<void> _deletePlaylist(int index) async {
    if (!mounted) return;
    final pl = _playlists[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => LegendaDialog(
        title: '\u0423\u0414\u0410\u041B\u0418\u0422\u042C?',
        child: Text('"${pl['name']}"',
            style: lcdStyle(size: 12, color: WinampColors.lcdText)),
        primaryActions: [
          LegendaActionButton(
              label: '\u041E\u0422\u041C\u0415\u041D\u0410',
              onTap: () => Navigator.of(ctx).pop(false)),
          LegendaActionButton(
              label: '\u0423\u0414\u0410\u041B\u0418\u0422\u042C',
              onTap: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
    if (confirmed != true) return;
    _playlists.removeAt(index);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString('pathephon.playlists', jsonEncode(_playlists));
    if (mounted) setState(() {});
  }

  Future<void> _exportToM3u() async {
    if (_playlists.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u041D\u0435\u0442 \u043F\u043B\u0435\u0439\u043B\u0438\u0441\u0442\u043E\u0432')),
        );
      }
      return;
    }
    int? selectedIndex;
    if (!mounted) return;
    selectedIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => LegendaDialog(
        title: '\u042D\u041A\u0421\u041F\u041E\u0420\u0422',
        child: SizedBox(
          width: double.maxFinite,
          height: 280,
          child: ListView.builder(
            itemCount: _playlists.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.of(ctx).pop(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: WinampColors.metalDark, width: 0.5))),
                child: Text(_playlists[i]['name'] as String,
                    style: lcdStyle(size: 12)),
              ),
            ),
          ),
        ),
        primaryActions: [
          LegendaActionButton(
              label: '\u041E\u0422\u041C\u0415\u041D\u0410',
              onTap: () => Navigator.of(ctx).pop()),
        ],
      ),
    );
    if (selectedIndex == null) return;
    final pl = _playlists[selectedIndex];
    final tracksJson = pl['tracks'] as List<dynamic>;
    final tracks = tracksJson
        .map((j) => Track.fromJson(j as Map<String, dynamic>))
        .toList();
    try {
      final result = await FilePicker.getDirectoryPath();
      if (result == null) return;
      final name = pl['name'] as String? ?? 'playlist';
      final file = File('$result/$name.m3u');
      final buf = StringBuffer();
      buf.writeln('#EXTM3U');
      for (final t in tracks) {
        buf.writeln(
            '#EXTINF:${t.durationMs ~/ 1000},${t.artist.isNotEmpty ? "${t.artist} - " : ""}${t.title}');
        final path = t.filePath.isNotEmpty ? t.filePath : t.uri;
        buf.writeln(path);
      }
      await file.writeAsString(buf.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u042D\u043A\u0441\u043F\u043E\u0440\u0442: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u041E\u0448\u0438\u0431\u043A\u0430: $e')),
        );
      }
    }
  }

  Future<void> _importFromM3u() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
      );
      if (result == null || result.isEmpty) return;
      final path = result.first.path;
      if (path == null) return;
      final file = File(path);
      final content = await file.readAsString();
      final lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      final tracks = <Track>[];
      String? pendingTitle;
      String? pendingArtist;
      int? pendingDuration;
      for (final line in lines) {
        if (line.startsWith('#EXTM3U')) continue;
        if (line.startsWith('#EXTINF:')) {
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
        final uri = line.startsWith('file://') || line.startsWith('content://')
            ? line
            : Uri.file(line).toString();
        tracks.add(Track(
          id: uri,
          uri: uri,
          filePath: line.startsWith('file://')
              ? Uri.parse(line).toFilePath()
              : line,
          title: pendingTitle ??
              line
                  .split('/')
                  .last
                  .replaceAll(RegExp(r'\.(mp3|flac|ogg|m4a|wav|opus|aac)$'), ''),
          artist: pendingArtist ?? '',
          durationMs: (pendingDuration ?? 0) * 1000,
        ));
        pendingTitle = null;
        pendingArtist = null;
        pendingDuration = null;
      }
      if (tracks.isEmpty) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final name =
          path.split('/').last.replaceAll(RegExp(r'\.(m3u|m3u8)$'), '');
      final newPlaylist = {
        'id': 'playlist_${DateTime.now().millisecondsSinceEpoch}',
        'name': name,
        'createdAt': DateTime.now().toIso8601String(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };
      _playlists.insert(0, newPlaylist);
      await prefs.setString('pathephon.playlists', jsonEncode(_playlists));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryStateProvider);
    final playback = ref.watch(playbackServiceProvider);

    return Scaffold(
      backgroundColor: WinampColors.bgMain,
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: WinampColors.bgPanel,
            border: Border.all(color: WinampColors.metalMid, width: 2),
          ),
          child: Column(children: [
            // Title bar (no trailing button — НАЗАД is now in the action grid below)
            WinampTitleBar(
              title: '\u041F\u0410\u0422\u0415\u0424\u041E\u041D \u0411\u0418\u0411\u041B\u0418\u041E\u0422\u0415\u041A\u0410',
            ),
            // Action bar: tab toggles + 2x4 action button grid + search
            Container(
              color: WinampColors.bgPanel,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(children: [
                // Row 1: tab toggles ТРЕКИ | ПЛЕЙЛИСТЫ
                Row(children: [
                  Expanded(
                    child: _LegendaTabButton(
                      label: '\u0422\u0420\u0415\u041A\u0418',
                      active: !_showPlaylists,
                      onTap: () => setState(() => _showPlaylists = false),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _LegendaTabButton(
                      label: '\u041F\u041B\u0415\u0419\u041B\u0418\u0421\u0422\u042B',
                      active: _showPlaylists,
                      onTap: () => setState(() => _showPlaylists = true),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                // Action buttons row 1: DIR | ADD | FILE | SAVE
                Row(children: [
                  Expanded(child: _LegendaActBtn(
                      label: 'DIR',
                      icon: Icons.folder_open,
                      onTap: _pickAndPlayFolder)),
                  const SizedBox(width: 4),
                  Expanded(child: _LegendaActBtn(
                      label: 'ADD',
                      icon: Icons.playlist_add,
                      onTap: _addFolderToQueue)),
                  const SizedBox(width: 4),
                  Expanded(child: _LegendaActBtn(
                      label: 'FILE',
                      icon: Icons.audio_file,
                      onTap: _pickAndPlayFiles)),
                  const SizedBox(width: 4),
                  Expanded(child: _LegendaActBtn(
                      label: 'SAVE',
                      icon: Icons.save,
                      onTap: _saveCurrentPlaylist)),
                ]),
                const SizedBox(height: 4),
                // Action buttons row 2: EXP | IMP | FIND | НАЗАД
                Row(children: [
                  Expanded(child: _LegendaActBtn(
                      label: 'EXP',
                      icon: Icons.file_download,
                      onTap: _exportToM3u)),
                  const SizedBox(width: 4),
                  Expanded(child: _LegendaActBtn(
                      label: 'IMP',
                      icon: Icons.file_upload,
                      onTap: _importFromM3u)),
                  const SizedBox(width: 4),
                  Expanded(child: _LegendaActBtn(
                      label: _isSearching ? 'CLOSE' : 'FIND',
                      icon: _isSearching ? Icons.close : Icons.search,
                      onTap: () {
                        setState(() {
                          _isSearching = !_isSearching;
                          if (!_isSearching) {
                            _searchQuery = '';
                            _searchController.clear();
                          }
                        });
                      })),
                  const SizedBox(width: 4),
                  Expanded(child: _LegendaActBtn(
                      label: '\u041D\u0410\u0417\u0410\u0414',
                      icon: Icons.arrow_back,
                      onTap: () => widget.onBack?.call())),
                ]),
                // Search field (when active)
                if (_isSearching && !_showPlaylists)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: WinampColors.lcdBg,
                      border: Border.all(color: WinampColors.metalMid, width: 1),
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: lcdStyle(size: 12),
                      decoration: InputDecoration(
                        hintText: '\u041F\u043E\u0438\u0441\u043A...',
                        hintStyle: lcdStyle(size: 12, color: WinampColors.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.toLowerCase()),
                    ),
                  ),
              ]),
            ),
            // Content: tracks or playlists
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: WinampColors.lcdBg,
                  border: Border.all(color: WinampColors.metalDark, width: 1),
                ),
                child: _showPlaylists
                    ? _buildPlaylistsList()
                    : state.when(
                        loading: () => Center(
                          child: CircularProgressIndicator(
                              color: WinampColors.lcdText, strokeWidth: 2),
                        ),
                        error: (e, _) => Center(
                          child: Text('\u041E\u0448\u0438\u0431\u043A\u0430: $e',
                              style: lcdStyle(size: 11, color: WinampColors.textMuted)),
                        ),
                        data: (tracks) {
                          final filtered = _searchQuery.isEmpty
                              ? tracks
                              : tracks.where((t) {
                                  final q = _searchQuery;
                                  return t.title.toLowerCase().contains(q) ||
                                      t.artist.toLowerCase().contains(q) ||
                                      t.album.toLowerCase().contains(q) ||
                                      t.filePath.toLowerCase().contains(q);
                                }).toList();
                          if (filtered.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.library_music,
                                      size: 48, color: WinampColors.lcdDim),
                                  const SizedBox(height: 8),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? '\u041D\u0438\u0447\u0435\u0433\u043E \u043D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D\u043E'
                                        : '\u0424\u0410\u0419\u041B\u042B \u041D\u0415 \u0412\u042B\u0411\u0420\u0410\u041D\u042B',
                                    style: lcdStyle(
                                        size: 12, color: WinampColors.textSecondary),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '\u041D\u0430\u0436\u043C\u0438\u0442\u0435 DIR \u0438\u043B\u0438 FILE',
                                    style: lcdStyle(
                                        size: 10, color: WinampColors.textMuted),
                                  ),
                                ],
                              ),
                            );
                          }
                          return ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: filtered.length,
                            itemExtent: 24,
                            itemBuilder: (_, i) {
                              final t = filtered[i];
                              return GestureDetector(
                                onTap: () {
                                  playback.playQueue(
                                      tracks: filtered, startIndex: i);
                                  ref.read(isPlayingProvider.notifier).state =
                                      true;
                                  widget.onBack?.call();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  child: Row(children: [
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '${(i + 1).toString().padLeft(2, '0')}',
                                        style: lcdStyle(
                                            size: 11,
                                            color: WinampColors.textMuted),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        t.title,
                                        style: lcdStyle(size: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (t.artist.isNotEmpty)
                                      Text(
                                        ' ${t.artist}',
                                        style: lcdStyle(
                                            size: 10,
                                            color: WinampColors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (t.durationMs > 0)
                                      Text(
                                        ' ${formatDuration(Duration(milliseconds: t.durationMs))}',
                                        style: lcdStyle(
                                            size: 10,
                                            color: WinampColors.textMuted),
                                      ),
                                  ]),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPlaylistsList() {
    if (!_playlistsLoaded) {
      return Center(
        child: CircularProgressIndicator(
            color: WinampColors.lcdText, strokeWidth: 2),
      );
    }
    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add, size: 48, color: WinampColors.lcdDim),
            const SizedBox(height: 8),
            Text('\u041D\u0415\u0422 \u041F\u041B\u0415\u0419\u041B\u0418\u0421\u0422\u041E\u0412',
                style: lcdStyle(size: 12, color: WinampColors.textSecondary)),
            const SizedBox(height: 6),
            Text('\u041D\u0430\u0436\u043C\u0438\u0442\u0435 SAVE',
                style: lcdStyle(size: 10, color: WinampColors.textMuted)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _playlists.length,
      itemExtent: 32,
      itemBuilder: (_, i) {
        final pl = _playlists[i];
        final tracksCount = (pl['tracks'] as List).length;
        return Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _loadPlaylist(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Icon(Icons.playlist_play,
                        size: 16, color: WinampColors.lcdText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        pl['name'] as String? ?? '',
                        style: lcdStyle(size: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(' [$tracksCount]',
                        style: lcdStyle(
                            size: 10, color: WinampColors.textMuted)),
                  ]),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _deletePlaylist(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.delete_outline,
                    size: 14, color: WinampColors.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Compact Winamp-styled tab toggle button.
class _LegendaTabButton extends StatelessWidget {
  const _LegendaTabButton(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 22,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: active
                ? [WinampColors.metalDark, WinampColors.metalDarker]
                : [WinampColors.metalLight, WinampColors.metalMid, WinampColors.metalDark],
          ),
          border: Border.all(color: WinampColors.metalDarker, width: 1),
        ),
        child: Center(
          child: Text(label,
              style: lcdStyle(
                      size: 10,
                      color: active
                          ? WinampColors.lcdText
                          : WinampColors.metalDarker)
                  .copyWith(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

/// Winamp-styled action button (icon + label below).
/// 50% larger than original: height 48 (was 32), icon 18 (was 12), label 11pt (was 7pt).
/// No fixed width — parent uses Expanded so all buttons in a row share width equally.
class _LegendaActBtn extends StatelessWidget {
  const _LegendaActBtn(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              WinampColors.metalLight,
              WinampColors.metalMid,
              WinampColors.metalDark
            ],
          ),
          border: Border.all(color: WinampColors.metalDarker, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: WinampColors.metalDarker),
            const SizedBox(height: 2),
            Text(label,
                style: lcdStyle(size: 11, color: WinampColors.metalDarker)
                    .copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

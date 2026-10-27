import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/tube_colors.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  List<Track> _results = [];

  void _doSearch(List<Track> tracks) {
    if (_query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    final q = _query.toLowerCase();
    setState(() {
      _results = tracks.where((t) =>
        t.title.toLowerCase().contains(q) ||
        t.artist.toLowerCase().contains(q) ||
        t.album.toLowerCase().contains(q) ||
        t.filePath.toLowerCase().contains(q)
      ).toList();
    });
  }

  Future<void> _saveAsPlaylist() async {
    if (_results.isEmpty) return;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: 'Поиск: $_query');
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1410),
          title: const Text('Сохранить как плейлист', style: TextStyle(color: Color(0xFFF4E9D2))),
          content: TextField(controller: c, autofocus: true, style: const TextStyle(color: Color(0xFFF4E9D2))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Color(0xFF8A7F6A)))),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Сохранить', style: TextStyle(color: Color(0xFFFF6B1A)))),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString('pathephon.playlists') ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.insert(0, {
      'id': 'playlist_${DateTime.now().millisecondsSinceEpoch}',
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
      'tracks': _results.map((t) => t.toJson()).toList(),
    });
    await prefs.setString('pathephon.playlists', jsonEncode(list));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Сохранено: $name (${_results.length} треков)')));
    }
  }

  void _playAll() {
    if (_results.isEmpty) return;
    final playback = ref.read(playbackServiceProvider);
    ref.read(libraryStateProvider.notifier).setPickedTracks(_results);
    playback.playQueue(tracks: _results, startIndex: 0);
    ref.read(isPlayingProvider.notifier).state = true;
  }

  void _showTrackOptions(Track t, int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.play_arrow, color: Color(0xFFFF6B1A)),
            title: const Text('Воспроизвести', style: TextStyle(color: Color(0xFFF4E9D2))),
            onTap: () {
              Navigator.pop(ctx);
              final playback = ref.read(playbackServiceProvider);
              playback.playQueue(tracks: _results, startIndex: index);
              ref.read(isPlayingProvider.notifier).state = true;
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Color(0xFFFF6B1A)),
            title: const Text('Добавить в очередь', style: TextStyle(color: Color(0xFFF4E9D2))),
            onTap: () {
              Navigator.pop(ctx);
              ref.read(libraryStateProvider.notifier).addToCurrentQueue([t], ProviderScope.containerOf(context));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Добавлено: ${t.title}')));
              }
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryStateProvider);
    final tracks = state.valueOrNull ?? const <Track>[];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: TubeColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Поиск по библиотеке...',
            hintStyle: TextStyle(color: TubeColors.textMuted),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty ? IconButton(
              icon: const Icon(Icons.clear, color: TubeColors.textMuted),
              onPressed: () { _controller.clear(); setState(() { _query = ''; _results = []; }); },
            ) : null,
          ),
          onChanged: (v) { _query = v; _doSearch(tracks); },
        ),
        actions: [
          if (_results.isNotEmpty) IconButton(
            icon: const Icon(Icons.save, color: TubeColors.brass),
            tooltip: 'Сохранить как плейлист',
            onPressed: _saveAsPlaylist,
          ),
          if (_results.isNotEmpty) IconButton(
            icon: const Icon(Icons.play_circle, color: TubeColors.brass),
            tooltip: 'Воспроизвести все',
            onPressed: _playAll,
          ),
        ],
      ),
      body: _results.isEmpty && _query.isNotEmpty
        ? const Center(child: Text('Ничего не найдено', style: TextStyle(color: TubeColors.textMuted)))
        : _results.isEmpty
          ? const Center(child: Icon(Icons.search, size: 80, color: TubeColors.brass))
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final t = _results[i];
                return ListTile(
                  leading: const Icon(Icons.music_note, color: TubeColors.brass),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TubeColors.textPrimary)),
                  subtitle: Text([t.artist, t.album].where((s) => s.isNotEmpty).join(' - '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: TubeColors.textSecondary, fontSize: 12)),
                  onTap: () => _showTrackOptions(t, i),
                );
              },
            ),
    );
  }
}
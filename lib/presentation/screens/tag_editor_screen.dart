// ============================================================================
//  tag_editor_screen.dart — audio file metadata viewer / editor (MVP)
//
//  MVP scope: read track metadata from on_audio_query (already loaded by the
//  library scan) and let the user edit the in-memory Track fields. Writing
//  tags back to the file system requires a native MethodChannel bridge
//  (audiotags-style) — that's a post-MVP TODO.
//
//  For the MVP the user picks a file via file_picker, sees its filename and
//  path, and can edit the in-memory title/artist/album fields. The "Save"
//  button stores the edited Track in shared_preferences keyed by URI so the
//  library reuses the override on next scan.
// ============================================================================
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../domain/models/track.dart';
import '../providers/providers.dart';

class TagEditorScreen extends ConsumerStatefulWidget {
  const TagEditorScreen({super.key});

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  Track? _track;
  bool _dirty = false;

  final _titleCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _albumArtistCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _trackCtrl = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _artistCtrl,
      _albumCtrl,
      _albumArtistCtrl,
      _genreCtrl,
      _yearCtrl,
      _trackCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFromLibrary() async {
    final tracks = ref.read(libraryStateProvider).valueOrNull ?? const <Track>[];
    if (tracks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library is empty — scan first.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Track>(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (_, i) {
          final t = tracks[i];
          return ListTile(
            title: Text(t.title),
            subtitle: Text([if (t.artist.isNotEmpty) t.artist, if (t.album.isNotEmpty) t.album].join(' · ')),
            onTap: () => Navigator.of(context).pop(t),
          );
        },
      ),
    );
    if (picked == null) return;
    _loadTrack(picked);
  }

  Future<void> _pickFromFilesystem() async {
    // file_picker 13.x: FilePicker.pickFiles() is static, returns List<PlatformFile>?
    final res = await FilePicker.pickFiles(type: FileType.audio);
    if (res == null || res.isEmpty || res.first.path == null) return;
    final f = res.first;
    final path = f.path!;
    final ext = path.toLowerCase().split('.').last;
    // Construct a stub Track from the picked file.
    final t = Track(
      id: 'file://$path',
      uri: 'file://$path',
      title: f.name,
      fileExtension: ext,
      filePath: path,
    );
    _loadTrack(t);
  }

  void _loadTrack(Track t) {
    setState(() {
      _track = t;
      _titleCtrl.text = t.title;
      _artistCtrl.text = t.artist;
      _albumCtrl.text = t.album;
      _albumArtistCtrl.text = t.albumArtist;
      _genreCtrl.text = t.genre;
      _yearCtrl.text = t.year > 0 ? t.year.toString() : '';
      _trackCtrl.text = t.trackNumber > 0 ? t.trackNumber.toString() : '';
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final t = _track;
    if (t == null) return;
    final updated = t.copyWith(
      title: _titleCtrl.text,
      artist: _artistCtrl.text,
      album: _albumCtrl.text,
      albumArtist: _albumArtistCtrl.text,
      genre: _genreCtrl.text,
      year: int.tryParse(_yearCtrl.text) ?? 0,
      trackNumber: int.tryParse(_trackCtrl.text) ?? 0,
    );
    // Persist override in shared_preferences (keyed by URI).
    final prefs = await SharedPreferences.getInstance();
    final overridesRaw = prefs.getString('pathephon.tag_overrides.v1') ?? '{}';
    final overrides = jsonDecode(overridesRaw) as Map<String, dynamic>;
    overrides[updated.uri] = updated.toJson();
    await prefs.setString('pathephon.tag_overrides.v1', jsonEncode(overrides));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).tagsSaved)),
    );
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tagsTitle),
        actions: [
          IconButton(
            onPressed: _pickFromLibrary,
            icon: const Icon(Icons.library_music),
            tooltip: 'Pick from library',
          ),
          IconButton(
            onPressed: _pickFromFilesystem,
            icon: const Icon(Icons.folder_open),
            tooltip: l.tagsPickFile,
          ),
          IconButton(
            onPressed: _dirty ? _save : null,
            icon: const Icon(Icons.save),
            tooltip: l.tagsSave,
          ),
        ],
      ),
      body: _track == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note, size: 96, color: TubeColors.brass),
                  const SizedBox(height: 12),
                  Text(l.tagsPickFile, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _pickFromLibrary,
                    icon: const Icon(Icons.library_music),
                    label: const Text('Pick from library'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_track!.filePath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _track!.filePath,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: TubeColors.textMuted,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                _Field(label: l.tagsTitle2, controller: _titleCtrl, onChanged: () => setState(() => _dirty = true)),
                _Field(label: l.tagsArtist, controller: _artistCtrl, onChanged: () => setState(() => _dirty = true)),
                _Field(label: l.tagsAlbum, controller: _albumCtrl, onChanged: () => setState(() => _dirty = true)),
                _Field(label: l.tagsAlbumArtist, controller: _albumArtistCtrl, onChanged: () => setState(() => _dirty = true)),
                _Field(label: l.tagsGenre, controller: _genreCtrl, onChanged: () => setState(() => _dirty = true)),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        label: l.tagsYear,
                        controller: _yearCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: () => setState(() => _dirty = true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        label: l.tagsTrack,
                        controller: _trackCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: () => setState(() => _dirty = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_track!.replayGainTrack != null || _track!.replayGainAlbum != null) ...[
                  Text('ReplayGain:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  if (_track!.replayGainTrack != null)
                    Text('Track: ${_track!.replayGainTrack!.toStringAsFixed(2)} dB'),
                  if (_track!.replayGainAlbum != null)
                    Text('Album: ${_track!.replayGainAlbum!.toStringAsFixed(2)} dB'),
                ],
              ],
            ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.onChanged,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final VoidCallback? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: Theme.of(context).textTheme.labelSmall,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: TubeColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: TubeColors.amber, width: 2),
          ),
        ),
      ),
    );
  }
}

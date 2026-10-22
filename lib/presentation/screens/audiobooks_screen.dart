// ============================================================================
//  audiobooks_screen.dart — list + sleep timer + bookmarks
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tube_colors.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/models/audiobook.dart';
import '../../domain/models/bookmark.dart';
import '../providers/providers.dart';

class AudiobooksScreen extends ConsumerWidget {
  const AudiobooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(audiobooksStateProvider);
    final sleep = ref.watch(sleepRemainingProvider).valueOrNull;
    final abSvc = ref.watch(audioBookServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.audiobooksTitle),
        actions: [
          if (sleep != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  formatDuration(sleep),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: TubeColors.phosphorGreen),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.bedtime),
            onSelected: (v) {
              switch (v) {
                case '15':
                  abSvc.startSleepTimer(const Duration(minutes: 15));
                  break;
                case '30':
                  abSvc.startSleepTimer(const Duration(minutes: 30));
                  break;
                case '60':
                  abSvc.startSleepTimer(const Duration(minutes: 60));
                  break;
                case 'cancel':
                  abSvc.cancelSleepTimer();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: '15', child: Text(l.audiobooksSleep15)),
              PopupMenuItem(value: '30', child: Text(l.audiobooksSleep30)),
              PopupMenuItem(value: '60', child: Text(l.audiobooksSleep60)),
              const PopupMenuItem(value: 'cancel', child: Text('Отмена')),
            ],
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${l.commonError}: $e')),
        data: (books) {
          if (books.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.audiobooksEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: books.length,
            itemBuilder: (_, i) => _AudiobookTile(book: books[i]),
          );
        },
      ),
    );
  }
}

class _AudiobookTile extends ConsumerWidget {
  const _AudiobookTile({required this.book});
  final Audiobook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final abSvc = ref.watch(audioBookServiceProvider);

    return ExpansionTile(
      title: Text(book.title),
      subtitle: Text([
        if (book.author.isNotEmpty) book.author,
        formatDuration(Duration(milliseconds: book.totalDurationMs)),
      ].join(' · ')),
      leading: const Icon(Icons.menu_book, color: TubeColors.brass),
      children: [
        if (book.lastPositionMs > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l.audiobooksContinue(formatDuration(Duration(milliseconds: book.lastPositionMs))),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: TubeColors.amber),
              ),
            ),
          ),
        FutureBuilder<List<Bookmark>>(
          future: abSvc.bookmarks(book.id),
          builder: (_, snap) {
            final bm = snap.data ?? const <Bookmark>[];
            return Column(
              children: [
                for (final b in bm)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.bookmark, color: TubeColors.amber, size: 18),
                    title: Text(b.label.isEmpty ? formatDuration(Duration(milliseconds: b.positionMs)) : b.label),
                    onTap: () => abSvc.jumpToBookmark(b),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, size: 18),
                      onPressed: () => abSvc.deleteBookmark(b.id),
                    ),
                  ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add, color: TubeColors.phosphorGreen),
                  title: Text(l.audiobooksAddBookmark),
                  onTap: () async {
                    await abSvc.addBookmark(audiobookId: book.id);
                    ref.invalidate(audiobooksStateProvider);
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

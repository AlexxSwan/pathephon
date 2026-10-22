// ============================================================================
//  duration_format.dart — format Duration like a vintage tape counter
// ============================================================================
import 'package:intl/intl.dart';

/// Returns `mm:ss` for tracks under an hour, `h:mm:ss` otherwise.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Returns "1 ч 23 мин" / "1h 23m" depending on locale.
String formatLongDuration(Duration d, String locale) {
  final isRu = locale.startsWith('ru');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) {
    return isRu ? '$h ч $m мин' : '${h}h ${m}m';
  }
  if (m > 0) {
    final s = d.inSeconds.remainder(60);
    return isRu ? '$m мин $s сек' : '${m}m ${s}s';
  }
  final s = d.inSeconds;
  return isRu ? '$s сек' : '${s}s';
}

/// Returns file size like "12.4 МБ" / "12.4 MB".
String formatBytes(int bytes, String locale) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} ${locale.startsWith('ru') ? 'КБ' : 'KB'}';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} ${locale.startsWith('ru') ? 'МБ' : 'MB'}';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} ${locale.startsWith('ru') ? 'ГБ' : 'GB'}';
}

/// Format date like "12 янв. 1985" / "Jan 12, 1985".
String formatDate(DateTime d, String locale) {
  final fmt = DateFormat.yMMMd(locale.startsWith('ru') ? 'ru_RU' : 'en_US');
  return fmt.format(d);
}

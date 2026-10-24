// ============================================================================
//  permission_gate.dart - one-time permission request screen
//
//  Requests: audio + photos + notification
//  Notification is REQUIRED on Android 13+ for audio_service to show
//  lock screen widget and notification controls.
// ============================================================================
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/tube_colors.dart';
import '../providers/providers.dart';

class PermissionGate extends ConsumerStatefulWidget {
  const PermissionGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends ConsumerState<PermissionGate> {
  bool? _audioGranted;
  bool? _imagesGranted;
  bool? _notifGranted;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final flagGranted = prefs.getBool('pathephon.permissions.granted') ?? false;
    debugPrint('[pathephon] PermissionGate: flagGranted=$flagGranted');

    final audio = await Permission.audio.status;
    final photos = await Permission.photos.status;
    final notif = await Permission.notification.status;
    debugPrint('[pathephon] PermissionGate: audio=$audio, photos=$photos, notif=$notif');

    if (flagGranted && audio.isGranted && photos.isGranted && notif.isGranted) {
      setState(() {
        _audioGranted = true;
        _imagesGranted = true;
        _notifGranted = true;
        _checking = false;
      });
      return;
    }

    setState(() {
      _audioGranted = audio.isGranted;
      _imagesGranted = photos.isGranted;
      _notifGranted = notif.isGranted;
      _checking = false;
    });
  }

  Future<void> _requestAll() async {
    setState(() => _checking = true);
    final audio = await Permission.audio.request();
    final photos = await Permission.photos.request();
    final notif = await Permission.notification.request();
    debugPrint('[pathephon] PermissionGate: requested audio=$audio, photos=$photos, notif=$notif');

    final prefs = ref.read(sharedPreferencesProvider);
    final allGranted = audio.isGranted && photos.isGranted && notif.isGranted;
    if (allGranted) {
      await prefs.setBool('pathephon.permissions.granted', true);
    }
    setState(() {
      _audioGranted = audio.isGranted;
      _imagesGranted = photos.isGranted;
      _notifGranted = notif.isGranted;
      _checking = false;
    });
  }

  Future<void> _skip() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('pathephon.permissions.granted', true);
    setState(() {
      _audioGranted = true;
      _imagesGranted = true;
      _notifGranted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1410),
        body: Center(child: CircularProgressIndicator(color: TubeColors.amberHot)),
      );
    }

    final allOk = _audioGranted == true && _imagesGranted == true && _notifGranted == true;
    if (allOk) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1410),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.graphic_eq, size: 100, color: TubeColors.amber),
              const SizedBox(height: 24),
              Text(
                "\u041F\u0430\u0442\u0435\u0444\u043E\u043D",
                style: Theme.of(context).textTheme.displaySmall?.copyWith(color: TubeColors.amberHot),
              ),
              const SizedBox(height: 32),
              Text(
                "\u0414\u043B\u044F \u0440\u0430\u0431\u043E\u0442\u044B \u043D\u0435\u043E\u0431\u0445\u043E\u0434\u0438\u043C\u044B \u0440\u0430\u0437\u0440\u0435\u0448\u0435\u043D\u0438\u044F:",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: TubeColors.textPrimary),
              ),
              const SizedBox(height: 24),
              _PermissionRow(
                icon: Icons.library_music,
                title: "\u0410\u0443\u0434\u0438\u043E\u0444\u0430\u0439\u043B\u044B",
                desc: "\u0414\u043E\u0441\u0442\u0443\u043F \u043A \u043C\u0443\u0437\u044B\u043A\u0435",
                granted: _audioGranted == true,
              ),
              const SizedBox(height: 12),
              _PermissionRow(
                icon: Icons.image,
                title: "\u0418\u0437\u043E\u0431\u0440\u0430\u0436\u0435\u043D\u0438\u044F",
                desc: "\u0414\u043E\u0441\u0442\u0443\u043F \u043A \u043E\u0431\u043B\u043E\u0436\u043A\u0430\u043C",
                granted: _imagesGranted == true,
              ),
              const SizedBox(height: 12),
              _PermissionRow(
                icon: Icons.notifications,
                title: "\u0423\u0432\u0435\u0434\u043E\u043C\u043B\u0435\u043D\u0438\u044F",
                desc: "\u0423\u043F\u0440\u0430\u0432\u043B\u0435\u043D\u0438\u0435 \u043D\u0430 \u044D\u043A\u0440\u0430\u043D\u0435 \u0431\u043B\u043E\u043A\u0438\u0440\u043E\u0432\u043A\u0438",
                granted: _notifGranted == true,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _requestAll,
                  icon: const Icon(Icons.check_circle_outline, color: Color(0xFF1A1410)),
                  label: const Text(
                    "\u0420\u0430\u0437\u0440\u0435\u0448\u0438\u0442\u044C",
                    style: TextStyle(color: Color(0xFF1A1410), fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TubeColors.amberHot,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings, color: TubeColors.brass),
                label: const Text(
                  "\u041E\u0442\u043A\u0440\u044B\u0442\u044C \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0438",
                  style: TextStyle(color: TubeColors.brass),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _skip,
                child: const Text(
                  "\u041F\u0440\u043E\u043F\u0443\u0441\u0442\u0438\u0442\u044C",
                  style: TextStyle(color: TubeColors.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
  });
  final IconData icon;
  final String title;
  final String desc;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF241B14),
        border: Border.all(
          color: granted ? TubeColors.phosphorGreen : TubeColors.brass,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: granted ? TubeColors.phosphorGreen : TubeColors.brass, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: TubeColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: TubeColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Icon(
            granted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: granted ? TubeColors.phosphorGreen : TubeColors.textMuted,
            size: 24,
          ),
        ],
      ),
    );
  }
}
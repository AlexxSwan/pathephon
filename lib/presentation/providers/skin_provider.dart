// ============================================================================
//  skin_provider.dart — Riverpod provider for skin switching
//  Reads initial value from SharedPreferences, defaults to 'retro'
// ============================================================================
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

/// 'retro' or 'winamp'. Persisted in SharedPreferences as 'pathephon.skin'.
final skinProvider = StateProvider<String>((ref) {
  return ref.read(sharedPreferencesProvider).getString('pathephon.skin') ?? 'retro';
});

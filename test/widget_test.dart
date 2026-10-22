// Smoke test — verifies AppLocalizations delegates and supported locales.
//
// The gen-l10n-generated AppLocalizations is abstract and requires a
// Localizations context to instantiate. We test the static surface only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pathephon/core/l10n/generated/app_localizations.dart';

void main() {
  test('AppLocalizations supports RU and EN', () {
    expect(AppLocalizations.supportedLocales, contains(const Locale('ru')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
  });

  test('Localizations delegate loads both locales', () async {
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    expect(ru.appTitle, 'Патефон');

    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.appTitle, 'Pathephon');
  });
}

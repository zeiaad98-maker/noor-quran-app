import 'package:shared_preferences/shared_preferences.dart';

/// Ayah marks (v13.3, FIX B — the SurahApp-style word popup toolbar):
/// * فاصل (bookmark): the user marks an ayah to return to. Stored
///   as a set of "surah:verse" ids in SharedPreferences.
/// * تلوين (highlight): the user colours an ayah. Stored the same
///   way, as a separate set — a coloured ayah gets a green tint on
///   the Mushaf page, a bookmarked / noted ayah a gold one.
///
/// Both are plain id sets (no text is invented or stored); the
/// reader loads them together with the noted ids to tint the page,
/// and the ملاحظاتي screen lists the bookmarks (الفواصل) so the
/// user can jump back to them.
class AyahBookmarks {
  static const String _key = 'bookmarked_ayahs';

  static String idFor(int surah, int verse) => '$surah:$verse';

  static Future<Set<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  static Future<bool> isBookmarked(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const [])
        .contains(idFor(surah, verse));
  }

  /// Toggles the bookmark; returns true when the ayah is now
  /// bookmarked, false when it was removed.
  static Future<bool> toggle(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key) ?? const []).toSet();
    final id = idFor(surah, verse);
    final nowBookmarked = !ids.contains(id);
    if (nowBookmarked) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    await prefs.setStringList(_key, ids.toList()..sort());
    return nowBookmarked;
  }

  static Future<void> remove(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key) ?? const []).toSet();
    if (ids.remove(idFor(surah, verse))) {
      await prefs.setStringList(_key, ids.toList()..sort());
    }
  }
}

class AyahHighlights {
  static const String _key = 'highlighted_ayahs';

  static String idFor(int surah, int verse) => '$surah:$verse';

  static Future<Set<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const []).toSet();
  }

  static Future<bool> isHighlighted(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const [])
        .contains(idFor(surah, verse));
  }

  /// Toggles the colour; returns true when the ayah is now coloured,
  /// false when the colour was removed.
  static Future<bool> toggle(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key) ?? const []).toSet();
    final id = idFor(surah, verse);
    final nowHighlighted = !ids.contains(id);
    if (nowHighlighted) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    await prefs.setStringList(_key, ids.toList()..sort());
    return nowHighlighted;
  }

  static Future<void> remove(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_key) ?? const []).toSet();
    if (ids.remove(idFor(surah, verse))) {
      await prefs.setStringList(_key, ids.toList()..sort());
    }
  }
}

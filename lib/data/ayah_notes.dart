import 'package:shared_preferences/shared_preferences.dart';

/// Per-ayah user notes, stored in SharedPreferences under
/// `ayah_note_<surah>_<verse>` (one key per ayah).
class AyahNote {
  final int surah;
  final int verse;
  final String text;

  const AyahNote({
    required this.surah,
    required this.verse,
    required this.text,
  });
}

class AyahNotes {
  static String keyFor(int surah, int verse) => 'ayah_note_${surah}_$verse';

  static String idFor(int surah, int verse) => '$surah:$verse';

  static Future<String?> getNote(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyFor(surah, verse));
  }

  static Future<void> saveNote(int surah, int verse, String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyFor(surah, verse), text);
  }

  static Future<void> deleteNote(int surah, int verse) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyFor(surah, verse));
  }

  /// Set of "surah:verse" ids that have a note (for verse highlighting).
  static Future<Set<String>> notedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = <String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('ayah_note_')) continue;
      final parts = key.substring('ayah_note_'.length).split('_');
      if (parts.length == 2) {
        ids.add('${parts[0]}:${parts[1]}');
      }
    }
    return ids;
  }

  /// All notes, ordered by surah then verse.
  static Future<List<AyahNote>> getAllNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notes = <AyahNote>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('ayah_note_')) continue;
      final parts = key.substring('ayah_note_'.length).split('_');
      if (parts.length != 2) continue;
      final surah = int.tryParse(parts[0]);
      final verse = int.tryParse(parts[1]);
      final text = prefs.getString(key);
      if (surah == null || verse == null || text == null || text.isEmpty) {
        continue;
      }
      notes.add(AyahNote(surah: surah, verse: verse, text: text));
    }
    notes.sort((a, b) {
      final bySurah = a.surah.compareTo(b.surah);
      return bySurah != 0 ? bySurah : a.verse.compareTo(b.verse);
    });
    return notes;
  }
}

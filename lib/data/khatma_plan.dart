import 'dart:convert';

import 'package:quran/quran.dart' as quran;

/// Khatma (full-Quran reading) plans.
///
/// A plan splits the 604 Mushaf pages into daily sessions. Sessions are
/// stored by page range, and the start/end surah:ayah of each session is
/// derived from the page data of the `quran` package, so the plan always
/// matches the Madinah Mushaf pagination the reader shows.
///
/// The plan is persisted as JSON in SharedPreferences under `khatma_plan`
/// (see [KhatmaPlan.toJson]/[KhatmaPlan.fromJson]).
///
/// Presets:
/// * 30 days — one juz per day (sessions follow the real juz boundaries).
/// * 15 days — two ajza per day.
/// * 7 days — the 604 pages split into 7 near-equal sessions.
/// * custom — a fixed number of pages per day chosen by the user.

/// Total pages of the Madinah Mushaf.
const int khatmaTotalPages = 604;

/// One daily reading session: a contiguous range of Mushaf pages.
class KhatmaSession {
  final int startPage;
  final int endPage;
  final int startSurah;
  final int startAyah;
  final int endSurah;
  final int endAyah;
  final bool done;

  const KhatmaSession({
    required this.startPage,
    required this.endPage,
    required this.startSurah,
    required this.startAyah,
    required this.endSurah,
    required this.endAyah,
    this.done = false,
  });

  /// Builds a session from a page range, reading the boundary
  /// surah:ayah from the `quran` package page data.
  factory KhatmaSession.fromPages(int startPage, int endPage) {
    final firstData = quran.getPageData(startPage);
    final lastData = quran.getPageData(endPage);
    return KhatmaSession(
      startPage: startPage,
      endPage: endPage,
      startSurah: firstData.first['surah'] as int,
      startAyah: firstData.first['start'] as int,
      endSurah: lastData.last['surah'] as int,
      endAyah: lastData.last['end'] as int,
    );
  }

  KhatmaSession copyWith({bool? done}) => KhatmaSession(
        startPage: startPage,
        endPage: endPage,
        startSurah: startSurah,
        startAyah: startAyah,
        endSurah: endSurah,
        endAyah: endAyah,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'startPage': startPage,
        'endPage': endPage,
        'startSurah': startSurah,
        'startAyah': startAyah,
        'endSurah': endSurah,
        'endAyah': endAyah,
        'done': done,
      };

  factory KhatmaSession.fromJson(Map<String, dynamic> json) =>
      KhatmaSession(
        startPage: json['startPage'] as int,
        endPage: json['endPage'] as int,
        startSurah: json['startSurah'] as int,
        startAyah: json['startAyah'] as int,
        endSurah: json['endSurah'] as int,
        endAyah: json['endAyah'] as int,
        done: json['done'] as bool? ?? false,
      );

  /// Short Arabic label, e.g. «صفحات 1 – 20».
  String get pageLabel => 'صفحات $startPage – $endPage';

  /// e.g. «من الفاتحة 1 إلى البقرة 141».
  String get rangeLabel {
    final from = '${quran.getSurahNameArabic(startSurah)} $startAyah';
    final to = '${quran.getSurahNameArabic(endSurah)} $endAyah';
    return 'من $from إلى $to';
  }
}

/// The ready-made plan kinds offered in the UI.
enum KhatmaPreset {
  thirtyDays,
  fifteenDays,
  sevenDays,
  custom,
}

extension KhatmaPresetLabel on KhatmaPreset {
  String get title {
    switch (this) {
      case KhatmaPreset.thirtyDays:
        return 'ختمة 30 يوماً';
      case KhatmaPreset.fifteenDays:
        return 'ختمة 15 يوماً';
      case KhatmaPreset.sevenDays:
        return 'ختمة 7 أيام';
      case KhatmaPreset.custom:
        return 'خطة مخصصة';
    }
  }

  String get subtitle {
    switch (this) {
      case KhatmaPreset.thirtyDays:
        return 'جزء واحد كل يوم';
      case KhatmaPreset.fifteenDays:
        return 'جزآن كل يوم';
      case KhatmaPreset.sevenDays:
        return 'نحو 86 صفحة كل يوم';
      case KhatmaPreset.custom:
        return 'عدد صفحات ثابت كل يوم تختاره أنت';
    }
  }
}

class KhatmaPlan {
  final KhatmaPreset preset;
  final int pagesPerDay;
  final DateTime startDate;
  final List<KhatmaSession> sessions;

  const KhatmaPlan({
    required this.preset,
    required this.pagesPerDay,
    required this.startDate,
    required this.sessions,
  });

  /// Creates a plan for [preset]. For [KhatmaPreset.custom],
  /// [customPagesPerDay] is required (1..604).
  factory KhatmaPlan.create(
    KhatmaPreset preset, {
    int? customPagesPerDay,
    DateTime? startDate,
  }) {
    final start = startDate ?? DateTime.now();
    switch (preset) {
      case KhatmaPreset.thirtyDays:
        return KhatmaPlan(
          preset: preset,
          pagesPerDay: 21,
          startDate: start,
          sessions: _sessionsByJuz(1),
        );
      case KhatmaPreset.fifteenDays:
        return KhatmaPlan(
          preset: preset,
          pagesPerDay: 41,
          startDate: start,
          sessions: _sessionsByJuz(2),
        );
      case KhatmaPreset.sevenDays:
        return KhatmaPlan(
          preset: preset,
          pagesPerDay: 87,
          startDate: start,
          sessions: _sessionsByPages(7),
        );
      case KhatmaPreset.custom:
        final perDay = (customPagesPerDay ?? 10).clamp(1, khatmaTotalPages);
        final count = (khatmaTotalPages / perDay).ceil();
        return KhatmaPlan(
          preset: preset,
          pagesPerDay: perDay,
          startDate: start,
          sessions: _sessionsByPages(count),
        );
    }
  }

  /// Sessions that follow the real juz boundaries: [juzPerSession]
  /// juz per session (1 -> 30 sessions, 2 -> 15 sessions).
  static List<KhatmaSession> _sessionsByJuz(int juzPerSession) {
    // First page of each juz (1..30), found by scanning the pages.
    final juzFirstPage = <int, int>{};
    for (var page = 1; page <= khatmaTotalPages; page++) {
      final data = quran.getPageData(page);
      final juz = quran.getJuzNumber(
        data.first['surah'] as int,
        data.first['start'] as int,
      );
      juzFirstPage.putIfAbsent(juz, () => page);
    }
    final sessions = <KhatmaSession>[];
    for (var juz = 1; juz <= 30; juz += juzPerSession) {
      final firstPage = juzFirstPage[juz]!;
      final lastJuz = (juz + juzPerSession - 1).clamp(1, 30);
      final lastPage = lastJuz == 30
          ? khatmaTotalPages
          : juzFirstPage[lastJuz + 1]! - 1;
      sessions.add(KhatmaSession.fromPages(firstPage, lastPage));
    }
    return sessions;
  }

  /// The 604 pages split into [count] near-equal sessions.
  static List<KhatmaSession> _sessionsByPages(int count) {
    final per = khatmaTotalPages ~/ count;
    final extra = khatmaTotalPages % count;
    final sessions = <KhatmaSession>[];
    var page = 1;
    for (var i = 0; i < count; i++) {
      // Spread the remainder one page at a time over the first sessions.
      final size = per + (i < extra ? 1 : 0);
      sessions.add(KhatmaSession.fromPages(page, page + size - 1));
      page += size;
    }
    return sessions;
  }

  int get totalSessions => sessions.length;

  int get completedCount => sessions.where((s) => s.done).length;

  /// Progress 0.0..1.0 = completed sessions / all sessions.
  double get progress =>
      sessions.isEmpty ? 0 : completedCount / sessions.length;

  /// Index of the session due today (days since [startDate],
  /// clamped to the last session).
  int todaySessionIndex([DateTime? now]) {
    final today = now ?? DateTime.now();
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    final days = todayDay.difference(startDay).inDays;
    return days.clamp(0, sessions.length - 1);
  }

  KhatmaSession todaySession([DateTime? now]) =>
      sessions[todaySessionIndex(now)];

  /// First session not yet done, or null when the plan is complete.
  KhatmaSession? get nextIncomplete {
    for (final s in sessions) {
      if (!s.done) return s;
    }
    return null;
  }

  bool get isComplete => sessions.isNotEmpty && completedCount == sessions.length;

  KhatmaPlan toggleDone(int index, bool done) {
    final updated = List<KhatmaSession>.from(sessions);
    updated[index] = updated[index].copyWith(done: done);
    return KhatmaPlan(
      preset: preset,
      pagesPerDay: pagesPerDay,
      startDate: startDate,
      sessions: updated,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'pagesPerDay': pagesPerDay,
        'startDate': startDate.toIso8601String(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  factory KhatmaPlan.fromJson(Map<String, dynamic> json) {
    final preset = KhatmaPreset.values.firstWhere(
      (p) => p.name == (json['preset'] as String? ?? 'thirtyDays'),
      orElse: () => KhatmaPreset.thirtyDays,
    );
    return KhatmaPlan(
      preset: preset,
      pagesPerDay: json['pagesPerDay'] as int? ?? 21,
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '') ??
          DateTime.now(),
      sessions: (json['sessions'] as List<dynamic>? ?? [])
          .map((e) => KhatmaSession.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static KhatmaPlan? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return KhatmaPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

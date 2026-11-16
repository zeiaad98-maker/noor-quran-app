import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/khatma_plan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('30-day plan: 30 juz sessions covering pages 1..604', () {
    final plan = KhatmaPlan.create(
      KhatmaPreset.thirtyDays,
      startDate: DateTime(2026, 11, 16),
    );
    expect(plan.totalSessions, 30);
    expect(plan.sessions.first.startPage, 1);
    expect(plan.sessions.first.startSurah, 1);
    expect(plan.sessions.first.startAyah, 1);
    expect(plan.sessions.last.endPage, 604);
    expect(plan.sessions.last.endSurah, 114);
    expect(plan.sessions.last.endAyah, 6);
    // Contiguous, no gaps or overlaps.
    for (var i = 1; i < plan.sessions.length; i++) {
      expect(plan.sessions[i].startPage, plan.sessions[i - 1].endPage + 1);
    }
    expect(plan.progress, 0);
    expect(plan.isComplete, false);
  });

  test('15-day plan: 15 sessions, 7-day plan: 7 sessions', () {
    final p15 = KhatmaPlan.create(KhatmaPreset.fifteenDays);
    expect(p15.totalSessions, 15);
    expect(p15.sessions.first.startPage, 1);
    expect(p15.sessions.last.endPage, 604);

    final p7 = KhatmaPlan.create(KhatmaPreset.sevenDays);
    expect(p7.totalSessions, 7);
    expect(p7.sessions.first.startPage, 1);
    expect(p7.sessions.last.endPage, 604);
    for (var i = 1; i < p7.sessions.length; i++) {
      expect(p7.sessions[i].startPage, p7.sessions[i - 1].endPage + 1);
    }
  });

  test('custom plan: 10 pages/day gives 61 sessions', () {
    final plan = KhatmaPlan.create(
      KhatmaPreset.custom,
      customPagesPerDay: 10,
    );
    expect(plan.totalSessions, 61);
    expect(plan.sessions.first.startPage, 1);
    expect(plan.sessions.last.endPage, 604);
    expect(plan.sessions.first.endPage, 10);
  });

  test('progress counts completed sessions', () {
    var plan = KhatmaPlan.create(
      KhatmaPreset.thirtyDays,
      startDate: DateTime(2026, 11, 16),
    );
    plan = plan.toggleDone(0, true);
    plan = plan.toggleDone(1, true);
    plan = plan.toggleDone(2, true);
    expect(plan.completedCount, 3);
    expect(plan.progress, closeTo(0.1, 0.0001));
    expect(plan.nextIncomplete, plan.sessions[3]);
    expect(plan.todaySession(DateTime(2026, 11, 16)), plan.sessions[0]);
    expect(plan.todaySession(DateTime(2026, 11, 18)), plan.sessions[2]);
  });

  test('JSON round-trip keeps sessions and done flags', () {
    var plan = KhatmaPlan.create(
      KhatmaPreset.fifteenDays,
      startDate: DateTime(2026, 11, 16),
    );
    plan = plan.toggleDone(0, true);
    plan = plan.toggleDone(4, true);
    final restored = KhatmaPlan.decode(plan.encode());
    expect(restored, isNotNull);
    expect(restored!.totalSessions, 15);
    expect(restored.completedCount, 2);
    expect(restored.progress, closeTo(2 / 15, 0.0001));
    expect(restored.sessions[0].done, true);
    expect(restored.sessions[4].done, true);
    expect(restored.sessions[1].done, false);
    expect(KhatmaPlan.decode('not json'), isNull);
    expect(KhatmaPlan.decode(null), isNull);
  });
}

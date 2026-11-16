import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/khatma_plan.dart';
import '../services/reminder_service.dart';
import 'surah_reader_screen.dart';

/// Khatma plan screen: pick a plan, follow the daily sessions,
/// mark each session done, and set the daily wird reminder.
///
/// The plan is stored in SharedPreferences under `khatma_plan` (JSON),
/// the reminder switch under `wird_reminder_enabled` and its time
/// ("HH:MM") under `wird_reminder_time`.
class KhatmaScreen extends StatefulWidget {
  const KhatmaScreen({super.key});

  @override
  State<KhatmaScreen> createState() => _KhatmaScreenState();
}

class _KhatmaScreenState extends State<KhatmaScreen> {
  static const String _planKey = 'khatma_plan';
  static const String _reminderEnabledKey = 'wird_reminder_enabled';
  static const String _reminderTimeKey = 'wird_reminder_time';

  static const Color emerald = Color(0xFF0C6E52);
  static const Color gold = Color(0xFFB8934A);

  KhatmaPlan? _plan;
  bool _loading = true;
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = TimeOfDay(
    hour: ReminderService.defaultHour,
    minute: ReminderService.defaultMinute,
  );
  int _customPages = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTime =
        ReminderService.parseTime(prefs.getString(_reminderTimeKey));
    setState(() {
      _plan = KhatmaPlan.decode(prefs.getString(_planKey));
      _reminderEnabled = prefs.getBool(_reminderEnabledKey) ?? false;
      _reminderTime =
          TimeOfDay(hour: savedTime.hour, minute: savedTime.minute);
      _loading = false;
    });
  }

  Future<void> _savePlan(KhatmaPlan? plan) async {
    final prefs = await SharedPreferences.getInstance();
    if (plan == null) {
      await prefs.remove(_planKey);
    } else {
      await prefs.setString(_planKey, plan.encode());
    }
    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _startPlan(KhatmaPreset preset) async {
    final plan = KhatmaPlan.create(
      preset,
      customPagesPerDay: preset == KhatmaPreset.custom ? _customPages : null,
    );
    await _savePlan(plan);
  }

  Future<void> _toggleSession(int index, bool done) async {
    final plan = _plan;
    if (plan == null) return;
    await _savePlan(plan.toggleDone(index, done));
  }

  Future<void> _setReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reminderEnabledKey, enabled);
    if (enabled) {
      await ReminderService.scheduleDailyWird(
        _reminderTime.hour,
        _reminderTime.minute,
      );
    } else {
      await ReminderService.cancelWird();
    }
    if (mounted) setState(() => _reminderEnabled = enabled);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      helpText: 'وقت التذكير اليومي',
      cancelText: 'إلغاء',
      confirmText: 'حفظ',
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _reminderTimeKey,
      ReminderService.formatTime(picked.hour, picked.minute),
    );
    if (_reminderEnabled) {
      await ReminderService.scheduleDailyWird(picked.hour, picked.minute);
    }
    if (mounted) setState(() => _reminderTime = picked);
  }

  Future<void> _confirmDeletePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء خطة الختمة؟'),
        content: const Text('سيتم حذف الخطة وتقدّمها. يمكنك بدء خطة جديدة بعد ذلك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إنهاء الخطة', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _savePlan(null);
    }
  }

  void _openSession(KhatmaSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurahReaderScreen(
          surahNumber: session.startSurah,
          initialPage: session.startPage,
        ),
      ),
    );
  }

  String _ar(String input) {
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var res = input;
    for (var i = 0; i < 10; i++) {
      res = res.replaceAll(en[i], ar[i]);
    }
    return res;
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final m = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '${_ar('$h:$m')} $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خطتي للختمة',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: emerald,
        foregroundColor: Colors.white,
        actions: [
          if (_plan != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'إنهاء الخطة',
              onPressed: _confirmDeletePlan,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: emerald))
          : _plan == null
              ? _buildPresetPicker()
              : _buildPlanView(),
    );
  }

  Widget _buildPresetPicker() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'اختر خطة ختمة تناسبك',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'كل خطة تقسّم المصحف (604 صفحات) إلى جلسات يومية، ويمكنك تأشير كل جلسة بعد إتمامها.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ...KhatmaPreset.values
              .where((p) => p != KhatmaPreset.custom)
              .map((preset) => _presetCard(preset)),
          _customPresetCard(),
        ],
      ),
    );
  }

  Widget _presetCard(KhatmaPreset preset) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: gold.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: emerald,
          child: Icon(Icons.menu_book_rounded, color: Colors.white),
        ),
        title: Text(preset.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(preset.subtitle),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 16, color: gold),
        onTap: () => _startPlan(preset),
      ),
    );
  }

  Widget _customPresetCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: gold.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: emerald,
                  child: Icon(Icons.tune_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('خطة مخصصة',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('عدد صفحات ثابت كل يوم تختاره أنت'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  icon: const Icon(Icons.remove),
                  onPressed: _customPages > 1
                      ? () => setState(() => _customPages--)
                      : null,
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    '${_ar('$_customPages')} صفحات / يوم',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                IconButton.outlined(
                  icon: const Icon(Icons.add),
                  onPressed: _customPages < 100
                      ? () => setState(() => _customPages++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: emerald),
              onPressed: () => _startPlan(KhatmaPreset.custom),
              child: const Text('ابدأ الخطة المخصصة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanView() {
    final plan = _plan!;
    final todayIndex = plan.todaySessionIndex();
    final today = plan.sessions[todayIndex];
    final percent = (plan.progress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Card(
            color: emerald,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    plan.preset.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'أنجزت ${_ar('${plan.completedCount}')} من ${_ar('${plan.totalSessions}')} جلسات — ${_ar('$percent')}٪',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: plan.progress,
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(gold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: gold.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'جلسة اليوم — الجلسة ${_ar('${todayIndex + 1}')}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(today.pageLabel),
                  Text(today.rangeLabel,
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: emerald),
                    onPressed: () => _openSession(today),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(today.done
                        ? 'مراجعة جلستي'
                        : 'ابدأ جلستي'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: gold.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('تذكير يومي بالورد',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle:
                      const Text('تنبيه كل يوم في الوقت الذي تختاره'),
                  value: _reminderEnabled,
                  onChanged: _setReminderEnabled,
                ),
                if (_reminderEnabled)
                  ListTile(
                    leading: const Icon(Icons.access_time_rounded,
                        color: emerald),
                    title: Text('وقت التذكير: ${_formatTime(_reminderTime)}'),
                    trailing: const Icon(Icons.edit_outlined, color: gold),
                    onTap: _pickReminderTime,
                  ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Text('كل الجلسات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: plan.sessions.length,
            itemBuilder: (ctx, i) {
              final session = plan.sessions[i];
              final isToday = i == todayIndex;
              return Card(
                color: isToday
                    ? emerald.withValues(alpha: 0.08)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isToday
                      ? const BorderSide(color: emerald)
                      : BorderSide(
                          color: gold.withValues(alpha: 0.2)),
                ),
                child: CheckboxListTile(
                  value: session.done,
                  activeColor: emerald,
                  onChanged: (v) => _toggleSession(i, v ?? false),
                  title: Text(
                    'الجلسة ${_ar('${i + 1}')} — ${session.pageLabel}'
                    '${isToday ? ' (اليوم)' : ''}',
                    style: TextStyle(
                      fontWeight:
                          isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(session.rangeLabel),
                  secondary: IconButton(
                    icon: const Icon(Icons.play_circle_outline_rounded,
                        color: emerald),
                    tooltip: 'افتح الجلسة في المصحف',
                    onPressed: () => _openSession(session),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../data/audio_player_controller.dart';

/// Compact mini audio player bar, docked at the bottom of the reader
/// screen (overlaying the page, NOT a modal sheet).
///
/// Layout (reference screenshot): ••• | repeat | prev | play/pause ▶ |
/// replay | next | X. While a word is loading the play button keeps its green
/// background with a white spinner inside (never a grey disabled
/// circle) and a small "جارٍ تحميل الكلمة…" label appears above the
/// row.
///
/// Wiring — all to the existing [AudioPlayerController]:
/// play/pause → togglePlayPause, prev/next → previous/next,
/// repeat → toggleRepeatItem, replay → replayCurrent (restarts the
/// current word at once, whether playing or finished), X → [onClose]
/// (the reader stops the audio and hides the bar). The ••• menu holds
/// repeat-count and speed, same as the full sheet's more menu.
class MiniAudioBar extends StatelessWidget {
  final AudioPlayerController controller;
  final VoidCallback onClose;

  const MiniAudioBar({
    super.key,
    required this.controller,
    required this.onClose,
  });

  static const _green = Color(0xFF0D6E52);
  static const _gold = Color(0xFF8A723D);
  static const _cream = Color(0xFFFAF6EE);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: _cream,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.isLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    'جارٍ تحميل الكلمة…',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              // While repeating, show how many plays remain (v13.2
              // bug B / best-apps rule 3) — only while a repeat play
              // is actually running or loading: once the sequence has
              // stopped, the count is spent and the line goes away.
              if (controller.repeatItem &&
                  (controller.isPlaying || controller.isLoading))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    controller.repeatCount == 0
                        ? 'التكرار: مستمر — أوقفْه بزر التكرار'
                        : 'التكرار: متبقٍ ${controller.repeatRemaining} ${_repeatUnit(controller.repeatRemaining)}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: _green,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _moreButton(),
                  IconButton(
                    tooltip: 'تكرار العنصر الحالي',
                    icon: Icon(
                      Icons.repeat_one,
                      color: controller.repeatItem ? _green : Colors.grey,
                    ),
                    onPressed: controller.toggleRepeatItem,
                  ),
                  IconButton(
                    tooltip: 'السابق',
                    icon: const Icon(Icons.skip_previous, color: _green),
                    onPressed: controller.previous,
                  ),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: ElevatedButton(
                      // NEVER null while loading: a null onPressed
                      // renders ElevatedButton DISABLED (grey), which
                      // is the v10 "grey circle with a tiny white
                      // square" bug. The green background stays and
                      // the spinner shows inside it; the tap is a
                      // harmless no-op while loading (it would race
                      // the in-flight load).
                      onPressed: controller.isLoading
                          ? () {}
                          : controller.togglePlayPause,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: controller.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Icon(
                              controller.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              size: 30,
                            ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إعادة الكلمة',
                    icon: const Icon(Icons.replay, color: _green),
                    onPressed: controller.replayCurrent,
                  ),
                  IconButton(
                    tooltip: 'التالي',
                    icon: const Icon(Icons.skip_next, color: _green),
                    onPressed: controller.next,
                  ),
                  IconButton(
                    tooltip: 'إغلاق وإيقاف الصوت',
                    icon: const Icon(Icons.close, color: _green),
                    onPressed: onClose,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _moreButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: _gold),
      tooltip: 'خيارات التكرار والسرعة',
      onSelected: (value) {
        if (value.startsWith('count:')) {
          controller.setRepeatCount(int.parse(value.substring(6)));
        } else if (value.startsWith('speed:')) {
          controller.setSpeed(double.parse(value.substring(6)));
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'header-count',
          enabled: false,
          child: Text('عدد التكرار',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final (count, label) in [
          (1, 'مرة واحدة'),
          (3, '3 مرات'),
          (5, '5 مرات'),
          (10, '10 مرات'),
          (0, 'مستمر'),
        ])
          PopupMenuItem<String>(
            value: 'count:$count',
            child: Row(
              children: [
                if (controller.repeatCount == count)
                  const Icon(Icons.check, size: 18, color: _green),
                if (controller.repeatCount == count)
                  const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'header-speed',
          enabled: false,
          child: Text('سرعة التشغيل',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final (speed, label) in [
          (0.75, 'بطيئة 0.75×'),
          (1.0, 'عادية 1×'),
          (1.25, 'سريعة 1.25×'),
          (1.5, 'سريعة 1.5×'),
        ])
          PopupMenuItem<String>(
            value: 'speed:$speed',
            child: Row(
              children: [
                if (controller.speed == speed)
                  const Icon(Icons.check, size: 18, color: _green),
                if (controller.speed == speed) const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
      ],
    );
  }

  /// Arabic unit for the remaining-repeat count (1 مرة، 2 مرتان، 3+ مرات).
  static String _repeatUnit(int count) {
    if (count == 1) return 'مرة';
    if (count == 2) return 'مرتان';
    return 'مرات';
  }
}

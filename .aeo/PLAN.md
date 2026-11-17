# v13.2 — PLAN (1.0.14+15) — FINAL SCOPE

Goal (one sentence): the WORD plays from Quran.com's dedicated per-word MP3 files (wbw), the meaning is short and plain, and the five user-reported audio bugs are fixed in the best-apps arrangement — cache-on-play, no cutting, no segments.

Mode: Standard, playbook: Build a feature (small) + Data verification.

Background: the Muallim+Tunaiji two-voice plan was DROPPED by the user 5 minutes after he chose it (13:25). All its code/data was reverted (quran_audio.dart restored to HEAD 820f172, fetch scripts + verify script deleted, both fetches killed, no bundles written). Tree verified clean. Then the user added: short meanings, ayah-file check, bugs 1+2 (mixed-up ayahs, forever spinner), bugs A–D (word plays ayah, repeat broken, no highlight, invisible ayah affordance), and ordered the best-apps arrangement copied (research done 13:56).

## Success criteria
- [x] Word plays ONLY from wbw: https://audio.qurancdn.com/wbw/SSS_AAA_WWW.mp3, via cacheWbwFile (cache-on-play). Old host verses.quran.com/wbw/ only as fallback if the new host fails.
- [x] Mapping verified: shift table `assets/quran_data/word_wbw_shifts.json` (2,705 ayahs, 4,560 shift points), reconstruction 0 mismatches over 77,429 words vs the API's audio_urls. 24 real wbw files checked (HTTP 200, durations 0.63–3.50 s).
- [x] Fallback chain (CHANGED — bug A): wbw fails → sheet error with retry. NO segment/ayah fallback: the segment subsystem is DELETED (quran_audio segment code, `word_segments_husary.json` asset + pubspec entry, `tool/fetch_husary_word_segments.py`, segment tests, probe test).
- [x] Sheet carries an honest note: the word is one fixed teaching voice (wbw recording, reciter not publicly named), never the selected reciter's voice.
- [x] NO wbw files bundled in the APK (Quran Foundation terms). Streaming + on-device caching only.
- [x] Meanings short + plain (مخلوف NOT in Dalail — verified 3 ways — so truncation fallback): غريب when present, else Raghib first sentence (~120 chars, hard cap 160, clarity guard keeps a second sentence when the first is a fragment). Coverage 49,054/77,429 = 63.4% with a short gloss, 100% non-blank; median 32 chars, max 159. Sample words verified clear: 2:36 فَأَخْرَجَهُمَا (37 chars), 5:4 وَاتَّقُوا (92 chars).
- [x] Ayah files verified, NO change: 7 real Tunaiji everyayah files (1:1, 2:6, 2:33, 2:255, 36:1, 55:1, 112:1), all HTTP 200, ffmpeg decode clean, natural fade (not cut).
- [x] Bug 1 (mixed-up ayahs): root causes fixed — stale-finish race (old file completing during a new load; `_finishToken` gate + stop-old-first), and the 4 merged ayahs (2:181, 8:6, 13:37, 37:130) mapped via `audioPositionForQcfWord`.
- [x] Bug 2 (forever spinner): root causes fixed — `stop()` clears `isLoading`, 60 s total `playBudget` invalidates any slow attempt + error, timeouts on setSpeed/play, token-checked finally.
- [x] Bug A (word plays ayah): word = wbw file ONLY, never an ayah file. Regression test asserts only wbw URLs load.
- [x] Bug B (repeat broken): `setRepeatCount` enables repeat (count 1 = off), manual next/prev/stop cancels repeat, settings persist via SharedPreferences, remaining-plays line in sheet + mini bar (shown only while playing/loading).
- [x] Bug C (no highlighting): QCF page colours the playing ayah (tint) + playing word (strong tint + word colour), cleared on stop/pause, toggleable in settings (`highlight_playback`, default on).
- [x] UX D (invisible ayah affordance): word card has a prominent "استمع للآية" button; long-press on a word plays its ayah; tap on a word plays JUST the word immediately + opens the card + shows the mini bar.
- [x] Reciters downloads: progress bar + Cancel button (rule 5).
- [ ] `flutter pub get` exit 0, `flutter analyze` exit 0, full `flutter test` exit 0 (real exit codes, TMPDIR=~/tmp-flutter). New tests: v132_audio, v132_meaning, v132_bugs.
- [ ] pubspec.yaml line 4 = 1.0.14+15. Local commit only — no upload (parent delivers).

## Constraints
- Touch nothing else: ayah stays الطنيجي by default, layout, reciters list, tafsirs, mosques unchanged.
- No timing data, no segments, no padding tuning for the word — nothing to cut.
- Never `git add -A` (generated android/ stays untracked).

## Steps
1. [x] Revert two-voice plan (tree clean, verified).
2. [x] wbw mapping verification (API words vs tokens; shift table; 24 real files).
3. [x] Implement wbw-first word audio + sheet note; delete segment subsystem.
4. [x] Meanings: Dalail check (مخلوف absent) → truncation fallback + tests (subagent c6204e3c, collected).
5. [x] Ayah files verified (7 real files, no change).
6. [x] Bugs 1+2, A–D + best-apps arrangement: controller races/budget/repeat, QCF highlight, word-card ayah button, long-press, mini-bar/sheet remaining lines, reciters Cancel.
7. [ ] Full test suite + analyze with real exit codes; version bump; commit.

## Next step
Step 7: full suite green, then bump + commit.

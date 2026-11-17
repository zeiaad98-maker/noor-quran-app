#!/usr/bin/env python3
"""Build assets/quran_data/word_wbw_shifts.json — the wbw file-number
mapping for every ayah, derived from the Quran.com Verses API
(audio_url per word, the ground truth).

WHY A BUNDLED TABLE (v13.2): the wbw file numbering does NOT follow
any rule computable from our tokens alone:
  * pause marks count as positions of their own — but which marks
    count is inconsistent in the API text (2:81 word 1 carries U+06DA
    in our tokens and the API drops it, no shift; 2:255 word 7
    carries the SAME mark and it shifts by 1);
  * the rub el hizb ornament U+06DE (۞) counts as position 1
    (2:26 word 1 is file 002) but never appears in our tokens.
So the mapping is stored explicitly, as shift points: for ayah
"s:a", a sorted list of word positions AFTER which the file
numbering increments by one extra step (0 = before word 1, i.e. a
leading ۞). file(word i) = i + #{shift points < i}. Ayahs absent
from the table have no shifts (file == position).

Derivation from the API: for word positions 1..n with file numbers
f(1)..f(n) (f(0) = 0), every jump f(i) - f(i-1) > 1 contributes
(i-1) repeated (jump - 1) times. The script then RECONSTRUCTS every
file number from the shift table and requires ZERO mismatches
against the API before writing the asset.

Run: python3 tool/build_wbw_shifts.py
Output: assets/quran_data/word_wbw_shifts.json
"""
import json
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

CHAPTERS_API = (
    "https://api.quran.com/api/v4/verses/by_chapter/%d"
    "?words=true&word_fields=text_uthmani&per_page=50&page=%d"
)
MORPH = "assets/quran_data/word_morphology.json"
OUT = "assets/quran_data/word_wbw_shifts.json"


def fetch_json(url, tries=3):
    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "noor-quran/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - retry on any transient error
            last = e
            time.sleep(1)
    raise RuntimeError(f"fetch failed {url}: {last}")


def fetch_chapter(chapter):
    """All verses of one chapter with their words (paginated)."""
    verses = []
    page = 1
    while True:
        data = fetch_json(CHAPTERS_API % (chapter, page))
        verses.extend(data["verses"])
        if page >= data["pagination"]["total_pages"]:
            break
        page += 1
    return verses


def file_number(audio_url):
    """wbw/002_033_006.mp3 -> 6 ; None/missing -> None."""
    if not audio_url:
        return None
    try:
        return int(audio_url.rsplit("_", 1)[1].split(".")[0])
    except (ValueError, IndexError):
        return None


def shifts_from_files(files):
    """files: 1-based file numbers per word position. Returns the
    sorted shift-point list (see module docstring)."""
    shifts = []
    prev = 0
    for i, f in enumerate(files, start=1):
        jump = f - prev
        if jump > 1:
            shifts.extend([i - 1] * (jump - 1))
        prev = f
    return shifts


def file_from_shifts(shifts, word_index):
    return word_index + sum(1 for s in shifts if s < word_index)


# Ayahs whose API audio_url is missing/empty for a word, with the file
# number established by direct CDN evidence (documented, not guessed):
#   * 36:52 word 7 (هَٰذَا): the API returns an empty audio_url, but
#     BOTH candidate files exist on the CDN as real speech. Duration
#     settles it: known هَٰذَا recordings (same word, same voice, 5
#     other ayahs) run 1.10–1.38 s; file 007 is 1.02 s (close) while
#     file 008 is 0.65 s (half the length of a two-syllable word with
#     two long vowels — a pause/saktah file instead). So word 7 = 007
#     and the extra position lands AFTER word 7: shifts [7], i.e.
#     files [1,2,3,4,5,6,7,9,10,11,12,13] — matching every API
#     audio_url the ayah does publish. One-word judgment call, flagged
#     in the v13.2 report for the user's ear to confirm.
MANUAL_FILE_NUMBERS = {
    "36:52": {7: 7},
}


def main():
    morph = json.load(open(MORPH, encoding="utf-8"))
    total_ayahs = len(morph)
    print(f"ayahs in morphology: {total_ayahs}", flush=True)

    with ThreadPoolExecutor(max_workers=8) as pool:
        chapters = list(pool.map(fetch_chapter, range(1, 115)))
    print("fetched all chapters", flush=True)

    table = {}
    checked_words = 0
    mismatched = []
    missing_url = []
    for chapter, verses in enumerate(chapters, start=1):
        for verse in verses:
            key = verse["verse_key"]
            words = [w for w in verse["words"]
                     if w.get("char_type_name") == "word"]
            files = [file_number(w.get("audio_url")) for w in words]
            if key in MANUAL_FILE_NUMBERS:
                for pos, num in MANUAL_FILE_NUMBERS[key].items():
                    files[pos - 1] = num
            if any(f is None for f in files):
                missing_url.append(key)
                continue
            shifts = shifts_from_files(files)
            if shifts:
                table[key] = shifts
            # Validate by reconstruction against the API, word by word.
            for i, f in enumerate(files, start=1):
                checked_words += 1
                if file_from_shifts(shifts, i) != f:
                    mismatched.append((key, i, f,
                                       file_from_shifts(shifts, i)))
        if chapter % 20 == 0:
            print(f"  chapter {chapter} done", flush=True)

    print(f"words checked: {checked_words}")
    print(f"ayahs with shifts: {len(table)} / {total_ayahs}")
    print(f"total shift points: {sum(len(v) for v in table.values())}")
    print(f"max shifts in one ayah: "
          f"{max((len(v) for v in table.values()), default=0)}")
    print(f"ayahs with a missing audio_url: {len(missing_url)} {missing_url[:5]}")
    print(f"reconstruction mismatches: {len(mismatched)} {mismatched[:5]}")
    if mismatched or missing_url:
        print("REFUSING to write the asset — ground truth not reproduced")
        sys.exit(1)

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(table, fh, ensure_ascii=False, separators=(",", ":"))
    import os
    print(f"wrote {OUT} ({os.path.getsize(OUT)} bytes)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""One-off generator: fetch Husary (Quran.com recitation 6) per-word
segment timestamps for ALL 6236 ayahs and write a compact bundled asset.

Source: Quran.com API v4 /verses/by_chapter/{s}?audio=6&per_page=50.
Output: assets/quran_data/word_segments_husary.json
  {"2:33": [[850, 1760], [1770, 5010], ...], ...}   # [startMs, endMs] per word
Ayahs with no segments are OMITTED (the app falls back to wbw for them);
the missing list is printed + written to word_segments_husary.missing.txt.

Run from the repo root:  python3 tool/fetch_husary_word_segments.py
"""
import json
import sys
import time
import urllib.request

BASE = "https://api.quran.com/api/v4/verses/by_chapter/%d?audio=6&words=false&fields=text_uthmani&per_page=50&page=%d"
OUT = "assets/quran_data/word_segments_husary.json"
MISSING = "assets/quran_data/word_segments_husary.missing.txt"


def fetch(url, tries=3):
    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "noor-quran/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001 - retry transient network errors
            last = e
            time.sleep(1.0)
    raise last


def main():
    out = {}
    missing = []
    total_verses = 0
    for surah in range(1, 115):
        page = 1
        while True:
            data = fetch(BASE % (surah, page))
            verses = data["verses"]
            for v in verses:
                total_verses += 1
                key = v["verse_key"]
                audio = v.get("audio") or {}
                segs = audio.get("segments") or []
                pairs = []
                idx_ok = True
                prev_w1 = 0
                for s in segs:
                    if len(s) < 4:
                        idx_ok = False
                        break
                    w0, w1, start, end = s[0], s[1], s[2], s[3]
                    if w0 != prev_w1 or w1 <= w0 or start >= end:
                        idx_ok = False
                        break
                    # A segment may span several words ([0, 2, ...] =
                    # both words recited in one breath, e.g. 30:2):
                    # every word in the span gets the span's timing,
                    # so the list stays 1:1 with the morphology words.
                    for _ in range(w1 - w0):
                        pairs.append([start, end])
                    prev_w1 = w1
                ok = bool(pairs) and idx_ok
                if ok:
                    out[key] = pairs
                else:
                    missing.append(key)
            pg = data["pagination"]
            if page >= pg["total_pages"]:
                break
            page += 1
            time.sleep(0.1)
        print(f"surah {surah}: {len(verses)} verses, pages done", flush=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"), ensure_ascii=False)
    with open(MISSING, "w", encoding="utf-8") as f:
        f.write("\n".join(missing))
    print(f"total verses seen: {total_verses}")
    print(f"ayahs with segments: {len(out)}")
    print(f"ayahs missing/invalid segments: {len(missing)} -> {MISSING}")
    print(f"words total: {sum(len(v) for v in out.values())}")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    sys.exit(main())

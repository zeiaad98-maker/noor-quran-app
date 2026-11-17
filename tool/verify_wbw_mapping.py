#!/usr/bin/env python3
"""Verify v13.2 wbw word audio (mapping + real files).

1. MAPPING: for 7 sample ayahs, compares OUR wordsForAyah() tokens
   (bundled morphology dump — the exact data the app reads) against
   the Quran.com Verses API word list (text_uthmani + audio_url).
   Reports: word COUNT match (this is what decides the wbw file
   number WWW), exact-text match rate, and normalized-text match rate
   (bare letters only — Uthmani orthography varies in tatweel /
   dagger-alef encoding between sources; a normalized mismatch is a
   REAL mapping problem, an exact-only mismatch is encoding).
2. FILES: downloads REAL wbw MP3s for >= 20 words (first + last +
   longest word of each sample ayah, deduped) from the NEW host
   audio.qurancdn.com (old host verses.quran.com only on failure),
   and checks each with ffprobe (duration > 0, non-trivial size).

Files go to /tmp only — NOTHING is bundled in the APK (Quran
Foundation terms: redistribution needs written permission).

Writes tool/v132_wbw_verify_report.json + prints a summary.

Run from the repo root:  python3 tool/verify_wbw_mapping.py
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.request

API = (
    "https://api.quran.com/api/v4/verses/by_key/%d:%d"
    "?words=true&word_fields=text_uthmani"
)
NEW_HOST = "https://audio.qurancdn.com/wbw/%03d_%03d_%03d.mp3"
OLD_HOST = "https://verses.quran.com/wbw/%03d_%03d_%03d.mp3"

MORPH = "assets/quran_data/word_morphology.json"
AYAHS = [(1, 1), (2, 6), (2, 33), (2, 255), (36, 1), (55, 1), (112, 1)]

# Waqf (pause) marks — verified against the API (see part 3): the wbw
# file numbering counts each of these as a position of its own, so a
# word's file number is its position PLUS the pause marks in the
# words before it. U+06D9 never occurs in the tokens; U+06E9 (sajdah)
# sits after the last word of its ayah and shifts nothing.
PAUSE_MARKS = set("\u06d6\u06d7\u06d8\u06da\u06db\u06dc\u06ec")

CHAPTERS_API = (
    "https://api.quran.com/api/v4/verses/by_chapter/%d"
    "?words=true&word_fields=text_uthmani&per_page=50&page=%d"
)


def predicted_file_numbers(tokens):
    """wbw file number per word position (1-based), from our tokens:
    position + pause marks in all PRECEDING words."""
    out = []
    shift = 0
    for tok in tokens:
        out.append(len(out) + 1 + shift)
        shift += sum(1 for ch in tok if ch in PAUSE_MARKS)
    return out


def fetch_json(url, tries=3):
    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "noor-quran/1.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            last = e
    raise last


def bare(word):
    """Bare letters only: strip tatweel, dagger-alef, all Mn marks,
    spaces, and normalize alef variants — for mapping comparison
    only. (The API writes a pause mark as 'word ۖ' with a space;
    our tokens have it attached — the space is not a real
    difference.)"""
    out = []
    for ch in word:
        if ch in (" ", "\u0640"):  # space, tatweel
            continue
        if ch == "\u0670":  # dagger alef
            continue
        if unicodedata.category(ch) == "Mn":
            continue
        if ch in ("\u0625", "\u0623", "\u0622", "\u0671"):
            ch = "\u0627"  # alef variants -> bare alef
        if ch == "\u0649":
            ch = "\u064a"  # alef maqsura -> yeh
        out.append(ch)
    return "".join(out)


def pick_words(tokens):
    """First + last + longest word (by chars) of an ayah, deduped."""
    n = len(tokens)
    picks = {1, n}
    longest = max(range(n), key=lambda i: len(tokens[i])) + 1
    picks.add(longest)
    return sorted(picks)


def ffprobe_duration(path):
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", path],
        capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return float(json.loads(r.stdout)["format"]["duration"])
    except (KeyError, ValueError):
        return None


def main():
    morph = json.load(open(MORPH, encoding="utf-8"))
    tmp = tempfile.mkdtemp(prefix="v132_wbw_")
    report = {"mapping": {}, "files": [], "hosts": {}}
    all_ok = True

    print("== 1. MAPPING: our tokens vs Quran.com API words ==")
    for surah, ayah in AYAHS:
        key = f"{surah}:{ayah}"
        ours = [e[0] for e in morph[key]]
        data = fetch_json(API % (surah, ayah))
        api_words = data["verse"]["words"]
        # The API lists non-word chars too (e.g. verse-end marks);
        # only char_type_name == 'word' carries audio.
        api_words = [w for w in api_words
                     if w.get("char_type_name") == "word"]
        api_texts = [w["text_uthmani"] for w in api_words]
        api_urls = [w.get("audio_url") for w in api_words]
        count_ok = len(ours) == len(api_texts)
        exact = sum(1 for a, b in zip(ours, api_texts) if a == b)
        norm = sum(1 for a, b in zip(ours, api_texts)
                   if bare(a) == bare(b))
        url_ok = all(
            u == "wbw/%03d_%03d_%03d.mp3" % (surah, ayah, i + 1)
            for i, u in enumerate(api_urls))
        bad_norm = [(i + 1, ours[i], api_texts[i])
                    for i in range(min(len(ours), len(api_texts)))
                    if bare(ours[i]) != bare(api_texts[i])]
        print(f"  {key}: ours={len(ours)} api={len(api_texts)} "
              f"count_ok={count_ok} exact={exact}/{len(ours)} "
              f"normalized={norm}/{len(ours)} audio_url_ok={url_ok} "
              f"normalized_mismatches={bad_norm if bad_norm else 'none'}")
        report["mapping"][key] = {
            "ours": len(ours), "api": len(api_texts), "count_ok": count_ok,
            "exact_matches": exact, "normalized_matches": norm,
            "audio_url_ok": url_ok, "normalized_mismatches": bad_norm,
        }
        if not (count_ok and norm == len(ours) and url_ok):
            all_ok = False

    print("\n== 2. FILES: real wbw MP3s (new host, old host on failure) ==")
    checked = set()
    for surah, ayah in AYAHS:
        ours = [e[0] for e in morph[f"{surah}:{ayah}"]]
        for w in pick_words(ours):
            checked.add((surah, ayah, w))
    # Extra mid-ayah words to reach >= 20 files checked.
    checked |= {(2, 33, 11), (2, 255, 25), (2, 6, 5), (112, 1, 2),
                (1, 1, 2), (2, 255, 30), (2, 33, 15)}
    print(f"  words selected: {len(checked)}")
    for surah, ayah, word in sorted(checked):
        path = os.path.join(tmp, f"{surah}_{ayah}_{word}.mp3")
        host_used = None
        status = None
        for host, url in (("new", NEW_HOST % (surah, ayah, word)),
                          ("old", OLD_HOST % (surah, ayah, word))):
            try:
                req = urllib.request.Request(
                    url, headers={"User-Agent": "noor-quran/1.0"})
                with urllib.request.urlopen(req, timeout=30) as r:
                    status = r.status
                    data = r.read()
                host_used = host
                break
            except Exception as e:  # noqa: BLE001
                status = str(e)
        if host_used is None:
            print(f"  {surah}:{ayah} w{word}: FAILED both hosts ({status})")
            report["files"].append({
                "surah": surah, "ayah": ayah, "word": word,
                "ok": False, "error": str(status)})
            all_ok = False
            continue
        with open(path, "wb") as f:
            f.write(data)
        dur = ffprobe_duration(path)
        size = len(data)
        ok = dur is not None and dur > 0.2 and size > 1000
        print(f"  {surah}:{ayah} w{word}: host={host_used} "
              f"HTTP {status} size={size} duration={dur} ok={ok}")
        report["files"].append({
            "surah": surah, "ayah": ayah, "word": word,
            "host": host_used, "http": status, "size": size,
            "duration_s": dur, "ok": ok})
        if not ok:
            all_ok = False

    print("\n== 3. FULL MAPPING: predicted file numbers vs API, "
          "all 6,236 ayahs ==")
    total_words = 0
    mismatched_ayahs = []
    mismatched_words = 0
    for surah in range(1, 115):
        page = 1
        while True:
            data = fetch_json(CHAPTERS_API % (surah, page))
            for v in data["verses"]:
                key = v["verse_key"]
                ours = [e[0] for e in morph[key]]
                api_words = [w for w in v["words"]
                             if w.get("char_type_name") == "word"]
                if len(ours) != len(api_words):
                    mismatched_ayahs.append(
                        (key, f"count ours={len(ours)} api={len(api_words)}"))
                    continue
                predicted = predicted_file_numbers(ours)
                bad = []
                for i, w in enumerate(api_words):
                    u = w.get("audio_url") or ""
                    try:
                        actual = int(u.split("_")[-1].split(".")[0])
                    except ValueError:
                        actual = -1
                    if actual != predicted[i]:
                        bad.append((i + 1, predicted[i], actual))
                total_words += len(ours)
                if bad:
                    mismatched_words += len(bad)
                    mismatched_ayahs.append((key, bad[:5]))
            pg = data["pagination"]
            if page >= pg["total_pages"]:
                break
            page += 1
            time.sleep(0.1)
        print(f"  surah {surah} done", flush=True)
    print(f"  words checked: {total_words}")
    print(f"  mismatched words: {mismatched_words}")
    print(f"  mismatched ayahs: {len(mismatched_ayahs)} "
          f"{mismatched_ayahs[:10] if mismatched_ayahs else ''}")
    report["full_mapping"] = {
        "words_checked": total_words,
        "mismatched_words": mismatched_words,
        "mismatched_ayahs": mismatched_ayahs[:20],
    }
    if mismatched_words:
        all_ok = False

    out_path = os.path.join(os.getcwd(), "tool", "v132_wbw_verify_report.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\nreport: {out_path}")
    print(f"ALL OK: {all_ok}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Build assets/quran_data/word_lexicon.json from مفردات ألفاظ القرآن
للراغب الأصفهاني (ت ٥٠٢هـ), fetched from Dalail (book 23636) into
/tmp/raghib_pages/batch_*.json via get_pages (8 pages per call).

Output: {normalized_root: "definition", ...} — only roots that occur in
the Quran (per assets/quran_data/word_morphology.json), so the asset
stays small. Each definition is the opening definitional passage of the
root's entry in مفردات الراغب, verbatim (footnotes stripped).

Run:  python3 tool/build_word_lexicon.py
"""
import json
import re
import sys
from pathlib import Path

WORKTREE = Path(__file__).resolve().parent.parent
PAGES_DIR = Path('/tmp/raghib_pages')
MORPH = WORKTREE / 'assets/quran_data/word_morphology.json'
OUT = WORKTREE / 'assets/quran_data/word_lexicon.json'

AR_LETTER = r'[\u0621-\u064A\u0671-\u06D3]'


def normalize(s: str) -> str:
    s = re.sub(r'[\u064B-\u0655\u0670\u0640\u06D6-\u06ED]', '', s)
    s = (s.replace('\u0622', '\u0627').replace('\u0623', '\u0627')
          .replace('\u0625', '\u0627').replace('\u0671', '\u0627'))
    s = s.replace('\u0649', '\u064A').replace('\u0629', '\u0647')
    s = re.sub(r'\s+', '', s)
    return s


def root_candidates(root: str):
    """Same candidate scheme as QuranWordData._rootKeyCandidates (Dart).

    Raghib's headwords spell roots the classical way: a weak-final
    root may appear with ا (سمو -> سما), a geminate root undoubled
    (أسس -> أس، أبب -> أبّ), a weak-final root may drop the weak
    letter entirely (أخو -> أخ), and a hollow root appears with ا
    in the middle (كون -> كان، مول -> مال، شيا -> شاء). Exact matches
    always win.
    """
    base = normalize(root)
    cands = [base]
    if not base:
        return cands
    last = base[-1]
    if last in ('و', 'ي', 'ا'):
        for rep in ('ا', 'و', 'ي'):
            if rep != last:
                cands.append(base[:-1] + rep)
    if len(base) >= 2 and base[-1] == base[-2]:
        cands.append(base[:-1])          # geminate undoubled
    if last in ('و', 'ي'):
        cands.append(base[:-1])          # weak-final dropped
    if len(base) == 3 and base[1] in ('و', 'ي'):
        # hollow root: medial weak letter spelled ا (كان، مال، دار)
        cands.append(base[0] + 'ا' + base[2])
        # ...and with a final hamza spelled ء (شاء، جاء)
        if base[2] == 'ا':
            cands.append(base[0] + 'ا' + 'ء')
    seen, out = set(), []
    for c in cands:
        if c and c not in seen:
            seen.add(c)
            out.append(c)
    return out


def load_pages() -> list:
    """Return [(page_id, text)] in page order."""
    pages = {}
    for path in sorted(PAGES_DIR.glob('batch_*.json')):
        try:
            d = json.load(open(path, encoding='utf-8'))
        except Exception as e:
            print(f'WARN: cannot read {path}: {e}', file=sys.stderr)
            continue
        text = d.get('content', [{}])[0].get('text', '')
        for m in re.finditer(r'\[p(\d+)\](.*?)(?=\[p\d+\]|\Z)', text, re.S):
            pages[int(m.group(1))] = m.group(2)
    return sorted(pages.items())


def clean_page(text: str) -> str:
    # The Dalail page text is \r-separated paragraphs with a header
    # line ("[pN] <book> صNN [book_id=...]") and a breadcrumb line
    # ("الباب: ..."). Drop those, plus the footnote block after the
    # "_________" rule at the page bottom.
    lines = []
    for ln in re.split(r'[\r\n]+', text):
        s = ln.strip()
        if not s:
            continue
        if '[book_id=' in s:
            continue
        if s.startswith('الباب:'):
            continue
        if s.startswith('حد:'):
            # Dalail's own limit notes, not book text.
            continue
        lines.append(s)
    text = '\n'.join(lines)
    # Footnotes sit after a line of underscores at the page bottom.
    text = re.split(r'_{4,}', text)[0]
    return text


HEADWORD_RE = re.compile(r'^' + AR_LETTER + r'{1,6}$')
SKIP_LINES = {'كتاب الألف', 'كتاب الباء', 'كتاب التاء', 'كتاب الثاء',
              'كتاب الجيم', 'كتاب الحاء', 'كتاب الخاء', 'كتاب الدال',
              'كتاب الذال', 'كتاب الراء', 'كتاب الزاي', 'كتاب السين',
              'كتاب الشين', 'كتاب الصاد', 'كتاب الضاد', 'كتاب الطاء',
              'كتاب الظاء', 'كتاب العين', 'كتاب الغين', 'كتاب الفاء',
              'كتاب القاف', 'كتاب الكاف', 'كتاب اللام', 'كتاب الميم',
              'كتاب النون', 'كتاب الهاء', 'كتاب الواو', 'كتاب الياء',
              'مقدمة المحقق', 'مقدمة المؤلف'}


def split_entries(full_text: str):
    """Split the book text into (headword, body) entries.

    A headword is a line of 1-6 Arabic letters. EXCEPTION: when two
    such lines are adjacent, the second is the Quranic word being
    defined (e.g. headword «ذعن» followed by «مُذْعِنِينَ» on its own
    line), i.e. part of the previous entry's body — not a new entry.
    """
    entries = []
    current_head = None
    current_body = []
    prev_was_headword = False
    for raw in re.split(r'[\r\n]+', full_text):
        line = raw.strip()
        if not line or line in SKIP_LINES:
            prev_was_headword = False
            continue
        stripped = re.sub(r'[\u064B-\u0655\u0670]', '', line)
        if (HEADWORD_RE.match(stripped) and len(stripped) <= 6
                and not prev_was_headword):
            if current_head is not None:
                entries.append((current_head, ' '.join(current_body)))
            current_head = stripped
            current_body = []
            prev_was_headword = True
        else:
            if current_head is not None:
                current_body.append(line)
            prev_was_headword = False
    if current_head is not None:
        entries.append((current_head, ' '.join(current_body)))
    return entries


CITE_RES = [r'قال الله تعالى', r'قال تعالى', r'قوله تعالى', r'وقال تعالى',
            r'قال الله', r'وقال الله', r'قال عز وجل', r'قوله عز وجل',
            r'روي أنّه', r'وروي أنّه']


def _strip_with_map(s: str):
    """Diacritic-stripped copy plus stripped->original index map."""
    out, idx = [], []
    for i, ch in enumerate(s):
        if '\u064B' <= ch <= '\u0655' or ch == '\u0670':
            continue
        out.append(ch)
        idx.append(i)
    return ''.join(out), idx


def extract_definition(body: str) -> str:
    """Opening definitional passage of an entry, verbatim, trimmed."""
    body = re.sub(r'«[^»]*»', '', body)          # footnote markers «١»
    body = re.sub(r'\([٠-٩0-9]+\)', '', body)     # (١) refs
    body = re.sub(r'\[[^\]]*\]', '', body)        # [البقرة/ ١٣٣] refs
    body = re.sub(r'\s+', ' ', body).strip()
    # Entries usually open with the definition ("الأب: الوالد، ...",
    # "سَمَاءُ كلّ شيء: أعلاه، ..."). Only when the entry opens with a
    # Quranic citation do we skip ahead to the first "word:" after it.
    head = body[:15]
    opens_with_cite = any(p in head for p in
                          ('قال الله تعالى', 'قال تعالى', 'قوله تعالى',
                           'وقال تعالى', 'قال الله', 'قال عز'))
    if opens_with_cite:
        stripped0, idx0 = _strip_with_map(body)
        cite_end = 0
        for pat in CITE_RES:
            i = stripped0.find(pat)
            if 0 <= i < 80:
                j = min(i + len(pat), len(idx0) - 1)
                cite_end = max(cite_end, idx0[j] + 1)
        m = re.search(r'([\u0621-\u064A\u064B-\u0655]{1,14})\s*:',
                      body[cite_end:])
        start = cite_end + m.start(1) if m else 0
    else:
        start = 0
    text = body[start:]
    # Cut before the first Quranic citation after the definition opens
    # (diacritic-tolerant via the stripped copy).
    stripped, idx_map = _strip_with_map(text)
    cut = len(text)
    for pat in CITE_RES:
        i = stripped.find(pat, 15)
        if 0 < i < len(stripped) and idx_map[i] < cut:
            cut = idx_map[i]
    text = text[:cut].strip()
    # Drop a dangling preposition left by the cut ("... اسم صنم في").
    text = re.sub(r'\s+(في|من|إلى|عن|على|ب|و|ثم|أي|أن|إن)\s*$', '', text)
    # Cap at ~500 chars, ending on a sentence boundary when possible.
    if len(text) > 500:
        short = text[:500]
        for sep in ('. ', '؟ ', '، '):
            j = short.rfind(sep)
            if j > 200:
                short = short[:j + 1].strip()
                break
        else:
            short = short.rsplit(' ', 1)[0]
        text = short
    return text.strip(' .،;:ـ')


def main():
    pages = load_pages()
    print(f'pages loaded: {len(pages)} '
          f'(ids {pages[0][0]}..{pages[-1][0]})')
    full = '\n'.join(clean_page(t) for _, t in pages)
    entries = split_entries(full)
    print(f'raw entries found: {len(entries)}')

    morph = json.load(open(MORPH, encoding='utf-8'))
    quran_roots = set()
    for words in morph.values():
        for w in words:
            m = re.search(r'الجذر \(([^)]+)\)', w[1] if len(w) >= 2 else '')
            if m:
                quran_roots.add(normalize(m.group(1)))
    print(f'unique normalized Quran roots: {len(quran_roots)}')

    # Keys reachable from Quran roots (exact or weak-final variant).
    reachable = {}
    for root in quran_roots:
        for cand in root_candidates(root):
            reachable.setdefault(cand, root)

    lexicon = {}
    skipped = []
    for head, body in entries:
        key = normalize(head)
        if key in reachable and key not in lexicon:
            definition = extract_definition(body)
            if len(definition) >= 6:
                lexicon[key] = definition
            else:
                skipped.append((head, 'too short'))
        elif key in lexicon:
            pass  # duplicate headword spelling; keep first
    print(f'lexicon entries kept: {len(lexicon)}')
    # A root is covered when ANY of its candidates is a lexicon key
    # (same logic as the Dart lookup — shared candidates cover every
    # root that maps to them).
    covered_roots = {r for r in quran_roots
                     if any(c in lexicon for c in root_candidates(r))}
    print(f'Quran roots covered: {len(covered_roots)} / {len(quran_roots)} '
          f'({100 * len(covered_roots) / len(quran_roots):.1f}%)')
    missing = sorted(set(quran_roots) - covered_roots)
    print(f'missing roots (sample): {missing[:20]}')
    print(f'skipped: {skipped[:10]}')

    # Words covered by the lexicon (same logic as Dart coverageStats).
    total = with_lex = 0
    for words in morph.values():
        for w in words:
            total += 1
            desc = w[1] if len(w) >= 2 else ''
            m = re.search(r'الجذر \(([^)]+)\)', desc)
            if m and any(c in lexicon for c in root_candidates(m.group(1))):
                with_lex += 1
    print(f'words with lexicon definition: {with_lex} / {total} '
          f'({100 * with_lex / total:.1f}%)')

    OUT.write_text(json.dumps(lexicon, ensure_ascii=False, sort_keys=True),
                   encoding='utf-8')
    print(f'wrote {OUT} ({OUT.stat().st_size} bytes)')


if __name__ == '__main__':
    main()

"""Build assets/quran_data/surah_sciences.json from Dalail-fetched pages.

Sources (all verified in Dalail):
- Names + maqsad: مصاعد النظر للإشراف على مقاصد السور — برهان الدين البقاعي
  (ت ٨٨٥هـ)، الطبعة الأولى ١٤٠٨هـ/١٩٨٧م، مكتبة المعارف - الرياض.
  Dalail book 1404, 3 vols, 1,180 pages.
- Fadail: موسوعة فضائل سور وآيات القرآن - القسم الصحيح — محمد بن رزق
  الطرهوني. Dalail book 144114, 767 pages.
- نزول السورة: already complete 114/114 in surah_info.json — NOT touched here.

Pages fetched: /tmp/bugh_pages/batch_*.json (loader: /tmp/bugh_load.py).
Plans: /tmp/bugh_outlines/maqasid_plan.json, fadail_plan.json.
Surahs 1-2 keep their hand-verified sample values (cleaned).

Parser rules (all verified against the fetched text):
- Maqsad: opening of the "مقصودها" section — pattern "(و)?مقصودها[،:]"
  (covers bare "مقصودها:" and comma "ومقصودها،") or
  "والمقصود من هذه السورة:". Verbatim, capped ~2000 chars.
- Names: ONLY from explicit naming sentences:
    * "وتسمى: X" / "وتسمى X" / "وتسميتها بـ X"
    * "واسمها أيضاً: X" (a real list)
    * quoted: اسمها "..." / واسمها "..."
    * chapter-title parenthetical: "سورة فصلت (السجدة)"
    * "وهي إحدى الزهراوين" -> الزهراء (Baqarah + Aal-Imran only)
  The bare "اسمها ..." pattern is BANNED — it matches discussion text.
  Name items are validated: 1-4 words, no discussion tokens.
  Manual override: surah 9 list prints "الفاتحة" but the book's own
  etymology passage says "وكذا الفاضحة: لأن من افتضح..." — the printed
  "الفاتحة" is a print error; names_list uses "الفاضحة".
- Fadail: first "* ..." bullet after "باقي فضائل سورة" (if present),
  else after "الفصل الأول" (if present), else the first bullet overall.
  Hadith: the narrator line after the bullet ("عن X:" possibly preceded
  by "- " or "(١٣٢) ") through the closing quote of the matn.
  No-bullet أبواب stating "لم يصح ... سوى أنها من المفصل" use that
  sentence itself as the headline.
- Surahs with no باب in the موسوعة get the honest note
  "لم يفرد لها المؤلف باباً خاصاً في القسم الصحيح من الموسوعة."
- Surahs where Baqa'i lists no other names get the honest note
  "لم يذكر البقاعي في مصاعد النظر أسماء أخرى لهذه السورة."
"""
import json, os, re, sys

sys.path.insert(0, '/tmp')
from bugh_load import load_bugh_pages, clean_page

WT = '/home/hatch/workspace/noor-quran-meanings'
DIAC = re.compile(r'[\u064B-\u0652\u0640]')


def strip_diac(s):
    return DIAC.sub('', s)


# ---------------------------------------------------------------- plans
MQ_PLAN = json.load(open('/tmp/bugh_outlines/maqasid_plan.json'))
FD_PLAN = json.load(open('/tmp/bugh_outlines/fadail_plan.json'))
# extra pages fetched after the first plan (bullets beyond the first 3 pp.)
FD_EXTRA = {8: [258], 9: [262], 10: [266, 267, 268, 269, 270],
            50: [429, 430, 431, 432, 433]}
for n, extra in FD_EXTRA.items():
    FD_PLAN[str(n)]['pages'] = sorted(set(FD_PLAN[str(n)]['pages'] + extra))

PAGES = load_bugh_pages()

SURAH_NAMES = {
    1: 'الفاتحة', 2: 'البقرة', 3: 'آل عمران', 4: 'النساء', 5: 'المائدة',
    6: 'الأنعام', 7: 'الأعراف', 8: 'الأنفال', 9: 'التوبة', 10: 'يونس',
    11: 'هود', 12: 'يوسف', 13: 'الرعد', 14: 'إبراهيم', 15: 'الحجر',
    16: 'النحل', 17: 'الإسراء', 18: 'الكهف', 19: 'مريم', 20: 'طه',
    21: 'الأنبياء', 22: 'الحج', 23: 'المؤمنون', 24: 'النور',
    25: 'الفرقان', 26: 'الشعراء', 27: 'النمل', 28: 'القصص',
    29: 'العنكبوت', 30: 'الروم', 31: 'لقمان', 32: 'السجدة',
    33: 'الأحزاب', 34: 'سبأ', 35: 'فاطر', 36: 'يس', 37: 'الصافات',
    38: 'ص', 39: 'الزمر', 40: 'غافر', 41: 'فصلت', 42: 'الشورى',
    43: 'الزخرف', 44: 'الدخان', 45: 'الجاثية', 46: 'الأحقاف',
    47: 'محمد', 48: 'الفتح', 49: 'الحجرات', 50: 'ق', 51: 'الذاريات',
    52: 'الطور', 53: 'النجم', 54: 'القمر', 55: 'الرحمن', 56: 'الواقعة',
    57: 'الحديد', 58: 'المجادلة', 59: 'الحشر', 60: 'الممتحنة',
    61: 'الصف', 62: 'الجمعة', 63: 'المنافقون', 64: 'التغابن',
    65: 'الطلاق', 66: 'التحريم', 67: 'الملك', 68: 'القلم',
    69: 'الحاقة', 70: 'المعارج', 71: 'نوح', 72: 'الجن', 73: 'المزمل',
    74: 'المدثر', 75: 'القيامة', 76: 'الإنسان', 77: 'المرسلات',
    78: 'النبأ', 79: 'النازعات', 80: 'عبس', 81: 'التكوير',
    82: 'الانفطار', 83: 'المطففين', 84: 'الانشقاق', 85: 'البروج',
    86: 'الطارق', 87: 'الأعلى', 88: 'الغاشية', 89: 'الفجر',
    90: 'البلد', 91: 'الشمس', 92: 'الليل', 93: 'الضحى', 94: 'الشرح',
    95: 'التين', 96: 'العلق', 97: 'القدر', 98: 'البينة', 99: 'الزلزلة',
    100: 'العاديات', 101: 'القارعة', 102: 'التكاثر', 103: 'العصر',
    104: 'الهمزة', 105: 'الفيل', 106: 'قريش', 107: 'الماعون',
    108: 'الكوثر', 109: 'الكافرون', 110: 'النصر', 111: 'المسد',
    112: 'الإخلاص', 113: 'الفلق', 114: 'الناس',
}

# ---------------------------------------------------------------- helpers
STOP_TOKENS = set('''واضح دال بتأمل لأن فإن إلى أن وكذا بما
في على كان يكون تكون ذلك هذه هذا ثم أيضا جواب القسم آيته فواصله الظرف
مظروفه بديع القدر ليس فيها ما لا من عن إلى حتى إن أن أو و ثم لو إذا
أي أية بهذا به بذلك كذلك هكذا كما قاله قال المعلوم صوابه صواب جوابه'''.split())
# NOTE: الذي/التي/الذين (as in "الذين كفروا"، a real name of surah محمد),
# هو/هي (as in "قل هو الله أحد") and قد (as in "قد سمع") are deliberately
# NOT stop tokens — the strict naming patterns they guard cannot produce
# discussion fragments with them, and real names contain them.


def norm_word(w):
    """Strip diacritics/tatweel and a leading و from a name word."""
    w = strip_diac(w).replace('ـ', '')
    return w.lstrip('و')


def valid_name(item, strict=True):
    """A surah name is 1-4 Arabic words, none of them a discussion token
    (quoted names bypass the stoplist: the quotes prove it is a name)."""
    item = item.strip(' ،.؛:"«»()')
    if not item or len(item) > 40:
        return False
    words = [norm_word(w) for w in item.split()]
    if not words or len(words) > 4:
        return False
    for w in words:
        if strict and w in STOP_TOKENS:
            return False
        if not re.fullmatch(r'[ء-ي]+', w):
            return False
    return True


def split_names(chunk, strict=True, max_items=None, split_on_wa=True,
                stop_at_first_invalid=False):
    """Split a naming chunk on ، (and on و, unless split_on_wa is False)
    into validated name items. Returns the diacritic-stripped forms
    (what the popup displays). max_items caps how many leading items
    are taken (for unquoted "واسمها" sentences, where discussion tails
    follow the names). split_on_wa=False keeps discussion phrases whole
    so their stop tokens still kill them (splitting on و would shred
    them into small fragments that pass validation).
    stop_at_first_invalid=True: a failed item ends the list (names lead
    the sentence; the first discussion fragment ends it) — used for
    unquoted "واسمها" sentences like surah 114's "واسمها دال على ذلك،
    لأن الإنسان مطبوع على الشر، وأكثر شره بالمكر والخداع" where a
    later fragment ("أكثر شره بالمكر والخداع") would otherwise pass."""
    chunk = re.sub(r'\s+', ' ', chunk).strip(' ،.')
    sep = r'،| و(?=[ء-ي])' if split_on_wa else r'،'
    items = []
    for part in re.split(sep, chunk):
        part = part.strip(' ،.()')
        if part.startswith('وكذا '):
            part = part[5:]
        if part.startswith('كذا '):
            part = part[4:]
        if part.startswith('و') and len(part) > 1 and part[1] != ' ':
            part = part[1:]
        if valid_name(part, strict=strict):
            items.append(' '.join(norm_word(w) for w in part.split()))
            if max_items is not None and len(items) >= max_items:
                break
        elif stop_at_first_invalid:
            break
    return items


def mq_text(n):
    return '\n'.join(clean_page(PAGES.get((1404, pg), ''))
                     for pg in MQ_PLAN[str(n)]['pages'])


def fd_text(n):
    return '\n'.join(clean_page(PAGES.get((144114, pg), ''))
                     for pg in FD_PLAN[str(n)]['pages'])


def naming_chunk(text, start, max_lines=3):
    """The name list starting at `start`: accumulate whole lines until one
    ends with '.' (max `max_lines` lines). Never swallow the next
    paragraph (the old regex did, merging names with discussion text)."""
    lines = text[start:].split('\n')
    out = []
    for ln in lines[:max_lines]:
        out.append(ln.strip())
        if ln.strip().endswith('.'):
            break
    return ' '.join(out).strip()


# ---------------------------------------------------------------- names
def parse_names(n, text):
    names, verbatim = [], []
    # title parenthetical: "سورة فصلت (السجدة)"
    m = re.search(r'سورة [ء-ي]+ \(([^)]+)\)', text)
    if m and valid_name(m.group(1)):
        names.append(' '.join(norm_word(w) for w in m.group(1).split()))
    # "وتسمى: X" / "وتسمى X" / "وتسمى - أيضاً -: X" / "وتسمى أيضاً: X"
    # (list ends at the first line ending with '.')
    for m in re.finditer(r'وتسمى\s*(?:-\s*أيضاً\s*-\s*)?(?:أيضاً\s*)?:?\s*',
                         text):
        chunk = naming_chunk(text, m.end())
        verbatim.append('وتسمى: ' + chunk)
        names += split_names(chunk)
    # "وتسميتها بـ X" / "وتسميتها بالـ X" (ب attached, no tatweel)
    for m in re.finditer(r'وتسميتها ب(?:ـ)?\s*([^\n.،]+)', text):
        names += split_names(m.group(1))
    # "واسمها أيضاً: X" — a real list (spans lines until one ends with '.')
    for m in re.finditer(r'واسمها أيضاً:\s*', text):
        chunk = naming_chunk(text, m.end())
        verbatim.append('واسمها أيضاً: ' + chunk)
        names += split_names(chunk)
    # unquoted "واسمها X، وكذا Y" — names lead, discussion follows:
    # take only the leading items and stop at the first discussion
    # fragment; do NOT split on و (a discussion tail shredded on و
    # yields small fragments that pass validation).
    for m in re.finditer(r'واسمها\s+(?![أأ]يضاً|")', text):
        chunk = naming_chunk(text, m.end())
        names += split_names(chunk, max_items=2, split_on_wa=False,
                             stop_at_first_invalid=True)
    # quoted names: اسمها "..." / واسمها "..." (quotes prove it is a name)
    for m in re.finditer(r'و?اسمها\s*"([^"]+)"', text):
        if valid_name(m.group(1), strict=False):
            names.append(' '.join(norm_word(w) for w in m.group(1).split()))
    # الزهراوان: Baqarah + Aal-Imran are the two الزهراوين
    if 'الزهراوين' in text and n in (2, 3):
        names.append('الزهراء')
    # "عليه السلام" is an honorific, not part of the name: "سورة موسى
    # عليه السلام" -> "سورة موسى"; "نوح عليه السلام" -> "نوح" (canonical,
    # dropped below).
    names = [x[:-len(' عليه السلام')] if x.endswith(' عليه السلام') else x
             for x in names]
    # dedupe, keep order; drop the surah's own canonical name
    seen, out = set(), []
    for x in names:
        if x == SURAH_NAMES[n] or x in seen:
            continue
        seen.add(x)
        out.append(x)
    return out, verbatim


# manual overrides: (names_list, reason)
NAME_OVERRIDES = {
    # printed list says "الفاتحة"; the book's own etymology passage says
    # "وكذا الفاضحة: لأن من افتضح كان أهلًا للبراءة منه" — print error.
    9: (['التوبة', 'الفاضحة', 'البحوث', 'المبعثرة', 'المثيرة', 'الحافرة',
         'المخزية', 'المهلكة', 'المشردة', 'المرشدة', 'المنكلة', 'المدمدمة',
         'سورة البعوث', 'سورة العذاب', 'المقشقشة'],
        'printed "الفاتحة" corrected to "الفاضحة" per the book\'s own '
        'etymology passage in the same chapter'),
    # opening line prints "وتسمى سورة اللائكة" (missing م); the chapter's
    # own etymology sentence says "وكذا تسميتها بالملائكة" — print error.
    35: (['سورة الملائكة'],
         'printed "اللائكة" corrected to "الملائكة" per the book\'s own '
         'etymology sentence in the same chapter'),
    # "المنافقين" is only the genitive case of the canonical name
    # المنافقون (from "وتسميتها بالمنافقين") — not a separate name.
    63: ([], 'no alternative name: "المنافقين" is the genitive of '
            'the canonical name المنافقون'),
    # printed "النبا" without hamza; standard spelling "النبأ".
    78: (['النبأ', 'التساؤل'],
         'printed "النبا" normalized to the standard spelling "النبأ"'),
}

NO_NAMES_NOTE = 'لم يذكر البقاعي في مصاعد النظر أسماء أخرى لهذه السورة.'

# ---------------------------------------------------------------- maqsad
MAQSAD_RE = re.compile(r'(?:و)?مقصودها[،:]\s*|والمقصود من هذه السورة:\s*')


def parse_maqsad(text):
    m = MAQSAD_RE.search(text)
    if not m:
        return None, None
    body = text[m.end():]
    # cut at the next section heading (all line-anchored: "أدلة" unanchored
    # falsely matched inside "المجادلة من" and truncated surah 59)
    cut = re.search(r'\n(و)?مقصود |\n[اأ]دلة |\nعدد آياتها|\nوآيها |\nوهي (مدنية|مكية)',
                    body)
    if cut:
        body = body[:cut.start()]
    body = re.sub(r'\s+', ' ', body).strip()
    if len(body) > 2000:
        # cut at a sentence boundary before 2000
        cut_at = body.rfind('،', 1500, 2000)
        body = body[:cut_at + 1] if cut_at > 0 else body[:2000]
    verbatim = body
    # short: the first sentence; if it is very short, extend with the
    # next '،'-clauses OF THE SAME sentence (surah 27's "وصف" alone is
    # useless). Never cross a '.' — surah 3's whole maqsud is the one
    # word "التوحيد" and the next sentence is explanation, not the short.
    first_sentence = body.split('.')[0].strip()
    clauses = [c.strip() for c in first_sentence.split('،') if c.strip()]
    short = clauses[0] if clauses else ''
    for c in clauses[1:]:
        if len(short) >= 25:
            break
        short = f'{short}، {c}'
    if len(short) > 140:
        short = short[:140]
    return short, verbatim


# ---------------------------------------------------------------- fadail
BULLET_RE = re.compile(r'^\*\s*(.+?)\s*:?\s*$', re.M)
NARR_RE = re.compile(
    r'^(?:- )?\(?[٠-٩0-9]+\)?\s*عن ([ء-ي ]+?)\s*:\s*$|'
    r'^(?:- )?عن ([ء-ي ]+?)\s*:\s*$',
    re.M)
COLLECTOR_RE = re.compile(
    r'قال (أحمد|مسلم|الترمذي|أبو داود|النسائي|ابن ماجه|الدارمي|الحاكم|'
    r'ابن الضريس|الطيالسي|الإسماعيلي|ابن نصر|السيوطي|ابن جرير|ابن أبي حاتم|'
    r'البخاري|البيهقي|الطبراني|ابن حبان|الخطيب)\s*:')
NO_BAB_NOTE = 'لم يفرد لها المؤلف باباً خاصاً في القسم الصحيح من الموسوعة.'


def parse_fadail(n):
    text = fd_text(n)
    if not text.strip():
        return None, None, None, 'no_text'
    # section anchor: "باقي فضائل سورة" > "الفصل الأول" > start
    anchor = 0
    for pat in ('باقي فضائل سورة', 'الفصل الأول'):
        i = text.find(pat)
        if i >= 0:
            anchor = i
            break
    bullets = list(BULLET_RE.finditer(text, anchor))
    if not bullets:
        # "لم يصح ... سوى أنها من المفصل" — that sentence IS the content
        m = re.search(r'لم يصح[^.\n]*?(?:من المفصل[^.\n]*)', text)
        if m:
            return m.group(0).strip(), None, None, 'lam_yasih'
        return None, None, None, 'no_bullet'
    b = bullets[0]
    headline = b.group(1).strip()
    rest = text[b.end():]
    # hadith: narrator line, then through the closing quote of the matn
    nm = NARR_RE.search(rest)
    hadith = None
    narrator = None
    source = None
    if nm:
        narrator = (nm.group(1) or nm.group(2)).strip()
        htext = rest[nm.start():]
        # cut at the next bullet or at 1200 chars
        nb = BULLET_RE.search(htext[10:])
        if nb:
            htext = htext[:10 + nb.start()]
        htext = re.sub(r'\s+', ' ', htext).strip()
        # through the closing quote of the matn if present
        q = htext.rfind('"')
        if q > 100:
            htext = htext[:q + 1]
        if len(htext) > 1200:
            htext = htext[:1200]
        hadith = htext
        cm = COLLECTOR_RE.search(hadith)
        if cm:
            source = cm.group(1)
    return headline, hadith, (narrator, source), 'ok'


# ---------------------------------------------------------------- build
def main():
    # Surahs 1-2 keep their hand-verified sample values (cleaned).
    # The sample file was deleted after the full extraction (its entries
    # live in surah_sciences.json now); read from whichever exists.
    sample_path = f'{WT}/assets/quran_data/surah_sciences_sample.json'
    if os.path.exists(sample_path):
        sample = json.load(open(sample_path, encoding='utf-8'))
        sample_by_n = {e['surah']: e for e in sample['surahs']}
    else:
        current = json.load(
            open(f'{WT}/assets/quran_data/surah_sciences.json',
                 encoding='utf-8'))
        sample_by_n = {e['surah']: e for e in current['surahs']
                       if e['surah'] in (1, 2)}
    out = {
        'sources': {
            'names_maqasid': 'مصاعد النظر للإشراف على مقاصد السور — '
                             'برهان الدين البقاعي (ت ٨٨٥هـ)، الطبعة الأولى '
                             '١٤٠٨هـ/١٩٨٧م، مكتبة المعارف - الرياض. '
                             'Dalail book 1404.',
            'fadail': 'موسوعة فضائل سور وآيات القرآن - القسم الصحيح — '
                      'محمد بن رزق الطرهوني. Dalail book 144114.',
            'nuzul': 'نزول السورة مكتمل 114/114 في surah_info.json — '
                     'غير مشمول هنا.',
            'notes': 'الأسماء من مصاعد النظر فقط، بدون تقسيم توقيفية/'
                     'اجتهادية (لم يثبت التقسيم من المصدر). سورة 9: '
                     'المطبوع "الفاتحة" صُحح إلى "الفاضحة" وفق شرح '
                     'البقاعي نفسه في الفصل.',
        },
        'surahs': [],
    }
    review = []
    for n in range(1, 115):
        if n in (1, 2):
            e = dict(sample_by_n[n])
            # clean any "حد:" pollution lines from the sample values
            for k in list(e):
                if isinstance(e[k], str):
                    e[k] = re.sub(r'\s*حد:[^\n]*', '', e[k]).strip()
            # surah 2's sample headline swallowed raw page text
            # ("› (١) عن أبي هريرة\nالفصل الأول...") — keep only the
            # first line (the real bullet text).
            if isinstance(e.get('fadail_headline'), str):
                h = e['fadail_headline']
                h = re.split(r'[›\n]', h)[0].strip()
                e['fadail_headline'] = h
            out['surahs'].append(e)
            review.append((n, 'SAMPLE', 'SAMPLE', 'SAMPLE'))
            continue
        mt = mq_text(n)
        names, verbatim = parse_names(n, mt)
        if n in NAME_OVERRIDES:
            names = NAME_OVERRIDES[n][0]
        maqsad_short, maqsad_verbatim = parse_maqsad(mt)
        if str(n) in FD_PLAN:
            headline, hadith, ns, fstatus = parse_fadail(n)
        else:
            headline, hadith, ns, fstatus = NO_BAB_NOTE, None, None, 'no_bab'
        if not names:
            names_verbatim = NO_NAMES_NOTE
        else:
            names_verbatim = '؛ '.join(verbatim) if verbatim else None
        e = {
            'surah': n,
            'name_ar': SURAH_NAMES[n],
            'names_list': names,
            'names_verbatim': names_verbatim,
            'names_etymology_verbatim': None,
            'maqsad_short': maqsad_short,
            'maqsad_verbatim': maqsad_verbatim,
            'nuzul_verbatim': None,
            'fadail_headline': headline,
            'fadail_hadith': hadith,
            'fadail_source': (f'{ns[0]}، {ns[1]}' if ns and ns[0]
                              else (ns[1] if ns and ns[1] else None)),
        }
        out['surahs'].append(e)
        review.append((n,
                       f'names={len(names)}' + (' OVERRIDE' if n in NAME_OVERRIDES else ''),
                       'maqsad=OK' if maqsad_short else 'MAQSAD-MISSING',
                       f'fadail={fstatus}' + (' H' if headline else '')
                       + (' +hadith' if hadith else '')))
    with open(f'{WT}/assets/quran_data/surah_sciences.json', 'w',
              encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    with open('/tmp/bugh_review.tsv', 'w', encoding='utf-8') as f:
        f.write('surah\tnames\tmaqsad\tfadail\t#names\tmaqsad_short\t'
                'fadail_headline\n')
        for n, nm, mq, fd in review:
            e = out['surahs'][n - 1]
            f.write(f"{n}\t{nm}\t{mq}\t{fd}\t{len(e['names_list'])}\t"
                    f"{e['maqsad_short'] or ''}\t"
                    f"{e['fadail_headline'] or ''}\n")
    n_names = sum(1 for e in out['surahs'] if e['names_list'])
    n_maq = sum(1 for e in out['surahs'] if e['maqsad_verbatim'])
    n_fad = sum(1 for e in out['surahs'] if e['fadail_headline'])
    n_fad_h = sum(1 for e in out['surahs'] if e['fadail_hadith'])
    print(f'names: {n_names}/114  maqsad: {n_maq}/114  '
          f'fadail: {n_fad}/114 (with hadith: {n_fad_h})')
    print('MISSING maqsad:', [e['surah'] for e in out['surahs']
                              if not e['maqsad_verbatim']])
    print('NO names:', [e['surah'] for e in out['surahs']
                        if not e['names_list']])
    print('NO fadail:', [e['surah'] for e in out['surahs']
                         if not e['fadail_headline']])


if __name__ == '__main__':
    main()

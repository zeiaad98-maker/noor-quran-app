"""Merge GeoNames Syria mosques (feature code S.MSQE) into the OSM bundle.

GeoNames (geonames.org, CC-BY 4.0 — attribution required, see the
mosques screen footer) is the only verified non-OSM bulk source that
adds real Syria mosques: 411 MSQE rows, of which ~56 sit >250 m from
any OSM-bundle entry. Names come from the Arabic alternate name when
present (393/411 have one); otherwise the ASCII transliteration is
used. Clear tombs/shrines are excluded (qubbat, ziyarat, tomb, shrine,
mausoleum, maqam, darih, rijal allah, ضريح/مقام/قبة) — but shaykh/sidi/
wali are NOT excluded, because they are common parts of real mosque
names (e.g. جامع الشيخ صخر, جامع سيدنا خالد بن الوليد).

Dedupe vs the bundle at 250 m (GeoNames coordinates are often
imprecise old NGA data, so 250 m — not 50 m — is used), and among
GeoNames rows themselves. Output rewrites
assets/quran_data/syria_mosques.json in the same compact format.
"""
import json
import math
import re
from collections import defaultdict

BUNDLE = '/home/hatch/workspace/noor-quran/assets/quran_data/syria_mosques.json'
GEONAMES = '/tmp/geonames_sy/SY.txt'
OUT = BUNDLE
DEDUPE_M = 250

AR = re.compile(r'[\u0600-\u06FF]')
SHRINE = re.compile(
    r'qubbat|qubba|ziyarat|ziy[aā]rat|tomb|shrine|mausoleum|maqam|darih|durih|rij[aā]l all[aā]h',
    re.I)
SHRINE_AR = ('ضريح', 'مقام', 'قبة', 'مدفن', 'رجال الله')


def hav_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def arabic_name(alts):
    for a in (alts or '').split(','):
        if AR.search(a):
            return a.strip()
    return ''


def is_shrine(name, alts):
    n = (name or '') + ' ' + (alts or '')
    if SHRINE.search(n):
        return True
    return any(w in n for w in SHRINE_AR)


bundle = json.load(open(BUNDLE, encoding='utf-8'))
mosques = bundle['mosques']
print('bundle before merge:', len(mosques))

# Grid index (cell ~1.1 km) for nearest-distance lookups.
CELL = 0.01
grid = defaultdict(list)
for b in mosques:
    grid[(int(b[1] // CELL), int(b[2] // CELL))].append(b)


def nearest_dist(lat, lon, extra=()):
    cx, cy = int(lat // CELL), int(lon // CELL)
    best = None
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for b in grid.get((cx + dx, cy + dy), []):
                d = hav_m(lat, lon, b[1], b[2])
                if best is None or d < best:
                    best = d
    for e in extra:
        d = hav_m(lat, lon, e[1], e[2])
        if best is None or d < best:
            best = d
    return best  # None = no bundle mosque within ~1.6 km


rows = []
with open(GEONAMES, encoding='utf-8') as f:
    for line in f:
        p = line.rstrip('\n').split('\t')
        if len(p) < 19:
            continue
        if p[6] == 'S' and p[7] == 'MSQE':
            rows.append(p)
print('GeoNames S.MSQE rows:', len(rows))

cands = []
for p in rows:
    name, asciiname, alts = p[1], p[2], p[3]
    lat, lon = float(p[4]), float(p[5])
    if is_shrine(name, alts):
        continue
    ar = arabic_name(alts)
    cands.append({'name': ar or asciiname, 'lat': lat, 'lon': lon,
                  'gid': p[0], 'arabic': bool(ar)})
print('after shrine filter:', len(cands))

added = []
skipped_near = 0
for c in sorted(cands, key=lambda c: (not c['arabic'], c['gid'])):
    d = nearest_dist(c['lat'], c['lon'], added)
    if d is not None and d <= DEDUPE_M:
        skipped_near += 1
        continue
    added.append([c['name'], round(c['lat'], 5), round(c['lon'], 5)])
    grid.setdefault((int(c['lat'] // CELL), int(c['lon'] // CELL)), []).append(
        [c['name'], c['lat'], c['lon']])
print('added from GeoNames:', len(added),
      '(with Arabic name:', sum(1 for a in added if AR.search(a[0])),
      ', transliteration only:', sum(1 for a in added if not AR.search(a[0])), ')')
print('skipped as within 250 m of bundle/added:', skipped_near)
for a in added:
    print('  +', a)

mosques = mosques + added
mosques.sort(key=lambda m: (m[1], m[2]))
named = sum(1 for m in mosques if m[0].strip())
data = {
    'count': len(mosques),
    'named': named,
    'unnamed': len(mosques) - named,
    'source': 'OpenStreetMap Syria extract (Geofabrik syria-latest.osm.pbf, 2026-11-16), maximal extraction + GeoNames Syria dump (S.MSQE, CC-BY 4.0, download.geonames.org/export/dump/SY.zip) merged at 250 m; deduped within 50 m (100 m same-name)',
    'mosques': mosques,
}
with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
print('bundle after merge:', len(mosques), 'named:', named,
      'unnamed:', len(mosques) - named)
print('wrote', OUT)

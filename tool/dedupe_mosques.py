"""Dedupe raw mosque candidates and build the compact bundled asset.

Dedupe rule: sort named entries first (ways before nodes when both named,
since a way centroid is usually the building centre), then greedily keep
an entry unless it is within 50 m of an already-kept entry AND
(same normalised name OR either entry is unnamed). Two differently-named
mosques 50 m apart are kept as distinct.

Output: assets/quran_data/syria_mosques.json
  {"count": N, "named": M, "unnamed": K, "source": "...", "mosques": [[name, lat, lon], ...]}
Coordinates rounded to 5 decimals (~1.1 m). Unnamed entries ship with
empty name; the app labels them "مسجد".
"""
import json
import math

RAW = '/tmp/mosques_raw.json'
OUT = '/home/hatch/workspace/noor-quran-mosques/assets/quran_data/syria_mosques.json'

def haversine_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))

def norm(name):
    return ' '.join((name or '').split())

def is_clearly_not_mosque(name):
    """OSM tagging errors and shrines, not mosques: a church mis-tagged
    religion=muslim ('كنيسة (مغلقة)'), and مقامات/أضرحة/مزارات (shrines
    and tombs tagged as Muslim places of worship)."""
    n = norm(name)
    if 'كنيس' in n or 'church' in n.lower():
        return True
    return n.startswith(('مقام ', 'مقام', 'ضريح', 'مزار'))

with open(RAW, encoding='utf-8') as f:
    cands = json.load(f)

print('raw candidates:', len(cands))
excluded = [c for c in cands if is_clearly_not_mosque(c['name'])]
print('excluded as clearly-not-mosque:', len(excluded),
      [norm(c['name']) for c in excluded][:30])
cands = [c for c in cands if not is_clearly_not_mosque(c['name'])]

# Priority: named first, then ways before nodes, then lower osm id.
def priority(c):
    named = 0 if norm(c['name']) else 1
    kind = 0 if c['kind'] == 'way' else 1
    return (named, kind, c['osm_id'])

cands.sort(key=priority)

kept = []
dropped = 0
for c in cands:
    dup = False
    for k in kept:
        if haversine_m(c['lat'], c['lon'], k['lat'], k['lon']) <= 50:
            if norm(c['name']) == norm(k['name']) or not norm(c['name']) or not norm(k['name']):
                dup = True
                break
    if dup:
        dropped += 1
    else:
        kept.append(c)

print('kept:', len(kept), 'dropped as dupes:', dropped)
named = sum(1 for k in kept if norm(k['name']))
print('named:', named, 'unnamed:', len(kept) - named)

kept.sort(key=lambda k: (k['lat'], k['lon']))
mosques = [[norm(k['name']), round(k['lat'], 5), round(k['lon'], 5)] for k in kept]
data = {
    'count': len(mosques),
    'named': named,
    'unnamed': len(mosques) - named,
    'source': 'OpenStreetMap Syria extract (Geofabrik syria-261115.osm.pbf, 2026-11-15); amenity=place_of_worship + religion=muslim, plus building=mosque and name-based catches (جامع/مسجد) where religion tag is missing; deduped within 50 m',
    'mosques': mosques,
}
with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
print('wrote', OUT)

# Spot checks
def nearest(lat, lon, n=3):
    scored = sorted(kept, key=lambda k: haversine_m(lat, lon, k['lat'], k['lon']))
    return [(round(haversine_m(lat, lon, k['lat'], k['lon'])), norm(k['name']) or '(unnamed)', k['lat'], k['lon']) for k in scored[:n]]

print('SPOT جامع الإيمان (33.4666772,36.1994628):', nearest(33.4666772, 36.1994628))
print('SPOT Umayyad (~33.5118,36.3068):', nearest(33.5118, 36.3068))
print('SPOT Muadamiyah centre (33.44,36.186) nearest 5:', nearest(33.44, 36.186, 5))
print('SPOT Aleppo citadel (36.1992,37.1626) nearest 3:', nearest(36.1992, 37.1626))
print('SPOT Homs centre (34.7269,36.7235) nearest 3:', nearest(34.7269, 36.7235))
# جامع عثمان in Muadamiyah? search names near user point
near = [k for k in kept if haversine_m(33.44, 36.186, k['lat'], k['lon']) <= 8000]
print('within 8km of (33.44,36.186):', len(near))
print('names containing عثمان within 8km:', [ (norm(k['name']), k['lat'], k['lon']) for k in near if 'عثمان' in norm(k['name']) ])
print('names containing الزيتونة:', [(norm(k['name']), k['lat'], k['lon']) for k in kept if 'الزيتونة' in norm(k['name'])])
print('names containing الأموي:', [(norm(k['name']), k['lat'], k['lon']) for k in kept if 'الأموي' in norm(k['name'])])

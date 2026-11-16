"""Extract mosques in Syria from the Geofabrik syria-latest.osm.pbf.

MAXIMAL extraction (v12): every feature that could plausibly be a mosque.
Pass 1: collect all node locations (needed to centroid ways).
Pass 2: collect candidate features, one reason each (first match wins):
  - building=mosque (any amenity/religion)
  - amenity=place_of_worship + religion=muslim
  - amenity=place_of_worship + no religion tag + name has جامع/مسجد/مصلى
  - amenity=place_of_worship + other (non-Abrahamic) religion + name has
    جامع/مسجد/مصلى (catches mis-tagged religion values)
  - religion=muslim + building set (not 'no'), no amenity
  - religion=muslim + name has جامع/مسجد/مصلى, no amenity/building
  - name-only: name has جامع/مسجد/مصلى, no amenity, no highway tag,
    name does not start with a street/square word (شارع/طريق/ساحة/...)
    and is not a church/shrine name
  - relations: amenity=place_of_worship + religion=muslim, centroided
    from member nodes (their buildings are normally mapped as ways too,
    so dedupe usually collapses them; counted separately here)
Nodes carry their own coords; ways are centroided from member nodes.
Churches (religion=christian/jewish/...) are never kept by a name rule;
building=mosque is trusted as-is.
"""
import json
import osmium
from collections import Counter

PBF = '/tmp/syria-latest.osm.pbf'
MOSQUE_WORDS = ('جامع', 'مسجد', 'مصلى')
NON_MUSLIM_RELIGIONS = (
    'christian', 'jewish', 'buddhist', 'hindu', 'sikh', 'taoist',
    'shinto', 'jain', 'pagan', 'zoroastrian', 'bahai', 'other',
)
STREET_WORDS = (
    'شارع', 'طريق', 'ساحة', 'حي ', 'مدرسة', 'مستشفى', 'حديقة', 'سوق',
    'جسر', 'مقام', 'ضريح', 'مزار', 'كنيس', 'دوار', 'نفق', 'جادة',
    'موقف', 'مدخل', 'باب ',
)


def _strip_diacritics(s):
    return ''.join(
        ch for ch in (s or '')
        if not (0x064B <= ord(ch) <= 0x0652 or ord(ch) == 0x0670))


def has_mosque_word(name):
    """True only if جامع/مسجد/مصلى appears as a whole word (after
    stripping the definite article ال and diacritics). A plain
    substring test is WRONG: it matches جامعة (university), الجامعي
    (university-related), المجامع, etc. — 146 of the first maximal
    pass's 205 'name-only' candidates were universities, bus stops,
    hospitals and dorms, not mosques."""
    for tok in _strip_diacritics(name).split():
        t = tok[2:] if tok.startswith('ال') else tok
        if t in MOSQUE_WORDS:
            return True
    return False


def looks_like_street_or_shrine(name):
    n = (name or '').strip()
    if 'كنيس' in n or 'church' in n.lower():
        return True
    return n.startswith(STREET_WORDS)


class NodeLocations(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.locs = {}

    def node(self, n):
        if n.location.valid():
            self.locs[n.id] = (n.location.lat, n.location.lon)


class MosqueCollector(osmium.SimpleHandler):
    def __init__(self, locs):
        super().__init__()
        self.locs = locs
        self.candidates = []  # dicts: kind, osm_id, name, lat, lon, tags
        self.stats = Counter()
        self.rel_members = []  # (osm_id, name, [node refs], [way refs])

    def _name(self, tags):
        return tags.get('name') or tags.get('name:ar') or tags.get('name:en') or ''

    def _is_mosque(self, tags):
        amenity = tags.get('amenity')
        religion = tags.get('religion')
        building = tags.get('building')
        highway = tags.get('highway')
        name = self._name(tags)
        if building == 'mosque':
            return True, 'building=mosque'
        if amenity == 'place_of_worship':
            if religion == 'muslim':
                return True, 'pow+muslim'
            if religion is None and has_mosque_word(name):
                return True, 'pow+noreligion+mosqueword'
            if (religion is not None and religion not in NON_MUSLIM_RELIGIONS
                    and has_mosque_word(name)):
                return True, 'pow+otherreligion+mosqueword'
            return False, ''
        # No amenity=place_of_worship: other signals.
        if religion == 'muslim' and building not in (None, 'no'):
            return True, 'muslim+building'
        if religion == 'muslim' and has_mosque_word(name):
            return True, 'muslim+mosqueword'
        if (has_mosque_word(name) and highway is None
                and not looks_like_street_or_shrine(name)):
            return True, 'name-only'
        return False, ''

    def _record(self, kind, osm_id, tags, lat, lon, reason):
        self.candidates.append({
            'kind': kind, 'osm_id': osm_id,
            'name': self._name(tags), 'lat': lat, 'lon': lon,
            'reason': reason,
            'religion': tags.get('religion'),
            'amenity': tags.get('amenity'),
            'building': tags.get('building'),
        })

    def node(self, n):
        self.stats['nodes_seen'] += 1
        if not n.location.valid():
            return
        ok, reason = self._is_mosque(n.tags)
        if ok:
            self._record('node', n.id, n.tags, n.location.lat, n.location.lon, reason)

    def way(self, w):
        self.stats['ways_seen'] += 1
        ok, reason = self._is_mosque(w.tags)
        if not ok:
            return
        pts = [self.locs[ref.ref] for ref in w.nodes if ref.ref in self.locs]
        if not pts:
            return
        lat = sum(p[0] for p in pts) / len(pts)
        lon = sum(p[1] for p in pts) / len(pts)
        self._record('way', w.id, w.tags, lat, lon, reason)

    def relation(self, r):
        t = r.tags
        if t.get('amenity') == 'place_of_worship':
            self.stats['relations_pow'] += 1
            if t.get('religion') == 'muslim':
                self.stats['relations_pow_muslim'] += 1
                node_refs = [m.ref for m in r.members if m.type == 'n']
                way_refs = [m.ref for m in r.members if m.type == 'w']
                self.rel_members.append(
                    (r.id, self._name(t), node_refs, way_refs))
        if t.get('building') == 'mosque':
            self.stats['relations_building_mosque'] += 1


locs_h = NodeLocations()
locs_h.apply_file(PBF, locations=True)
print('nodes with locations:', len(locs_h.locs))

col = MosqueCollector(locs_h.locs)
col.apply_file(PBF, locations=True)
print('stats:', dict(col.stats))
print('candidates (nodes+ways):', len(col.candidates))
print('by reason:', Counter(c['reason'] for c in col.candidates))
print('by kind:', Counter(c['kind'] for c in col.candidates))
print('named:', sum(1 for c in col.candidates if c['name']))
print('unnamed:', sum(1 for c in col.candidates if not c['name']))

# Relations: centroid from member node locations; log the rest.
way_ids = {c['osm_id'] for c in col.candidates if c['kind'] == 'way'}
rel_added = 0
for rid, name, node_refs, way_refs in col.rel_members:
    pts = [locs_h.locs[ref] for ref in node_refs if ref in locs_h.locs]
    if pts:
        lat = sum(p[0] for p in pts) / len(pts)
        lon = sum(p[1] for p in pts) / len(pts)
        col.candidates.append({
            'kind': 'relation', 'osm_id': rid, 'name': name,
            'lat': lat, 'lon': lon, 'reason': 'relation-pow-muslim',
            'religion': 'muslim', 'amenity': 'place_of_worship',
            'building': None,
        })
        rel_added += 1
    elif any(w in way_ids for w in way_refs):
        print('relation', rid, name, 'covered by member way already')
    else:
        print('relation', rid, name, 'NO centroid and NO member way candidate')
print('relations added as candidates:', rel_added)
print('total candidates:', len(col.candidates))
print('by reason (final):', Counter(c['reason'] for c in col.candidates))

with open('/tmp/mosques_raw.json', 'w', encoding='utf-8') as f:
    json.dump(col.candidates, f, ensure_ascii=False)
print('wrote /tmp/mosques_raw.json')

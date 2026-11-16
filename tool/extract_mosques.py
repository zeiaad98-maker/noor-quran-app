"""Extract mosques in Syria from the Geofabrik syria-latest.osm.pbf.

Pass 1: collect all node locations (needed to centroid ways).
Pass 2: collect candidate features:
  - amenity=place_of_worship AND religion=muslim (any name), OR
  - amenity=place_of_worship AND no religion tag AND name contains جامع/مسجد, OR
  - building=mosque (any amenity/religion), OR
  - amenity=place_of_worship AND religion missing AND name:ar contains جامع/مسجد
Nodes carry their own coords; ways are centroided from member nodes.
Relations are counted but not extracted (rare for mosques; logged).
"""
import json
import math
import osmium

PBF = '/tmp/syria-latest.osm.pbf'
MOSQUE_WORDS = ('جامع', 'مسجد')


def has_mosque_word(name):
    return any(w in (name or '') for w in MOSQUE_WORDS)


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
        self.stats = {'nodes_seen': 0, 'ways_seen': 0, 'relations_pow': 0}

    def _name(self, tags):
        return tags.get('name') or tags.get('name:ar') or tags.get('name:en') or ''

    def _is_mosque(self, tags):
        amenity = tags.get('amenity')
        religion = tags.get('religion')
        building = tags.get('building')
        name = self._name(tags)
        if building == 'mosque':
            return True, 'building=mosque'
        if amenity == 'place_of_worship':
            if religion == 'muslim':
                return True, 'pow+muslim'
            if religion is None and has_mosque_word(name):
                return True, 'pow+noname-religion+mosque-word'
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
        if r.tags.get('amenity') == 'place_of_worship':
            self.stats['relations_pow'] += 1


locs_h = NodeLocations()
locs_h.apply_file(PBF, locations=True)
print('nodes with locations:', len(locs_h.locs))

col = MosqueCollector(locs_h.locs)
col.apply_file(PBF, locations=True)
print('stats:', col.stats)
print('candidates:', len(col.candidates))
from collections import Counter
print('by reason:', Counter(c['reason'] for c in col.candidates))
print('by kind:', Counter(c['kind'] for c in col.candidates))
print('named:', sum(1 for c in col.candidates if c['name']))
print('unnamed:', sum(1 for c in col.candidates if not c['name']))

with open('/tmp/mosques_raw.json', 'w', encoding='utf-8') as f:
    json.dump(col.candidates, f, ensure_ascii=False)
print('wrote /tmp/mosques_raw.json')

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// add or edit the commented locations please, we using openstreetmap not gmasp
// when the backend is ready, only this file and the "to connect"
// comments in main.dart need to change.
//the coordinates are close guesses around the campus center and the
// accessibility details are placeholders. before the real release, walk the campus (or use
// the "Add accessibility info" page) and fix them. for exact coordinates, right-click the
// building in google maps and click the coordinates at the top of the menu.

const Color kAccessible = Color(0xFF2E9E5B);
const Color kPartial = Color(0xFFF2A100);
const Color kInaccessible = Color(0xFFD64545);

enum PlaceType {
  college,
  office,
  library,
  food,
  health,
  sports,
  dorm,
  landmark,
  gate,
  parking,
  other,
  hotel,
}

extension PlaceTypeX on PlaceType {
  IconData get icon => switch (this) {
    PlaceType.college => Icons.school,
    PlaceType.office => Icons.apartment,
    PlaceType.library => Icons.local_library,
    PlaceType.food => Icons.restaurant,
    PlaceType.health => Icons.local_hospital,
    PlaceType.sports => Icons.sports_basketball,
    PlaceType.dorm => Icons.hotel,
    PlaceType.landmark => Icons.account_balance,
    PlaceType.gate => Icons.door_front_door,
    PlaceType.parking => Icons.local_parking,
    PlaceType.other => Icons.place,
    PlaceType.hotel => Icons.hotel,
  };

  String get label => switch (this) {
    PlaceType.college => 'College & Institute',
    PlaceType.office => 'Offices & Services',
    PlaceType.library => 'Library & Learning',
    PlaceType.food => 'Food & Canteen',
    PlaceType.health => 'Health & Clinic',
    PlaceType.sports => 'Sports & Open Space',
    PlaceType.dorm => 'Dormitory',
    PlaceType.landmark => 'Landmark & Museum',
    PlaceType.gate => 'Gate & Entrance',
    PlaceType.parking => 'Parking',
    PlaceType.other => 'Spot on the map',
    PlaceType.hotel => 'Hotel & Lodging',
  };

  // shorter text for the filter chips at the top of the map
  String get chipLabel => switch (this) {
    PlaceType.college => 'Colleges',
    PlaceType.office => 'Offices',
    PlaceType.library => 'Library',
    PlaceType.food => 'Food',
    PlaceType.health => 'Health',
    PlaceType.sports => 'Sports',
    PlaceType.dorm => 'Dorms',
    PlaceType.landmark => 'Landmarks',
    PlaceType.gate => 'Gates',
    PlaceType.parking => 'Parking',
    PlaceType.other => 'Other',
    PlaceType.hotel => 'Hotels',
  };
}

// accessibility (pwd) features. the first 3 (ramp, elevator, restroom) decide the pin color,
// the rest are extra details that only show up in the details sheet and the filters.

enum Pwd {
  ramp,
  elevator,
  restroom,
  wideDoors,
  handrails,
  tactile,
  braille,
  parking,
  groundFloor,
  restArea,
  helpDesk,
}

// these 3 are the "core" ones, they have their own true / false fields in Place
const List<Pwd> kCorePwd = [Pwd.ramp, Pwd.elevator, Pwd.restroom];

// the headings used to group the features in the details sheet
const List<String> kPwdGroups = [
  'Getting in',
  'Moving around',
  'Facilities & help',
];

extension PwdX on Pwd {
  String get label => switch (this) {
    Pwd.ramp => 'Wheelchair ramp',
    Pwd.elevator => 'Elevator',
    Pwd.restroom => 'Accessible restroom',
    Pwd.wideDoors => 'Wide doors (80 cm+)',
    Pwd.handrails => 'Handrails',
    Pwd.tactile => 'Tactile paving',
    Pwd.braille => 'Braille / tactile signs',
    Pwd.parking => 'PWD parking slot',
    Pwd.groundFloor => 'Main services on ground floor',
    Pwd.restArea => 'Seating / rest area',
    Pwd.helpDesk => 'PWD assistance desk',
  };

  // shorter text for the filter chips
  String get chipLabel => switch (this) {
    Pwd.ramp => 'Ramp',
    Pwd.elevator => 'Elevator',
    Pwd.restroom => 'Accessible restroom',
    Pwd.wideDoors => 'Wide doors',
    Pwd.handrails => 'Handrails',
    Pwd.tactile => 'Tactile paving',
    Pwd.braille => 'Braille signs',
    Pwd.parking => 'PWD parking',
    Pwd.groundFloor => 'Ground floor services',
    Pwd.restArea => 'Rest area',
    Pwd.helpDesk => 'Help desk',
  };

  IconData get icon => switch (this) {
    Pwd.ramp => Icons.accessible_forward,
    Pwd.elevator => Icons.elevator,
    Pwd.restroom => Icons.wc,
    Pwd.wideDoors => Icons.meeting_room,
    Pwd.handrails => Icons.linear_scale,
    Pwd.tactile => Icons.blind,
    Pwd.braille => Icons.touch_app,
    Pwd.parking => Icons.local_parking,
    Pwd.groundFloor => Icons.looks_one,
    Pwd.restArea => Icons.event_seat,
    Pwd.helpDesk => Icons.support_agent,
  };

  String get group => switch (this) {
    Pwd.ramp || Pwd.wideDoors || Pwd.parking || Pwd.groundFloor => 'Getting in',
    Pwd.elevator ||
    Pwd.handrails ||
    Pwd.tactile ||
    Pwd.restArea => 'Moving around',
    Pwd.restroom || Pwd.braille || Pwd.helpDesk => 'Facilities & help',
  };
}

// small data classes

class Review {
  const Review(this.name, this.rating, this.text, this.when);
  final String name;
  final double rating;
  final String text;
  final String when;
}

// an office, department or room inside a building
class Unit {
  const Unit(
    this.name, {
    this.floor = 'Ground floor',
    this.accessible = true,
    this.note,
  });
  final String name;
  final String floor;
  final bool accessible; // can a wheelchair user reach it
  final String? note;
}

// a hallway / corridor / stairs inside a building. level: 0 = ok, 1 = be careful, 2 = blocked
class Hallway {
  const Hallway(this.name, this.level, this.note);
  final String name;
  final int level;
  final String note;

  Color get color => level == 0
      ? kAccessible
      : level == 1
      ? kPartial
      : kInaccessible;

  IconData get icon => level == 0
      ? Icons.check_circle
      : level == 1
      ? Icons.warning_amber_rounded
      : Icons.cancel;
}

// other things a building has (wifi, computer lab...) that are not about accessibility
class Facility {
  const Facility(this.icon, this.label);
  final IconData icon;
  final String label;
}

// a walkway between buildings, drawn as a colored line on the map
// level: 0 = smooth and flat, 1 = slope or narrow, 2 = has steps (not wheelchair friendly)
class CampusPath {
  const CampusPath(this.id, this.name, this.level, this.note, this.points);
  final String id;
  final String name;
  final int level;
  final String note;
  final List<LatLng> points;

  Color get color => level == 0
      ? kAccessible
      : level == 1
      ? kPartial
      : kInaccessible;

  String get levelLabel => level == 0
      ? 'Wheelchair friendly'
      : level == 1
      ? 'Be careful'
      : 'Not wheelchair friendly';

  // the point in the middle of the line, where the name tag is drawn
  LatLng get middle => points[points.length ~/ 2];
}

// a place (building, office, gate...)
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.type,
    required this.rating,
    required this.reviewCount,
    required this.ramp,
    required this.elevator,
    required this.restroom,
    required this.description,
    required this.lat,
    required this.lng,
    required this.reviews,
    this.known = true,
    this.code,
    this.floors = 1,
    this.hours,
    this.openMin,
    this.closeMin,
    this.weekdaysOnly = false,
    this.extras = const {},
    this.notApplicable = const {},
    this.facilities = const [],
    this.units = const [],
    this.hallways = const [],
    this.widthM = 0,
    this.depthM = 0,
    this.angle = 0,
  });

  final String id;
  final String name;
  final String? code; // short name shown on the map, like "CEAT"
  final PlaceType type;
  final double rating;
  final int reviewCount;
  final bool ramp;
  final bool elevator;
  final bool restroom;
  final String description;
  final double lat;
  final double lng;
  LatLng get position => LatLng(lat, lng);
  final List<Review> reviews;
  final bool known; // false for a tapped spot nobody has reported on yet

  final int floors;
  final String?
  hours; // text shown to the user, like "Mon-Fri, 8:00 AM - 5:00 PM"
  final int?
  openMin; // opening time in minutes after midnight (null = no fixed hours)
  final int? closeMin;
  final bool weekdaysOnly; // true = closed on saturday and sunday
  final Set<Pwd>
  extras; // accessibility features besides ramp / elevator / restroom
  final Set<Pwd>
  notApplicable; // features that make no sense here (elevator at a gate)
  final List<Facility> facilities;
  final List<Unit> units; // offices, departments and rooms inside
  final List<Hallway> hallways; // hallways, corridors and stairs inside

  // size of the building outline drawn on the map, in meters (0 = just a pin, no outline).
  // angle turns the outline in degrees, so it can follow the real building
  final double widthM;
  final double depthM;
  final double angle;

  bool isNa(Pwd p) => notApplicable.contains(p);

  // frontend-only helper: add a new review to this place (the backend will do this
  // from places/{id}/reviews later)
  void addReview(Review r) => reviews.add(r);

  bool has(Pwd p) => switch (p) {
    Pwd.ramp => ramp,
    Pwd.elevator => elevator,
    Pwd.restroom => restroom,
    _ => extras.contains(p),
  };

  // how many of ramp / elevator / restroom make sense for this place, and how many it has
  int get coreTotal => kCorePwd.where((p) => !isNa(p)).length;
  int get score => kCorePwd.where((p) => !isNa(p) && has(p)).length;

  // all features (the 3 core ones + the extras) that apply here, and how many it has
  int get featureTotal => Pwd.values.where((p) => !isNa(p)).length;
  int get featureCount => Pwd.values.where((p) => !isNa(p) && has(p)).length;

  // 0 = fully accessible, 1 = partly, 2 = not accessible, -1 = nobody reported it
  int get level {
    if (!known) return -1;
    if (coreTotal == 0) return extras.length >= 2 ? 0 : 1;
    if (score == coreTotal) return 0;
    if (score == 0) return 2;
    return 1;
  }

  Color get statusColor => switch (level) {
    0 => kAccessible,
    1 => kPartial,
    2 => kInaccessible,
    _ => Colors.grey,
  };

  String get statusLabel => switch (level) {
    0 => 'Fully accessible',
    1 => 'Partially accessible',
    2 => 'Not accessible',
    _ => 'No accessibility info yet',
  };

  // null when the place has no fixed opening hours. uses the phone's clock
  bool? get isOpenNow {
    if (openMin == null || closeMin == null) return null;
    final now = DateTime.now();
    if (weekdaysOnly && now.weekday >= DateTime.saturday) return false;
    final minutes = now.hour * 60 + now.minute;
    return minutes >= openMin! && minutes < closeMin!;
  }

  // --- the building outline ---
  double get _metersPerLng => 111320.0 * math.cos(lat * math.pi / 180);

  // the 4 corners of the outline (empty when the place is only a pin)
  List<LatLng> get footprint {
    if (widthM <= 0 || depthM <= 0) return const [];
    final a = angle * math.pi / 180;
    final c = math.cos(a);
    final s = math.sin(a);
    LatLng corner(double x, double y) {
      // x = east, y = north (meters from the center), turned by the angle
      final rx = x * c - y * s;
      final ry = x * s + y * c;
      return LatLng(lat + ry / 111320.0, lng + rx / _metersPerLng);
    }

    final w = widthM / 2;
    final d = depthM / 2;
    return [corner(-w, -d), corner(w, -d), corner(w, d), corner(-w, d)];
  }

  // is this map point inside the building outline? used so tapping a building opens it
  bool containsPoint(LatLng p) {
    if (widthM <= 0 || depthM <= 0) return false;
    final a = angle * math.pi / 180;
    final dx = (p.longitude - lng) * _metersPerLng;
    final dy = (p.latitude - lat) * 111320.0;
    final x = dx * math.cos(a) + dy * math.sin(a);
    final y = -dx * math.sin(a) + dy * math.cos(a);
    return x.abs() <= widthM / 2 && y.abs() <= depthM / 2;
  }

  // used by the search bar. gives back what matched (a room, a facility...), an empty
  // string when the name or code matched, or null when nothing matched. q must be lowercase
  String? matchedOn(String q) {
    if (name.toLowerCase().contains(q)) return '';
    if (code != null && code!.toLowerCase().contains(q)) return '';
    for (final u in units) {
      if (u.name.toLowerCase().contains(q)) return '${u.name} • ${u.floor}';
    }
    for (final f in facilities) {
      if (f.label.toLowerCase().contains(q)) return f.label;
    }
    for (final h in hallways) {
      if (h.name.toLowerCase().contains(q)) return h.name;
    }
    for (final e in Pwd.values) {
      if (has(e) && e.label.toLowerCase().contains(q)) return e.label;
    }
    if (type.label.toLowerCase().contains(q)) return type.label;
    return null;
  }

  // BACKEND: builds a place from one firestore document (doc.id and doc.data()).
  // example, inside a stream or future:
  //   final snap = await FirebaseFirestore.instance.collection('places').get();
  //   final places = snap.docs.map((d) => Place.fromMap(d.id, d.data())).toList();
  // the document fields are named exactly like the keys below. to write a place (the
  // "Add accessibility info" page), save a map with the same keys. 'extras' and
  // 'notApplicable' are lists of the Pwd names, like ['handrails', 'braille'].
  factory Place.fromMap(String id, Map<String, dynamic> m) {
    PlaceType typeFrom(Object? s) => PlaceType.values.firstWhere(
      (t) => t.name == s,
      orElse: () => PlaceType.other,
    );
    Set<Pwd> pwdSet(Object? list) => Pwd.values
        .where((p) => (list is List ? list : const []).contains(p.name))
        .toSet();

    return Place(
      id: id,
      name: '${m['name'] ?? 'Unnamed place'}',
      code: m['code'] as String?,
      type: typeFrom(m['type']),
      rating: (m['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (m['reviewCount'] as num?)?.toInt() ?? 0,
      ramp: m['ramp'] == true,
      elevator: m['elevator'] == true,
      restroom: m['restroom'] == true,
      description: '${m['description'] ?? ''}',
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      floors: (m['floors'] as num?)?.toInt() ?? 1,
      hours: m['hours'] as String?,
      openMin: (m['openMin'] as num?)?.toInt(),
      closeMin: (m['closeMin'] as num?)?.toInt(),
      weekdaysOnly: m['weekdaysOnly'] == true,
      extras: pwdSet(m['extras']),
      notApplicable: pwdSet(m['notApplicable']),
      widthM: (m['widthM'] as num?)?.toDouble() ?? 0,
      depthM: (m['depthM'] as num?)?.toDouble() ?? 0,
      angle: (m['angle'] as num?)?.toDouble() ?? 0,
      units: [
        for (final u in (m['units'] as List? ?? const []))
          Unit(
            '${u['name']}',
            floor: '${u['floor'] ?? 'Ground floor'}',
            accessible: u['accessible'] != false,
            note: u['note'] as String?,
          ),
      ],
      hallways: [
        for (final h in (m['hallways'] as List? ?? const []))
          Hallway(
            '${h['name']}',
            (h['level'] as num?)?.toInt() ?? 0,
            '${h['note'] ?? ''}',
          ),
      ],
      // reviews usually live in their own sub-collection (places/{id}/reviews), so
      // load them separately and pass them in here when you have them
      reviews: const [],
    );
  }
}

// one search result: the place, and what matched inside it (empty = its name matched)
class SearchHit {
  const SearchHit(this.place, this.via);
  final Place place;
  final String via;
}

// searches names, codes, offices, rooms, hallways, facilities and accessibility features.
// results where the name matches come first
List<SearchHit> searchPlaces(String raw, {int limit = 6}) {
  final q = raw.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final byName = <SearchHit>[];
  final byInside = <SearchHit>[];
  for (final p in kPlaces) {
    final via = p.matchedOn(q);
    if (via == null) continue;
    (via.isEmpty ? byName : byInside).add(SearchHit(p, via));
  }
  return [...byName, ...byInside].take(limit).toList();
}

// the place that is closest to a point and has an accessible restroom (null if none)
Place? nearestAccessibleRestroom(LatLng from) {
  final dist = Distance();
  Place? best;
  var bestMeters = double.infinity;
  for (final p in kPlaces) {
    if (!p.restroom) continue;
    final m = dist.as(LengthUnit.Meter, from, p.position);
    if (m < bestMeters) {
      bestMeters = m;
      best = p;
    }
  }
  return best;
}

// the campus places. SAMPLE DATA for now, this should come from firestore seePlace.fromMap above and the "to connect" comment in main.dart)

//to load these from firestore instead, remove the word const below so the list can be replaced later (List<Place> kPlaces = [...]), see the guide above DashboardPage in main.dart


const List<Place> kPlaces = [


  Place(
    id: 'bsu-gate',
    code: 'GATE',
    name: 'BSU Main Gate',
    type: PlaceType.gate,
    rating: 4.00,
    reviewCount: 9,
    ramp: true,
    elevator: false,
    restroom: false,
    notApplicable: {Pwd.elevator, Pwd.restroom},
    extras: {Pwd.tactile, Pwd.wideDoors},
    description:
        'Main entrance along Halsema Highway. There is a separate pedestrian '
        'lane with a curb cut, so wheelchair users do not have to share the '
        'road with vehicles.',
    lat: 16.452470,
    lng: 120.589800,
    reviews: [
      Review(
        'Rina P.',
        4,
        'The pedestrian lane is wide and flat. Crossing the highway needs help.',
        '1 week ago',
      ),
    ],
    facilities: [
      Facility(Icons.security, 'Guard house'),
      Facility(Icons.local_taxi, 'Jeepney / taxi drop-off'),
    ],
    hallways: [
      Hallway(
        'Pedestrian lane',
        0,
        'About 1.5 m wide, paved, with a curb cut at the entrance.',
      ),
    ],
    widthM: 22,
    depthM: 8,
    angle: 20,
  ),
  Place(
    id: 'bsu-pwd-parking',
    code: 'P1',
    name: 'Admin Parking (PWD slots)',
    type: PlaceType.parking,
    rating: 0,
    reviewCount: 0,
    ramp: true,
    elevator: false,
    restroom: false,
    notApplicable: {Pwd.elevator, Pwd.restroom},
    extras: {Pwd.parking, Pwd.tactile},
    description:
        'Parking in front of the Administration Building. The slots nearest '
        'the walkway are reserved for persons with disabilities and have a '
        'curb cut onto the path.',
    lat: 16.451900,
    lng: 120.590450,
    reviews: [],
    facilities: [Facility(Icons.local_parking, 'Reserved PWD slots')],
    widthM: 24,
    depthM: 12,
  ),




  Place(
    id: 'bsu-admin',
    code: 'ADMIN',
    name: 'BSU Administration Building',
    type: PlaceType.office,
    rating: 4.30,
    reviewCount: 27,
    ramp: true,
    elevator: false,
    restroom: true,
    floors: 2,
    hours: 'Mon-Fri, 8:00 AM - 5:00 PM',
    openMin: 8 * 60,
    closeMin: 17 * 60,
    weekdaysOnly: true,
    extras: {Pwd.wideDoors, Pwd.handrails, Pwd.groundFloor, Pwd.restArea},
    description:
        'Main office building. There is a ramp at the front entrance and a '
        'restroom on the ground floor, but the upper floors can only be '
        'reached by stairs.',
    lat: 16.4520325,
    lng: 120.5906603,
    reviews: [
      Review(
        'Maria S.',
        4.5,
        'The ramp at the front is smooth. Offices on the second floor were a problem.',
        '2 weeks ago',
      ),
      Review(
        'Jon D.',
        4,
        'Ground floor restroom is big enough to turn around.',
        '1 month ago',
      ),
    ],
    facilities: [
      Facility(Icons.wifi, 'Free Wi-Fi'),
      Facility(Icons.event_seat, 'Waiting area'),
      Facility(Icons.water_drop, 'Drinking water'),
    ],
    units: [
      Unit('Registrar\'s Office', note: 'Lowered counter at window 1'),
      Unit('Cashier'),
      Unit('Admissions Office'),
      Unit('Office of the President', floor: '2nd floor', accessible: false),
      Unit('Accounting Office', floor: '2nd floor', accessible: false),
      Unit('HRMO', floor: '2nd floor', accessible: false),
      Unit('Board Room', floor: '2nd floor', accessible: false),
    ],
    hallways: [
      Hallway(
        'Ground floor main hallway',
        0,
        'About 2 m wide with smooth tile floor, leads to the registrar and cashier.',
      ),
      Hallway(
        'Hallway to the restroom',
        0,
        'Flat, no door sill. The restroom door is wide enough for a wheelchair.',
      ),
      Hallway(
        'Stairs to the 2nd floor',
        2,
        'Stairs only, with a handrail on one side. No lift. Offices upstairs '
            'can be asked to meet downstairs.',
      ),
    ],
    widthM: 34,
    depthM: 18,
    angle: -8,
  ),
  Place(
    id: 'bsu-sas',
    code: 'SAS',
    name: 'Student Affairs & PWD Help Desk',
    type: PlaceType.office,
    rating: 0,
    reviewCount: 0,
    ramp: true,
    elevator: false,
    restroom: true,
    notApplicable: {Pwd.elevator},
    hours: 'Mon-Fri, 8:00 AM - 5:00 PM',
    openMin: 8 * 60,
    closeMin: 17 * 60,
    weekdaysOnly: true,
    extras: {Pwd.wideDoors, Pwd.groundFloor, Pwd.helpDesk, Pwd.restArea},
    description:
        'Single-storey office where students can ask for help with '
        'accessibility needs, escorts and class room changes. (Placeholder '
        'entry, please confirm the office with the university.)',
    lat: 16.4563744,
    lng: 120.5893143,
    reviews: [],
    facilities: [
      Facility(Icons.support_agent, 'Student assistance'),
      Facility(Icons.event_seat, 'Waiting area'),
    ],
    units: [
      Unit('PWD Help Desk'),
      Unit('Guidance & Counseling'),
      Unit('Scholarships Office'),
    ],
    hallways: [
      Hallway('Front hallway', 0, 'Flat and wide, no steps from the entrance.'),
    ],
    widthM: 18,
    depthM: 12,
  ),




  Place(
    id: 'bsu-cis',
    code: 'CIS',
    name: 'College of Information Sciences',
    type: PlaceType.college,
    rating: 4.50,
    reviewCount: 11,
    ramp: true,
    elevator: true,
    restroom: true,
    floors: 3,
    hours: 'Mon-Sat, 7:00 AM - 8:00 PM',
    openMin: 7 * 60,
    closeMin: 20 * 60,
    extras: {
      Pwd.wideDoors,
      Pwd.handrails,
      Pwd.tactile,
      Pwd.braille,
      Pwd.restArea,
    },
    description:
        'A newer building (opened 2022). Entrance ramp, an elevator to every '
        'floor and wide classroom doors. (Features are placeholders, please '
        'confirm on site.)',
    lat: 16.450268,
    lng: 120.591508,
    reviews: [
      Review(
        'Dan C.',
        4.5,
        'Elevator is easy to find and the hallways are wide.',
        '4 days ago',
      ),
    ],
    facilities: [
      Facility(Icons.computer, 'Computer laboratories'),
      Facility(Icons.wifi, 'Free Wi-Fi'),
      Facility(Icons.ac_unit, 'Air-conditioned rooms'),
      Facility(Icons.print, 'Printing'),
    ],
    units: [
      Unit('Dean\'s Office'),
      Unit('Computer Laboratory 1', floor: '1st floor'),
      Unit('Computer Laboratory 2', floor: '2nd floor'),
      Unit('Computer Laboratory 3', floor: '2nd floor'),
      Unit('Networking Laboratory', floor: '3rd floor'),
      Unit('Faculty Room', floor: '3rd floor'),
      Unit('Lecture Rooms 101-106', floor: '1st floor'),
    ],
    hallways: [
      Hallway('Main lobby and hallway', 0, 'Wide, flat, tile floor.'),
      Hallway(
        'Elevator lobby',
        0,
        'Elevator with floor buttons at wheelchair height.',
      ),
      Hallway('Stairs (east side)', 1, 'Stairs with handrails on both sides.'),
    ],
    widthM: 30,
    depthM: 18,
  ),
  Place(
    id: 'bsu-ceat',
    code: 'CEAT',
    name: 'CEAT Building',
    type: PlaceType.college,
    rating: 3.72,
    reviewCount: 21,
    ramp: true,
    elevator: false,
    restroom: false,
    floors: 3,
    hours: 'Mon-Sat, 7:00 AM - 7:00 PM',
    openMin: 7 * 60,
    closeMin: 19 * 60,
    extras: {Pwd.handrails, Pwd.groundFloor},
    description:
        'Ground floor rooms have a ramp. Upper floors only have stairs and '
        'there is no accessible restroom yet.',
    lat: 16.458787,
    lng: 120.589770,
    reviews: [
      Review(
        'Paolo M.',
        3.5,
        'Ground floor rooms are okay. Second floor is a problem.',
        '1 week ago',
      ),
      Review(
        'Lea T.',
        4,
        'Ramp is good. The path from the gate is mostly flat.',
        '2 months ago',
      ),
    ],
    facilities: [
      Facility(Icons.science, 'Engineering laboratories'),
      Facility(Icons.computer, 'Drafting & computer room'),
      Facility(Icons.wifi, 'Wi-Fi in the lobby'),
    ],
    units: [
      Unit('Dean\'s Office'),
      Unit('Civil Engineering Department'),
      Unit(
        'Agricultural & Biosystems Engineering Dept.',
        floor: '2nd floor',
        accessible: false,
      ),
      Unit('Drafting Room', floor: '2nd floor', accessible: false),
      Unit('Materials Testing Lab', floor: '3rd floor', accessible: false),
    ],
    hallways: [
      Hallway('Ground floor hallway', 0, 'Flat, about 1.8 m wide.'),
      Hallway(
        'Stairs to the 2nd and 3rd floor',
        2,
        'Stairs only, no lift. Classes for students who cannot climb can be '
            'moved to the ground floor, ask the Dean\'s Office.',
      ),
    ],
    widthM: 40,
    depthM: 16,
    angle: 6,
  ),
  Place(
    id: 'bsu-ca',
    code: 'CA',
    name: 'College of Agriculture',
    type: PlaceType.college,
    rating: 3.90,
    reviewCount: 16,
    ramp: true,
    elevator: false,
    restroom: true,
    floors: 2,
    hours: 'Mon-Sat, 7:00 AM - 7:00 PM',
    openMin: 7 * 60,
    closeMin: 19 * 60,
    extras: {Pwd.groundFloor, Pwd.wideDoors},
    description:
        'Ground floor has the Dean\'s Office and the main lecture rooms. '
        'Laboratories upstairs are reached by stairs only.',
    lat: 16.4539829,
    lng: 120.5903708,
    reviews: [
      Review(
        'Tess B.',
        4,
        'Restroom downstairs is accessible. Labs upstairs are not.',
        '3 weeks ago',
      ),
    ],
    facilities: [
      Facility(Icons.science, 'Soil & crop laboratories'),
      Facility(Icons.wifi, 'Wi-Fi in the lobby'),
    ],
    units: [
      Unit('Dean\'s Office'),
      Unit('Lecture Rooms'),
      Unit('Soil Science Laboratory', floor: '2nd floor', accessible: false),
      Unit('Crop Science Department', floor: '2nd floor', accessible: false),
    ],
    hallways: [
      Hallway(
        'Ground floor hallway',
        0,
        'Flat and covered, with a ramp at the entrance.',
      ),
      Hallway('Stairs to the 2nd floor', 2, 'Stairs only.'),
    ],
    widthM: 32,
    depthM: 16,
    angle: -4,
  ),
  Place(
    id: 'bsu-cas',
    code: 'CAS',
    name: 'College of Arts and Sciences',
    type: PlaceType.college,
    rating: 4.20,
    reviewCount: 15,
    ramp: true,
    elevator: false,
    restroom: true,
    floors: 3,
    hours: 'Mon-Sat, 7:00 AM - 7:00 PM',
    openMin: 7 * 60,
    closeMin: 19 * 60,
    extras: {Pwd.wideDoors, Pwd.groundFloor},
    description: 'Main College of Arts and Sciences complex along the western academic quad.',
    lat: 16.4534608,
    lng: 120.5903910,
    reviews: [],
    facilities: [Facility(Icons.science, 'Science laboratories')],
    widthM: 36,
    depthM: 20,
  ),
  Place(
    id: 'bsu-cf',
    code: 'CF',
    name: 'College of Forestry',
    type: PlaceType.college,
    rating: 3.30,
    reviewCount: 7,
    ramp: true,
    elevator: false,
    restroom: false,
    floors: 2,
    extras: {Pwd.handrails},
    description:
        'Entrance has a short ramp. The restrooms are small and the second '
        'floor has stairs only.',
    lat: 16.456373,
    lng: 120.594043,
    reviews: [],
    facilities: [Facility(Icons.wifi, 'Wi-Fi in the lobby')],
    units: [
      Unit('Dean\'s Office'),
      Unit(
        'Forest Resources Department',
        floor: '2nd floor',
        accessible: false,
      ),
    ],
    hallways: [
      Hallway('Entrance walkway', 1, 'Short ramp, a bit steep after rain.'),
    ],
    widthM: 28,
    depthM: 14,
    angle: 10,
  ),
  Place(
    id: 'bsu-cte',
    code: 'CTE',
    name: 'College of Teacher Education',
    type: PlaceType.college,
    rating: 4.00,
    reviewCount: 13,
    ramp: true,
    elevator: false,
    restroom: true,
    floors: 2,
    extras: {Pwd.wideDoors, Pwd.groundFloor, Pwd.restArea},
    description:
        'Most classrooms are on the ground floor and have wide doors. The '
        'accessible restroom is near the dean\'s office.',
    lat: 16.454549,
    lng: 120.590052,
    reviews: [
      Review(
        'Joy A.',
        4,
        'Ground floor classrooms are easy to get to.',
        '2 weeks ago',
      ),
    ],
    facilities: [
      Facility(Icons.wifi, 'Wi-Fi in the lobby'),
      Facility(Icons.event_seat, 'Student lounge'),
    ],
    units: [
      Unit('Dean\'s Office'),
      Unit('Education Department'),
      Unit('Audio-Visual Room'),
      Unit('Practicum Office', floor: '2nd floor', accessible: false),
    ],
    hallways: [
      Hallway(
        'Ground floor hallway',
        0,
        'Wide and flat, covered walkway outside.',
      ),
      Hallway('Stairs to the 2nd floor', 2, 'Stairs only.'),
    ],
    widthM: 30,
    depthM: 16,
  ),
  Place(
    id: 'bsu-nursing',
    code: 'CON',
    name: 'College of Nursing',
    type: PlaceType.college,
    rating: 4.20,
    reviewCount: 8,
    ramp: true,
    elevator: true,
    restroom: false,
    floors: 2,
    extras: {Pwd.wideDoors, Pwd.handrails},
    description:
        'Has a ramp and a small elevator. The restrooms are not wheelchair-'
        'sized yet.',
    lat: 16.449298,
    lng: 120.590918,
    reviews: [],
    facilities: [
      Facility(Icons.medical_services, 'Skills laboratory'),
      Facility(Icons.wifi, 'Wi-Fi in the lobby'),
    ],
    units: [
      Unit('Dean\'s Office'),
      Unit('Skills Laboratory', floor: '2nd floor'),
      Unit('Simulation Room', floor: '2nd floor'),
    ],
    hallways: [
      Hallway('Lobby and elevator', 0, 'Flat, elevator fits one wheelchair.'),
    ],
    widthM: 26,
    depthM: 14,
    angle: -12,
  ),
  Place(
    id: 'bsu-chet',
    code: 'CHET',
    name: 'College of Home Economics & Technology',
    type: PlaceType.college,
    rating: 3.10,
    reviewCount: 6,
    ramp: true,
    elevator: false,
    restroom: false,
    floors: 2,
    extras: {Pwd.groundFloor},
    description:
        'Ramp at the main entrance. The food laboratory is on the ground '
        'floor, the clothing laboratory is upstairs.',
    lat: 16.4529270,
    lng: 120.5904493,
    reviews: [],
    facilities: [Facility(Icons.restaurant, 'Food laboratory')],
    units: [
      Unit('Dean\'s Office'),
      Unit('Food Laboratory'),
      Unit('Clothing Laboratory', floor: '2nd floor', accessible: false),
    ],
    hallways: [
      Hallway(
        'Entrance walkway',
        1,
        'Gravel on the side path, use the concrete one.',
      ),
    ],
    widthM: 28,
    depthM: 14,
    angle: 15,
  ),
  Place(
    id: 'bsu-cvm',
    code: 'CVM',
    name: 'College of Veterinary Medicine',
    type: PlaceType.college,
    rating: 2.50,
    reviewCount: 4,
    ramp: false,
    elevator: false,
    restroom: false,
    floors: 2,
    description:
        'Entrance has steps and no ramp yet. No accessible restroom reported.',
    lat: 16.449135,
    lng: 120.591516,
    reviews: [],
    facilities: [Facility(Icons.pets, 'Animal clinic')],
    units: [
      Unit('Dean\'s Office', accessible: false, note: 'Reached by 4 steps'),
      Unit('Veterinary Clinic', accessible: false),
    ],
    hallways: [Hallway('Front steps', 2, 'Four concrete steps, no ramp.')],
    widthM: 26,
    depthM: 14,
    angle: -6,
  ),
  Place(
    id: 'bsu-ihk',
    code: 'GYM',
    name: 'Institute of Human Kinetics & Gymnasium',
    type: PlaceType.sports,
    rating: 3.80,
    reviewCount: 10,
    ramp: true,
    elevator: false,
    restroom: true,
    notApplicable: {Pwd.elevator},
    hours: 'Mon-Sat, 6:00 AM - 8:00 PM',
    openMin: 6 * 60,
    closeMin: 20 * 60,
    extras: {Pwd.wideDoors, Pwd.restArea},
    description:
        'Indoor court with side ramps. Bleachers have a flat space for '
        'wheelchairs at the end of the first row.',
    lat: 16.458152,
    lng: 120.589043,
    reviews: [],
    facilities: [
      Facility(Icons.sports_basketball, 'Indoor court'),
      Facility(Icons.shower, 'Showers & lockers'),
    ],
    units: [
      Unit('Institute Director\'s Office'),
      Unit('Gym Floor'),
      Unit('Fitness Room', floor: '2nd floor', accessible: false),
    ],
    hallways: [
      Hallway('Side ramp entrance', 0, 'Gentle slope, non-slip surface.'),
    ],
    widthM: 40,
    depthM: 26,
    angle: 4,
  ),
  Place(
    id: 'bsu-open-gym',
    code: 'OGYM',
    name: 'BSU Open Gym',
    type: PlaceType.sports,
    rating: 4.10,
    reviewCount: 8,
    ramp: true,
    elevator: false,
    restroom: false,
    notApplicable: {Pwd.elevator},
    description: 'BSU Open Gym located beside the Athletic Oval track.',
    lat: 16.4582052,
    lng: 120.5898705,
    reviews: [],
    facilities: [Facility(Icons.sports_basketball, 'Open court')],
    widthM: 35,
    depthM: 20,
  ),




  Place(
    id: 'bsu-library',
    code: 'LIB',
    name: 'BSU Library',
    type: PlaceType.library,
    rating: 4.10,
    reviewCount: 33,
    ramp: true,
    elevator: true,
    restroom: false,
    floors: 2,
    hours: 'Mon-Fri, 8:00 AM - 6:00 PM',
    openMin: 8 * 60,
    closeMin: 18 * 60,
    weekdaysOnly: true,
    extras: {Pwd.wideDoors, Pwd.braille, Pwd.restArea, Pwd.helpDesk},
    description:
        'Ramp at the entrance and an elevator to the upper floors. The '
        'restrooms are not wheelchair-sized yet.',
    lat: 16.455111,
    lng: 120.590194,
    reviews: [
      Review(
        'Ana R.',
        4,
        'Elevator works well. Wish the restrooms were wider.',
        '3 weeks ago',
      ),
    ],
    facilities: [
      Facility(Icons.wifi, 'Free Wi-Fi'),
      Facility(Icons.computer, 'Computer section'),
      Facility(Icons.ac_unit, 'Air-conditioned reading rooms'),
      Facility(Icons.print, 'Photocopy'),
    ],
    units: [
      Unit('Circulation Desk', note: 'Lowered counter section'),
      Unit('General Reading Room'),
      Unit('Computer Section'),
      Unit('Periodicals Section', floor: '2nd floor'),
      Unit('Thesis & Archives', floor: '2nd floor'),
      Unit('Study Carrels', floor: '2nd floor'),
    ],
    hallways: [
      Hallway('Entrance ramp and lobby', 0, 'Smooth ramp with a handrail.'),
      Hallway(
        'Aisles between shelves',
        1,
        'About 90 cm wide in the old section, tight for a wheelchair turn.',
      ),
      Hallway(
        'Elevator lobby',
        0,
        'Elevator reaches the 2nd floor reading rooms.',
      ),
    ],
    widthM: 32,
    depthM: 20,
    angle: 8,
  ),
  Place(
    id: 'bsu-museum',
    code: 'MUSEUM',
    name: 'BSU University Museum',
    type: PlaceType.landmark,
    rating: 4.60,
    reviewCount: 14,
    ramp: true,
    elevator: true,
    restroom: true,
    hours: 'Mon-Fri, 9:00 AM - 4:00 PM',
    openMin: 9 * 60,
    closeMin: 16 * 60,
    weekdaysOnly: true,
    extras: {Pwd.wideDoors, Pwd.handrails, Pwd.restArea, Pwd.groundFloor},
    description:
        'Exhibits are on one level with wide doors, a ramp at the entrance '
        'and an accessible restroom inside.',
    lat: 16.456189,
    lng: 120.590723,
    reviews: [
      Review(
        'Grace L.',
        4.5,
        'Easy to move around, the staff helped with the door.',
        '3 days ago',
      ),
    ],
    facilities: [
      Facility(Icons.museum, 'Exhibit hall'),
      Facility(Icons.chair, 'Seating along the exhibits'),
    ],
    units: [
      Unit('Exhibit Hall'),
      Unit('Information Counter', note: 'Lowered counter'),
    ],
    hallways: [
      Hallway(
        'Exhibit aisle',
        0,
        'Wide, one level, about 1.5 m between displays.',
      ),
    ],
    widthM: 24,
    depthM: 16,
    angle: -10,
  ),
  Place(
    id: 'bsu-health',
    code: 'CLINIC',
    name: 'BSU Health Services',
    type: PlaceType.health,
    rating: 2.34,
    reviewCount: 12,
    ramp: false,
    elevator: false,
    restroom: false,
    notApplicable: {Pwd.elevator},
    hours: 'Mon-Fri, 8:00 AM - 5:00 PM',
    openMin: 8 * 60,
    closeMin: 17 * 60,
    weekdaysOnly: true,
    description:
        'The entrance has steps and no ramp. Narrow doorway and no '
        'accessible restroom reported yet.',
    lat: 16.4558952,
    lng: 120.5907681,
    reviews: [
      Review(
        'Carl V.',
        2,
        'Two steps at the entrance. I could not get in without help.',
        '5 days ago',
      ),
    ],
    facilities: [
      Facility(Icons.medical_services, 'Consultation'),
      Facility(Icons.medication, 'Basic medicines'),
    ],
    units: [
      Unit('Nurse\'s Station', accessible: false, note: 'Reached by 2 steps'),
      Unit('Dental Clinic', accessible: false),
      Unit('Consultation Room', accessible: false),
    ],
    hallways: [
      Hallway(
        'Entrance steps',
        2,
        'Two steps, no ramp. Ask the staff to come out.',
      ),
      Hallway('Inside hallway', 1, 'Narrow, about 80 cm.'),
    ],
    widthM: 20,
    depthM: 12,
    angle: 5,
  ),



  Place(
    id: 'bsu-mcdo',
    code: 'MCDO',
    name: "BSU McDonald's",
    type: PlaceType.food,
    rating: 4.82,
    reviewCount: 38,
    ramp: true,
    elevator: true,
    restroom: true,
    hours: 'Daily, 6:00 AM - 10:00 PM',
    openMin: 6 * 60,
    closeMin: 22 * 60,
    extras: {Pwd.wideDoors, Pwd.parking, Pwd.restArea, Pwd.groundFloor},
    description:
        'Wide entrance with a gentle ramp, spacious aisles between tables, '
        'and an accessible restroom on the ground floor.',
    lat: 16.450374,
    lng: 120.590559,
    reviews: [
      Review(
        'Ben K.',
        5,
        'Ramp is smooth and the doors open easily. Plenty of space for my chair.',
        '2 weeks ago',
      ),
    ],
    facilities: [
      Facility(Icons.wifi, 'Free Wi-Fi'),
      Facility(Icons.ac_unit, 'Air-conditioned'),
      Facility(Icons.restaurant, 'Dine-in & take-out'),
    ],
    hallways: [
      Hallway(
        'Dining area aisles',
        0,
        'Wide aisles, some tables have a free side for wheelchairs.',
      ),
    ],
    widthM: 22,
    depthM: 14,
    angle: 15,
  ),

  Place(
    id: 'bsu-oval',
    code: 'OVAL',
    name: 'BSU Athletic Oval',
    type: PlaceType.sports,
    rating: 4.30,
    reviewCount: 24,
    ramp: true,
    elevator: false,
    restroom: false,
    notApplicable: {Pwd.elevator, Pwd.restroom},
    extras: {Pwd.restArea, Pwd.handrails},
    description:
        'The main university running track and sports ground located at the '
        'northern athletic compound, with paved surrounding walkways and '
        'trackside access.',
    lat: 16.457102,
    lng: 120.589947,
    reviews: [],
    facilities: [
      Facility(Icons.sports, 'Running track'),
      Facility(Icons.event_seat, 'Bleachers & track seating'),
      Facility(Icons.festival, 'Sports & event grounds'),
    ],
    hallways: [
      Hallway(
        'Track perimeter path',
        0,
        'Flat, paved track-side loop suitable for wheelchair mobility.',
      ),
    ],
    widthM: 90,
    depthM: 60,
  ),

  Place(
    id: 'bsu-field',
    code: 'FIELD',
    name: 'Centennial Park',
    type: PlaceType.landmark,
    rating: 4.20,
    reviewCount: 12,
    ramp: true,
    elevator: false,
    restroom: false,
    notApplicable: {Pwd.elevator, Pwd.restroom},
    extras: {Pwd.restArea, Pwd.handrails},
    description:
        'Centennial Park open grounds fronting the Admin and CAS quad.',
    lat: 16.451093,
    lng: 120.590428,
    reviews: [],
    facilities: [
      Facility(Icons.event_seat, 'Covered benches'),
      Facility(Icons.festival, 'Park grounds'),
    ],
    hallways: [
      Hallway('Walkway around the park', 0, 'Paved and flat all around.'),
    ],
    widthM: 62,
    depthM: 40,
  ),
  Place(
    id: 'bsu-dorm-men',
    code: 'MDORM',
    name: "Men's Dormitory",
    type: PlaceType.dorm,
    rating: 2.60,
    reviewCount: 6,
    ramp: false,
    elevator: false,
    restroom: false,
    floors: 2,
    description:
        'Entrance has steps and the rooms are on the second floor. Not '
        'accessible for wheelchair users yet.',
    lat: 16.4565624,
    lng: 120.5921189,
    reviews: [],
    facilities: [
      Facility(Icons.wifi, 'Wi-Fi in the common area'),
      Facility(Icons.local_laundry_service, 'Laundry area'),
    ],
    hallways: [Hallway('Stairs to the rooms', 2, 'Stairs only.')],
    widthM: 30,
    depthM: 12,
    angle: 10,
  ),
  Place(
    id: 'bsu-dorm-ladies',
    code: 'LDORM',
    name: "Ladies' Dormitory",
    type: PlaceType.dorm,
    rating: 3.40,
    reviewCount: 8,
    ramp: true,
    elevator: false,
    restroom: false,
    floors: 2,
    extras: {Pwd.groundFloor, Pwd.handrails},
    description:
        'Ground floor rooms can be reached by a ramp. The second floor has '
        'stairs only.',
    lat: 16.4582356,
    lng: 120.5904962,
    reviews: [],
    facilities: [
      Facility(Icons.wifi, 'Wi-Fi in the common area'),
      Facility(Icons.local_laundry_service, 'Laundry area'),
    ],
    units: [
      Unit('Ground floor rooms'),
      Unit('Second floor rooms', floor: '2nd floor', accessible: false),
    ],
    hallways: [
      Hallway('Ground floor hallway', 0, 'Flat, about 1.5 m wide.'),
      Hallway('Stairs to the 2nd floor', 2, 'Stairs only.'),
    ],
    widthM: 30,
    depthM: 12,
    angle: -5,
  ),
  // --- new demo places for the presentation (sample data, coordinates to confirm) ---

  Place(
    id: 'bgh',
    code: 'BGH',
    name: 'Benguet General Hospital',
    type: PlaceType.health,
    rating: 3.8,
    reviewCount: 6,
    ramp: true,
    elevator: true,
    restroom: true,
    floors: 3,
    hours: 'Mon-Sun, 7:00 AM - 8:00 PM',
    openMin: 7 * 60,
    closeMin: 20 * 60,
    extras: {Pwd.wideDoors, Pwd.handrails, Pwd.restArea},
    description:
        'General hospital serving Benguet. Placeholder accessibility info, please confirm on site.',
    lat: 16.478,
    lng: 120.552,
    reviews: [
      Review('Alona B.', 4, 'The ramp at the emergency entrance is smooth.', '2 weeks ago'),
    ],
    facilities: [
      Facility(Icons.medical_services, 'Emergency'),
      Facility(Icons.local_hospital, 'Inpatient care'),
    ],
    hallways: [
      Hallway('Main entrance', 0, 'Wide lobby, ramp at the front.'),
      Hallway('Stairs to the upper floors', 2, 'Elevator available to all floors.'),
    ],
    widthM: 44,
    depthM: 26,
    angle: 8,
  ),
  Place(
    id: 'tiongsan',
    code: 'TIONG',
    name: 'Tiongsan La Trinidad',
    type: PlaceType.landmark,
    rating: 4.1,
    reviewCount: 3,
    ramp: true,
    elevator: false,
    restroom: true,
    hours: 'Mon-Sun, 8:00 AM - 5:00 PM',
    openMin: 8 * 60,
    closeMin: 17 * 60,
    extras: {Pwd.restArea, Pwd.handrails},
    description:
        'Local landmark / community area in La Trinidad. Placeholder accessibility info, please confirm on site.',
    lat: 16.46,
    lng: 120.585,
    reviews: [],
    facilities: [Facility(Icons.place, 'Community area')],
    widthM: 30,
    depthM: 20,
    angle: -6,
  ),
  Place(
    id: 'rest-lt',
    code: 'REST',
    name: 'La Trinidad Restaurant',
    type: PlaceType.food,
    rating: 4.6,
    reviewCount: 17,
    ramp: true,
    elevator: false,
    restroom: true,
    hours: 'Daily, 10:00 AM - 8:00 PM',
    openMin: 10 * 60,
    closeMin: 20 * 60,
    extras: {Pwd.wideDoors, Pwd.restArea, Pwd.parking},
    description:
        'Restaurant near the campus. Placeholder accessibility info, please confirm on site.',
    lat: 16.455,
    lng: 120.575,
    reviews: [
      Review('Marco T.', 5, 'Wide doors and a ramp at the front. Restroom is big enough.', '1 week ago'),
    ],
    facilities: [Facility(Icons.restaurant, 'Dine-in & take-out')],
    hallways: [Hallway('Entrance', 0, 'Ramp at the front, wide lobby.')],
    widthM: 24,
    depthM: 16,
    angle: 12,
  ),
  Place(
    id: 'bsu-guest-house',
    code: 'GUEST',
    name: 'BSU Guest House',
    type: PlaceType.hotel,
    rating: 4.1,
    reviewCount: 11,
    ramp: true,
    elevator: false,
    restroom: true,
    hours: 'Daily, 24 hours',
    openMin: 0,
    closeMin: 24 * 60,
    extras: {Pwd.restArea, Pwd.groundFloor},
    description:
        'Guest house for visitors of the university. Placeholder accessibility info, please confirm on site.',
    lat: 16.456,
    lng: 120.596,
    reviews: [],
    facilities: [Facility(Icons.event_seat, 'Seating for guests')],
    widthM: 26,
    depthM: 14,
    angle: -8,
  ),
  Place(
    id: 'lath-view-hotel',
    code: 'LATH',
    name: 'La Trinidad View Hotel',
    type: PlaceType.hotel,
    rating: 4.4,
    reviewCount: 8,
    ramp: true,
    elevator: true,
    restroom: true,
    floors: 4,
    hours: 'Daily, 24 hours',
    openMin: 0,
    closeMin: 24 * 60,
    extras: {Pwd.wideDoors, Pwd.handrails, Pwd.restArea},
    description:
        'Hotel near the campus. Placeholder accessibility info, please confirm on site.',
    lat: 16.462,
    lng: 120.568,
    reviews: [],
    facilities: [Facility(Icons.event_seat, 'Lobby seating')],
    hallways: [
      Hallway('Entrance', 0, 'Ramp and wide doors.'),
      Hallway('Stairs', 2, 'Elevator to all floors.'),
    ],
    widthM: 36,
    depthM: 20,
    angle: 6,
  ),
];

// Walkways between places
final List<CampusPath> kPaths = [
  CampusPath(
    'path-academic-spine',
    'Main Academic Spine',
    0,
    'Flat paved corridor connecting the Admin building, CAS, CA, CTE, and Library.',
    [
      LatLng(16.4520325, 120.5906603), // Admin
      LatLng(16.4529270, 120.5904493), // CHET
      LatLng(16.4534608, 120.5903910), // CAS
      LatLng(16.4539829, 120.5903708), // CA
      LatLng(16.4545490, 120.5900520), // CTE
      LatLng(16.4551110, 120.5901940), // Library
    ],
  ),
  CampusPath(
    'path-sports-complex',
    'Sports Complex Walkway',
    0,
    'Paved path connecting the IHK Building, Open Gym, and Engineering.',
    [
      LatLng(16.4581520, 120.5890430), // IHK
      LatLng(16.4582052, 120.5898705), // Open Gym
      LatLng(16.4587870, 120.5897700), // CEAT
      LatLng(16.4582356, 120.5904962), // Ladies Dorm
    ],
  ),
  CampusPath(
    'path-clinic-museum',
    'Library to Clinic & Museum',
    0,
    'Paved walkway connecting Main Library, Health Services Clinic, and Museum.',
    [
      LatLng(16.4551110, 120.5901940), // Library
      LatLng(16.4558952, 120.5907681), // Clinic
      LatLng(16.4561890, 120.5907230), // Museum
    ],
  ),
  CampusPath(
    'path-south-campus',
    'South Quad (Nursing, VetMed, CIS)',
    0,
    'Connecting the southern cluster along the lower road.',
    [
      LatLng(16.4491350, 120.5915160), // VetMed
      LatLng(16.4492980, 120.5909180), // Nursing
      LatLng(16.4503740, 120.5905590), // McDo
      LatLng(16.4502680, 120.5915080), // CIS
      LatLng(16.4510930, 120.5904280), // Centennial Park
    ],
  ),
];

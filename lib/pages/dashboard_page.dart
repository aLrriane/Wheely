import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../bsu_data.dart';
import 'account_page.dart';
import 'add_photo_page.dart';
import 'history_page.dart';
import 'login_page.dart';
import 'review_page.dart';
import 'saves_page.dart';
import 'search_results_page.dart';
import '../widgets/wheely_logo.dart';

// map opens here: BSU main campus in La Trinidad (coordinates from wikipedia)
final LatLng kDefaultCenter = LatLng(16.45194, 120.59073);

// the map and the address search stay inside this box (about 2 km around the campus)
final LatLngBounds kCampusBounds = LatLngBounds(
  LatLng(16.434, 120.572),
  LatLng(16.470, 120.610),
);

// openstreetmap services but much better if we actually use google maps, if you have api keys then we can use it instead
const String kUserAgent = 'WheelyAccess/1.0 (student project)';

// a spot the user tapped on the map. the street name is filled in after the lookup
class DroppedPin {
  DroppedPin(this.point);
  final LatLng point;
  String name = 'Dropped pin';
  String? address;
  bool loading = true;

  // lets a tapped spot use the same details sheet as our community places
  Place toPlace() => Place(
    id: 'spot-${point.latitude.toStringAsFixed(6)}-${point.longitude.toStringAsFixed(6)}',
    name: name,
    type: PlaceType.other,
    rating: 0,
    reviewCount: 0,
    ramp: false,
    elevator: false,
    restroom: false,
    known: false,
    description: address ?? 'No description yet.',
    lat: point.latitude,
    lng: point.longitude,
    reviews: const [],
  );
}

enum LegStatus {
  ok,
  none,
  error,
} // none = no path exists, error = no internet or server problem

// one route answer from the routing server
class LegResult {
  const LegResult(
    this.status, {
    this.km = 0,
    this.seconds = 0,
    this.points = const [],
  });
  final LegStatus status;
  final double km;
  final int seconds;
  final List<LatLng> points;
  bool get ok => status == LegStatus.ok;
}

// one end of a route (start or destination)
class RouteEnd {
  const RouteEnd(this.point, this.name, this.place);
  final LatLng point;
  final String name;
  final Place? place; // set when it is one of our community places
}

class RouteResult {
  const RouteResult({
    required this.from,
    required this.to,
    required this.straightMeters,
    required this.wheel,
    required this.foot,
  });
  final RouteEnd from;
  final RouteEnd to;
  final double straightMeters;
  final LegResult wheel; // wheelchair-friendly route
  final LegResult foot; // normal walking route, only used to compare
}

class Verdict {
  const Verdict(this.level, this.title, this.notes);
  final int level; // 0 = ok, 1 = be careful, 2 = not accessible
  final String title;
  final List<String> notes;

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

// decides if the path is accessible. it looks at 2 things:
// 1. did the router find a wheelchair path, and is it much longer than a normal walk
// 2. what the community says about the destination (ramp, elevator, restroom)
Verdict judgeRoute(RouteResult r) {
  var level = 0;
  final notes = <String>[];
  void worse(int l) {
    if (l > level) level = l;
  }

  if (r.wheel.status == LegStatus.error) {
    worse(1);
    notes.add(
      "Couldn't check the path right now (no internet, or the route server is busy). Only the straight line distance is shown.",
    );
  } else if (r.wheel.status == LegStatus.none) {
    worse(2);
    if (r.foot.ok) {
      notes.add(
        'There is a walking route, but no wheelchair-friendly path was found. It probably has stairs or very steep parts.',
      );
    } else {
      notes.add(
        'No path was found between these two points. One of them may be far from a road or path.',
      );
    }
  } else if (r.foot.ok && r.wheel.km > r.foot.km * 1.3 + 0.05) {
    worse(1);
    final extra = ((r.wheel.km - r.foot.km) * 1000).round();
    notes.add(
      'The wheelchair route is about $extra m longer than the normal walking route because it goes around stairs or steep parts.',
    );
  } else {
    notes.add(
      'Found a path that avoids stairs and very steep parts, based on OpenStreetMap data.',
    );
  }

  final place = r.to.place;
  if (place != null) {
    final missing = [
      if (!place.ramp && !place.isNa(Pwd.ramp)) 'a ramp',
      if (!place.elevator && !place.isNa(Pwd.elevator)) 'an elevator',
      if (!place.restroom && !place.isNa(Pwd.restroom))
        'an accessible restroom',
    ];
    if (place.score == 0) {
      worse(2);
      notes.add(
        '${place.name} has no ramp, elevator or accessible restroom reported by the community.',
      );
    } else if (missing.isNotEmpty) {
      worse(1);
      notes.add(
        '${place.name} is missing ${missing.join(', ')} (reported by the community).',
      );
    } else {
      notes.add(
        '${place.name} has all the accessibility features that apply to it (reported by the community).',
      );
    }
    // stairs or other blocked parts inside the building (from the hallway list)
    final blocked = place.hallways.where((h) => h.level == 2).toList();
    if (blocked.isNotEmpty) {
      notes.add(
        'Inside ${place.name}: ${blocked.map((h) => h.name).join(', ')} may not be reachable by wheelchair.',
      );
    }
  } else {
    notes.add(
      "This spot isn't in our community list yet, so we can't tell if the entrance is accessible.",
    );
  }

  final title = level == 0
      ? 'Path looks accessible'
      : level == 1
      ? 'Be careful'
      : 'Not accessible';
  return Verdict(level, title, notes);
}

// the routing server sends the path as a compressed string, this turns it back into points
// (valhalla uses 6 decimal places for this)
List<LatLng> decodePolyline6(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1e6, lng / 1e6));
  }
  return points;
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String formatDuration(int seconds) {
  if (seconds < 60) return 'under 1 min';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

// HOW TO CONNECT THE BACKEND AND THE OTHER PAGES (quick guide, everything is front end for now)
//
// 1. places (buildings, rooms, hallways): they are the list kPlaces in bsu_data.dart.
//    to load them from firestore, change that list from "const List<Place> kPlaces = [...]"
//    to "List<Place> kPlaces = [...]" (no const), then in initState below do:
//      final snap = await FirebaseFirestore.instance.collection('places').get();
//      kPlaces = snap.docs.map((d) => Place.fromMap(d.id, d.data())).toList();
//      if (mounted) setState(() {});
//    the walkway lines (kPaths) can be loaded the same way from a 'paths' collection.
// 2. login / account: when the login page is done, push the DashboardPage after login and
//    use FirebaseAuth.instance.currentUser everywhere a "to connect" note asks for the user id.
// 3. saves, history, reports, reviews: every one of them has a small empty function marked
//    "BACKEND HOOKS" (search for that) so you only fill in those, the screens already call them.
// 4. other pages (Account, Saves, History, Login, Write a review, Add accessibility info):
//    each button that opens one has a "to connect: replace null with ..." note next to it.
//    make the page, import its file at the top, and put it in place of null.

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final MapController _mapController = MapController();
  Timer? _searchDebounce; // restarts on every keystroke, fires after the pause

  // ids of the places the user bookmarked (the purple bookmark in the details sheet).
  // to connect: fill this from the server when the app starts, see _persistSave below
  final Set<String> _saved = {};
  // places the user opened recently (the History page shows these). frontend only for
  // now, it will go to users/{uid}/history when the backend is ready (see _logHistory)
  final List<Place> _history = [];
  // filter chips that are turned on (category row and accessibility row)
  final Set<PlaceType> _typeFilters = {};
  final Set<Pwd> _pwdFilters = {};
  bool _savedOnly = false; // the "Saved" chip, shows only bookmarked places

  // map layers the user can turn on and off (the layers button)
  bool _showBuildings = true;
  bool _showLabels = true;
  bool _showWalkways = true;
  int _zoomBand =
      1; // see _bandFor, starts at 1 because the map opens at zoom 17
  Place? _selected;
  String _query = '';
  LatLng? _myLatLng; // user's gps position (null until we get it), drawn as the blue dot

  // the pin that appears when you tap the map, and the ones the user saved
  DroppedPin? _pin;
  final List<DroppedPin> _savedSpots = [];

  // directions (from / to)
  bool _directionsOpen = false;
  bool _routing = false;
  int _routeToken =
      0; // goes up on every new request so old answers get ignored
  RouteResult? _route;
  final _fromController = TextEditingController(text: 'My location');
  final _toController = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();
  // filled in when a suggestion is picked, null means use whatever was typed
  LatLng? _fromPoint;
  Place? _fromPlace;
  LatLng? _toPoint;
  Place? _toPlace;
  final Distance _distance =
      Distance(); // from latlong2, measures meters between 2 points
  DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
    _fromFocus.addListener(() => setState(() {}));
    _toFocus.addListener(() => setState(() {}));
    _askForLocation(); // asks for location permission as soon as the page opens
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _fromController.dispose();
    _toController.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // debounced search: the list only rebuilds (and shows suggestions) after the
  // user pauses typing, so fast typing doesn't spam the UI
  void _onSearchChanged(String v) {
    setState(() => _query = v);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  List<Place> get _visiblePlaces => kPlaces.where((p) {
    // category chips: if any are on, only those categories show
    if (_typeFilters.isNotEmpty && !_typeFilters.contains(p.type)) return false;
    // accessibility chips: the place must have every feature that is turned on
    for (final f in _pwdFilters) {
      if (!p.has(f)) return false;
    }
    if (_savedOnly && !_saved.contains(p.id)) return false;
    return true;
  }).toList();

  // how much text the map shows at the current zoom:
  // 0 = zoomed out (only pins), 1 = short codes like "CEAT", 2 = full building names
  int _bandFor(double zoom) => zoom >= 17.5 ? 2 : (zoom >= 16.5 ? 1 : 0);

  List<Marker> get _markers => [
    // building names / codes, drawn just under each pin
    if (_showLabels && _zoomBand > 0)
      for (final p in _visiblePlaces)
        if (_zoomBand == 2 || p.code != null)
          Marker(
            point: p.position,
            width: _zoomBand == 2 ? 150 : 80,
            height: 24,
            alignment: Alignment
                .bottomCenter, // so the top of the label sits on the point
            child: IgnorePointer(
              child: _MapLabel(_zoomBand == 2 ? p.name : p.code!),
            ),
          ),
    // little round buttons on the walkways, tap one to read about that path
    if (_showWalkways && _zoomBand > 0)
      for (final path in kPaths)
        Marker(
          point: path.middle,
          width: 30,
          height: 30,
          child: Semantics(
            button: true,
            label: '${path.name}, ${path.levelLabel}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showPath(path),
              child: Container(
                decoration: BoxDecoration(
                  color: path.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  path.level == 2 ? Icons.stairs : Icons.alt_route,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
    for (final p in _visiblePlaces)
      Marker(
        point: p.position,
        width: 56,
        height: 56,
        alignment: Alignment
            .topCenter, // so the bottom tip of the pin sits on the coordinates

        child: Semantics(
          button: true,
          label: '${p.name}, ${p.statusLabel}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectPlace(p),
            child: AnimatedScale(
              scale: _selected?.id == p.id ? 1.3 : 1.0,
              alignment: Alignment.bottomCenter,
              duration: const Duration(milliseconds: 150),
              child: _Pin(p),
            ),
          ),
        ),
      ),
    // blue dot for where the user is
    if (_myLatLng != null)
      Marker(
        point: _myLatLng!,
        width: 56,
        height: 56,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.withValues(alpha: 0.18),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.shade600,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      ),
    // pins the user saved (purple)
    for (final spot in _savedSpots)
      Marker(
        point: spot.point,
        width: 48,
        height: 48,
        alignment: Alignment.topCenter,
        child: Semantics(
          button: true,
          label: 'Saved spot, ${spot.name}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSpot(spot),
            child: const _SpotPin(Colors.deepPurple, icon: Icons.bookmark),
          ),
        ),
      ),
    // the red pin from the last tap (not shown if it is already saved)
    if (_pin != null && !_isSpotSaved(_pin!))
      Marker(
        point: _pin!.point,
        width: 48,
        height: 48,
        alignment: Alignment.topCenter,
        child: const _SpotPin(Color(0xFFD93025)),
      ),
    // start and end of the route
    if (_route != null) ...[
      Marker(
        point: _route!.from.point,
        width: 28,
        height: 28,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.trip_origin, color: Colors.blue.shade700, size: 28),
        ),
      ),
      Marker(
        point: _route!.to.point,
        width: 48,
        height: 48,
        alignment: Alignment.topCenter,
        child: const _SpotPin(Color(0xFFD93025)),
      ),
    ],
  ];

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // opens another page. while page is still null (not made yet) it only shows a message.
  // replace: true is for log out, so the back button cant go back to the dashboard
  void _openPage(String name, Widget? page, {bool replace = false}) {
    if (page == null) {
      _toast('$name page is not connected yet');
      return;
    }
    final route = MaterialPageRoute<void>(builder: (_) => page);
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  }

  // gives back where the user is, or null if gps is off or they denied the permission
  Future<LatLng?> _askForLocation() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      if (mounted) _toast('Please turn on your location (GPS)');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted)
        _toast('Location permission is needed to show where you are');
      return null;
    }
    final pos = await Geolocator.getCurrentPosition();
    final me = LatLng(pos.latitude, pos.longitude);
    if (!mounted) return null;
    setState(() => _myLatLng = me);
    return me;
  }

  Future<void> _goToMyLocation() async {
    final me = await _askForLocation();
    if (me == null) return;
    _mapController.move(me, 16);
  }

  // moves the map to a point. shiftFraction pushes the view south by that part of the
  // screen height, so the point shows up above the bottom sheet instead of behind it
  void _focusOn(LatLng p, {double? zoom, double shiftFraction = 0.18}) {
    final z = zoom ?? math.max(_mapController.camera.zoom, 15.5);
    final h = MediaQuery.of(context).size.height;
    // how many meters one screen pixel covers at this zoom, then converted to degrees
    final metersPerPixel =
        156543.03392 * math.cos(p.latitude * math.pi / 180) / math.pow(2, z);
    final shiftDegrees = h * shiftFraction * metersPerPixel / 111320;
    _mapController.move(LatLng(p.latitude - shiftDegrees, p.longitude), z);
  }

  void _focusPlace(Place p) => _focusOn(p.position, zoom: 18);

  void _selectPlace(Place p) {
    _searchFocus.unfocus();
    _routeToken++; // a route that is still loading is no longer wanted
    // a place hidden by the filters has no pin on the map, so turn the filters off
    final hidden = !_visiblePlaces.contains(p);
    setState(() {
      if (hidden) {
        _typeFilters.clear();
        _pwdFilters.clear();
        _savedOnly = false;
      }
      _selected = p;
      _pin = null;
      // picking a place closes the directions panel
      _directionsOpen = false;
      _routing = false;
      _route = null;
    });
    _focusPlace(p);
    _logHistory(p);
  }

  void _clearSelection() {
    setState(() => _selected = null);
  }

  // close the sheet if the open place got filtered out
  void _afterFilterChange() {
    if (_selected != null && !_visiblePlaces.contains(_selected)) {
      _selected = null;
    }
  }

  void _toggleType(PlaceType t) {
    setState(() {
      if (!_typeFilters.add(t)) _typeFilters.remove(t);
      _afterFilterChange();
    });
  }

  void _togglePwd(Pwd f) {
    setState(() {
      if (!_pwdFilters.add(f)) _pwdFilters.remove(f);
      _afterFilterChange();
    });
  }

  // finds the closest place with an accessible restroom. measures from the user's gps
  // position, or from the middle of the map when the location is not available
  void _findNearestRestroom() {
    final from = _myLatLng ?? _mapController.camera.center;
    final p = nearestAccessibleRestroom(from);
    if (p == null) {
      _toast('No accessible restroom in the list yet');
      return;
    }
    final meters = _distance.as(LengthUnit.Meter, from, p.position);
    _toast(
      'Nearest accessible restroom: ${p.name} (${formatDistance(meters)}, straight line)',
    );
    _selectPlace(p);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final savedCount = _saved.length + _savedSpots.length;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          // the map itself, tiles come from openstreetmap so no api key is needed
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: kDefaultCenter,
                initialZoom: 17,
                minZoom: 14,
                maxZoom: 19,
                // keeps the map around the campus so it can't be dragged far away
                cameraConstraint: CameraConstraint.contain(
                  bounds: kCampusBounds,
                ),
                // when the zoom crosses a step, the labels change (pins only -> codes -> names)
                onPositionChanged: (camera, hasGesture) {
                  final band = _bandFor(camera.zoom);
                  if (band != _zoomBand) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _zoomBand = band);
                    });
                  }
                },
                onTap: (tapPosition, point) {
                  _searchFocus.unfocus();
                  _fromFocus.unfocus();
                  _toFocus.unfocus();
                  // tapping a building opens it, tapping empty map drops a pin
                  // (not while the directions panel is open)
                  if (!_directionsOpen) _dropPin(point);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.dashboard',
                  maxNativeZoom: 19,
                ),
                // building outlines, colored by how accessible each building is.
                // the shape comes from widthM / depthM / angle in bsu_data.dart
                if (_showBuildings)
                  PolygonLayer(
                    polygons: [
                      for (final p in _visiblePlaces)
                        if (p.footprint.isNotEmpty)
                          Polygon(
                            points: p.footprint,
                            color: p.statusColor.withValues(
                              alpha: _selected?.id == p.id ? 0.55 : 0.28,
                            ),
                            borderColor: p.statusColor,
                            borderStrokeWidth: _selected?.id == p.id ? 3 : 1.5,
                          ),
                    ],
                  ),
                // campus walkways: green = smooth, orange = slope or narrow, red = steps
                if (_showWalkways)
                  PolylineLayer(
                    polylines: [
                      for (final path in kPaths)
                        Polyline(
                          points: path.points,
                          strokeWidth: 5,
                          color: path.color.withValues(alpha: 0.9),
                          borderStrokeWidth: 1.5,
                          borderColor: Colors.white,
                        ),
                    ],
                  ),
                // the route line: blue = wheelchair route, red = normal walking route
                // (only drawn in red when no wheelchair route exists)
                PolylineLayer(
                  polylines: [
                    if (_route != null && !_route!.wheel.ok && _route!.foot.ok)
                      Polyline(
                        points: _route!.foot.points,
                        strokeWidth: 5,
                        color: kInaccessible,
                      ),
                    if (_route != null && _route!.wheel.ok)
                      Polyline(
                        points: _route!.wheel.points,
                        strokeWidth: 6,
                        color: Colors.blue.shade600,
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                  ],
                ),
                MarkerLayer(markers: _markers),
                // openstreetmap asks that this credit stays visible
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),

          // top: search bar + filter button, with the suggestions under it while typing,
          // or the from / to panel when directions are open
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_directionsOpen) ...[
                      _buildDirectionsPanel(),
                      if (_fromFocus.hasFocus || _toFocus.hasFocus)
                        _buildDirectionSuggestions(),
                    ] else ...[
                      _buildSearchBar(),
                      if (_searchFocus.hasFocus && _query.trim().isNotEmpty)
                        _buildSuggestions(),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // legend and the round buttons, hidden while a sheet is open
          if (!_sheetOpen && !_directionsOpen) ...[
            Positioned(
              left: 16,
              bottom: 48 + bottomInset,
              child: _buildLegend(),
            ),
            Positioned(
              right: 16,
              bottom: 264 + bottomInset,
              child: FloatingActionButton(
                heroTag: 'layers',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                tooltip: 'Map layers',
                onPressed: _openLayers,
                child: const Icon(Icons.layers_outlined),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 192 + bottomInset,
              child: FloatingActionButton(
                heroTag: 'saved',
                backgroundColor: Colors.white,
                foregroundColor: Colors.deepPurple,
                tooltip: 'Saved places',
                onPressed: _openSaved,
                child: Badge(
                  isLabelVisible: savedCount > 0,
                  label: Text('$savedCount'),
                  child: const Icon(Icons.bookmark),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 120 + bottomInset,
              child: FloatingActionButton(
                heroTag: 'directions',
                backgroundColor: Colors.lightBlue.shade100,
                foregroundColor: Colors.black,
                tooltip: 'Directions',
                onPressed: () => _startDirections(),
                child: const Icon(Icons.directions),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 48 + bottomInset,
              child: FloatingActionButton(
                heroTag: 'my-location',
                backgroundColor: Colors.white,
                foregroundColor: Colors.lightBlue.shade700,
                tooltip: 'My location',
                onPressed: _goToMyLocation,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],

          // details sheet: for one of our place pins, or for any other spot the user
          // tapped (same layout, just with "no info yet" parts)
          if (_selected != null)
            _buildSheet(_selected!)
          else if (_pin != null)
            _buildSheet(_pin!.toPlace(), spot: _pin),

          // result of the directions search
          if (_directionsOpen && (_routing || _route != null))
            _buildRouteCard(),
        ],
      ),
    );
  }

  bool _isSpotSaved(DroppedPin pin) =>
      _savedSpots.any((s) => s.point == pin.point);

  // true when something slides up from the bottom, so the legend and buttons get out of the way
  bool get _sheetOpen =>
      _selected != null ||
      _pin != null ||
      (_directionsOpen && (_routing || _route != null));

  void _dropPin(LatLng point) {
    // tapping inside a building outline (or right next to a pin) opens that place
    // instead of dropping a plain pin
    for (final p in _visiblePlaces) {
      if (p.containsPoint(point) ||
          _distance.as(LengthUnit.Meter, point, p.position) < 15) {
        _selectPlace(p);
        return;
      }
    }
    final pin = DroppedPin(point);
    setState(() {
      _selected = null;
      _pin = pin;
    });
    _focusOn(point, shiftFraction: 0.12);
    _lookupAddress(pin);
  }

  // tapping one of the purple saved pins
  void _openSpot(DroppedPin spot) {
    _searchFocus.unfocus();
    _routeToken++;
    setState(() {
      _selected = null;
      _pin = spot;
      _directionsOpen = false;
      _routing = false;
      _route = null;
    });
    _focusOn(spot.point, shiftFraction: 0.12);
  }

  void _closePin() => setState(() => _pin = null);

  // the Saves page shows saved pins as places (see DroppedPin.toPlace). this turns one
  // back into its pin, or null when the place is one of our community places.
  // it works after the pin was removed too, so the Undo button on the Saves page can
  // save it again
  DroppedPin? _spotFor(Place p) {
    if (!p.id.startsWith('spot-')) return null;
    for (final s in _savedSpots) {
      if (s.toPlace().id == p.id) return s;
    }
    return DroppedPin(p.position)
      ..name = p.name
      ..address = p.description
      ..loading = false;
  }

  void _toggleSpotSaved(DroppedPin pin) {
    final index = _savedSpots.indexWhere((s) => s.point == pin.point);
    setState(() {
      if (index == -1) {
        _savedSpots.add(pin);
      } else {
        _savedSpots.removeAt(index);
      }
    });
    _persistSavedSpot(pin, index == -1);
  }

  // save / unsave one of our places (the bookmark button in the sheet and the saved list)
  void _toggleSaved(Place p) {
    setState(() {
      if (!_saved.add(p.id)) _saved.remove(p.id);
    });
    _persistSave(p, _saved.contains(p.id));
  }

  // the front end works without these, they are empty on purpose.
  // every place the app needs to tell the server something goes through one of these
  // 4 small functions, so the backend person only has to fill them in.

  // to connect (saves): runs every time a place is saved or unsaved. example with firestore:
  //   final uid = FirebaseAuth.instance.currentUser?.uid;
  //   if (uid == null) return; // not logged in
  //   final doc = FirebaseFirestore.instance
  //       .collection('users').doc(uid).collection('saves').doc(p.id);
  //   saved ? doc.set({'savedAt': FieldValue.serverTimestamp()}) : doc.delete();
  // and to load them again when the app starts, read that same collection in initState and
  // fill the _saved set with the document ids (then call setState).
  void _persistSave(Place p, bool saved) {}

  // to connect (saved pins): same idea for the purple pins. save the lat / lng / name
  // in users/{uid}/savedSpots, with the point as the document id
  void _persistSavedSpot(DroppedPin spot, bool saved) {}

  // to connect (history page): runs every time the user opens a place. add a document to
  // users/{uid}/history with {placeId: p.id, viewedAt: serverTimestamp}. the History page
  // can then show the last 20 of them ordered by viewedAt
  void _logHistory(Place p) {
    // frontend only for now: keep the opened places in memory. when the backend is
    // ready, send this to users/{uid}/history instead of keeping it local.
    setState(() {
      _history.removeWhere((h) => h.id == p.id);
      _history.insert(0, p);
      if (_history.length > 20) _history.removeLast();
    });
  }

  // to connect (reports): runs when the user sends the "Report a problem" form.
  // example: add a document to the 'reports' collection with
  //   {placeId: p.id, reasons: reasons, note: note, userId: uid, createdAt: serverTimestamp}
  // so an admin can check it and update the place (for example set elevator to false)
  void _submitReport(Place p, List<String> reasons, String note) {
    _toast('Thank you! Your report about ${p.name} was noted');
  }

  // nominatim = free openstreetmap search. it only allows 1 request per second,
  // so we wait a bit if the last one was too recent. returns null if anything fails
  Future<dynamic> _nominatim(String path, Map<String, String> query) async {
    final wait = _lastNominatim
        .add(const Duration(milliseconds: 1100))
        .difference(DateTime.now());
    if (wait > Duration.zero) await Future.delayed(wait);
    _lastNominatim = DateTime.now();
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', path, query);
      final res = await http
          .get(uri, headers: {'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body);
    } catch (_) {
      return null; // no internet, timeout, etc.
    }
  }

  // finds the street name of the tapped spot (coordinates -> address)
  Future<void> _lookupAddress(DroppedPin pin) async {
    final data = await _nominatim('/reverse', {
      'format': 'jsonv2',
      'lat': '${pin.point.latitude}',
      'lon': '${pin.point.longitude}',
      'zoom': '18',
      'addressdetails': '1',
    });
    if (!mounted) return;
    setState(() {
      pin.loading = false;
      if (data is! Map<String, dynamic>)
        return; // lookup failed, keep "Dropped pin"

      String? street;
      final address = data['address'];
      if (address is Map<String, dynamic>) {
        // the street can be under different keys depending on the kind of road
        for (final key in [
          'road',
          'pedestrian',
          'footway',
          'path',
          'neighbourhood',
          'suburb',
          'village',
          'town',
          'city',
        ]) {
          final value = address[key];
          if (value is String && value.isNotEmpty) {
            street = value;
            break;
          }
        }
      }
      final name = data['name'];
      if (street != null) {
        pin.name = street;
      } else if (name is String && name.isNotEmpty) {
        pin.name = name;
      }
      final display = data['display_name'];
      if (display is String) pin.address = display;
    });
  }

  // turns typed text (like "Open field") into a point on the map
  Future<RouteEnd?> _searchAddress(String text) async {
    final data = await _nominatim('/search', {
      'format': 'jsonv2',
      'q': text,
      'countrycodes': 'ph',
      'limit': '1',
      // only look inside the campus area. to search anywhere, delete these 2 lines
      'viewbox':
          '${kCampusBounds.west},${kCampusBounds.north},${kCampusBounds.east},${kCampusBounds.south}',
      'bounded': '1',
    });
    if (data is List && data.isNotEmpty && data.first is Map) {
      final m = data.first as Map;
      final lat = double.tryParse('${m['lat']}');
      final lon = double.tryParse('${m['lon']}');
      if (lat == null || lon == null) return null;
      final name = m['name'];
      return RouteEnd(
        LatLng(lat, lon),
        (name is String && name.isNotEmpty) ? name : text,
        null,
      );
    }
    return null;
  }

  // opens the from / to panel. when a destination is given it finds the route right away
  void _startDirections({LatLng? toPoint, String? toName, Place? toPlace}) {
    _searchFocus.unfocus();
    _routeToken++;
    setState(() {
      _directionsOpen = true;
      _routing = false;
      _selected = null;
      _pin = null;
      _route = null;
      _fromController.text = 'My location';
      _fromPoint = null;
      _fromPlace = null;
      _toController.text = toName ?? '';
      _toPoint = toPoint;
      _toPlace = toPlace;
    });
    if (toPoint != null) _getRoute();
  }

  void _closeDirections() {
    _routeToken++; // a route that is still loading gets ignored
    _fromFocus.unfocus();
    _toFocus.unfocus();
    setState(() {
      _directionsOpen = false;
      _routing = false;
      _route = null;
    });
  }

  // works out what a from / to field means: a picked suggestion, my gps location,
  // one of our places, or (last) an address the search service can find
  Future<RouteEnd?> _resolveEnd(
    String text,
    LatLng? pickedPoint,
    Place? pickedPlace,
  ) async {
    final t = text.trim();
    final lower = t.toLowerCase();
    if (pickedPoint != null) return RouteEnd(pickedPoint, t, pickedPlace);

    if (t.isEmpty || lower == 'my location') {
      final me = await _askForLocation() ?? _myLatLng;
      return me == null ? null : RouteEnd(me, 'My location', null);
    }
    for (final p in kPlaces) {
      if (p.name.toLowerCase() == lower || p.code?.toLowerCase() == lower) {
        return RouteEnd(p.position, p.name, p);
      }
    }
    for (final p in kPlaces) {
      if (p.name.toLowerCase().contains(lower)) {
        return RouteEnd(p.position, p.name, p);
      }
    }
    // an office, room or feature inside a building ("registrar", "computer lab")
    final hits = searchPlaces(t, limit: 1);
    if (hits.isNotEmpty) {
      final p = hits.first.place;
      return RouteEnd(p.position, p.name, p);
    }
    return _searchAddress(t);
  }

  Future<void> _getRoute() async {
    _fromFocus.unfocus();
    _toFocus.unfocus();
    if (_toController.text.trim().isEmpty && _toPoint == null) {
      _toast('Type where you want to go first');
      return;
    }
    final token = ++_routeToken;
    setState(() {
      _routing = true;
      _route = null;
    });
    try {
      await _getRouteInternal(token);
      return;
    } catch (_) {
      // never leave the app stuck on the loading screen (no route / crash / timeout)
      if (!mounted || token != _routeToken) return;
      setState(() => _routing = false);
      _toast('Could not get the route right now. Please try again.');
    }
  }

  Future<void> _getRouteInternal(int token) async {
    final from = await _resolveEnd(
      _fromController.text,
      _fromPoint,
      _fromPlace,
    );
    final to = await _resolveEnd(_toController.text, _toPoint, _toPlace);
    if (!mounted || token != _routeToken) return;
    if (from == null || to == null) {
      setState(() => _routing = false);
      _toast(
        from == null
            ? "Couldn't find the starting point"
            : "Couldn't find the destination",
      );
      return;
    }

    // ask for 2 routes, a wheelchair one and a normal walking one, so we can compare them
    final results = await Future.wait([
      _valhalla(from.point, to.point, wheelchair: true),
      _valhalla(from.point, to.point, wheelchair: false),
    ]);
    if (!mounted || token != _routeToken) return;

    final result = RouteResult(
      from: from,
      to: to,
      straightMeters: _distance.as(LengthUnit.Meter, from.point, to.point),
      wheel: results[0],
      foot: results[1],
    );
    setState(() {
      _routing = false;
      _route = result;
    });
    _fitRoute(result);
  }

  // valhalla = free routing server that uses openstreetmap data
  Future<LegResult> _valhalla(
    LatLng a,
    LatLng b, {
    required bool wheelchair,
  }) async {
    final request = {
      'locations': [
        {'lat': a.latitude, 'lon': a.longitude},
        {'lat': b.latitude, 'lon': b.longitude},
      ],
      'costing': 'pedestrian',
      // type 'wheelchair' makes the router avoid stairs and steep slopes
      'costing_options': {
        'pedestrian': {'type': wheelchair ? 'wheelchair' : 'foot'},
      },
      'directions_options': {'units': 'kilometers'},
    };
    final uri = Uri.https('valhalla1.openstreetmap.de', '/route', {
      'json': jsonEncode(request),
    });
    try {
      final res = await http
          .get(uri, headers: {'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data is Map && data['trip'] is Map) {
        final trip = data['trip'] as Map;
        final summary = trip['summary'] as Map;
        final leg = (trip['legs'] as List).first as Map;
        final shape = leg['shape'];
        // valhalla sometimes sends the shape as an encoded string, sometimes as a
        // plain list of coordinates - support both so a good route is never lost
        List<LatLng> points;
        if (shape is String) {
          points = decodePolyline6(shape);
        } else if (shape is List) {
          points = [
            for (final c in shape)
              LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble()),
          ];
        } else {
          return const LegResult(LegStatus.error);
        }
        return LegResult(
          LegStatus.ok,
          km: (summary['length'] as num).toDouble(),
          seconds: (summary['time'] as num).toInt(),
          points: points,
        );
      }
      // these error codes mean "no path between these two points"
      if (data is Map && const [442, 171, 154].contains(data['error_code'])) {
        return const LegResult(LegStatus.none);
      }
      return const LegResult(LegStatus.error);
    } catch (_) {
      return const LegResult(LegStatus.error);
    }
  }

  // zooms the map so the whole route is visible between the top panel and the bottom card
  void _fitRoute(RouteResult r) {
    final points = <LatLng>[
      r.from.point,
      r.to.point,
      ...r.wheel.points,
      ...r.foot.points,
    ];
    final h = MediaQuery.of(context).size.height;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: EdgeInsets.fromLTRB(40, h * 0.28, 40, h * 0.45),
        maxZoom: 17,
      ),
    );
  }

  Widget _buildDirectionsPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: _closeDirections,
              ),
              Expanded(
                child: Column(
                  children: [
                    _directionField(
                      controller: _fromController,
                      focus: _fromFocus,
                      hint: 'Where are you?',
                      icon: Icons.trip_origin,
                      onEdited: () {
                        _fromPoint = null;
                        _fromPlace = null;
                      },
                    ),
                    const SizedBox(height: 8),
                    _directionField(
                      controller: _toController,
                      focus: _toFocus,
                      hint: 'Where to?',
                      icon: Icons.location_on,
                      onEdited: () {
                        _toPoint = null;
                        _toPlace = null;
                      },
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.lightBlue.shade100,
                          foregroundColor: Colors.black,
                        ),
                        icon: const Icon(Icons.accessible),
                        label: const Text('Get route'),
                        onPressed: _routing ? null : _getRoute,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _directionField({
    required TextEditingController controller,
    required FocusNode focus,
    required String hint,
    required IconData icon,
    required VoidCallback onEdited,
  }) {
    return TextField(
      controller: controller,
      focusNode: focus,
      textInputAction: TextInputAction.search,
      // on web and desktop a tap outside the field unfocuses it by default, which would remove the
      // suggestion list before its tap goes through. the map already unfocuses on tap
      onTapOutside: (_) {},
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      // typing again means the old picked point doesn't count anymore
      onChanged: (_) => setState(onEdited),
      onSubmitted: (_) => _getRoute(),
    );
  }

  // quick picks under the from / to fields (our places, and "My location" for the from field)
  Widget _buildDirectionSuggestions() {
    final fromFocused = _fromFocus.hasFocus;
    final controller = fromFocused ? _fromController : _toController;
    final q = controller.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? kPlaces.take(4).toList()
        : searchPlaces(q, limit: 4).map((h) => h.place).toList();
    final showMe = fromFocused && (q.isEmpty || 'my location'.contains(q));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Material(
        elevation: 4,
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMe)
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('My location'),
                onTap: () {
                  setState(() {
                    _fromController.text = 'My location';
                    _fromPoint = null;
                    _fromPlace = null;
                  });
                  _fromFocus.unfocus();
                },
              ),
            for (final p in matches)
              ListTile(
                leading: Icon(p.type.icon, color: p.statusColor),
                title: Text(p.name),
                subtitle: Text(p.statusLabel),
                onTap: () {
                  setState(() {
                    controller.text = p.name;
                    if (fromFocused) {
                      _fromPoint = p.position;
                      _fromPlace = p;
                    } else {
                      _toPoint = p.position;
                      _toPlace = p;
                    }
                  });
                  (fromFocused ? _fromFocus : _toFocus).unfocus();
                },
              ),
            if (!showMe && matches.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Not in our list, press search to look it up on the map',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard() {
    final maxHeight = MediaQuery.of(context).size.height * 0.5;
    final textTheme = Theme.of(context).textTheme;

    Widget content;
    if (_routing || _route == null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Looking for a wheelchair-friendly route...'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: _closeDirections,
            ),
          ],
        ),
      );
    } else {
      final r = _route!;
      final v = judgeRoute(r);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(v.icon, color: v.color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  v.title,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: _closeDirections,
              ),
            ],
          ),
          Text(
            '${r.from.name}  →  ${r.to.name}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(
                Icons.straighten,
                r.wheel.ok
                    ? formatDistance(r.wheel.km * 1000)
                    : formatDistance(r.straightMeters),
                r.wheel.ok ? 'wheelchair route' : 'straight line only',
              ),
              const SizedBox(width: 28),
              _stat(
                Icons.schedule,
                r.wheel.ok ? formatDuration(r.wheel.seconds) : '-',
                'estimated time',
              ),
            ],
          ),
          if (r.wheel.ok)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Straight line: ${formatDistance(r.straightMeters)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 12),
          for (final note in v.notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: v.color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note)),
                ],
              ),
            ),
          if (!r.wheel.ok && r.foot.ok)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'The red line on the map is the normal walking route, it is not wheelchair-friendly.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'This is only an estimate from map data. Slopes, curbs and blocked paths may be missing, so please double check on site.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          elevation: 16,
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: Colors.black54),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final active =
        _typeFilters.length + _pwdFilters.length + (_savedOnly ? 1 : 0);

    // round filter button beside the search bar. the count badge shows how many
    // filters are on. long press clears them all
    final filterButton = Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: active > 0 ? Colors.lightBlue.shade100 : Colors.white,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openFilterSheet,
        onLongPress: active > 0 ? _clearFilters : null,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(
            child: Tooltip(
              message: 'Filters',
              child: Badge(
                isLabelVisible: active > 0,
                label: Text('$active'),
                child: const Icon(Icons.tune),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(child: _buildSearchField()),
          const SizedBox(width: 8),
          filterButton,
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(30),
        color: Colors.white,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  // on web and desktop a tap outside the field unfocuses it by default, which would remove the
                  // suggestion list before its tap goes through. the map already unfocuses on tap
                  onTapOutside: (_) {},
                  decoration: const InputDecoration(
                    // you can search a building, a code (CEAT), an office, a room or a
                    // feature (elevator, library, clinic...)
                    hintText: 'Search buildings, offices, rooms',
                    border: InputBorder.none,
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _openSearchResults,
                ),
              ),
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Icon(Icons.search),
                ),
            ],
          ),
        ),
    );
  }

  // a place was picked (from the suggestions or the results page): write its name in
  // the search bar and open it on the map
  void _pickFromSearch(Place p) {
    _searchController.value = TextEditingValue(
      text: p.name,
      selection: TextSelection.collapsed(offset: p.name.length),
    );
    setState(() => _query = p.name);
    _selectPlace(p);
  }

  // opens the search results page for what was typed in the search bar
  void _openSearchResults(String text) {
    if (text.trim().isEmpty) return;
    _searchFocus.unfocus();
    _openPage(
      'Search results',
      SearchResultsPage(query: text, onOpenPlace: _pickFromSearch),
    );
  }

  // to connect (search): this searches the local list (kPlaces). if the places are loaded
  // from firestore (see the note above kPlaces), nothing changes here. only if there are
  // too many places to load at once, replace searchPlaces() with a query to the server.
  Widget _buildSuggestions() {
    final hits = searchPlaces(_searchController.text, limit: 5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Material(
        elevation: 4,
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: hits.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No results found'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final h in hits)
                    ListTile(
                      leading: Icon(
                        h.place.type.icon,
                        color: h.place.statusColor,
                      ),
                      title: Text(h.place.name),
                      // when the match was inside the building (a room, a feature),
                      // say what was found
                      subtitle: Text(
                        h.via.isEmpty
                            ? '${h.place.type.label}  •  ${h.place.statusLabel}'
                            : 'Found: ${h.via}',
                      ),
                      onTap: () => _pickFromSearch(h.place),
                    ),
                  ListTile(
                    leading: const Icon(Icons.search),
                    trailing: const Icon(Icons.chevron_right),
                    title: Text(
                      'See all results for "${_searchController.text.trim()}"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _openSearchResults(_searchController.text),
                  ),
                ],
              ),
      ),
    );
  }

  // the filter button is built inside _buildSearchBar. the chips (saved, type of
  // place, accessibility features) live in the bottom sheet below so the map stays clear.
  // the pins that don't match the chosen filters are hidden
  void _clearFilters() {
    setState(() {
      _typeFilters.clear();
      _pwdFilters.clear();
      _savedOnly = false;
      _afterFilterChange();
    });
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget chip(
            String label,
            IconData icon,
            bool selected,
            VoidCallback onTap,
          ) {
            return FilterChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              selected: selected,
              showCheckmark: false,
              selectedColor: Colors.lightBlue.shade100,
              onSelected: (_) {
                onTap(); // changes the map filters
                setSheet(() {}); // redraws the chips in this sheet
              },
            );
          }

          Widget section(String title, List<Widget> chips) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  title,
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: chips),
            ],
          );

          final active =
              _typeFilters.length + _pwdFilters.length + (_savedOnly ? 1 : 0);

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filters',
                            style: Theme.of(ctx).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // shows only the places the user bookmarked
                          section('Show', [
                            chip('Saved', Icons.bookmark, _savedOnly, () {
                              setState(() {
                                _savedOnly = !_savedOnly;
                                _afterFilterChange();
                              });
                            }),
                          ]),
                          section('Type of place', [
                            for (final t in PlaceType.values)
                              if (t != PlaceType.other)
                                chip(
                                  t.chipLabel,
                                  t.icon,
                                  _typeFilters.contains(t),
                                  () => _toggleType(t),
                                ),
                          ]),
                          section('Accessibility features', [
                            for (final f in Pwd.values)
                              chip(
                                f.chipLabel,
                                f.icon,
                                _pwdFilters.contains(f),
                                () => _togglePwd(f),
                              ),
                          ]),
                          const SizedBox(height: 8),
                          const Divider(),
                          // this is an action, not a filter, so it sits apart
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.near_me),
                            title: const Text('Find nearest accessible restroom'),
                            onTap: () {
                              Navigator.pop(ctx);
                              _findNearestRestroom();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: active == 0
                                ? null
                                : () {
                                    _clearFilters();
                                    setSheet(() {});
                                  },
                            child: const Text('Clear all'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              active == 0 ? 'Done' : 'Show results',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegend() {
    Widget row(Color c, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );

    return Material(
      elevation: 3,
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(kAccessible, 'Fully accessible'),
            row(kPartial, 'Partially accessible'),
            row(kInaccessible, 'Not accessible'),
          ],
        ),
      ),
    );
  }

  // a simple bottom sheet with a title and a list inside. used by the saved list, the
  // campus directory, the walkway list and the map layers. build() can use the setSheet
  // it is given to redraw the list (for example after un-saving something)
  void _showListSheet(
    String title,
    List<Widget> Function(BuildContext ctx, StateSetter setSheet) build,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final maxHeight = MediaQuery.of(ctx).size.height * 0.75;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(ctx).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: build(ctx, setSheet),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // the quick bookmark list (the purple bookmark button on the map). the "Saves" item in
  // the menu opens the full SavesPage instead (see _buildDrawer)
  void _openSaved() {
    _showListSheet('Saved places', (ctx, setSheet) {
      final places = kPlaces.where((p) => _saved.contains(p.id)).toList();
      if (places.isEmpty && _savedSpots.isEmpty) {
        return const [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Text(
              'Nothing saved yet. Open a building and tap Save, or tap the map and save the pin.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ];
      }
      return [
        for (final p in places)
          ListTile(
            leading: Icon(p.type.icon, color: p.statusColor),
            title: Text(p.name),
            subtitle: Text(p.statusLabel),
            trailing: IconButton(
              icon: const Icon(Icons.bookmark, color: Colors.deepPurple),
              tooltip: 'Remove from saved',
              onPressed: () {
                _toggleSaved(p);
                setSheet(() {});
              },
            ),
            onTap: () {
              Navigator.pop(ctx);
              _selectPlace(p);
            },
          ),
        for (final spot in List<DroppedPin>.of(_savedSpots))
          ListTile(
            leading: const Icon(Icons.location_on, color: Colors.deepPurple),
            title: Text(spot.name),
            subtitle: const Text('Saved pin'),
            trailing: IconButton(
              icon: const Icon(Icons.bookmark, color: Colors.deepPurple),
              tooltip: 'Remove from saved',
              onPressed: () {
                _toggleSpotSaved(spot);
                setSheet(() {});
              },
            ),
            onTap: () {
              Navigator.pop(ctx);
              _openSpot(spot);
            },
          ),
      ];
    });
  }

  // every building and office grouped by category, like a campus directory
  void _openDirectory() {
    _showListSheet('Campus directory', (ctx, setSheet) {
      return [
        for (final t in PlaceType.values)
          if (kPlaces.any((p) => p.type == t)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Icon(t.icon, size: 18, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(
                    t.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            for (final p in kPlaces.where((p) => p.type == t))
              ListTile(
                dense: true,
                leading: Icon(Icons.circle, size: 12, color: p.statusColor),
                title: Text(p.name),
                subtitle: Text(
                  p.code == null
                      ? p.statusLabel
                      : '${p.code}  •  ${p.statusLabel}',
                ),
                trailing: _saved.contains(p.id)
                    ? const Icon(
                        Icons.bookmark,
                        color: Colors.deepPurple,
                        size: 18,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _selectPlace(p);
                },
              ),
          ],
      ];
    });
  }

  // the list of campus walkways with how wheelchair friendly each one is
  void _openWalkways() {
    _showListSheet('Campus walkways', (ctx, setSheet) {
      return [
        for (final path in kPaths)
          ListTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: path.color,
              child: Icon(
                path.level == 2 ? Icons.stairs : Icons.alt_route,
                size: 18,
                color: Colors.white,
              ),
            ),
            title: Text(path.name),
            subtitle: Text(path.levelLabel),
            onTap: () {
              Navigator.pop(ctx);
              _focusPath(path);
              _showPath(path);
            },
          ),
      ];
    });
  }

  // turn parts of the map on and off
  void _openLayers() {
    _showListSheet('Map layers', (ctx, setSheet) {
      Widget toggle(
        String label,
        IconData icon,
        bool value,
        void Function(bool) set,
      ) {
        return SwitchListTile(
          secondary: Icon(icon),
          title: Text(label),
          value: value,
          onChanged: (v) {
            setState(() => set(v));
            setSheet(() {});
          },
        );
      }

      return [
        toggle(
          'Building outlines',
          Icons.domain,
          _showBuildings,
          (v) => _showBuildings = v,
        ),
        toggle(
          'Building names',
          Icons.text_fields,
          _showLabels,
          (v) => _showLabels = v,
        ),
        toggle(
          'Campus walkways',
          Icons.alt_route,
          _showWalkways,
          (v) => _showWalkways = v,
        ),
      ];
    });
  }

  // zooms the map so the whole walkway is visible
  void _focusPath(CampusPath path) {
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(path.points),
        padding: const EdgeInsets.all(80),
        maxZoom: 18,
      ),
    );
  }

  void _showPath(CampusPath path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(path.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 12, color: path.color),
                const SizedBox(width: 8),
                Text(
                  path.levelLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: path.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(path.note),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // the "Report a problem" form (elevator broken, ramp blocked...)
  // to connect: the sending part is _submitReport near the top of this class
  void _showReport(Place p) {
    final chosen = <String>{};
    final note = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Report a problem'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in kReportReasons)
                      FilterChip(
                        label: Text(r),
                        selected: chosen.contains(r),
                        onSelected: (_) => setDialog(() {
                          if (!chosen.add(r)) chosen.remove(r);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Tell us more (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _submitReport(p, chosen.toList(), note.text.trim());
                    },
              child: const Text('Send report'),
            ),
          ],
        ),
      ),
    );
  }

  // all the actions for one place (or saved spot), grouped in one place so the
  // buttons are easy to read and navigate instead of scattered over the sheet
  Widget _buildActions(Place p, {DroppedPin? spot}) {
    final saved = spot != null ? _isSpotSaved(spot) : _saved.contains(p.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.lightBlue.shade100,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.directions),
                  label: const Text('Guide'),
                  // guide = directions from where you are to this place
                  onPressed: () => _startDirections(
                    toPoint: p.position,
                    toName: p.name,
                    toPlace: p.known ? p : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
                  icon: Icon(
                    saved ? Icons.bookmark : Icons.bookmark_border,
                    color: saved ? Colors.deepPurple : null,
                  ),
                  label: Text(saved ? 'Saved' : 'Save'),
                  // a tapped spot is saved as a purple pin, a place is saved by its id.
                  // to connect: the saving to the server happens inside
                  // _toggleSaved / _toggleSpotSaved (see BACKEND HOOKS)
                  onPressed: () {
                    if (spot != null) {
                      _toggleSpotSaved(spot);
                    } else {
                      _toggleSaved(p);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add photo'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
              onPressed: () => _openPage('Add photo', AddPhotoPage(place: p)),
            ),
            if (p.known)
              OutlinedButton.icon(
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report a problem'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
                onPressed: () => _showReport(p),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Write a review'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
              onPressed: () => _openPage('Write a review', ReviewPage(place: p)),
            ),
          ],
        ),
      ],
    );
  }

  // slides up from the bottom and can be dragged taller or shorter.
  // the key makes it start over whenever a different place is picked
  // spot is only set when the user tapped empty map (not one of our places)
  Widget _buildSheet(Place p, {DroppedPin? spot}) {
    final textTheme = Theme.of(context).textTheme;
    final open = p.isOpenNow;

    Widget heading(String t) => Text(
      t,
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );

    return DraggableScrollableSheet(
      key: ValueKey(p.id),
      initialChildSize: 0.45,
      minChildSize: 0.2,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.45],
      builder: (context, scrollController) {
        return Material(
          elevation: 16,
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              // little bar on top that shows the sheet can be dragged
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // name, category and close button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(p.type.icon, size: 16, color: Colors.black54),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                p.floors > 1
                                    ? '${p.type.label}  •  ${p.floors} floors'
                                    : p.type.label,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                            // the short name that is also written on the map
                            if (p.code != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.lightBlue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  p.code!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: spot != null ? _closePin : _clearSelection,
                  ),
                ],
              ),
              // coordinates, and a loading bar while the street name is still being looked up
              if (spot != null) ...[
                Text(
                  '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
                if (spot.loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
              ],
              const SizedBox(height: 8),

              // rating, stars and the accessibility badge
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (p.reviewCount == 0)
                    const Text(
                      'No ratings yet',
                      style: TextStyle(color: Colors.black54),
                    )
                  else ...[
                    Text(
                      p.rating.toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    _Stars(p.rating),
                    Text('(${p.reviewCount})'),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: p.statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 10, color: p.statusColor),
                        const SizedBox(width: 6),
                        Text(
                          p.statusLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // opening hours, "Open now" is worked out from the phone's clock
              if (p.hours != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (open != null)
                                TextSpan(
                                  text: open ? 'Open now' : 'Closed now',
                                  style: TextStyle(
                                    color: open ? kAccessible : kInaccessible,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (open != null) const TextSpan(text: '  •  '),
                              TextSpan(
                                text: p.hours!,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_myLatLng != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${formatDistance(_distance.as(LengthUnit.Meter, _myLatLng!, p.position))} from you (straight line)',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              const SizedBox(height: 16),

              // all the actions for this place, grouped here so the buttons are
              // easy to read and navigate instead of scattered over the sheet
              _buildActions(p, spot: spot),
              const SizedBox(height: 20),

              // placeholder photos, the last tile is for adding a photo (not working yet)
              // to connect: load the real photo urls from firebase storage, for example
              // places/{id}/photos, and show them with Image.network in _PhotoTile
              SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < 3; i++) const _PhotoTile(),
                    _PhotoTile(
                      isAdd: true,
                      onTap: () => _openPage('Add photo', AddPhotoPage(place: p)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // accessibility checklist: a bar for how many features the place has, then
              // every feature grouped as "Getting in", "Moving around", "Facilities & help"
              Row(
                children: [
                  Expanded(child: heading('Is it accessible?')),
                  if (p.known)
                    Text(
                      '${p.featureCount} of ${p.featureTotal}',
                      style: TextStyle(
                        color: p.statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              if (p.known) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.featureTotal == 0
                        ? 0
                        : p.featureCount / p.featureTotal,
                    minHeight: 6,
                    color: p.statusColor,
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (!p.known)
                for (final f in kCorePwd)
                  _FeatureRow(f.icon, f.label, false, known: false)
              else
                for (final g in kPwdGroups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Text(
                      g.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.black45,
                      ),
                    ),
                  ),
                  for (final f in Pwd.values.where((f) => f.group == g))
                    _FeatureRow(
                      f.icon,
                      f.label,
                      p.has(f),
                      notApplicable: p.isNa(f),
                    ),
                ],
              // nobody reported this spot yet, so ask the community to add it
              if (!p.known) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add accessibility info'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                  ),
                  // to connect: replace null with the add-info page, like AddPlaceInfoPage(spot: p)
                  // when the user submits it, save it in the 'places' collection using the same
                  // keys that Place.fromMap reads (see bsu_data.dart)
                  onPressed: () => _openPage('Add accessibility info', null),
                ),
              ],

              // other things the building has (wifi, computer labs...)
              if (p.facilities.isNotEmpty) ...[
                const SizedBox(height: 24),
                heading('Facilities'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final f in p.facilities)
                      Chip(
                        avatar: Icon(f.icon, size: 16),
                        label: Text(f.label),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.grey.shade100,
                        side: BorderSide.none,
                      ),
                  ],
                ),
              ],

              // offices, departments and rooms, grouped by floor. a red row means a
              // wheelchair user can't get there (stairs only)
              if (p.units.isNotEmpty) ...[
                const SizedBox(height: 24),
                heading('Offices & rooms'),
                for (final entry in unitsByFloor(p).entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  for (final u in entry.value) _UnitRow(u),
                ],
              ],

              // hallways, corridors and stairs inside the building
              if (p.hallways.isNotEmpty) ...[
                const SizedBox(height: 24),
                heading('Hallways & stairs'),
                const SizedBox(height: 4),
                for (final h in p.hallways) _HallwayRow(h),
              ],
              const SizedBox(height: 20),

              heading('About'),
              const SizedBox(height: 6),
              Text(p.description),
              const SizedBox(height: 12),

              // reviews (the sample ones are fake for now)
              // to connect: load them from places/{id}/reviews (newest first). the review
              // page should add a document there and update the place's rating average
              Row(
                children: [
                  Expanded(child: heading('Reviews')),
                ],
              ),
              if (p.reviews.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No reviews yet. Be the first to write one.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              for (final r in p.reviews) _ReviewTile(r),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    void go(String label, Widget? page, {bool replace = false}) {
      Navigator.pop(context); // pop closes the drawer
      _openPage(label, page, replace: replace);
    }

    final savedCount = _saved.length + _savedSpots.length;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const WheelyLogo(compact: true),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wheely Access',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // to connect: show the logged in user here instead, like
                        // FirebaseAuth.instance.currentUser?.displayName ?? 'Guest'
                        Text('Find PWD-friendly places'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Account'),
              // to connect: replace null with const AccountPage() and import its file at the top.
              // the account page should read the logged in user (FirebaseAuth.instance.currentUser)
              onTap: () => go('Account', const AccountPage()),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: const Text('Saves'),
              trailing: savedCount == 0 ? null : Text('$savedCount'),
              // saved pins (the purple ones) are turned into places so they show in the
              // same list. removing one turns its bookmark off here on the map too
              onTap: () => go(
                'Saves',
                SavesPage(
                  places: [
                    ...kPlaces.where((p) => _saved.contains(p.id)),
                    for (final spot in _savedSpots) spot.toPlace(),
                  ],
                  onRemove: (p) {
                    final spot = _spotFor(p);
                    spot != null ? _toggleSpotSaved(spot) : _toggleSaved(p);
                  },
                  onOpenPlace: (p) {
                    final spot = _spotFor(p);
                    spot != null ? _openSpot(spot) : _selectPlace(p);
                  },
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('History'),
              // to connect: replace null with const HistoryPage(), it reads what _logHistory saves
              onTap: () => go('History', HistoryPage(places: List<Place>.of(_history))),
            ),
            ListTile(
              leading: const Icon(Icons.apartment),
              title: const Text('Campus directory'),
              onTap: () {
                Navigator.pop(context);
                _openDirectory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.alt_route),
              title: const Text('Campus walkways'),
              onTap: () {
                Navigator.pop(context);
                _openWalkways();
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help'),
              onTap: () {
                Navigator.pop(context);
                _showHelp();
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlue.shade100,
                    foregroundColor: Colors.black,
                  ),
                  // to connect: replace null with const LoginPage(). before going there, sign
                  // the user out, like  await FirebaseAuth.instance.signOut();
                  onPressed: () => go('Log Out', const LoginPage(), replace: true),
                  child: const Text('Log Out'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // help popup that explains the icons and pin colors (from our sketch)
  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What do these icons mean?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in PlaceType.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(t.icon),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t.label)),
                    ],
                  ),
                ),
              const Divider(height: 24),
              const Text(
                'Pin and building colors',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              _legendLine(kAccessible, 'Ramp, elevator and restroom'),
              _legendLine(kPartial, 'Some accessibility features'),
              _legendLine(kInaccessible, 'No accessibility features'),
              const Divider(height: 24),
              const Text(
                'Walkway lines',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              _lineLegend(kAccessible, 'Smooth and flat'),
              _lineLegend(kPartial, 'Slope or narrow, be careful'),
              _lineLegend(kInaccessible, 'Has steps'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _legendLine(Color c, String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(Icons.location_on, color: c),
        const SizedBox(width: 8),
        Expanded(child: Text(t)),
      ],
    ),
  );

  Widget _lineLegend(Color c, String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Container(
          width: 24,
          height: 5,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(t)),
      ],
    ),
  );
}

// smaller widgets used by the map pins and the bottom sheet
// the red / purple pin for spots that aren't one of our places
class _SpotPin extends StatelessWidget {
  const _SpotPin(this.color, {this.icon});
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_on, size: 48, color: color),
        Positioned(
          top: 9,
          child: CircleAvatar(
            radius: 8,
            backgroundColor: Colors.white,
            child: icon == null ? null : Icon(icon, size: 11, color: color),
          ),
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin(this.place);
  final Place place;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_on, size: 56, color: place.statusColor),
        Positioned(
          top: 11,
          child: CircleAvatar(
            radius: 11,
            backgroundColor: Colors.white,
            child: Icon(place.type.icon, size: 14, color: place.statusColor),
          ),
        ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars(this.rating, {this.size = 18});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final v = rating - i;
        final icon = v >= 0.75
            ? Icons.star
            : v >= 0.25
            ? Icons.star_half
            : Icons.star_border;
        return Icon(icon, size: size, color: const Color(0xFFFFB400));
      }),
    );
  }
}

// the choices in the "Report a problem" form
const List<String> kReportReasons = [
  'Elevator not working',
  'Ramp blocked',
  'Steps, no ramp',
  'Restroom locked or not usable',
  'Wrong information',
  'Other',
];

// groups the rooms of a building by floor, keeping the order they were written in
Map<String, List<Unit>> unitsByFloor(Place p) {
  final floors = <String, List<Unit>>{};
  for (final u in p.units) {
    floors.putIfAbsent(u.floor, () => []).add(u);
  }
  return floors;
}

// the white name tag that sits under a pin on the map
class _MapLabel extends StatelessWidget {
  const _MapLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

// one office / room in the "Offices & rooms" list
class _UnitRow extends StatelessWidget {
  const _UnitRow(this.unit);
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final color = unit.accessible ? kAccessible : kInaccessible;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            unit.accessible ? Icons.meeting_room : Icons.stairs,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(unit.name),
                if (unit.note != null)
                  Text(
                    unit.note!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            unit.accessible ? 'Reachable' : 'Stairs only',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// one hallway / corridor / stairs in the "Hallways & stairs" list
class _HallwayRow extends StatelessWidget {
  const _HallwayRow(this.hallway);
  final Hallway hallway;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(hallway.icon, size: 20, color: hallway.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hallway.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  hallway.note,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(
    this.icon,
    this.label,
    this.available, {
    this.known = true,
    this.notApplicable = false,
  });
  final IconData icon;
  final String label;
  final bool available;
  final bool known; // false = nobody reported it yet
  final bool
  notApplicable; // true = doesn't make sense here (elevator at a gate)

  @override
  Widget build(BuildContext context) {
    final grey = !known || notApplicable;
    final color = grey
        ? Colors.grey
        : available
        ? kAccessible
        : kInaccessible;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: grey ? Colors.black38 : Colors.black87),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: notApplicable ? Colors.black45 : null),
            ),
          ),
          Icon(
            notApplicable
                ? Icons.remove_circle_outline
                : !known
                ? Icons.help_outline
                : available
                ? Icons.check_circle
                : Icons.cancel,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 6),
          Text(
            notApplicable
                ? 'Not applicable'
                : !known
                ? 'Not reported yet'
                : available
                ? 'Available'
                : 'Not available',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({this.isAdd = false, this.onTap});
  final bool isAdd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 140,
          decoration: BoxDecoration(
            color: isAdd ? Colors.lightBlue.shade50 : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
            border: isAdd ? Border.all(color: Colors.lightBlue.shade200) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isAdd ? Icons.add_a_photo_outlined : Icons.image_outlined,
                size: 32,
                color: Colors.black45,
              ),
              if (isAdd) const SizedBox(height: 6),
              if (isAdd)
                const Text('Add photo', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile(this.review);
  final Review review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey.shade300,
            child: const Icon(Icons.person, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _Stars(review.rating, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      review.when,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(review.text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

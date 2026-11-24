import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import '../core/location.dart';
import '../theme/theme.dart';
import 'widgets.dart';

/// Free OpenStreetMap tiles (no API key). The user agent is required by the OSM tile policy.
TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: AppConfig.packageName,
      maxNativeZoom: 19,
    );

/// Attribution required by OpenStreetMap.
Widget osmAttribution() => const Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xCCFFFFFF)),
          child: Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1), child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10))),
        ),
      ),
    );

Widget housePin({double size = 44}) => Icon(Icons.home_rounded, color: C.flame, size: size, shadows: const [Shadow(blurRadius: 6, color: Colors.black38)]);

Widget riderPin() => Container(
      decoration: BoxDecoration(color: C.navy, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38)]),
      padding: const EdgeInsets.all(6),
      child: const Icon(Icons.delivery_dining, color: Colors.white, size: 24),
    );

/// Result of the pin picker.
class PickedSpot {
  PickedSpot(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Full-screen "Pin your house" map: drag the map so the pin sits on your house.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.lat, this.lng, this.title = 'Pin your house'});
  final double? lat;
  final double? lng;
  final String title;

  static Future<PickedSpot?> open(BuildContext context, {double? lat, double? lng, String title = 'Pin your house'}) =>
      Navigator.of(context).push<PickedSpot>(MaterialPageRoute(builder: (_) => MapPickerScreen(lat: lat, lng: lng, title: title)));

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  late LatLng _center = LatLng(widget.lat ?? AppConfig.defaultLat, widget.lng ?? AppConfig.defaultLng);
  bool _locating = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.lat == null) WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final problem = await Gps.ensureReady();
    if (problem != null) {
      if (mounted) {
        setState(() => _locating = false);
        showSnack(context, problem, error: true);
      }
      return;
    }
    final p = await Gps.current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (p == null) {
      showSnack(context, 'Could not find your location. Move the map to your house instead.', error: true);
      return;
    }
    _center = LatLng(p.latitude, p.longitude);
    if (_ready) _map.move(_center, 18);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: widget.lat == null ? 13 : 18,
            minZoom: 5,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () {
              _ready = true;
              _map.move(_center, widget.lat == null ? 13 : 18);
            },
            onPositionChanged: (camera, _) => _center = camera.center,
          ),
          children: [osmTiles()],
        ),
        // The pin stays in the middle; the map moves under it.
        IgnorePointer(child: Center(child: Padding(padding: const EdgeInsets.only(bottom: 40), child: housePin(size: 48)))),
        osmAttribution(),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 2,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Move the map so the house pin is exactly on your house. Zoom in to be sure.', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 104,
          child: FloatingActionButton(
            heroTag: 'locate',
            backgroundColor: Colors.white,
            foregroundColor: C.navy,
            onPressed: _locating ? null : _useMyLocation,
            tooltip: 'Use my location',
            child: _locating ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.my_location),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, PickedSpot(_center.latitude, _center.longitude)),
              icon: const Icon(Icons.check),
              label: const Text('Use this spot'),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A small non-interactive map preview with a house pin (and the rider, when given).
class SpotMap extends StatefulWidget {
  const SpotMap({super.key, required this.lat, required this.lng, this.riderLat, this.riderLng, this.height = 220, this.interactive = false});
  final double lat;
  final double lng;
  final double? riderLat;
  final double? riderLng;
  final double height;
  final bool interactive;

  @override
  State<SpotMap> createState() => _SpotMapState();
}

class _SpotMapState extends State<SpotMap> {
  final _map = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(SpotMap old) {
    super.didUpdateWidget(old);
    if (_ready && (old.riderLat != widget.riderLat || old.riderLng != widget.riderLng)) _fit();
  }

  void _fit() {
    final house = LatLng(widget.lat, widget.lng);
    if (widget.riderLat == null || widget.riderLng == null) {
      _map.move(house, 16);
      return;
    }
    final rider = LatLng(widget.riderLat!, widget.riderLng!);
    _map.fitCamera(CameraFit.coordinates(coordinates: [house, rider], padding: const EdgeInsets.all(56), maxZoom: 17));
  }

  @override
  Widget build(BuildContext context) {
    final house = LatLng(widget.lat, widget.lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.height,
        child: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: house,
              initialZoom: 16,
              interactionOptions: InteractionOptions(
                flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
              ),
              onMapReady: () {
                _ready = true;
                _fit();
              },
            ),
            children: [
              osmTiles(),
              MarkerLayer(markers: [
                Marker(point: house, width: 44, height: 44, alignment: Alignment.topCenter, child: housePin()),
                if (widget.riderLat != null && widget.riderLng != null)
                  Marker(point: LatLng(widget.riderLat!, widget.riderLng!), width: 46, height: 46, child: riderPin()),
              ]),
            ],
          ),
          osmAttribution(),
        ]),
      ),
    );
  }
}

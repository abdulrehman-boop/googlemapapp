import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
class MapScreen extends StatefulWidget {
  @override
  State<MapScreen> createState() => MapScreenState();
}
class MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  LatLng? _destination;
  LatLng? _currentPosition;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  StreamSubscription<Position>? _positionStream;
  String _infoText = '';
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _placePredictions = [];
  bool _darkMode = false;
  bool _showTraffic = false;
  final String googleApiKey = 'Your API key';
  @override
  void initState() {    super.initState();
  _determinePosition();
  }
  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) return Future.error('Permissions are permanently denied.');
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) {
        return Future.error('Location permission denied.');
      }
    }
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _addCurrentMarker();
    });
    _positionStream = Geolocator.getPositionStream().listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _updateLiveMarker();
        if (_destination != null) _drawRoute();
      });
    });
  }
  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    if (_darkMode) _setMapStyle(darkMapStyle);
  }
  void _setMapStyle(String style) async {
    mapController.setMapStyle(style);
  }
  void _onMapTapped(LatLng tappedPoint) {
    setState(() {
      _destination = tappedPoint;
      _markers.removeWhere((m) => m.markerId == MarkerId('destination'));
      _markers.add(Marker(
        markerId: MarkerId('destination'),
        position: tappedPoint,
        infoWindow: InfoWindow(title: 'Destination'),
      ));
      _drawRoute();
    });
    mapController.animateCamera(CameraUpdate.newLatLng(tappedPoint));
  }
  void _addCurrentMarker() {
    _markers.add(Marker(
      markerId: MarkerId('current'),
      position: _currentPosition!,
      infoWindow: InfoWindow(title: 'You'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    ));
  }
  void _updateLiveMarker() {
    _markers.removeWhere((m) => m.markerId == MarkerId('current'));
    _addCurrentMarker();
  }
  Future<void> _drawRoute() async {
    if (_currentPosition == null || _destination == null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
          '&destination=${_destination!.latitude},${_destination!.longitude}'
          '&mode=driving&departure_time=$now&key=$googleApiKey',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['routes'].isNotEmpty) {
        final route = data['routes'][0];
        final polyline = route['overview_polyline']['points'];
        final points = decodePolyline(polyline);

        final legs = route['legs'][0];
        final distance = legs['distance']['text'];
        final duration = legs['duration_in_traffic']?['text'] ?? legs['duration']['text'];
        setState(() {
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: PolylineId('drivingRoute'),
            color: Colors.blueAccent,
            width: 6,
            points: points,
          ));
          _infoText = 'ETA (Live): $duration • Distance: $distance';
        });
      }
    }
  }
  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }
  Future<void> _autocompleteSearch(String input) async {
    if (input.isEmpty) return;
    final String url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$googleApiKey&types=geocode';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      setState(() {
        _placePredictions = json['predictions'];
      });
    }
  }
  Future<void> _selectPrediction(String placeId) async {
    final String url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$googleApiKey';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final location = json['result']['geometry']['location'];
      final LatLng newDestination = LatLng(location['lat'], location['lng']);

      _searchController.text = json['result']['name'];
      setState(() {
        _placePredictions.clear();
        _onMapTapped(newDestination);
        mapController.animateCamera(CameraUpdate.newLatLngZoom(newDestination, 14));
      });
    }
  }
  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
  static const String darkMapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [
        {
          "color": "#212121"
        }
      ]
    },
    {
      "elementType": "labels.icon",
      "stylers": [
        {
          "visibility": "off"
        }
      ]
    }
  ]
  ''';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Navigator'),
        backgroundColor: Colors.indigo,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_darkMode ? Icons.dark_mode : Icons.light_mode, color: Colors.white),
            onPressed: () {
              setState(() {
                _darkMode = !_darkMode;
                _setMapStyle(_darkMode ? darkMapStyle : '');
              });
            },
            tooltip: 'Toggle Dark Mode',
          ),
          IconButton(
            icon: Icon(_showTraffic ? Icons.traffic : Icons.traffic_outlined, color: Colors.white),
            onPressed: () {
              setState(() {
                _showTraffic = !_showTraffic;
              });
            },
            tooltip: 'Toggle Traffic Layer',
          ),
        ],
      ),
      body: Stack(
        children: [
          _currentPosition == null
              ? Center(child: CircularProgressIndicator())
              : GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _currentPosition!,
              zoom: 14.0,
            ),
            onTap: _onMapTapped,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            trafficEnabled: _showTraffic,
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _autocompleteSearch,
                    decoration: InputDecoration(
                      hintText: 'Search location...',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (_placePredictions.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _placePredictions.length,
                      itemBuilder: (context, index) {
                        final prediction = _placePredictions[index];
                        return ListTile(
                          leading: Icon(Icons.location_on_outlined, color: Colors.indigo),
                          title: Text(prediction['description']),
                          onTap: () => _selectPrediction(prediction['place_id']),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_infoText.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: Text(
                  _infoText,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
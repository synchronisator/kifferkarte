import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_db_store/dio_cache_interceptor_db_store.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kifferkarte/location_manager.dart';
import 'package:kifferkarte/overpass.dart';
import 'package:kifferkarte/provider_manager.dart';
import 'package:kifferkarte/search.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:polybool/polybool.dart' as polybool;

const double radius = 100.0;

class MapWidget extends ConsumerStatefulWidget {
  MapWidget({super.key});

  @override
  ConsumerState<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends ConsumerState<MapWidget> {
  LocationManager locationManager = LocationManager();
  CacheStore _cacheStore = MemCacheStore();
  final _dio = Dio();
  List<Marker> marker = [];
  List<CircleMarker> circles = [];
  List<Polygon> polys = [];
  @override
  void initState() {
    super.initState();
    LocationManager().determinePosition();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(poiProvider.notifier).getPois();
      if (kIsWeb)
        setState(() {
          // _cacheStore = DbCacheStore(
          //   databasePath: '', // ignored on web
          //   databaseName: 'DbCacheStore',
          // )
          _cacheStore = MemCacheStore();
        });
      else {
        getNormalCache();
      }
      mapController.move(const LatLng(51.351, 10.591), 6);
    });
  }

  Future<void> update() async {
    await ref.read(poiProvider.notifier).getPois();
    await ref.read(wayProvider.notifier).getWays();
    var pois = await ref.read(poiProvider.notifier).getState();
    var ways = await ref.read(wayProvider.notifier).getState();
    getWays(ways);
    getPoiMarker(pois);
    getCircles(pois);
  }

  Future<void> getWays(List<Way> elements) async {
    setState(() {
      polys = elements
          .map((e) => Polygon(
              points: e.boundaries,
              color: Colors.yellow.withOpacity(0.5),
              isFilled: true))
          .toList();
    });
  }

  Future<void> getNormalCache() async {
    Directory path = await getTemporaryDirectory();
    setState(() {
      _cacheStore = DbCacheStore(
        databasePath: path.path,
        databaseName: 'DbCacheStore',
      );
      print("Set cache store");
    });
  }

  void getPoiMarker(List<Poi> elements) {
    setState(() {
      marker = elements
          .where((element) =>
              element.poiElement.lat != null && element.poiElement.lon != null)
          .map((e) => Marker(
                // Experimentation
                // anchorPos: AnchorPos.exactly(Anchor(40, 30)),
                point: LatLng(e.poiElement.lat!, e.poiElement.lon!),
                width: 80,
                height: 80,

                child: const Icon(
                  Icons.location_pin,
                  size: 25,
                  color: Colors.black,
                ),
              ))
          .toList();
    });
  }

  double toRadians(double degree) {
    return degree * pi / 180;
  }

  double toDegrees(double degree) {
    return degree * 180 / pi;
  }

  LatLng offset(LatLng center, double radius, double bearing) {
    double lat1 = toRadians(center.latitude);
    double lon1 = toRadians(center.longitude);
    double dByR = radius /
        6378137; // distance divided by 6378137 (radius of the earth) wgs84
    var lat =
        asin(sin(lat1) * cos(dByR) + cos(lat1) * sin(dByR) * cos(bearing));
    var lon = lon1 +
        atan2(sin(bearing) * sin(dByR) * cos(lat1),
            cos(dByR) - sin(lat1) * sin(lat));
    var offset = LatLng(toDegrees(lat), toDegrees(lon));
    return offset;
  }

  // https://github.com/bcalik/php-circle-to-polygon/blob/master/CircleToPolygon.php
  List<LatLng> circleToPolygon(
      LatLng center, double radius, int numberOfSegments) {
    List<LatLng> coordinates = [];
    for (int i = 0; i < numberOfSegments; i++) {
      coordinates.add(offset(center, radius, 2 * pi * i / numberOfSegments));
    }
    return coordinates;
  }

  void getCircles(List<Poi> elements) {
    Map<LatLng, CircleMarker> circleMarker = Map();
    for (Poi poi in elements) {
      if (poi.poiElement.lat == null || poi.poiElement.lon == null) continue;
      LatLng position = LatLng(poi.poiElement.lat!, poi.poiElement.lon!);
      circleMarker[position] = CircleMarker(
          // Experimentation
          // anchorPos: AnchorPos.exactly(Anchor(40, 30)),
          point: position,
          color: Colors.red.withOpacity(0.25),
          borderColor: Colors.red,
          borderStrokeWidth: 3,
          radius: radius,
          useRadiusInMeter: true);
    }
    List<Poi> intersected = [];
    List<Polygon> unioned = [];
    for (Poi poi in elements) {
      if (poi.poiElement.lat == null || poi.poiElement.lon == null) continue;
      List<polybool.Polygon> intersecting = [];
      polybool.Polygon? unitedPoly;
      for (Poi poi2 in elements) {
        if (poi2.poiElement.lat == null || poi2.poiElement.lon == null)
          continue;
        LatLng position = LatLng(poi.poiElement.lat!, poi.poiElement.lon!);
        Distance distance = new Distance();
        if (distance.as(LengthUnit.Meter, position,
                LatLng(poi.poiElement.lat!, poi.poiElement.lon!)) <=
            radius * 2) {
          List<LatLng> points = circleToPolygon(position, radius, 32);
          circleMarker.remove(position);
          intersected.add(poi2);
          intersecting.add(polybool.Polygon(regions: [
            points
                .map((e) => polybool.Coordinate(e.latitude, e.longitude))
                .toList()
          ]));
        }
      }
      for (int i = 0; i < intersecting.length; i++) {
        if (unitedPoly == null) {
          unitedPoly = intersecting[i];
        } else {
          unitedPoly = unitedPoly.union(intersecting[i]);
        }
      }
      if (unitedPoly != null && unitedPoly.regions.length > 0) {
        unioned.add(Polygon(
            points:
                unitedPoly!.regions.first.map((e) => LatLng(e.x, e.y)).toList(),
            color: Colors.red.withOpacity(0.25),
            borderColor: Colors.red,
            borderStrokeWidth: 3,
            isFilled: true));
        print("Poly");
      }
    }
    setState(() {
      circles = [];
      // circles = circleMarker.values.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
            mapController: mapController,
            children: [
              TileLayer(
                  maxZoom: 19,
                  minZoom: 0,
                  userAgentPackageName: "pro.obco.kifferkarte",
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  tileProvider: CachedTileProvider(
                      dio: _dio,
                      // maxStale keeps the tile cached for the given Duration and
                      // tries to revalidate the next time it gets requested
                      maxStale: const Duration(days: 30),
                      store: _cacheStore)),
              CurrentLocationLayer(
                alignPositionOnUpdate: AlignOnUpdate.always,
                alignDirectionOnUpdate: AlignOnUpdate.always,
              ),
              PolygonLayer(
                polygons: polys,
                polygonCulling: true,
              ),
              MarkerLayer(
                markers: marker,
              ),
              CircleLayer(circles: circles),
              RichAttributionWidget(
                animationConfig:
                    const ScaleRAWA(), // Or `FadeRAWA` as is default
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () => launchUrl(
                        Uri.parse('https://openstreetmap.org/copyright')),
                  ),
                ],
              ),
            ],
            options: MapOptions(
              maxZoom: 19,
              minZoom: 0,
              onPointerUp: (event, point) async {
                await update();
              },
            )),
        Positioned(
            bottom: 50,
            right: 10,
            child: FloatingActionButton(
              heroTag: "myLocation",
              child: const Icon(Icons.my_location),
              onPressed: () async {
                Position? position;
                position = await locationManager.determinePosition().timeout(
                  Duration(seconds: 5),
                  onTimeout: () {
                    position = locationManager.lastPosition;
                  },
                );
                if (position == null) {
                  print(locationManager.lastPosition);
                  if (locationManager.lastPosition != null) {
                    position = locationManager.lastPosition;
                  } else {
                    print("no position");
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Could ne get Position")));
                    return;
                  }
                } else {
                  print("yeah");
                }
                mapController.move(
                    LatLng(position!.latitude, position!.longitude),
                    mapController.camera.zoom);
              },
            )),
        Positioned(
            bottom: 120,
            right: 10,
            child: FloatingActionButton(
              heroTag: "vibrate",
              child: Icon(locationManager.listeningToPosition
                  ? (Icons.smartphone)
                  : (Icons.vibration)),
              onPressed: () async {
                if (locationManager.listeningToPosition) {
                  locationManager.stopPositionCheck(ref);
                } else {
                  locationManager.startPositionCheck(ref);
                }
              },
            )),
        Positioned(
            top: 10,
            right: 10,
            child: FloatingActionButton(
              heroTag: "zoomUp",
              child: const Icon(Icons.add),
              onPressed: () async {
                mapController.move(
                    mapController.camera.center, mapController.camera.zoom + 1);
                await update();
              },
            )),
        Positioned(
            top: 80,
            right: 10,
            child: FloatingActionButton(
              heroTag: "zoomDown",
              child: const Icon(Icons.remove),
              onPressed: () async {
                mapController.move(
                    mapController.camera.center, mapController.camera.zoom - 1);

                await update();
              },
            )),
        Positioned(
            top: 10,
            left: 10,
            child: FloatingActionButton(
              heroTag: "Search",
              child: const Icon(Icons.search),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => SearchView(
                    locationManager: locationManager,
                  ),
                ));
              },
            ))
      ],
    );
  }
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_dragmarker/dragmarker.dart';
import 'package:flutter_map_line_editor/polyeditor.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:geolocator/geolocator.dart';

// providers
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/chat.dart';
import 'package:xcnav/providers/settings.dart';

// widgets
import 'package:xcnav/widgets/waypoint_card.dart';
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_button.dart';
import 'package:xcnav/widgets/chat_bubble.dart';
import 'package:xcnav/widgets/map_marker.dart';

// dialogs
import 'package:xcnav/dialogs/fuel_adjustment.dart';
import 'package:xcnav/dialogs/edit_waypoint.dart';

// models
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';

import 'package:xcnav/fake_path.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum FocusMode {
  unlocked,
  me,
  group,
  addWaypoint,
  addPath,
  editPath,
}

class _MyHomePageState extends State<MyHomePage> {
  late MapController mapController;
  FocusMode focusMode = FocusMode.me;
  FocusMode prevFocusMode = FocusMode.me;

  static TextStyle instrLower = const TextStyle(fontSize: 35);
  static TextStyle instrUpper = const TextStyle(fontSize: 40);
  static TextStyle instrLabel = const TextStyle(
      fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic);

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  bool positionStreamStarted = false;

  late PolyEditor polyEditor;

  List<Polyline> polyLines = [];
  var editablePolyline =
      Polyline(color: Colors.amber, points: [], strokeWidth: 5);

  @override
  _MyHomePageState();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _toggleServiceStatusStream();

    positionStreamStarted = !positionStreamStarted;
    _toggleListening();

    // intialize the controllers
    mapController = MapController();

    polyEditor = PolyEditor(
      addClosePathMarker: false,
      points: editablePolyline.points,
      pointIcon: const Icon(
        Icons.crop_square,
        size: 23,
        color: Colors.black,
      ),
      intermediateIcon: const Icon(Icons.lens, size: 15, color: Colors.black),
      callbackRefresh: () => {setState(() {})},
    );

    polyLines.add(editablePolyline);

    // --- Location Spoofer for debugging
    FakeFlight fakeFlight = FakeFlight();
    Timer? timer;
    Provider.of<Settings>(context, listen: false).addListener(() {
      if (Provider.of<Settings>(context, listen: false).spoofLocation) {
        if (timer == null) {
          debugPrint("--- Starting Location Spoofer ---");
          timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
            Provider.of<MyTelemetry>(context, listen: false).updateGeo(
                Geo.fromPosition(fakeFlight.genFakeLocationFlight(),
                    Provider.of<MyTelemetry>(context, listen: false).geo));
            refreshMapView();
          });
        }
      } else {
        if (timer != null) {
          debugPrint("--- Stopping Location Spoofer ---");
          timer?.cancel();
          timer = null;
        }
      }
    });
  }

  void _toggleServiceStatusStream() {
    if (_serviceStatusStreamSubscription == null) {
      final serviceStatusStream = _geolocatorPlatform.getServiceStatusStream();
      _serviceStatusStreamSubscription =
          serviceStatusStream.handleError((error) {
        _serviceStatusStreamSubscription?.cancel();
        _serviceStatusStreamSubscription = null;
      }).listen((serviceStatus) {
        String serviceStatusValue;
        if (serviceStatus == ServiceStatus.enabled) {
          if (positionStreamStarted) {
            _toggleListening();
          }
          serviceStatusValue = 'enabled';
        } else {
          if (_positionStreamSubscription != null) {
            setState(() {
              _positionStreamSubscription?.cancel();
              _positionStreamSubscription = null;
              debugPrint('Position Stream has been canceled');
            });
          }
          serviceStatusValue = 'disabled';
        }
        debugPrint('Location service has been $serviceStatusValue');
      });
    }
  }

  void _toggleListening() {
    if (_positionStreamSubscription == null) {
      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 10,
            forceLocationManager: false,
            intervalDuration: const Duration(seconds: 5),
            //(Optional) Set foreground notification config to keep the app alive
            //when going to the background
            foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationText: "Still sending your position to the group.",
                notificationTitle: "xcNav",
                // TODO: this is broken in the lib right now.
                // notificationIcon:  name: "assets/images/xcnav.logo.wing.bw.png"}));
                enableWakeLock: true));
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          activityType: ActivityType.fitness,
          distanceFilter: 10,
          pauseLocationUpdatesAutomatically: false,
          // Only set to true if our app will be started up in the background.
          showBackgroundLocationIndicator: false,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
      }

      final positionStream = _geolocatorPlatform.getPositionStream(
          locationSettings: locationSettings);
      _positionStreamSubscription = positionStream.handleError((error) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
      }).listen((position) => {handleGeomUpdate(context, position)});
      _positionStreamSubscription?.pause();
    }

    setState(() {
      if (_positionStreamSubscription == null) {
        return;
      }

      String statusDisplayValue;
      if (_positionStreamSubscription!.isPaused) {
        _positionStreamSubscription!.resume();
        statusDisplayValue = 'resumed';
      } else {
        _positionStreamSubscription!.pause();
        statusDisplayValue = 'paused';
      }

      debugPrint('Listening for position updates $statusDisplayValue');
    });
  }

  void handleGeomUpdate(BuildContext context, Position geo) {
    Provider.of<MyTelemetry>(context, listen: false).updateGeo(Geo.fromPosition(
        geo, Provider.of<MyTelemetry>(context, listen: false).geo));
    refreshMapView();
  }

  void setFocusMode(FocusMode mode, [LatLng? center]) {
    setState(() {
      prevFocusMode = focusMode;
      focusMode = mode;
      debugPrint("FocusMode = $mode");
    });
    refreshMapView();
  }

  void refreshMapView() {
    Geo geo = Provider.of<MyTelemetry>(context, listen: false).geo;
    CenterZoom? centerZoom;
    if (focusMode == FocusMode.me) {
      centerZoom = CenterZoom(
          center: LatLng(geo.lat, geo.lng), zoom: mapController.zoom);
    } else if (focusMode == FocusMode.group) {
      List<LatLng> points = Provider.of<Group>(context, listen: false)
          .pilots
          // Don't consider telemetry older than 2 minutes
          .values
          .where((_p) =>
              _p.geo.time > DateTime.now().millisecondsSinceEpoch - 2000 * 60)
          .map((e) => e.geo.latLng)
          .toList();
      points.add(LatLng(geo.lat, geo.lng));
      centerZoom = mapController.centerZoomFitBounds(
          LatLngBounds.fromPoints(points),
          options:
              const FitBoundsOptions(padding: EdgeInsets.all(80), maxZoom: 13));
    } else {
      centerZoom =
          CenterZoom(center: mapController.center, zoom: mapController.zoom);
    }
    mapController.move(centerZoom.center, centerZoom.zoom);
  }

  void onMapTap(BuildContext context, LatLng latlng) {
    debugPrint("onMapTap: $latlng");
    if (focusMode == FocusMode.addWaypoint) {
      // --- Finish adding waypoint pin
      setFocusMode(prevFocusMode);
      editWaypoint(context, true, [latlng]);
    } else if (focusMode == FocusMode.addPath ||
        focusMode == FocusMode.editPath) {
      // --- Add waypoint in path
      polyEditor.add(editablePolyline.points, latlng);
    }
  }

  void onMapLongPress(BuildContext context, LatLng latlng) {}

  // --- Flight Plan Menu
  void showFlightPlan() {
    // TODO: move map view to see whole flight plan?
    showModalBottomSheet(
        context: context,
        elevation: 0,
        constraints: const BoxConstraints(maxHeight: 500),
        builder: (BuildContext context) {
          return Consumer<ActivePlan>(
            builder: (context, plan, child) => Column(
              children: [
                // Waypoint menu buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // --- Add New Waypoint
                    IconButton(
                        iconSize: 25,
                        onPressed: () {
                          Navigator.pop(context);
                          setFocusMode(FocusMode.addWaypoint);
                        },
                        icon: const ImageIcon(
                            AssetImage("assets/images/add_waypoint_pin.png"),
                            color: Colors.lightGreen)),
                    // --- Add New Path
                    IconButton(
                        iconSize: 25,
                        onPressed: () {
                          editablePolyline.points.clear();
                          Navigator.pop(context);
                          setFocusMode(FocusMode.addPath);
                        },
                        icon: const ImageIcon(
                            AssetImage("assets/images/add_waypoint_path.png"),
                            color: Colors.yellow)),
                    // --- Edit Waypoint
                    IconButton(
                      iconSize: 25,
                      onPressed: () => editWaypoint(
                        context,
                        false,
                        plan.selectedWp?.latlng ?? [],
                        editPointsCallback: () {
                          editablePolyline.points.clear();
                          editablePolyline.points
                              .addAll(plan.selectedWp?.latlng ?? []);
                          Navigator.popUntil(
                              context, ModalRoute.withName("/home"));
                          setFocusMode(FocusMode.editPath);
                        },
                      ),
                      icon: const Icon(Icons.edit),
                    ),
                    // --- Delete Selected Waypoint
                    IconButton(
                        iconSize: 25,
                        onPressed: () => plan.removeSelectedWaypoint(),
                        icon: const Icon(Icons.delete, color: Colors.red)),
                  ],
                ),
                // --- Waypoint list
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: plan.waypoints.length,
                    itemBuilder: (context, i) => WaypointCard(
                      key: ValueKey(plan.waypoints[i]),
                      waypoint: plan.waypoints[i],
                      index: i,
                      onSelect: () {
                        debugPrint("Selected $i");
                        plan.selectWaypoint(i);
                      },
                      onToggleOptional: () {
                        plan.toggleOptional(i);
                      },
                      isSelected: i == plan.selectedIndex,
                    ),
                    onReorder: (oldIndex, newIndex) {
                      debugPrint("WP order: $oldIndex --> $newIndex");
                      plan.sortWaypoint(oldIndex, newIndex);
                    },
                  ),
                ),
              ],
            ),
          );
        });
  }

  ///////////////////////////////////////////////////////////////////////////////////////////////////////
  //
  //
  // Main Build
  //
  //
  ///////////////////////////////////////////////////////////////////////////////////////////////////////
  @override
  Widget build(BuildContext context) {
    debugPrint("Build /home");
    return Scaffold(
        appBar: AppBar(
            // Here we take the value from the MyHomePage object that was created by
            // the App.build method, and use it to set our appbar title.
            automaticallyImplyLeading: true,
            leadingWidth: 35,
            toolbarHeight: 64,
            // leading: IconButton(
            //   padding: EdgeInsets.zero,
            //   icon: const Icon(
            //     Icons.menu,
            //     color: Colors.grey,
            //   ),
            //   onPressed: () => {},
            // ),
            title: SizedBox(
              height: 64,
              child: Consumer<MyTelemetry>(
                builder: (context, myTelementy, child) => Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // --- Speedometer
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: (myTelementy.geo.spd * 3.6 * km2Miles)
                                  .toStringAsFixed(0),
                              style: instrUpper,
                            ),
                            TextSpan(
                              text: " mph",
                              style: instrLabel,
                            )
                          ])),
                          const SizedBox(
                              height: 100,
                              child: VerticalDivider(
                                  thickness: 2, color: Colors.black)),
                          // --- Altimeter
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: (myTelementy.geo.alt * meters2Feet)
                                  .toStringAsFixed(0),
                              style: instrUpper,
                            ),
                            TextSpan(text: " ft", style: instrLabel)
                          ])),
                          const SizedBox(
                              height: 100,
                              child: VerticalDivider(
                                  thickness: 2, color: Colors.black)),
                          // --- Vario
                          Text.rich(TextSpan(children: [
                            TextSpan(
                              text: (myTelementy.geo.vario * meters2Feet * 60)
                                  .toStringAsFixed(0),
                              style: instrUpper
                                  .merge(const TextStyle(fontSize: 30)),
                            ),
                            TextSpan(text: " ft/m", style: instrLabel)
                          ])),
                        ])),
              ),
            )),
        drawer: Drawer(
            child: ListView(
          children: [
            // --- Profile (menu header)
            SizedBox(
              height: 110,
              child: DrawerHeader(
                  padding: EdgeInsets.zero,
                  child: Stack(children: [
                    Positioned(
                      left: 10,
                      top: 10,
                      child:
                          AvatarRound(Provider.of<Profile>(context).avatar, 40),
                    ),
                    Positioned(
                      left: 100,
                      right: 10,
                      top: 10,
                      bottom: 10,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text(
                              Provider.of<Profile>(context).name ?? "???",
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.start,
                              style: Theme.of(context).textTheme.headline4,
                            ),
                          ]),
                    ),
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton(
                          iconSize: 20,
                          icon: Icon(
                            Icons.edit,
                            color: Colors.grey[700],
                          ),
                          onPressed: () {
                            Navigator.pushNamed(context, "/profileEditor");
                          },
                        ))
                  ])),
            ),

            // --- Map tile-layer selection
            ListTile(
              minVerticalPadding: 20,
              leading: const Icon(
                Icons.local_airport,
                size: 30,
              ),
              title: Text(" Airspace",
                  style: Theme.of(context).textTheme.headline5),
              trailing: Switch(
                value: Provider.of<Settings>(context).showAirspace,
                onChanged: (value) => {
                  Provider.of<Settings>(context, listen: false).showAirspace =
                      value
                },
              ),
            ),

            const Divider(
              height: 20,
            ),

            ListTile(
              minVerticalPadding: 20,
              onTap: () => {Navigator.pushNamed(context, "/groupDetails")},
              leading: const Icon(
                Icons.groups,
                size: 30,
              ),
              title: Text(
                "Group",
                style: Theme.of(context).textTheme.headline5,
              ),
            ),

            ListTile(
              minVerticalPadding: 20,
              onTap: () => {Navigator.pushNamed(context, "/plans")},
              leading: const Icon(
                Icons.pin_drop,
                size: 30,
              ),
              title: Text(
                "Plans",
                style: Theme.of(context).textTheme.headline5,
              ),
            ),

            ListTile(
                minVerticalPadding: 20,
                onTap: () => {Navigator.pushNamed(context, "/flightLogs")},
                leading: const Icon(
                  Icons.menu_book,
                  size: 30,
                ),
                title: Text("History",
                    style: Theme.of(context).textTheme.headline5)),
            ListTile(
                minVerticalPadding: 20,
                onTap: () => {Navigator.pushNamed(context, "/settings")},
                leading: const Icon(
                  Icons.settings,
                  size: 30,
                ),
                title: Text("Settings",
                    style: Theme.of(context).textTheme.headline5)),
          ],
        )),
        body: Center(
          child: Stack(alignment: Alignment.center, children: [
            Consumer3<MyTelemetry, Settings, ActivePlan>(
              builder: (context, myTelemetry, settings, plan, child) =>
                  FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  interactiveFlags:
                      InteractiveFlag.all & ~InteractiveFlag.rotate,
                  center: myTelemetry.geo.latLng,
                  zoom: 12.0,
                  onTap: (tapPosition, point) => onMapTap(context, point),
                  onLongPress: (tapPosition, point) =>
                      onMapLongPress(context, point),
                  onPositionChanged: (mapPosition, hasGesture) {
                    // debugPrint("$mapPosition $hasGesture");
                    if (hasGesture &&
                        (focusMode == FocusMode.me ||
                            focusMode == FocusMode.group)) {
                      // --- Unlock any focus lock
                      setFocusMode(FocusMode.unlocked);
                    }
                  },
                  allowPanningOnScrollingParent: false,
                  plugins: [
                    DragMarkerPlugin(),
                  ],
                ),
                layers: [
                  TileLayerOptions(
                    // urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                    // subdomains: ['a', 'b', 'c'],
                    urlTemplate:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
                    // tileSize: 512,
                    // zoomOffset: -1,
                  ),

                  if (settings.showAirspace)
                    TileLayerOptions(
                      urlTemplate:
                          'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airports@EPSG%3A900913@png/{z}/{x}/{y}.png',
                      maxZoom: 17,
                      tms: true,
                      subdomains: ['1', '2'],
                      backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                    ),
                  if (settings.showAirspace)
                    TileLayerOptions(
                      urlTemplate:
                          'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_geometries@EPSG%3A900913@png/{z}/{x}/{y}.png',
                      maxZoom: 17,
                      tms: true,
                      subdomains: ['1', '2'],
                      backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                    ),
                  if (settings.showAirspace)
                    TileLayerOptions(
                      urlTemplate:
                          'https://{s}.tile.maps.openaip.net/geowebcache/service/tms/1.0.0/openaip_approved_airspaces_labels@EPSG%3A900913@png/{z}/{x}/{y}.png',
                      maxZoom: 17,
                      tms: true,
                      subdomains: ['1', '2'],
                      backgroundColor: const Color.fromARGB(0, 255, 255, 255),
                    ),

                  // Flight Log
                  PolylineLayerOptions(
                      polylines: [myTelemetry.buildFlightTrace()]),

                  // Trip snake lines
                  PolylineLayerOptions(polylines: plan.buildTripSnake()),

                  PolylineLayerOptions(
                    polylines: [plan.buildNextWpIndicator(myTelemetry.geo)],
                  ),

                  // Flight plan paths
                  PolylineLayerOptions(
                    polylines: plan.waypoints
                        .where((value) => value.latlng.length > 1)
                        .mapIndexed((i, e) => Polyline(
                            points: e.latlng,
                            strokeWidth: 6,
                            color: Color(e.color ?? Colors.black.value)))
                        .toList(),
                  ),

                  // Flight plan markers
                  DragMarkerPluginOptions(
                    markers: plan.waypoints
                        .mapIndexed((i, e) => e.latlng.length == 1
                            ? DragMarker(
                                point: e.latlng[0],
                                height: 60 * 0.8,
                                width: 40 * 0.8,
                                onTap: (_) => plan.selectWaypoint(i),
                                onDragEnd: (p0, p1) => {
                                      plan.moveWaypoint(i, [p1])
                                    },
                                builder: (context) => MapMarker(e, 60 * 0.8))
                            : null)
                        .whereNotNull()
                        .toList(),
                  ),

                  // Live locations other pilots
                  MarkerLayerOptions(
                    markers: Provider.of<Group>(context)
                        .pilots
                        // Don't share locations older than 5minutes
                        .values
                        .where((_p) =>
                            _p.geo.time >
                            DateTime.now().millisecondsSinceEpoch - 5000 * 60)
                        .toList()
                        .map((pilot) => Marker(
                            point: pilot.geo.latLng,
                            width: 40,
                            height: 40,
                            builder: (ctx) => Container(
                                transformAlignment: const Alignment(0, 0),
                                child: AvatarRound(pilot.avatar, 40))))
                        .toList(),
                  ),

                  // "ME" Live Location Marker
                  MarkerLayerOptions(
                    markers: [
                      Marker(
                        width: 50.0,
                        height: 50.0,
                        point: myTelemetry.geo.latLng,
                        builder: (ctx) => Container(
                          transformAlignment: const Alignment(0, 0),
                          child: Image.asset("assets/images/red_arrow.png"),
                          transform: Matrix4.rotationZ(myTelemetry.geo.hdg),
                        ),
                      ),
                    ],
                  ),

                  // Draggable line editor
                  if (focusMode == FocusMode.addPath ||
                      focusMode == FocusMode.editPath)
                    PolylineLayerOptions(polylines: polyLines),
                  if (focusMode == FocusMode.addPath ||
                      focusMode == FocusMode.editPath)
                    DragMarkerPluginOptions(markers: polyEditor.edit()),
                ],
              ),
            ),

            // --- Chat bubbles
            Consumer<Chat>(
              builder: (context, chat, child) {
                // get valid bubbles
                const numSeconds = 10;
                List<Message> bubbles = [];
                for (int i = chat.messages.length - 1; i > 0; i--) {
                  if (chat.messages[i].timestamp >
                      max(
                          DateTime.now().millisecondsSinceEpoch -
                              1000 * numSeconds,
                          chat.chatLastOpened)) {
                    bubbles.add(chat.messages[i]);
                    // "self destruct" the message after several seconds
                    Timer _hideBubble =
                        Timer(const Duration(seconds: numSeconds), () {
                      // TODO: This is prolly hacky... but it works for now
                      chat.notifyListeners();
                    });
                  } else {
                    break;
                  }
                }
                return Positioned(
                    right: 0,
                    bottom: 0,
                    // left: 100,
                    child: Column(
                      verticalDirection: VerticalDirection.up,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: bubbles
                          .map(
                            (e) => ChatBubble(
                                false,
                                e.text,
                                AvatarRound(
                                    Provider.of<Group>(context, listen: false)
                                            .pilots[e.pilotId]
                                            ?.avatar ??
                                        Image.asset(
                                            "assets/images/default_avatar.png"),
                                    20),
                                null,
                                e.timestamp),
                          )
                          .toList(),
                    ));
              },
            ),

            // --- Map overlay layers
            if (focusMode == FocusMode.addWaypoint)
              const Positioned(
                bottom: 15,
                child: Card(
                  color: Colors.amber,
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text.rich(
                      TextSpan(children: [
                        WidgetSpan(
                            child: Icon(
                          Icons.touch_app,
                          size: 20,
                          color: Colors.black,
                        )),
                        TextSpan(text: "Tap to place waypoint")
                      ]),
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                      // textAlign: TextAlign.justify,
                    ),
                  ),
                ),
              ),
            if (focusMode == FocusMode.addPath ||
                focusMode == FocusMode.editPath)
              Positioned(
                bottom: 15,
                right: 20,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Card(
                      color: Colors.amber,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text.rich(
                          TextSpan(children: [
                            WidgetSpan(
                                child: Icon(
                              Icons.touch_app,
                              size: 20,
                              color: Colors.black,
                            )),
                            TextSpan(text: "Tap to add to path")
                          ]),
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                          // textAlign: TextAlign.justify,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 45,
                      icon: const Icon(
                        Icons.cancel,
                        size: 45,
                        color: Colors.red,
                      ),
                      onPressed: () => {setFocusMode(prevFocusMode)},
                    ),
                    if (editablePolyline.points.length > 1)
                      IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 45,
                        icon: const Icon(
                          Icons.check_circle,
                          size: 45,
                          color: Colors.green,
                        ),
                        onPressed: () {
                          // --- finish editing path
                          editWaypoint(context, focusMode == FocusMode.addPath,
                              editablePolyline.points);
                          setFocusMode(prevFocusMode);
                        },
                      ),
                  ],
                ),
              ),

            // --- Map View Buttons
            Positioned(
              left: 0,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(5, 20, 0, 0),
                        child: MapButton(
                          size: 60,
                          selected: focusMode == FocusMode.me,
                          child: Image.asset(
                              "assets/images/icon_controls_centermap_me.png"),
                          onPressed: () => setFocusMode(
                              FocusMode.me,
                              Provider.of<MyTelemetry>(context, listen: false)
                                  .geo
                                  .latLng),
                        )),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 30, 0, 20),
                      child: MapButton(
                        size: 60,
                        selected: focusMode == FocusMode.group,
                        onPressed: () => setFocusMode(FocusMode.group),
                        child: Image.asset(
                            "assets/images/icon_controls_centermap_group.png"),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 60, 0, 0),
                      child: MapButton(
                        size: 60,
                        selected: false,
                        onPressed: () => {
                          mapController.move(
                              mapController.center, mapController.zoom + 1)
                        },
                        child: Image.asset(
                            "assets/images/icon_controls_zoom_in.png"),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(5, 30, 0, 20),
                      child: MapButton(
                        size: 60,
                        selected: false,
                        onPressed: () => {
                          mapController.move(
                              mapController.center, mapController.zoom - 1)
                        },
                        child: Image.asset(
                            "assets/images/icon_controls_zoom_out.png"),
                      ),
                    ),
                  ]),
            ),

            // --- Chat button
            Positioned(
                bottom: 10,
                left: 5,
                child: MapButton(
                  size: 60,
                  selected: false,
                  onPressed: () => {Navigator.pushNamed(context, "/party")},
                  child: const Icon(
                    Icons.chat,
                    size: 30,
                    color: Colors.black,
                  ),
                )),
            if (Provider.of<Chat>(context).numUnread > 0)
              Positioned(
                  bottom: 10,
                  left: 50,
                  child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.all(Radius.circular(10))),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(
                          "${Provider.of<Chat>(context).numUnread}",
                          style: const TextStyle(fontSize: 20),
                        ),
                      ))),

            // --- Connection status banner (along top of map)
            if (Provider.of<Client>(context).state == ClientState.disconnected)
              const Positioned(
                  top: 5,
                  child: Card(
                      color: Colors.amber,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(10, 4, 10, 4),
                        child: Text.rich(
                          TextSpan(children: [
                            WidgetSpan(
                                child: Icon(
                              Icons.language,
                              size: 20,
                              color: Colors.black,
                            )),
                            TextSpan(
                                text: "  connecting",
                                style: TextStyle(
                                    color: Colors.black, fontSize: 20)),
                          ]),
                        ),
                      )))
          ]),
        ),

        // --- Bottom Instruments
        bottomNavigationBar: Consumer2<ActivePlan, MyTelemetry>(
            builder: (context, activePlan, myTelemetry, child) {
          debugPrint("Update ETA");
          ETA etaNext = activePlan.selectedIndex != null
              ? activePlan.etaToWaypoint(myTelemetry.geo, myTelemetry.geo.spd,
                  activePlan.selectedIndex!)
              : ETA(0, 0);
          ETA etaTrip = activePlan.etaToTripEnd(
              myTelemetry.geo.spd, activePlan.selectedIndex ?? 0);
          etaTrip += etaNext;

          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              mainAxisSize: MainAxisSize.max,
              children: [
                // --- Fuel Indicator
                Flexible(
                  flex: 2,
                  fit: FlexFit.loose,
                  child: GestureDetector(
                    onTap: () => {showFuelDialog(context)},
                    child: Card(
                      color: myTelemetry.fuelIndicatorColor(etaNext, etaTrip),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Fuel",
                              style: instrLabel,
                            ),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                      text: myTelemetry.fuel.toStringAsFixed(1),
                                      style: instrLower),
                                  TextSpan(text: " L", style: instrLabel)
                                ],
                              ),
                              softWrap: false,
                            ),
                            myTelemetry.fuel > 0
                                ? Text(
                                    myTelemetry.fuelTimeRemaining(),
                                    style: instrLower,
                                  )
                                : Text(
                                    "-:--",
                                    style: instrLower.merge(
                                        TextStyle(color: Colors.grey[600])),
                                  )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                    height: 100,
                    width: 2,
                    child: VerticalDivider(thickness: 2, color: Colors.black)),

                // --- ETA to next waypoint
                Flexible(
                  fit: FlexFit.tight,
                  flex: 2,
                  child: GestureDetector(
                      onTap: showFlightPlan,
                      child: (activePlan.selectedIndex != null)
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                  Text(
                                    "ETA next",
                                    style: instrLabel,
                                  ),
                                  Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: etaNext.miles(),
                                        style: instrLower),
                                    TextSpan(text: " mi", style: instrLabel)
                                  ])),
                                  myTelemetry.inFlight
                                      ? Text(
                                          etaNext.hhmm(),
                                          style: instrLower,
                                        )
                                      : Text(
                                          "-:--",
                                          style: instrLower.merge(TextStyle(
                                              color: Colors.grey[600])),
                                        ),
                                ])
                          : Text(
                              "Select\nWaypoint",
                              style: instrLabel,
                              textAlign: TextAlign.center,
                            )),
                ),

                const SizedBox(
                    height: 100,
                    width: 2,
                    child: VerticalDivider(thickness: 2, color: Colors.black)),

                // --- Trip Time Remaining
                Flexible(
                  flex: 2,
                  fit: FlexFit.tight,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "ETA trip",
                          style: instrLabel,
                        ),
                        Text.rich(TextSpan(children: [
                          TextSpan(text: etaTrip.miles(), style: instrLower),
                          TextSpan(text: " mi", style: instrLabel)
                        ])),
                        myTelemetry.inFlight
                            ? Text(
                                etaTrip.hhmm(),
                                style: instrLower,
                              )
                            : Text(
                                "-:--",
                                style: instrLower
                                    .merge(TextStyle(color: Colors.grey[600])),
                              ),
                      ]),
                )
              ],
            ),
          );
        }));
  }
}

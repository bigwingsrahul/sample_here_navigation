import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart' hide LocationAccuracy;
import 'package:here_sdk/core.engine.dart';
import 'package:here_sdk/core.errors.dart';
import 'package:here_sdk/location.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/core.dart' as here;
import 'package:here_sdk/prefetcher.dart';
import 'package:here_sdk/routing.dart' as here; // Alias for here SDK
import 'package:here_sdk/navigation.dart' as here;
import 'package:here_sdk/routing.dart';
import 'package:navigation_sample/main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:navigation_sample/helper/positioning_provider.dart';
import 'package:navigation_sample/helper/utils.dart';

class NavigateToPlace extends StatefulWidget {
  final here.GeoCoordinates destination;
  const NavigateToPlace({super.key, required this.destination});

  @override
  State<NavigateToPlace> createState() => _NavigateToPlaceState();
}

class _NavigateToPlaceState extends State<NavigateToPlace>
    implements here.LocationListener, LocationStatusListener {
  late RoutingEngine routingEngine;
  here.VisualNavigator? _visualNavigator;
  here.LocationSimulator? _locationSimulator;
  late LocationEngine _locationEngine;
  HereMapController? mapController;
  String currentManeuverText = "";
  int _previousManeuverIndex = -1;
  String distanceLeft = "0 m";
  String durationLeft = "0 sec";
  int durationLeftInSeconds = 0;
  here.ManeuverAction? currentManeuverAction;
  bool canCheck = false;
  final RoutePrefetcher _routePrefetcher = RoutePrefetcher(SDKNativeEngine.sharedInstance!);
  final HEREPositioningProvider _herePositioningProvider =
      HEREPositioningProvider();

  @override
  void initState() {
    super.initState();
    routingEngine = RoutingEngine();
    _locationEngine = LocationEngine();
    SchedulerBinding.instance.addPersistentFrameCallback((duration) {
      if (canCheck && durationLeftInSeconds == 0) {
        canCheck = false;
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Stack(
        children: [
          HereMap(
            onMapCreated: _onMapCreated,
          ),
          if (currentManeuverText.isNotEmpty)
            Positioned(
              top: 64,
              left: 16,
              right: 16,
              child: Container(
                width: size.width,
                height: size.height * 0.13,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.green.shade800),
                child: Row(
                  children: [
                    currentManeuverAction == null
                        ? const SizedBox.shrink()
                        : SvgPicture.asset(
                            "assets/images/${getIconName(currentManeuverAction!)}",
                            width: 48,
                            height: 48,
                          ),
                    8.width,
                    Expanded(
                      child: Text(
                        currentManeuverText,
                        style: TextStyle(color: Colors.white, fontSize: 18)
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (currentManeuverText.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                durationLeft, style: TextStyle(color: Colors.white, fontSize: 22)
                              ),
                              8.width,
                              Text("($distanceLeft)", style: TextStyle(color: Colors.white, fontSize: 16)),
                              12.height,
                              Text("Est. time : ${DateFormat("hh:mm a").format(DateTime.now().add(Duration(seconds: durationLeftInSeconds)))}",
                                  style: TextStyle(color: Colors.white, fontSize: 16)),
                            ],
                          ),
                        ),
                        12.width,
                        GestureDetector(
                          onTap: () {
                            _visualNavigator?.stopRendering();
                            stopLocating();
                            // _locationSimulator?.stop();
                            Navigator.pop(context);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100),
                                color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 24),
                            child: const Text(
                              "Exit", style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            )
        ],
      ),
    );
  }

  _setupLocationSource(here.LocationListener locationListener, here.Route route) {
    try {
      // Provides fake GPS signals based on the route geometry.
      _locationSimulator = here.LocationSimulator.withRoute(route, here.LocationSimulatorOptions());
    } on InstantiationException {
      throw Exception("Initialization of LocationSimulator failed.");
    }

    _locationSimulator!.listener = locationListener;
    _locationSimulator!.start();
  }

  void startLocating() {
    _locationEngine.addLocationListener(this);
    _locationEngine.addLocationStatusListener(this);
    _locationEngine.startWithLocationAccuracy(LocationAccuracy.navigation);
  }

  void stopLocating() {
    _locationEngine.removeLocationStatusListener(this);
    _locationEngine.removeLocationListener(this);
    _locationEngine.stop();
    _herePositioningProvider.stop();
  }

  @override
  void dispose() {
    _visualNavigator?.stopRendering();
    stopLocating();
    // _locationSimulator?.stop();
    super.dispose();
  }

  void _onMapCreated(HereMapController hereMapController) {
    mapController = hereMapController;
    hereMapController.mapScene.loadSceneForMapScheme(MapScheme.normalDay,
        (MapError? error) async {
      if (error != null) {
        debugPrint('Map scene not loaded. MapError: ${error.toString()}');
        return;
      }

      if (!await _requestPermissions()) {
        print(
            "Cannot start app: Location service and permissions are needed for this app.");
        return;
      }

      // Enable traffic flow, low speed zones and 3D landmarks, by default.
      hereMapController.mapScene.enableFeatures(
          {MapFeatures.trafficFlow: MapFeatureModes.trafficFlowWithFreeFlow});
      hereMapController.mapScene.enableFeatures(
          {MapFeatures.lowSpeedZones: MapFeatureModes.lowSpeedZonesAll});
      hereMapController.mapScene.enableFeatures(
          {MapFeatures.landmarks: MapFeatureModes.landmarksTextured});

      createRoute();
    });
  }

  // Request permissions with the permission_handler plugin. Set the required permissions here:
  // Android: navigation_app/android/app/src/main/AndroidManifest.xml
  // iOS: navigation_app/ios/Runner/Info.plist
  Future<bool> _requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      print("Service");
      return false;
    }

    var locationPerm = await Geolocator.checkPermission();
    if (locationPerm != LocationPermission.whileInUse &&
        locationPerm != LocationPermission.always) {
      print("location");
      return false;
    }

    if (Platform.isAndroid) {
      // This permission is optionally needed on Android devices >= Q to improve the positioning signal.
      Permission.activityRecognition.request();
    }

    // All required permissions granted.
    return true;
  }

  void _showRouteOnMap(here.Route route) {
    // Show route as polyline.
    here.GeoPolyline routeGeoPolyline = route.geometry;
    double widthInPixels = 20;
    Color polylineColor = Colors.blue;
    MapPolyline routeMapPolyline;
    try {
      routeMapPolyline = MapPolyline.withRepresentation(
          routeGeoPolyline,
          MapPolylineSolidRepresentation(
              MapMeasureDependentRenderSize.withSingleSize(
                  RenderSizeUnit.pixels, widthInPixels),
              polylineColor,
              LineCap.round));
      mapController!.mapScene.addMapPolyline(routeMapPolyline);
    } on MapPolylineRepresentationInstantiationException catch (e) {
      print("MapPolylineRepresentation Exception: ${e.error.name}");
      return;
    } on MapMeasureDependentRenderSizeInstantiationException catch (e) {
      print("MapMeasureDependentRenderSize Exception: ${e.error.name}");
      return;
    }
  }

  void prefetchMapData(here.GeoCoordinates currentGeoCoordinates) {
    // Prefetches map data around the provided location with a radius of 2 km into the map cache.
    // For the best experience, prefetchAroundLocationWithRadius() should be called as early as possible.
    double radiusInMeters = 2000.0;
    _routePrefetcher.prefetchAroundLocationWithRadius(
        currentGeoCoordinates, radiusInMeters);
    // Prefetches map data within a corridor along the route that is currently set to the provided Navigator instance.
    // This happens continuously in discrete intervals.
    // If no route is set, no data will be prefetched.
    _routePrefetcher.prefetchAroundRouteOnIntervals(_visualNavigator!);
  }

  _startGuidance(here.Route route) {
    try {
      // Without a route set, this starts tracking mode.
      _visualNavigator = here.VisualNavigator();

      // This enables a navigation view including a rendered navigation arrow.
      _visualNavigator!.route = route;
      _showRouteOnMap(route);
      prefetchMapData(route.geometry.vertices.first);
      _visualNavigator!.startRendering(mapController!);

      // Hook in one of the many listeners. here we set up a listener to get instructions on the maneuvers to take while driving.
      // For more details, please check the "navigation_app" example and the Developer's Guide.
      _visualNavigator!.eventTextListener =
          here.EventTextListener((here.EventText eventText) {
        debugPrint("Voice maneuver text: ${eventText.text}");
        if (eventText.type == here.TextNotificationType.maneuver) {
          setState(() {
            currentManeuverAction =
                eventText.maneuverNotificationDetails?.maneuver.action;
          });
        }
      });

      _visualNavigator?.routeProgressListener =
          here.RouteProgressListener((here.RouteProgress routeProgress) {
        // Handle results from onRouteProgressUpdated():
        List<here.SectionProgress> sectionProgressList =
            routeProgress.sectionProgress;
        // sectionProgressList is guaranteed to be non-empty.
        here.SectionProgress lastSectionProgress =
            sectionProgressList.elementAt(sectionProgressList.length - 1);
        distanceLeft =
            formatDistance(lastSectionProgress.remainingDistanceInMeters);
        durationLeft =
            formatDuration(lastSectionProgress.remainingDuration.inSeconds);
        durationLeftInSeconds = lastSectionProgress.remainingDuration.inSeconds;

        setState(() {});

        debugPrint(
            'Distance to destination in meters: ${lastSectionProgress.remainingDistanceInMeters}');
        debugPrint(
            'Duration to destination is: ${lastSectionProgress.remainingDuration.inSeconds}');
        debugPrint(
            'Duration to destination is: ${formatDuration(lastSectionProgress.remainingDuration.inSeconds)}');
        debugPrint(
            'Traffic delay ahead in seconds: ${lastSectionProgress.trafficDelay.inSeconds}');

        // Contains the progress for the next maneuver ahead and the next-next maneuvers, if any.
        List<here.ManeuverProgress> nextManeuverList =
            routeProgress.maneuverProgress;

        if (nextManeuverList.isEmpty) {
          debugPrint('No next maneuver available.');
          return;
        }
        here.ManeuverProgress nextManeuverProgress = nextManeuverList.first;

        int nextManeuverIndex = nextManeuverProgress.maneuverIndex;
        Maneuver? nextManeuver =
            _visualNavigator?.getManeuver(nextManeuverIndex);

        if (nextManeuver == null) {
          // Should never happen as we retrieved the next maneuver progress above.
          return;
        }

        ManeuverAction action = nextManeuver.action;
        String roadName = _getRoadName(nextManeuver);
        String logMessage =
            '${action.name} on $roadName in ${nextManeuverProgress.remainingDistanceInMeters} meters.';

        if (_previousManeuverIndex != nextManeuverIndex) {
          debugPrint(
              'New maneuver: ${getManeuverMessage(action, roadName, nextManeuverProgress.remainingDistanceInMeters)}');
        } else {
          // A maneuver update contains a different distance to reach the next maneuver.
          debugPrint('Maneuver update: $logMessage');
          currentManeuverText = getManeuverMessage(
              action, roadName, nextManeuverProgress.remainingDistanceInMeters);
          setState(() {});
        }

        _previousManeuverIndex = nextManeuverIndex;
      });

      _visualNavigator?.routeDeviationListener = here.RouteDeviationListener((here.RouteDeviation routeDeviation) {

        print("Deviation started");

        here.Route? route = _visualNavigator?.route;

        if (route == null) {
          return;
        }

        // Get current geographic coordinates.
        here.MapMatchedLocation? currentMapMatchedLocation =
            routeDeviation.currentLocation.mapMatchedLocation;
        here.GeoCoordinates currentGeoCoordinates =
            currentMapMatchedLocation?.coordinates ??
                routeDeviation.currentLocation.originalLocation.coordinates;

        // Get last geographic coordinates on route.
        here.GeoCoordinates? lastGeoCoordinatesOnRoute;
        if (routeDeviation.lastLocationOnRoute != null) {
          here.MapMatchedLocation? lastMapMatchedLocationOnRoute =
              routeDeviation.lastLocationOnRoute?.mapMatchedLocation;
          lastGeoCoordinatesOnRoute = lastMapMatchedLocationOnRoute
                  ?.coordinates ??
              routeDeviation.lastLocationOnRoute?.originalLocation.coordinates;
        } else {
          print("User was never following the route. So, we take the start of the route instead.");
          lastGeoCoordinatesOnRoute = route.sections.first.departurePlace.originalCoordinates;
        }

        int distanceInMeters = currentGeoCoordinates
            .distanceTo(lastGeoCoordinatesOnRoute!)
            .round();

        print("Deviation distance is $distanceInMeters");

        if (distanceInMeters > 100) {

          // If too far away, consider to calculate a new route instead.
          Waypoint newStartingPoint = Waypoint(currentLocation);

          var truckOptions = here.TruckOptions();
          var routeOptions = here.RouteOptions();
          routeOptions.enableRouteHandle = true;
          truckOptions.routeOptions = routeOptions;
          var refreshRouteOption = here.RefreshRouteOptions.withTruckOptions(truckOptions);


          routingEngine.returnToRouteWithTraveledDistance(
              route,
              newStartingPoint,
              routeDeviation.lastTraveledSectionIndex,
              routeDeviation.traveledDistanceOnLastSectionInMeters,
                  (routingError, routes) {
            if (routingError == null) {
              here.Route newRoute = routes!.first;
              _visualNavigator?.route = newRoute;
              setState(() {});
            } else {
              // Handle error.
              print("Deviation error : ${routingError.toString()}");
            }
          });


        }
      });

      // VisualNavigator acts as LocationListener to receive location updates directly from a location provider.
      // Any progress along the route is a result of getting a new location fed into the VisualNavigator.
      // _setupLocationSource(_visualNavigator!, route);
      _herePositioningProvider.startLocating(_visualNavigator!, LocationAccuracy.navigation);

      // startLocating();
    } on InstantiationException {
      throw Exception("Initialization of VisualNavigator failed.");
    } catch (e) {
      print(e.toString());
    }
  }

  String _getRoadName(Maneuver maneuver) {
    RoadTexts currentRoadTexts = maneuver.roadTexts;
    RoadTexts nextRoadTexts = maneuver.nextRoadTexts;

    String? currentRoadName = currentRoadTexts.names.getDefaultValue();
    String? currentRoadNumber =
        currentRoadTexts.numbersWithDirection.getDefaultValue();
    String? nextRoadName = nextRoadTexts.names.getDefaultValue();
    String? nextRoadNumber =
        nextRoadTexts.numbersWithDirection.getDefaultValue();

    String? roadName = nextRoadName ?? nextRoadNumber;

    // On highways, we want to show the highway number instead of a possible road name,
    // while for inner city and urban areas road names are preferred over road numbers.
    if (maneuver.nextRoadType == RoadType.highway) {
      roadName = nextRoadNumber ?? nextRoadName;
    }

    if (maneuver.action == ManeuverAction.arrive) {
      // We are approaching the destination, so there's no next road.
      roadName = currentRoadName ?? currentRoadNumber;
    }

    // Happens only in rare cases, when also the fallback above is null.
    roadName ??= 'unnamed road';

    return roadName;
  }

  String getManeuverMessage(
      ManeuverAction action, String roadName, int remainingDistanceInMeters) {
    // Define the base message map
    final Map<ManeuverAction, String> messageMap = {
      ManeuverAction.depart: 'Head towards',
      ManeuverAction.arrive: 'You have reached your destination/waypoint',
      ManeuverAction.leftUTurn: 'Make a U-turn',
      ManeuverAction.sharpLeftTurn: 'Turn sharply left',
      ManeuverAction.leftTurn: 'Turn left',
      ManeuverAction.slightLeftTurn: 'Turn slightly left',
      ManeuverAction.continueOn: 'Continue straight ahead',
      ManeuverAction.slightRightTurn: 'Turn slightly right',
      ManeuverAction.rightTurn: 'Turn right',
      ManeuverAction.sharpRightTurn: 'Turn sharply right',
      ManeuverAction.rightUTurn: 'Make a U-turn',
      ManeuverAction.leftExit: 'Take the exit',
      ManeuverAction.rightExit: 'Take the exit',
      ManeuverAction.leftRamp: 'Join the highway',
      ManeuverAction.rightRamp: 'Join the highway',
      ManeuverAction.leftFork: 'Keep left',
      ManeuverAction.middleFork: 'Keep middle',
      ManeuverAction.rightFork: 'Keep right',
      ManeuverAction.enterHighwayFromLeft:
          'Merge onto the highway from the left',
      ManeuverAction.enterHighwayFromRight:
          'Merge onto the highway from the right',
      ManeuverAction.leftRoundaboutEnter: 'Enter the roundabout',
      ManeuverAction.rightRoundaboutEnter: 'Enter the roundabout',
      ManeuverAction.leftRoundaboutPass: 'Pass the roundabout',
      ManeuverAction.rightRoundaboutPass: 'Pass the roundabout',
    };

    // Generate roundabout exit messages
    final Map<ManeuverAction, String> roundaboutExitMessages = {
      ManeuverAction.leftRoundaboutExit1: 'Take the 1st exit at the roundabout',
      ManeuverAction.leftRoundaboutExit2: 'Take the 2nd exit at the roundabout',
      ManeuverAction.leftRoundaboutExit3: 'Take the 3rd exit at the roundabout',
      ManeuverAction.leftRoundaboutExit4: 'Take the 4th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit5: 'Take the 5th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit6: 'Take the 6th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit7: 'Take the 7th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit8: 'Take the 8th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit9: 'Take the 9th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit10:
          'Take the 10th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit11:
          'Take the 11th exit at the roundabout',
      ManeuverAction.leftRoundaboutExit12:
          'Take the 12th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit1:
          'Take the 1st exit at the roundabout',
      ManeuverAction.rightRoundaboutExit2:
          'Take the 2nd exit at the roundabout',
      ManeuverAction.rightRoundaboutExit3:
          'Take the 3rd exit at the roundabout',
      ManeuverAction.rightRoundaboutExit4:
          'Take the 4th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit5:
          'Take the 5th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit6:
          'Take the 6th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit7:
          'Take the 7th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit8:
          'Take the 8th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit9:
          'Take the 9th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit10:
          'Take the 10th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit11:
          'Take the 11th exit at the roundabout',
      ManeuverAction.rightRoundaboutExit12:
          'Take the 12th exit at the roundabout',
    };

    // Merge the maps
    final completeMessageMap = {}
      ..addAll(messageMap)
      ..addAll(roundaboutExitMessages);

    // Get the base message from the map
    final baseMessage = completeMessageMap[action] ?? 'Unknown maneuver';

    // Format the final message
    // return '$baseMessage on $roadName in ${formatDistance(remainingDistanceInMeters)}.';
    return '$baseMessage on $roadName';
  }

  String ordinalSuffix(int number) {
    if (!(number >= 1 && number <= 31)) return '';

    if (number % 10 == 1 && number % 100 != 11) return 'st';
    if (number % 10 == 2 && number % 100 != 12) return 'nd';
    if (number % 10 == 3 && number % 100 != 13) return 'rd';
    return 'th';
  }

  String getIconName(ManeuverAction action) {
    switch (action) {
      case ManeuverAction.depart:
        return 'depart.svg';
      case ManeuverAction.arrive:
        return 'arrive.svg';
      case ManeuverAction.leftUTurn:
        return 'left-u-turn.svg';
      case ManeuverAction.sharpLeftTurn:
        return 'sharp-left-turn.svg';
      case ManeuverAction.leftTurn:
        return 'left-turn.svg';
      case ManeuverAction.slightLeftTurn:
        return 'slight-left-turn.svg';
      case ManeuverAction.continueOn:
        return 'continue-on.svg';
      case ManeuverAction.slightRightTurn:
        return 'slight-right-turn.svg';
      case ManeuverAction.rightTurn:
        return 'right-turn.svg';
      case ManeuverAction.sharpRightTurn:
        return 'sharp-right-turn.svg';
      case ManeuverAction.rightUTurn:
        return 'right-u-turn.svg';
      case ManeuverAction.leftExit:
        return 'left-exit.svg';
      case ManeuverAction.rightExit:
        return 'right-exit.svg';
      case ManeuverAction.leftRamp:
        return 'left-ramp.svg';
      case ManeuverAction.rightRamp:
        return 'right-ramp.svg';
      case ManeuverAction.leftFork:
        return 'left-fork.svg';
      case ManeuverAction.middleFork:
        return 'middle-fork.svg';
      case ManeuverAction.rightFork:
        return 'right-fork.svg';
      case ManeuverAction.enterHighwayFromLeft:
        return 'enter-highway-left.svg';
      case ManeuverAction.enterHighwayFromRight:
        return 'enter-highway-right.svg';
      case ManeuverAction.leftRoundaboutEnter:
        return 'left-roundabout-enter.svg';
      case ManeuverAction.rightRoundaboutEnter:
        return 'right-roundabout-enter.svg';
      case ManeuverAction.leftRoundaboutPass:
        return 'left-roundabout-pass.svg';
      case ManeuverAction.rightRoundaboutPass:
        return 'right-roundabout-pass.svg';
      case ManeuverAction.leftRoundaboutExit1:
        return 'left-roundabout-exit1.svg';
      case ManeuverAction.leftRoundaboutExit2:
        return 'left-roundabout-exit2.svg';
      case ManeuverAction.leftRoundaboutExit3:
        return 'left-roundabout-exit3.svg';
      case ManeuverAction.leftRoundaboutExit4:
        return 'left-roundabout-exit4.svg';
      case ManeuverAction.leftRoundaboutExit5:
        return 'left-roundabout-exit5.svg';
      case ManeuverAction.leftRoundaboutExit6:
        return 'left-roundabout-exit6.svg';
      case ManeuverAction.leftRoundaboutExit7:
        return 'left-roundabout-exit7.svg';
      case ManeuverAction.leftRoundaboutExit8:
        return 'left-roundabout-exit8.svg';
      case ManeuverAction.leftRoundaboutExit9:
        return 'left-roundabout-exit9.svg';
      case ManeuverAction.leftRoundaboutExit10:
        return 'left-roundabout-exit10.svg';
      case ManeuverAction.leftRoundaboutExit11:
        return 'left-roundabout-exit11.svg';
      case ManeuverAction.leftRoundaboutExit12:
        return 'left-roundabout-exit12.svg';
      case ManeuverAction.rightRoundaboutExit1:
        return 'right-roundabout-exit1.svg';
      case ManeuverAction.rightRoundaboutExit2:
        return 'right-roundabout-exit2.svg';
      case ManeuverAction.rightRoundaboutExit3:
        return 'right-roundabout-exit3.svg';
      case ManeuverAction.rightRoundaboutExit4:
        return 'right-roundabout-exit4.svg';
      case ManeuverAction.rightRoundaboutExit5:
        return 'right-roundabout-exit5.svg';
      case ManeuverAction.rightRoundaboutExit6:
        return 'right-roundabout-exit6.svg';
      case ManeuverAction.rightRoundaboutExit7:
        return 'right-roundabout-exit7.svg';
      case ManeuverAction.rightRoundaboutExit8:
        return 'right-roundabout-exit8.svg';
      case ManeuverAction.rightRoundaboutExit9:
        return 'right-roundabout-exit9.svg';
      case ManeuverAction.rightRoundaboutExit10:
        return 'right-roundabout-exit10.svg';
      case ManeuverAction.rightRoundaboutExit11:
        return 'right-roundabout-exit11.svg';
      case ManeuverAction.rightRoundaboutExit12:
        return 'right-roundabout-exit12.svg';
    }
  }

  @override
  void onFeaturesNotAvailable(List<LocationFeature> features) {
    print(features.first.toString());
  }

  @override
  void onLocationUpdated(here.Location location) {
    print(location.coordinates.latitude);
    print(location.coordinates.longitude);

    print(_visualNavigator?.route == null);
  }

  @override
  void onStatusChanged(LocationEngineStatus locationEngineStatus) {
    print(locationEngineStatus.toString());
  }

  void createRoute() {
    List<here.Waypoint> wayPoints =
    [currentLocation, widget.destination].map((coord) {
      return here.Waypoint.withDefaults(coord);
    }).toList();

    var truckOptions = here.TruckOptions();
    var routeOptions = here.RouteOptions();
    routeOptions.enableRouteHandle = true;
    truckOptions.routeOptions = routeOptions;

    routingEngine.calculateTruckRoute(wayPoints, truckOptions, (error, routing) {
          if (error == null) {
            var route = routing!.first;
            _startGuidance(route);
          } else {
            print(error.name);
          }
        });
  }
}

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/core.errors.dart';
import 'package:here_sdk/consent.dart';
import 'package:here_sdk/mapview.dart';
import 'package:here_sdk/routing.dart';
import 'package:here_sdk/search.dart';
import 'package:navigation_sample/main.dart';
import 'package:navigation_sample/pages/navigate_to_place.dart';
import 'package:navigation_sample/models/search_result_model.dart';
import 'package:navigation_sample/helper/utils.dart';
import 'package:here_sdk/routing.dart' as here; // Alias for HERE SDK

class SearchNearbyScreen extends StatefulWidget {
  const SearchNearbyScreen({super.key});

  @override
  State<SearchNearbyScreen> createState() => _SearchNearbyScreenState();
}

class _SearchNearbyScreenState extends State<SearchNearbyScreen> {

  Timer? _debounce;
  late SearchEngine _searchEngine;
  late RoutingEngine _routingEngine;
  SearchOptions searchOptions = SearchOptions();
  List<SearchResultModel> searchItems = [];
  SearchResultModel? searchResultModel;
  final TextEditingController searchController = TextEditingController();
  HereMapController? mapController;
  WidgetPin? widgetPin;
  bool isLoading = false;
  ConsentEngine? _consentEngine;

  
  @override
  void initState() {
    super.initState();

    try {
      _searchEngine = SearchEngine();
      _routingEngine = RoutingEngine();
      _consentEngine = ConsentEngine();
    } on InstantiationException {
      throw Exception("Initialization of SearchEngine failed.");
    }

  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.sizeOf(context);
    return Scaffold(
      floatingActionButton: Visibility(
        visible: searchResultModel != null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: "reset",
              onPressed: (){
                searchResultModel = null;
                searchItems.clear();
                setState(() {});
            }, backgroundColor: Colors.redAccent, child: const Icon(Icons.replay),),
            12.height,
            FloatingActionButton(
              backgroundColor: Colors.green,
              heroTag: "navigate",
              onPressed: (){
                if(Platform.isIOS || _consentEngine!.userConsentState == ConsentUserReply.granted){
                  Navigator.push(context, MaterialPageRoute(builder: (context) => NavigateToPlace(destination: searchResultModel!.geoCoordinates)));
                }else{
                  _requestConsent();
                }
              }, child: const Icon(Icons.navigation),),
          ],
        ),
      ),
      body: Container(
        height: size.height,
        width: size.width,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color(0XFFEAF9FF),
              Color(0XFFEAF9FF),
              Color(0XFFEAF9FF),
            ],
          ),
        ),
        child: SafeArea(child: searchResultModel == null ? buildSearchView() : buildMapView()),
      ),
    );
  }

  searchQuery(TextQuery query, VoidCallback onFinish) {
    searchItems.clear();
    _searchEngine.searchByText(query, searchOptions, (SearchError? searchError, List<Place>? list) async {

      if (searchError != null) {
        log(query.query);
        log(searchError.toString());
        return;
      }

      log((list?.length ?? 0).toString());

      // Add new marker for each search result on map.
      if(list == null){
        setState(() {});
        return;
      }

      for (Place searchResult in list) {
        searchItems.add(SearchResultModel(searchResult.address.addressText, searchResult.geoCoordinates!));
      }

      onFinish();
    });
  }

  buildSearchView() {
    return Column(
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Search here",
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        4.height,
        Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
              color: Colors.grey.shade200),
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: TextFormField(
              controller: searchController,
              textAlignVertical: TextAlignVertical.center,
              onChanged: (val) {
                if (_debounce?.isActive ?? false) _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () async {
                  var query = TextQuery.withArea(searchController.text, TextQueryArea.withCenter(currentLocation));
                  searchQuery(query, () {
                    setState(() {});
                  });
                });
              },
              decoration: const InputDecoration(
                isCollapsed: true,
                suffixIcon: Icon(Icons.search),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        16.height,
        Expanded(
          child: ListView.builder(
              shrinkWrap: true,
              itemCount: searchItems.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const Icon(Icons.location_on_rounded),
                  title: Text(searchItems[index].name),
                  onTap: () {
                    searchResultModel = searchItems[index];
                    // isLoading = true;
                    setState(() {});
                  },
                );
              }),
        )
      ],
    ).paddingAll(16);
  }

  buildMapView() {
    return isLoading ? const Center(child: CircularProgressIndicator(),) : Column(
      children: [
        RichText(text: TextSpan(
          text: "Showing map view for ",
          style: const TextStyle(color: Colors.black),
          children: [
            TextSpan(
              text: "'${searchResultModel?.name}'",
              style: const TextStyle(color: Colors.grey)
            )
          ]
        )),
        16.height,
        Expanded(
          child: HereMap(
            onMapCreated: _onMapCreated,
          ),
        )
      ],
    ).paddingAll(16);
  }

  void _onMapCreated(HereMapController hereMapController) {
    mapController = hereMapController;
    hereMapController.mapScene.loadSceneForMapScheme(MapScheme.normalDay, (MapError? error) async {
      if (error != null) {
        debugPrint('Map scene not loaded. MapError: ${error.toString()}');
        return;
      }

      if(searchResultModel != null){
        // Add Current marker
        MapImage currentPinImage = await _createCurrentImage();
        MapMarker currentLocMarker = MapMarker(currentLocation, currentPinImage);
        mapController!.mapScene.addMapMarker(currentLocMarker);

        // Add location marker
        MapImage mapImage = await _createMapImage();
        addMapMarker(searchResultModel!.geoCoordinates, mapImage, mapController!);
        var res = await getDistanceDuration(searchResultModel!.geoCoordinates);

        widgetPin = mapController!
            .pinWidget(_createWidget(res), searchResultModel!.geoCoordinates);
        widgetPin?.anchor = Anchor2D.withHorizontalAndVertical(0.5, 1.5);
        // setState(() {
        //   isLoading = false;
        // });
      }
    });
  }


  Widget _createWidget(Map<String, String> data) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: MediaQuery.sizeOf(context).width * 0.65,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xffEAF9FF),
            border: Border.all(color: const Color(0xff363640)),
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    color: Colors.green),
                height: 48,
                width: 48,
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.car_repair),
              ),
              12.width,
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "${data["distance"]} miles, ${data["duration"]}",
                      )),
                  Text(
                    searchResultModel?.name ?? "-",
                    overflow: TextOverflow.ellipsis,
                  )
                ]),
              )
            ],
          ),
        ),
        RotatedBox(
            quarterTurns: 2,
            child: SvgPicture.asset("assets/images/ic_triangle.svg", color: const Color(0xff363641),))
      ],
    );
  }

  Future<MapImage> _createCurrentImage() async {
    ByteData fileData = await rootBundle.load("assets/images/pin.png");
    Uint8List pixelData = fileData.buffer.asUint8List();
    int width = 18; // Set desired width
    int height = 18; // Set desired height
    return MapImage.withImageDataImageFormatWidthAndHeight(
        pixelData, ImageFormat.png, width, height);
  }

  Future<MapImage> _createMapImage() async {
    ByteData fileData = await rootBundle.load('assets/images/map-pin.svg');
    Uint8List pixelData = fileData.buffer.asUint8List();
    int width = 11.round(); // Set desired width
    int height = 9.round(); // Set desired height
    return MapImage.withImageDataImageFormatWidthAndHeight(
        pixelData, ImageFormat.png, width, height);
  }


  void addMapMarker(GeoCoordinates coordinates, MapImage mapImage, HereMapController mapController) {
    Anchor2D anchor2D = Anchor2D.withHorizontalAndVertical(0.5, 1);

    MapMarker mapMarker = MapMarker.withAnchor(coordinates, mapImage, anchor2D);
    mapMarker.drawOrder = 0;

    mapController.mapScene.addMapMarker(mapMarker);
  }

  Future<Map<String, String>> getDistanceDuration(
      GeoCoordinates destination) async {
    Map<String, String> dataMap = {"distance": "0", "duration": "0"};

    var startWaypoint = Waypoint.withDefaults(currentLocation);
    var destinationWaypoint = Waypoint.withDefaults(destination);

    List<Waypoint> waypoints = [startWaypoint, destinationWaypoint];
    // Using Completer to wait for the asynchronous operation to complete
    Completer<void> completer = Completer<void>();

    _routingEngine.calculateTruckRoute(waypoints, TruckOptions(),
            (RoutingError? routingError, List<here.Route>? routeList) async {
          if (routingError == null) {
            // When error is null, it is guaranteed that the list is not empty.
            here.Route route = routeList!.first;
            dataMap["distance"] = route.lengthInMeters.toString();
            dataMap["duration"] = route.duration.inSeconds.toString();

            GeoPolyline routeGeoPoly = route.geometry;
            double polywidth = 3.0;
            var mypolyline = MapPolyline.withRepresentation(
                routeGeoPoly,
                MapPolylineSolidRepresentation(
                    MapMeasureDependentRenderSize.withSingleSize(
                        RenderSizeUnit.pixels, polywidth),
                    Colors.red,
                    LineCap.round));
            mapController!.mapScene.addMapPolyline(mypolyline);

            // Adjust camera to fit the route
            _zoomToRoute(route);

          } else {
            var error = routingError.toString();
            print('Error while calculating a route: $error');
          }

          // Complete the Completer once the route calculation is done
          completer.complete();
        });

    // Wait for the Completer to complete before returning dataMap
    await completer.future;

    return dataMap;
  }

  void _zoomToRoute(here.Route route) {
    if (mapController == null) return;

    GeoBox routeBoundingBox = route.boundingBox;
    GeoCoordinates northEast = routeBoundingBox.northEastCorner;
    GeoCoordinates southWest = routeBoundingBox.southWestCorner;

    mapController!.camera.lookAtAreaWithGeoOrientation(
      GeoBox(southWest, northEast),
      GeoOrientationUpdate(0, 0),
    );
  }

  Future<void> _requestConsent() async {
    if (!Platform.isIOS) {
      // This shows a localized widget that asks the user if data can be collected or not.
      await _consentEngine?.requestUserConsent(context);
    }

    if(Platform.isIOS || _consentEngine!.userConsentState == ConsentUserReply.granted){
      Navigator.push(context, MaterialPageRoute(builder: (context) => NavigateToPlace(destination: searchResultModel!.geoCoordinates)));
    }
  }

}

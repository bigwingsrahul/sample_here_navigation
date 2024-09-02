import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:here_sdk/core.dart';
import 'package:here_sdk/core.engine.dart';
import 'package:here_sdk/core.errors.dart';
import 'package:navigation_sample/pages/search_nearby_screen.dart';

GeoCoordinates currentLocation = GeoCoordinates(0.0, 0.0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _initializeHERESDK();
  await Geolocator.requestPermission();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  void initState() {
    super.initState();

    Geolocator.getPositionStream().listen((Position position) {
      currentLocation = GeoCoordinates(position.latitude, position.longitude);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: false,
      ),
      home: const SearchNearbyScreen(),
    );
  }
}


void _initializeHERESDK() async {

  SdkContext.init(IsolateOrigin.main);

  // Set your credentials for the HERE SDK.
  String accessKeyId = const String.fromEnvironment('ACCESSKEY');
  String accessKeySecret = const String.fromEnvironment('SECRETKEY');
  SDKOptions sdkOptions =
  SDKOptions.withAccessKeySecret(accessKeyId, accessKeySecret);

  try {
    await SDKNativeEngine.makeSharedInstance(sdkOptions);
  } on InstantiationException {
    throw Exception("Failed to initialize the HERE SDK.");
  }
}


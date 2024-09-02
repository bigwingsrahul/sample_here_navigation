import 'package:flutter/material.dart';

extension IntExtensions on int? {

  /// Leaves given height of space
  Widget get height => SizedBox(height: this?.toDouble());

  /// Leaves given width of space
  Widget get width => SizedBox(width: this?.toDouble());

}

extension WidgetExtension on Widget? {
  /// return padding all
  Padding paddingAll(double padding) {
    return Padding(padding: EdgeInsets.all(padding), child: this);
  }
}

String formatDuration(int seconds) {
  // Calculate hours, minutes, and remaining seconds
  int hours = seconds ~/ 3600;
  seconds = seconds % 3600;
  int minutes = seconds ~/ 60;
  seconds = seconds % 60;

  // Construct the formatted duration string
  String formattedDuration = '';
  if (hours > 0) {
    formattedDuration += '$hours hrs ';
  }
  if (minutes > 0 || hours > 0) {
    formattedDuration += '$minutes mins';
  }

  if(minutes == 0 && hours == 0 && seconds > 0) {
    formattedDuration = '$seconds secs';
  }

  return formattedDuration.trim();
}

String formatDistance(int distanceInMeters) {
  if (distanceInMeters >= 1000) {
    final distanceInKm = distanceInMeters / 1000;
    return '${distanceInKm.toStringAsFixed(1)} km';  // Format to 1 decimal place for km
  } else {
    return '${distanceInMeters.toStringAsFixed(0)} m';  // Format to no decimal places for meters
  }
}
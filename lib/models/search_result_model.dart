import 'package:here_sdk/core.dart';

class SearchResultModel {
  String name;
  GeoCoordinates geoCoordinates;

  SearchResultModel(this.name, this.geoCoordinates);
}
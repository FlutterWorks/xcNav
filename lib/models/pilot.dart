import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import 'package:xcnav/models/geo.dart';

class Pilot {
  // basic info
  late final String id;
  late String name;

  // telemetry
  late Geo geo;
  double? fuel;

  // visuals
  Image? avatar;
  String? avatarHash;
  List<Geo> flightTrace = [];
  Color color = Colors.grey.shade800;

  // Flightplan
  int? selectedWaypoint;

  Pilot.new(this.id, this.name, this.avatarHash, this.geo) {
    // Load Avatar
    _loadAvatar();
  }

  Pilot.fromJson(Map<String, dynamic> json) {
    id = json["id"];
    name = json["name"];
    avatarHash = json["avatarHash"];
    geo = Geo();
    _loadAvatar();
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "avatarHash": avatarHash,
    };
  }

  void updateTelemetry(dynamic telemetry, int timestamp) {
    Map<String, dynamic> gps = telemetry["gps"];
    fuel = (telemetry["fuel"] ?? 0.0) + 0.0;
    // Don't use LatLng value of (0, 0)
    if (gps["lat"] != 0.0 || gps["lng"] != 0.0) {
      geo = Geo.fromPosition(
          Position(
            longitude: gps["lng"] as double,
            latitude: gps["lat"] as double,
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
            accuracy: 1,
            altitude: gps["alt"] is int ? (gps["alt"] as int).toDouble() : gps["alt"],
            heading: 0,
            speed: 0,
            speedAccuracy: 1,
          ),
          geo,
          null,
          null);
      flightTrace.add(geo);
    } else {
      debugPrint("skipped");
    }
  }

  void _updateColor(Uint8List bytes) {
    img.Image? image = img.decodeJpg(bytes.toList());

    if (image != null) {
      // Update color from avatar
      int redBucket = 0;
      int greenBucket = 0;
      int blueBucket = 0;
      int pixelCount = 100;

      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          int c = image.getPixel(x, y);

          pixelCount++;
          redBucket += img.getRed(c);
          greenBucket += img.getGreen(c);
          blueBucket += img.getBlue(c);
        }
      }

      color = Color.fromRGBO(redBucket ~/ pixelCount ~/ 2, greenBucket ~/ pixelCount, blueBucket ~/ pixelCount, 1);
    }
  }

  void _loadAvatar() async {
    if (avatarHash != null && avatarHash != "") {
      // - Check if we have locally cached file matching pilot_id
      Directory tempDir = await getTemporaryDirectory();
      File fileAvatar = File("${tempDir.path}/avatars/$id.jpg");

      if (await fileAvatar.exists()) {
        // load cached file
        Uint8List loadedBytes = await fileAvatar.readAsBytes();
        String loadedHash = md5.convert(loadedBytes).toString();

        if (loadedHash == avatarHash) {
          // cache hit
          debugPrint("Loaded avatar from cache");
          avatar = Image.memory(loadedBytes);
          _updateColor(loadedBytes);
          avatarHash = loadedHash;
        }
      }

      if (avatarHash == null) {
        // - cache miss, load from S3
        _fetchAvatarS3(id).then((value) {
          Uint8List bytes = base64Decode(value["avatar"]);
          avatar = Image.memory(bytes);
          avatarHash = md5.convert(bytes).toString();
          _updateColor(bytes);

          // save file to the temp file
          fileAvatar.create(recursive: true).then((value) => fileAvatar.writeAsBytes(bytes));
        });
      }
    } else {
      // - fallback on default avatar
      avatar = Image.asset("assets/images/default_avatar.png");
    }
  }

  Future _fetchAvatarS3(String pilotID) async {
    Uri uri =
        Uri.https("gx49w49rb4.execute-api.us-west-1.amazonaws.com", "/xcnav_avatar_service", {"pilot_id": pilotID});
    return http
        .get(
      uri,
    )
        .then((http.Response response) {
      final int statusCode = response.statusCode;

      if (statusCode < 200 || statusCode > 400) {
        throw Exception("Error while fetching avatar");
      }
      return json.decode(response.body);
    });
  }

  Polyline buildFlightTrace() {
    return Polyline(
        points: flightTrace.map((e) => e.latLng).toList().sublist(max(0, flightTrace.length - 40)),
        strokeWidth: 4,
        color: color.withAlpha(150));
  }
}

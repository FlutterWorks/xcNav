import 'dart:async';

import 'package:collection/collection.dart';
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/airports.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';
import 'package:xml/xml.dart';

// --- Models
import 'package:xcnav/models/waypoint.dart';

import 'package:xcnav/providers/active_plan.dart';

class FlightPlan {
  String name;
  late bool goodFile;
  late final Map<WaypointID, Waypoint> waypoints = {};

  /// Path and filename
  Future<String> getFilename() {
    Completer<String> completer = Completer();
    getApplicationDocumentsDirectory().then((tempDir) {
      completer.complete("${tempDir.path}/flight_plans/$name.json");
    });
    return completer.future;
  }

  LatLngBounds? getBounds() {
    if (waypoints.isEmpty) return null;
    List<LatLng> points = [];
    for (final wp in waypoints.values) {
      points.addAll(wp.latlng);
    }
    // max zoom value
    if (points.length == 1) {
      points.add(LatLng(points.first.latitude, points.first.longitude + 0.02));
      points.add(LatLng(points.first.latitude, points.first.longitude - 0.02));
    }
    return LatLngBounds.fromPoints(points)..pad(0.2);
  }

  FlightPlan(this.name) {
    goodFile = true;
  }

  FlightPlan.fromActivePlan(this.name, ActivePlan activePlan) {
    waypoints.addAll(activePlan.waypoints);
    goodFile = true;
  }

  FlightPlan.fromJson(this.name, dynamic data) {
    try {
      List<dynamic> dataList = data["waypoints"];
      final waypointList = dataList.map((e) => Waypoint.fromJson(e)).toList();
      for (final each in waypointList) {
        waypoints[each.id] = each;
      }

      goodFile = true;
    } catch (err, trace) {
      goodFile = false;
      DatadogSdk.instance.logs?.error("Failed to parse FlightPlan",
          errorMessage: err.toString(),
          errorStackTrace: trace,
          attributes: {"filename": name, "data": data.toString()});
    }
  }

  FlightPlan.fromiFlightPlanner(this.name, String url) {
    final pattern = RegExp(r"((?<!^)[\-]?)?([\-]{0,2}[\d\.]+/[\-]?[\d\.]+)|([\w\d]{3,4})");

    List<LatLng> latlngs = [];

    LatLng parseLatLng(String raw) {
      final double lat = parseAsDouble(raw.split("/")[0]);
      final double lng = parseAsDouble(raw.split("/")[1]);
      return LatLng(lat, lng);
    }

    for (final each in pattern.allMatches(url)) {
      final latlngRaw = each.group(2);
      final airportCode = each.group(3);

      if (airportCode != null) {
        // Airport
        Airport? airport = getAirport(airportCode);

        // Try extending US code
        if (airport == null && airportCode.length == 3) {
          airport = getAirport("K$airportCode");
        }

        if (airport != null) {
          final waypoint = Waypoint(name: "$airportCode - ${airport.name}", latlngs: [airport.latlng], icon: "airport");
          if (latlngs.isEmpty) {
            // start a path
            latlngs.add(airport.latlng);
          } else if (latlngs.length > 1) {
            // end a path
            latlngs.add(airport.latlng);
            final path = Waypoint(name: "To: ${airport.name}", latlngs: latlngs);
            waypoints[path.id] = path;
            latlngs = [airport.latlng];
          } else {
            // empty unfinished path
            latlngs.clear();
            latlngs = [];
          }
          waypoints[waypoint.id] = waypoint;
        } else {
          final msg = "Couldn't find airport $airportCode.";
          debugPrint("Error: $msg");
          DatadogSdk.instance.logs?.error(msg, attributes: {"url": url});
          goodFile = false;
          return;
        }
      } else if (latlngRaw != null) {
        // Append to path
        latlngs.add(parseLatLng(latlngRaw));
      }
    }

    if (waypoints.isEmpty) {
      goodFile = false;
    } else {
      goodFile = true;
    }
  }

  FlightPlan.fromKml(this.name, XmlElement document, List<XmlElement> folders) {
    void scanElement(XmlElement element) {
      element.findAllElements("Placemark").forEach((element) {
        String name = element.getElement("name")?.text.trim() ?? "untitled";
        if (element.getElement("Point") != null || element.getElement("LineString") != null) {
          final List<LatLng> points = (element.getElement("Point") ?? element.getElement("LineString"))!
              .getElement("coordinates")!
              .text
              .trim()
              .split(RegExp(r'[\n ]'))
              .where((element) => element.isNotEmpty)
              .map((e) {
            final raw = e.split(",");
            return LatLng(double.parse(raw[1]), double.parse(raw[0]));
          }).toList();

          // (substr 1 to trim off the # symbol)
          final styleUrl = element.getElement("styleUrl")!.text.substring(1);

          int color = 0xff000000;
          String? icon;

          // First try old style
          final styleElement = document
              .findAllElements("Style")
              .where((e) => e.getAttribute("id") != null && e.getAttribute("id")!.startsWith(styleUrl));
          if (styleElement.isNotEmpty) {
            String? colorText =
                (styleElement.first.getElement("IconStyle") ?? styleElement.first.getElement("LineStyle"))
                    ?.getElement("color")
                    ?.text;
            if (colorText != null) {
              colorText = colorText.substring(0, 2) +
                  colorText.substring(6, 8) +
                  colorText.substring(4, 6) +
                  colorText.substring(2, 4);
              color = int.parse((colorText), radix: 16) | 0xff000000;
            }
          } else {
            // Try the new google style format

            // first styleMap and the destination url
            final styleMap = document.findAllElements("StyleMap").where((e) => e.getAttribute("id")! == styleUrl).first;
            final finalStyleUrl = styleMap
                .findAllElements("Pair")
                .where((e) => e.getElement("key")!.text == "normal")
                .first
                .getElement("styleUrl")!
                .text
                .substring(1);
            // grab destination url
            var finalStyleElement = document
                .findAllElements("gx:CascadingStyle")
                .where((e) => e.getAttribute("kml:id") == finalStyleUrl)
                .firstOrNull;
            // Try again with google-earth style
            finalStyleElement ??= document
                .findAllElements("Style")
                .where((element) => element.getAttribute("id")?.startsWith(finalStyleUrl) ?? false)
                .firstOrNull;

            // if style found...
            if (finalStyleElement != null) {
              if (points.length > 1) {
                // LineStyle
                String? colorText =
                    finalStyleElement.getElement("Style")?.getElement("LineStyle")?.getElement("color")?.text;
                colorText ??= finalStyleElement.getElement("LineStyle")?.getElement("color")?.text;
                if (colorText != null) {
                  colorText = colorText.substring(0, 2) +
                      colorText.substring(6, 8) +
                      colorText.substring(4, 6) +
                      colorText.substring(2, 4);
                  color = int.parse((colorText), radix: 16) | 0xff000000;
                }
              } else {
                // IconStyle
                String? href = finalStyleElement
                    .getElement("Style")
                    ?.getElement("IconStyle")
                    ?.getElement("Icon")
                    ?.getElement("href")
                    ?.text;
                href ??= finalStyleElement.getElement("IconStyle")?.getElement("Icon")?.getElement("href")?.text;
                if (href != null) {
                  String? finalColorString = RegExp(r'color=([a-f0-9]{6})').firstMatch(href)?.group(1).toString();
                  if (finalColorString != null) {
                    color = int.parse((finalColorString), radix: 16) | 0xff000000;
                  }
                  for (final each in iconOptions.keys) {
                    if (href.contains(each ?? "--")) {
                      icon = each;
                      break;
                    }
                  }
                  // google earth web icons
                  String? iconID = RegExp(r'id=([0-9]{4})').firstMatch(href)?.group(1).toString();
                  const iconIds = {
                    "2006": "star",
                    "2396": "x",
                    "2113": "exclamation",
                    "2271": "flag",
                    "2011": "airport",
                    "2127": "windsock",
                    "2061": "camp",
                    "2243": "paraglider",
                    "2137": "fuel",
                    "2174": "sleep",
                    "2058": "camera",
                  };
                  if (iconID != null && iconIds.containsKey(iconID)) {
                    icon = iconIds[iconID];
                  }
                }
              }
            }
          }

          if (points.isNotEmpty) {
            if (points.length > 1) {
              // Trim length strings from title b xm
              final match = RegExp(r'(.*)[\s]+(?:[-])[\s]*([0-9\.]+)[\s]*(miles|mi|km|Miles|Mi|Km)$').firstMatch(name);
              name = match?.group(1) ?? name;
            }
            final waypoint = Waypoint(name: name, latlngs: points, color: color, icon: icon);
            waypoints[waypoint.id] = waypoint;
          } else {
            debugPrint("Dropping $name with no points.");
          }
        }
      });
    }

    try {
      if (folders.isNotEmpty) {
        for (final each in folders) {
          scanElement(each);
        }
      } else {
        // if no folders selected, scan whole document
        scanElement(document);
      }

      goodFile = true;
    } catch (err, trace) {
      debugPrint("Error loading kml file: ${err.toString()}");
      goodFile = false;
      DatadogSdk.instance.logs?.error("Failed to import KML",
          errorMessage: err.toString(), errorStackTrace: trace, attributes: {"filename": name});
    }
  }
}

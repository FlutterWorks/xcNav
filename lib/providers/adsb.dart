import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:xcnav/models/ga.dart';
import 'package:xcnav/models/geo.dart';

import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/units.dart';

enum TtsState { playing, stopped }

class ProximityConfig {
  final double vertical;
  final double horizontalDist;
  final double horizontalTime;

  /// Units in meters and seconds
  ProximityConfig(
      {required this.vertical,
      required this.horizontalDist,
      required this.horizontalTime});
}

class ADSB with ChangeNotifier {
  RawDatagramSocket? sock;
  Map<int, GA> planes = {};

  late FlutterTts flutterTts;
  TtsState ttsState = TtsState.stopped;
  late final BuildContext context;

  int lastHeartbeat = 0;

  ADSB(BuildContext ctx) {
    context = ctx;

    flutterTts = FlutterTts();
    flutterTts.awaitSpeakCompletion(true);
    flutterTts.setStartHandler(() {
      print("Playing");
      ttsState = TtsState.playing;
    });

    flutterTts.setCompletionHandler(() {
      print("Complete");
      ttsState = TtsState.stopped;
    });

    flutterTts.setCancelHandler(() {
      print("Cancel");
      ttsState = TtsState.stopped;
    });

    flutterTts.setErrorHandler((msg) {
      print("error: $msg");
      ttsState = TtsState.stopped;
    });

    RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 4000).then((_sock) {
      sock = _sock;

      _sock.listen((event) {
        // debugPrint("ADSB event: ${event.toString()}");
        Datagram? dg = _sock.receive();
        if (dg != null) {
          // debugPrint("${dg.data.toString()}");
          decodeGDL90(dg.data);
        }
      }, onError: (error) {
        debugPrint("ADSB socket error: ${error.toString()}");
      }, onDone: () {
        debugPrint("ADSB socket done.");
      });
    });
  }

  @override
  void dispose() {
    if (sock != null) sock!.close();
    super.dispose();
    flutterTts.stop();
  }

  int decode24bit(Uint8List data) {
    int value = ((data[0] & 0x7f) << 16) | (data[1] << 8) | data[2];
    if (data[0] & 0x80 > 0) {
      value -= 0x7fffff;
    }
    return value;
  }

  void decodeTraffic(Uint8List data) {
    final int id = (data[1] << 16) | (data[2] << 8) | data[3];

    final double lat = decode24bit(data.sublist(4, 7)) * 180.0 / 0x7fffff;
    final double lng = decode24bit(data.sublist(7, 10)) * 180.0 / 0x7fffff;

    final Uint8List _altRaw = data.sublist(10, 12);
    final double alt =
        ((((_altRaw[0] << 4) + (_altRaw[1] >> 4)) * 25) - 1000) / meters2Feet;

    final double hdg = data[16] * 360 / 256.0;
    final double spd = ((data[13] << 4) + (data[14] >> 4)) * 0.51444;

    // TODO: why are we getting really high IDs? (reserved IDs)
    GAtype type = GAtype.unknown;
    final i = data[17];
    if (i == 1 || i == 9 || i == 10) {
      type = GAtype.small;
    } else if (i == 7) {
      type = GAtype.heli;
    } else {
      type = GAtype.large;
    }

    // debugPrint("GA $id (${type.toString()}): $lat, $lng, $spd m/s  $alt m, $hdg deg");

    if (type.index > 0 && type.index < 22 && (lat != 0 || lng != 0)) {
      planes[id] = GA(id, LatLng(lat, lng), alt, spd, hdg, type,
          DateTime.now().millisecondsSinceEpoch);
    }
  }

  void decodeGDL90(Uint8List data) {
    switch (data[1]) {
      case 0:
        // --- heartbeat
        lastHeartbeat = DateTime.now().millisecondsSinceEpoch;
        break;
      case 20:
        // --- traffic
        decodeTraffic(data.sublist(2));
        break;
      default:
        break;
    }
  }

  void cleanupOldEntries() {
    final thresh = DateTime.now().millisecondsSinceEpoch - 1000 * 12;
    for (GA each in planes.values.toList()) {
      if (each.timestamp < thresh) planes.remove(each.id);
    }
  }

  /// Wrap delta heading to +/- 180deg
  double deltaHdg(double a, double b) {
    return (a - b + 180) % 360 - 180;
  }

  void checkProximity(Geo observer) {
    ProximityConfig config =
        Provider.of<Settings>(context, listen: false).adsbProxConfig;

    for (GA each in planes.values) {
      final double dist = latlngCalc.distance(each.latlng, observer.latLng);
      final double bearing = latlngCalc.bearing(each.latlng, observer.latLng);

      final double delta = deltaHdg(bearing, each.hdg).abs();

      final double tangentOffset = sin(delta * pi / 180) * dist;
      final double altOffset = each.alt - observer.alt;

      // TODO: deduce speed if not provided?
      final double? eta =
          (each.spd > 0 && delta < 30 && tangentOffset < config.horizontalDist)
              ? dist / each.spd
              : null;

      final bool warning =
          (((eta ?? double.infinity) < config.horizontalTime) ||
                  dist < config.horizontalDist) &&
              altOffset.abs() < config.vertical;

      planes[each.id]!.warning = warning;

      if (warning && ttsState == TtsState.stopped) {
        speakWarning(each, observer, eta);
      }
    }
  }

  void speakWarning(GA ga, Geo observer, double? eta) {
    //     tts.setVolume(volume);
    // tts.setRate(rate);
    // if (languageCode != null) {
    //   tts.setLanguage(languageCode!);
    // }
    // tts.setPitch(pitch);
    final settings = Provider.of<Settings>(context, listen: false);

    // direction
    final int oclock = (((deltaHdg(
                            latlngCalc.bearing(observer.latLng, ga.latlng),
                            observer.hdg * 180 / pi) /
                        360.0 *
                        12.0)
                    .round() +
                11) %
            12) +
        1;

    // distance, eta
    final int dist = convertDistValueCoarse(settings.displayUnitsDist,
            latlngCalc.distance(ga.latlng, observer.latLng))
        .toInt();
    final String distMsg =
        ((dist > 0) ? dist.toStringAsFixed(0) : "less than one") +
            unitStrDistCoarseVerbal[settings.displayUnitsDist]!;
    final String? etaStr =
        eta != null ? eta.toStringAsFixed(0) + " seconds out" : null;

    // vertical separation
    String vertSep = ".";
    final double altOffset = ga.alt - observer.alt;
    if (altOffset > 100) vertSep = " high.";
    if (altOffset < -100) vertSep = " low.";

    // Type
    final String typeStr = gaTypeStr[ga.type] ?? "";

    String msg =
        "Warning! $typeStr $oclock o'clock$vertSep ${etaStr ?? distMsg}... ";
    debugPrint(msg);
    flutterTts.speak(msg);
  }

  /// Trigger update refresh
  /// Provide observer geo to calculate warnings
  void refresh(Geo observer) {
    if (planes.isNotEmpty) {
      cleanupOldEntries();
      checkProximity(observer);
      notifyListeners();
    }
  }
}

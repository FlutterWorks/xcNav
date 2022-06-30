import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/providers/adsb.dart';

import 'package:xcnav/units.dart';

class Settings with ChangeNotifier {
  // --- Modes
  bool _groundMode = false;
  bool _groundModeTelemetry = false;

  // --- Debug Tools
  bool _spoofLocation = false;

  // --- UI
  bool _showAirspace = false;
  bool _mapControlsRightSide = false;
  bool _showPilotNames = false;

  // --- Units
  var _displayUnitsSpeed = DisplayUnitsSpeed.mph;
  var _displayUnitsVario = DisplayUnitsVario.fpm;
  var _displayUnitsDist = DisplayUnitsDist.imperial;
  var _displayUnitsFuel = DisplayUnitsFuel.liter;

  // --- ADSB
  bool _adsbEnabled = false;
  final Map<String, ProximityConfig> proximityProfileOptions = {
    "Off": ProximityConfig(vertical: 0, horizontalDist: 0, horizontalTime: 0),
    "Small": ProximityConfig(vertical: 200, horizontalDist: 300, horizontalTime: 30),
    "Medium": ProximityConfig(vertical: 400, horizontalDist: 600, horizontalTime: 45),
    "Large": ProximityConfig(vertical: 800, horizontalDist: 1200, horizontalTime: 60),
    "X-Large": ProximityConfig(vertical: 1000, horizontalDist: 2000, horizontalTime: 90),
  };
  late ProximityConfig proximityProfile;
  late String proximityProfileName;

  // --- Patreon
  String _patreonName = "";
  String _patreonEmail = "";

  Settings() {
    selectProximityConfig("Medium");
    _loadSettings();
  }

  _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      _displayUnitsSpeed = DisplayUnitsSpeed.values[prefs.getInt("settings.displayUnitsSpeed") ?? 0];
      _displayUnitsVario = DisplayUnitsVario.values[prefs.getInt("settings.displayUnitsVario") ?? 0];
      _displayUnitsDist = DisplayUnitsDist.values[prefs.getInt("settings.displayUnitsDist") ?? 0];
      _mapControlsRightSide = prefs.getBool("settings.mapControlsRightSide") ?? false;
      _showPilotNames = prefs.getBool("settings.showPilotNames") ?? false;
      _displayUnitsFuel = DisplayUnitsFuel.values[prefs.getInt("settings.displayUnitsFuel") ?? 0];

      _groundMode = prefs.getBool("settings.groundMode") ?? false;
      _groundModeTelemetry = prefs.getBool("settings.groundModeTelemetry") ?? false;

      // --- ADSB
      selectProximityConfig(prefs.getString("settings.adsbProximityProfile") ?? "Medium");
      _adsbEnabled = prefs.getBool("settings.adsbEnabled") ?? false;

      // --- Patreon
      _patreonName = prefs.getString("settings.patreonName") ?? "";
      _patreonEmail = prefs.getString("settings.patreonEmail") ?? "";
    });
  }

  // --- mapControlsRightSide
  bool get mapControlsRightSide => _mapControlsRightSide;
  set mapControlsRightSide(bool value) {
    _mapControlsRightSide = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.mapControlsRightSide", _mapControlsRightSide);
    });
    notifyListeners();
  }

  // --- showPilotNames
  bool get showPilotNames => _showPilotNames;
  set showPilotNames(bool value) {
    _showPilotNames = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.showPilotNames", _showPilotNames);
    });
    notifyListeners();
  }

  // --- displayUnits
  DisplayUnitsSpeed get displayUnitsSpeed => _displayUnitsSpeed;
  set displayUnitsSpeed(DisplayUnitsSpeed value) {
    _displayUnitsSpeed = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsSpeed", _displayUnitsSpeed.index);
    });
    notifyListeners();
  }

  DisplayUnitsVario get displayUnitsVario => _displayUnitsVario;
  set displayUnitsVario(DisplayUnitsVario value) {
    _displayUnitsVario = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsVario", _displayUnitsVario.index);
    });
    notifyListeners();
  }

  DisplayUnitsDist get displayUnitsDist => _displayUnitsDist;
  set displayUnitsDist(DisplayUnitsDist value) {
    _displayUnitsDist = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsDist", _displayUnitsDist.index);
    });
    notifyListeners();
  }

  DisplayUnitsFuel get displayUnitsFuel => _displayUnitsFuel;
  set displayUnitsFuel(DisplayUnitsFuel value) {
    _displayUnitsFuel = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt("settings.displayUnitsFuel", _displayUnitsFuel.index);
    });
    notifyListeners();
  }

  bool get spoofLocation => _spoofLocation;
  set spoofLocation(bool value) {
    _spoofLocation = value;
    notifyListeners();
  }

  bool get showAirspace => _showAirspace;
  set showAirspace(bool value) {
    _showAirspace = value;
    notifyListeners();
  }

  bool get groundMode => _groundMode;
  set groundMode(bool value) {
    _groundMode = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.groundMode", _groundMode);
    });
    notifyListeners();
  }

  bool get groundModeTelemetry => _groundModeTelemetry;
  set groundModeTelemetry(bool value) {
    _groundModeTelemetry = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.groundModeTelemetry", _groundModeTelemetry);
    });
    notifyListeners();
  }

  // --- ADSB
  void selectProximityConfig(String name) {
    proximityProfile = proximityProfileOptions[name] ?? proximityProfileOptions["Medium"]!;
    proximityProfileName = name;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.adsbProximityProfile", name);
    });
    notifyListeners();
  }

  bool get adsbEnabled => _adsbEnabled;
  set adsbEnabled(bool value) {
    _adsbEnabled = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool("settings.adsbEnabled", _adsbEnabled);
    });
    notifyListeners();
  }

  // --- Patreon
  String get patreonName => _patreonName;
  set patreonName(String value) {
    _patreonName = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.patreonName", _patreonName);
    });
    notifyListeners();
  }

  String get patreonEmail => _patreonEmail;
  set patreonEmail(String value) {
    _patreonEmail = value;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString("settings.patreonEmail", _patreonEmail);
    });
    notifyListeners();
  }
}

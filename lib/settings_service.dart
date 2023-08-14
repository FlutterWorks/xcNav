import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xcnav/map_service.dart';

import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';

/// Holds and stores an individual setting.
class SettingConfig<T> {
  final SharedPreferences _prefsInstance;

  /// This id will be used as the save path in `sharedPreferences`
  final String id;
  final String catagory;
  final String title;
  final String? description;
  final Widget? icon;
  final Widget? subtitle;

  late ValueNotifier<T> _value;
  T defaultValue;

  ValueListenable<T> get listenable => _value;

  T get value {
    return _value.value ?? defaultValue;
  }

  set value(T newValue) {
    _value.value = newValue;
    if (id == "") return;
    if (value is Enum) {
      // Handle enum type
      _prefsInstance.setInt("settings.$id", (value as Enum).index);
      debugPrint("Set enum type ${(value as Enum).index}");
    } else {
      switch (T) {
        case List<String>:
          _prefsInstance.setStringList("settings.$id", newValue as List<String>);
          break;
        case String:
          _prefsInstance.setString("settings.$id", newValue as String);
          break;
        case bool:
          _prefsInstance.setBool("settings.$id", newValue as bool);
          break;
        case double:
          _prefsInstance.setDouble("settings.$id", newValue as double);
          break;
        case int:
          _prefsInstance.setInt("settings.$id", newValue as int);
          break;
      }
    }
  }

  SettingConfig(SettingsMgr mgr, this._prefsInstance, this.catagory, this.id, this.defaultValue,
      {required this.title, this.description, this.icon, bool hidden = false, this.subtitle}) {
    if (id.startsWith("settings.")) {
      throw "Setting ID automatically starts with \"settings.\"";
    }

    if (id == "") {
      _value = ValueNotifier<T>(defaultValue);
    } else {
      if (defaultValue is Enum) {
        // Handle enum type
        int? loadedInt = _prefsInstance.getInt("settings.$id");
        if (loadedInt == null) {
          _value = ValueNotifier<T>(defaultValue);
        } else {
          switch (T) {
            // NOTE: Need to add each supporte enum here
            case DisplayUnitsDist:
              _value = ValueNotifier<T>(DisplayUnitsDist.values[loadedInt] as T);
              break;
            case DisplayUnitsSpeed:
              _value = ValueNotifier<T>(DisplayUnitsSpeed.values[loadedInt] as T);
              break;
            case DisplayUnitsVario:
              _value = ValueNotifier<T>(DisplayUnitsVario.values[loadedInt] as T);
              break;
            case DisplayUnitsFuel:
              _value = ValueNotifier<T>(DisplayUnitsFuel.values[loadedInt] as T);
              break;
            case AltimeterMode:
              _value = ValueNotifier<T>(AltimeterMode.values[loadedInt] as T);
              break;
            case ProximitySize:
              _value = ValueNotifier<T>(ProximitySize.values[loadedInt] as T);
              break;
            case MapTileSrc:
              _value = ValueNotifier<T>(MapTileSrc.values[loadedInt] as T);
              break;
            default:
              throw "Unrecognized enum class ${T.toString()}";
          }
        }
      } else {
        switch (T) {
          case List<String>:
            _value =
                ValueNotifier<T>((_prefsInstance.getStringList("settings.$id") ?? defaultValue as List<String>) as T);
            break;
          case String:
            _value = ValueNotifier<T>((_prefsInstance.getString("settings.$id") ?? defaultValue as String) as T);
            break;
          case bool:
            _value = ValueNotifier<T>((_prefsInstance.getBool("settings.$id") ?? defaultValue as bool) as T);
            break;
          case double:
            _value = ValueNotifier<T>((_prefsInstance.getDouble("settings.$id") ?? defaultValue as double) as T);
            break;
          case int:
            _value = ValueNotifier<T>((_prefsInstance.getInt("settings.$id") ?? defaultValue as int) as T);
            break;
          default:
            throw "Unsupported Settings Type($T) !";
        }
      }
    }

    // Register with manager
    if (!hidden) {
      mgr.settings.putIfAbsent(catagory, () => []);
      mgr.settings[catagory]!.add(SettingMgrItem(config: this));
      if (mgr.ids.contains(id)) {
        throw "Settings Manager already has id $id !";
      } else {
        mgr.ids.add(id);
      }
    }
  }
}

class SettingAction {
  final String catagory;
  String title;
  final String? description;
  final Icon? actionIcon;

  Function() callback;

  SettingAction(SettingsMgr mgr, this.catagory, this.callback,
      {required this.title, this.description, this.actionIcon}) {
    // Register with manager
    mgr.settings.putIfAbsent(catagory, () => []);
    mgr.settings[catagory]!.add(SettingMgrItem(action: this));
  }
}

class SettingMgrItem {
  final SettingConfig? config;
  final SettingAction? action;

  bool get isConfig => config != null;
  bool get isAction => action != null;

  // --- pass-through fields
  String get catagory => config?.catagory ?? action?.catagory ?? "";
  String get title => config?.title ?? action?.title ?? "";
  String? get description => config?.description ?? action?.description;

  SettingMgrItem({this.config, this.action}) {
    if (config != null && action != null) {
      throw "Cannot set both config and action in SettingMgrItem";
    }
    if (config == null && action == null) {
      throw "Must set either config or action in SettingMgrItem";
    }
  }
}

/// Manages global instances of `Setting`s
class SettingsMgr {
  /// Flat look-up list of settings
  Set ids = {};

  /// Look-up list of settings by catagory
  Map<String, List<SettingMgrItem>> settings = {};

  // --- General
  late final SettingConfig<bool> groundMode;

  late final SettingConfig<bool> autoRecordFlight;

  // --- UI
  late final SettingConfig<AltimeterMode> primaryAltimeter;
  late final SettingConfig<double> altimeterVsiThresh;
  late final SettingConfig<bool> mapControlsRightSide;
  late final SettingConfig<bool> showPilotNames;
  late final SettingConfig<bool> showWeatherOverlay;
  late final SettingConfig<bool> showAirspaceOverlay;

  // --- Display Units
  late final SettingConfig<DisplayUnitsDist> displayUnitDist;
  late final SettingConfig<DisplayUnitsSpeed> displayUnitSpeed;
  late final SettingConfig<DisplayUnitsVario> displayUnitVario;
  late final SettingConfig<DisplayUnitsFuel> displayUnitFuel;

  // --- Misc
  late final SettingConfig<ProximitySize> adsbProximitySize;
  late final SettingAction adsbTestAudio;
  late final SettingConfig<bool> rumOptOut;

  // --- Debug Tools
  late final SettingConfig<bool> spoofLocation;
  late final SettingAction clearMapCache;
  late final SettingAction clearAvatarCache;
  late final SettingAction eraseIdentity;

  // --- Hidden
  late final SettingConfig<bool> chatTTS;
  late final SettingConfig<bool> groundModeTelem;
  late final SettingConfig<bool> northlockMap;
  late final SettingConfig<bool> northlockWind;
  late final SettingConfig<MapTileSrc> mainMapTileSrc;
  late final SettingConfig<double> mainMapOpacity;
  late final SettingConfig<String> datadogSdkId;

  SettingsMgr(SharedPreferences prefs) {
    // --- General
    groundMode = SettingConfig(this, prefs, "General", "groundMode", false,
        title: "Ground Support Mode",
        icon: const Icon(Icons.directions_car),
        description: "Alters UI and doesn't record track.");

    autoRecordFlight = SettingConfig(this, prefs, "General", "autoRecordFlight", true,
        title: "Auto Record Flight",
        icon: const Icon(Icons.play_arrow),
        description: "Flight recorder automatically starts and stops.");

    // --- UI
    primaryAltimeter = SettingConfig(this, prefs, "UI", "primaryAltimeter", AltimeterMode.msl,
        title: "Primary Altimeter",
        icon: const Icon(Icons.vertical_align_top),
        description: "Which altimeter is on top.");
    altimeterVsiThresh = SettingConfig(this, prefs, "UI", "altimeterVsiThresh", 0.15,
        title: "Altimeter Arrow Threshold (m/s)",
        icon: SvgPicture.asset(
          "assets/images/arrow.svg",
          height: 20,
        ),
        description: "The \"deadzone\" for the up/down arrow next to altimeter.");
    mapControlsRightSide = SettingConfig(this, prefs, "UI", "mapControlsRightSide", false,
        title: "Right-handed UI",
        description: "Move map control buttons to the right side.",
        icon: const Icon(Icons.swap_horiz));
    showPilotNames = SettingConfig(this, prefs, "UI", "showPilotNames", false,
        title: "Always show pilot names", description: "", icon: const Icon(Icons.abc));

    showWeatherOverlay = SettingConfig(this, prefs, "UI", "showWeatherOverlay", false,
        title: "Show weather overlay", description: "", icon: const Icon(Icons.cloud));
    showAirspaceOverlay = SettingConfig(this, prefs, "UI", "showAirspaceOverlay", true,
        title: "Show airspace overlay",
        icon: SvgPicture.asset(
          "assets/images/airspace.svg",
          color: Colors.grey.shade400,
        ));

    // --- Display Units
    displayUnitDist = SettingConfig(this, prefs, "Display Units", "displayUnitDist", DisplayUnitsDist.imperial,
        title: "Distance", icon: const Icon(Icons.architecture));
    displayUnitSpeed = SettingConfig(this, prefs, "Display Units", "displayUnitSpeed", DisplayUnitsSpeed.mph,
        title: "Speed", icon: const Icon(Icons.timer));
    displayUnitVario = SettingConfig(this, prefs, "Display Units", "displayUnitVario", DisplayUnitsVario.fpm,
        title: "Vario", icon: const Icon(Icons.trending_up));

    // NOTE: hide this for now
    displayUnitFuel = SettingConfig(this, prefs, "Display Units", "displayUnitFuel", DisplayUnitsFuel.liter,
        title: "Fuel", icon: const Icon(Icons.local_gas_station), hidden: true);

    displayUnitDist.listenable.addListener(() {
      configUnits(dist: displayUnitDist.value);
    });
    displayUnitSpeed.listenable.addListener(() {
      configUnits(speed: displayUnitSpeed.value);
    });
    displayUnitVario.listenable.addListener(() {
      configUnits(vario: displayUnitVario.value);
    });
    displayUnitFuel.listenable.addListener(() {
      configUnits(fuel: displayUnitFuel.value);
    });

    configUnits(
        speed: displayUnitSpeed.value,
        vario: displayUnitVario.value,
        dist: displayUnitDist.value,
        fuel: displayUnitFuel.value);

    // --- Misc
    adsbProximitySize = SettingConfig(this, prefs, "Misc", "adsbProximitySize", ProximitySize.medium,
        title: "ADSB Proximity Profile", icon: const Icon(Icons.radar));
    adsbTestAudio =
        SettingAction(this, "Misc", () => null, title: "Test Audio Cues", actionIcon: const Icon(Icons.volume_up));
    rumOptOut = SettingConfig(this, prefs, "Misc", "rumOptOut", false,
        title: "Opt-out of anonymous usage data",
        icon: const Icon(Icons.cancel),
        subtitle: Text.rich(TextSpan(children: [
          const WidgetSpan(child: Icon(Icons.help, size: 16, color: Colors.lightBlue)),
          const TextSpan(text: " View list of metrics captured "),
          TextSpan(
              text: "HERE.",
              style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  launchUrl(Uri.parse("https://github.com/eidolonFIRE/xcNav/blob/main/usage_stats.md"));
                })
        ])));

    // --- Debug Tools
    spoofLocation = SettingConfig(this, prefs, "Debug Tools", "", false,
        title: "Spoof Location",
        icon: const Icon(
          Icons.location_off,
          color: Colors.red,
        ),
        description: "Useful for test driving while on the ground.");
    clearMapCache = SettingAction(this, "Debug Tools", () {},
        title: "Clear Map Cache",
        actionIcon: const Icon(
          Icons.map,
          color: Colors.red,
        ));
    clearAvatarCache = SettingAction(this, "Debug Tools", () => null,
        title: "Clear Cached Avatars",
        actionIcon: const Icon(
          Icons.account_circle,
          color: Colors.red,
        ));
    eraseIdentity = SettingAction(this, "Debug Tools", () => null,
        title: "Erase Identity",
        actionIcon: const Icon(
          Icons.badge,
          color: Colors.red,
        ));

    // --- Hidden
    chatTTS = SettingConfig(this, prefs, "UI", "chatTTS", false, title: "Chat text-to-speech", hidden: true);
    groundModeTelem = SettingConfig(this, prefs, "General", "groundModeTelem", false,
        title: "Ground Mode Telemetry",
        icon: const Icon(Icons.minor_crash),
        description: "Transmit telemetry while in ground support mode.",
        hidden: true);
    northlockMap = SettingConfig(this, prefs, "UI", "northlockMap", false, title: "Lock map to North-Up", hidden: true);
    northlockWind =
        SettingConfig(this, prefs, "UI", "northlockWind", false, title: "Lock wind detector to North-Up", hidden: true);
    mainMapTileSrc =
        SettingConfig(this, prefs, "UI", "mainMapTileSrc", MapTileSrc.topo, title: "Map Tile Sourc", hidden: true);
    mainMapOpacity = SettingConfig(this, prefs, "UI", "mainMapOpacity", 1.0, title: "Main Map Opacity", hidden: true);
    datadogSdkId = SettingConfig(this, prefs, "Debug", "datadogSdkId", "", title: "DatadogSdk user ID", hidden: true);
  }
}

/// Singleton
late final SettingsMgr settingsMgr;

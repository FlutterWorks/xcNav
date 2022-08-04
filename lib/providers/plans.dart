import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:xcnav/models/flight_plan.dart';

class Plans with ChangeNotifier {
  final Map<String, FlightPlan> _loadedPlans = {};
  Map<String, FlightPlan> get loadedPlans => _loadedPlans;

  Plans() {
    refreshPlansFromDirectory();
  }

  Future setPlan(FlightPlan plan) {
    _loadedPlans[plan.name] = plan;
    notifyListeners();
    return _savePlanToFile(plan.name);
  }

  bool hasPlan(String name) {
    return _loadedPlans.keys.toSet().contains(name);
  }

  void refreshPlansFromDirectory() async {
    debugPrint("Refreshing Plans From Directory");
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory appDocDirFolder = Directory("${appDocDir.path}/flight_plans/");
    if (await appDocDirFolder.exists()) {
      _loadedPlans.clear();
      // Async load in all the files

      var files = await appDocDirFolder.list(recursive: false, followLinks: false).toList();
      // debugPrint("${files.length} log files found.");
      List<Completer> completers = [];
      for (var each in files) {
        var completer = Completer();
        completers.add(completer);
        File.fromUri(each.uri).readAsString().then((value) {
          var plan = FlightPlan.fromJson(each.uri.pathSegments.last.replaceAll(".json", ""), jsonDecode(value));
          if (plan.waypoints.isNotEmpty) {
            _loadedPlans[plan.name] = plan;
          } else {
            // plan was empty, delete it
            File planFile = File.fromUri(each.uri);
            planFile.exists().then((value) {
              planFile.delete();
            });
          }

          completer.complete();
        });
      }
      // debugPrint("${completers.length} completers created.");
      Future.wait(completers.map((e) => e.future).toList()).then((value) {
        notifyListeners();
      });
    } else {
      debugPrint('"flight_plans" directory doesn\'t exist yet!');
    }
  }

  void deletePlan(String name) {
    // Delete the file
    final plan = _loadedPlans[name];
    if (plan != null) {
      plan.getFilename().then((filename) {
        File planFile = File(filename);
        planFile.exists().then((value) {
          planFile.delete();
        });
      });
      _loadedPlans.remove(name);
      notifyListeners();
    } else {
      debugPrint("Warn: Tried to delete a plan that isn't loaded $name");
      debugPrint(_loadedPlans.keys.toString());
    }
  }

  Future duplicatePlan(String oldName, String newName) async {
    final plan = _loadedPlans[oldName];
    if (plan != null) {
      plan.name = newName;
      _savePlanToFile(oldName);
      refreshPlansFromDirectory();
    } else {
      debugPrint("Warn: Tried to rename a plan that isn't loaded $oldName");
      debugPrint(_loadedPlans.keys.toString());
    }
  }

  void renamePlan(String oldName, String newName) {
    final plan = _loadedPlans[oldName];
    if (plan != null) {
      deletePlan(oldName);
      plan.name = newName;
      setPlan(plan);
    } else {
      debugPrint("Warn: Tried to rename a plan that isn't loaded $oldName");
      debugPrint(_loadedPlans.keys.toString());
    }
  }

  Future _savePlanToFile(String name) {
    final plan = _loadedPlans[name];
    if (plan != null) {
      Completer completer = Completer();
      plan.getFilename().then((filename) {
        File file = File(filename);

        file.create(recursive: true).then((value) => file
            .writeAsString(jsonEncode({"title": name, "waypoints": plan.waypoints.map((e) => e.toJson()).toList()}))
            .then((_) => completer.complete()));
      });
      return completer.future;
    } else {
      return Future.value();
    }
  }
}

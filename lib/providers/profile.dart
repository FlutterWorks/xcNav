import 'dart:async';
import 'dart:io';

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:xcnav/secrets.dart';

class Profile with ChangeNotifier {
  String? name;
  String? id;
  String? secretID;
  Image avatar = Image.asset("assets/images/default_avatar.png");
  Uint8List? _avatarRaw;
  String? avatarHash;
  String? _tier;

  late String hash;

  Uint8List? get avatarRaw => _avatarRaw;

  late SharedPreferences prefs;

  bool isLoaded = false;
  final _onLoad = Completer();
  Future<void> get onLoad => _onLoad.future;

  Profile() {
    load();
    hash = _hash();
  }

  load() async {
    prefs = await SharedPreferences.getInstance();

    name = prefs.getString("profile.name");
    id = prefs.getString("profile.id");
    secretID = prefs.getString("profile.secretID");
    tier = prefs.getString("profile.tier");

    final loadedAvatarStr = prefs.getString("profile.avatar");
    _avatarRaw = loadedAvatarStr != null ? base64Decode(loadedAvatarStr) : null;
    if (_avatarRaw != null) {
      avatar = Image.memory(_avatarRaw!);
    } else {
      avatar = Image.asset("assets/images/default_avatar.png");
    }
    updateAvatarHash();

    debugPrint("Loaded Profile: $name, $id, $secretID, avatar: ${_avatarRaw?.length ?? 0}");

    hash = _hash();

    isLoaded = true;
    _onLoad.complete();

    // Add context to logging
    DatadogSdk.instance.setUserInfo(name: name, id: id);
  }

  bool get isValid => nameValidator(name) == null && id != null;

  static String? nameValidator(String? name) {
    if (name != null) {
      if (name.trim().length < 2) return "Must be at least 2 characters.";
    } else {
      return "Must not be empty.";
    }
    return null;
  }

  eraseIdentity() {
    prefs.remove("profile.name");
    prefs.remove("profile.id");
    prefs.remove("profile.secretID");
    prefs.remove("profile.avatar");
    prefs.remove("profile.tier");

    // Delete cached avatar
    path_provider.getTemporaryDirectory().then((tempDir) {
      var infile = File("${tempDir.path}/avatar.jpg");
      infile.exists().then((exists) {
        if (exists) {
          infile.delete();
        }
      });
    });
  }

  updateAvatarHash() {
    if (_avatarRaw != null) {
      avatarHash = md5.convert(_avatarRaw!).toString();
    } else {
      avatarHash = null;
    }
  }

  String? get tier => _tier;
  set tier(String? newTier) {
    _tier = newTier;
    if (_tier == null) {
      prefs.remove("profile.tier");
    } else {
      prefs.setString("profile.tier", _tier!);
    }
  }

  updateNameAvatar(String newName, Uint8List newRawAvatar) {
    name = newName.trim();
    _avatarRaw = newRawAvatar;
    avatar = Image.memory(newRawAvatar);
    updateAvatarHash();

    pushAvatar();

    prefs.setString("profile.name", newName.trim());
    prefs.setString("profile.avatar", base64Encode(newRawAvatar));

    // Save avatar to file
    path_provider.getTemporaryDirectory().then((tempDir) {
      var outfile = File("${tempDir.path}/avatar.jpg");
      outfile.writeAsBytes(newRawAvatar);
    });

    notifyListeners();
  }

  Future pushAvatar() async {
    return http
        .post(Uri.parse("https://$profileStoreUrl"),
            headers: {"Content-Type": "application/json", "authorizationToken": profileStoreToken},
            body: jsonEncode({"pilot_id": id, "avatar": base64Encode(avatarRaw!)}))
        .then((http.Response response) {
      final int statusCode = response.statusCode;

      if (statusCode < 200 || statusCode > 400) {
        // throw Exception("Error while pushing avatar: $statusCode");
        debugPrint("Error while pushing avatar: $statusCode");
      }
      return response.body;
    });
  }

  updateID(String newID, String newSecretID) {
    id = newID;
    secretID = newSecretID;

    debugPrint("Profile Update: $newID, $secretID");

    prefs.setString("profile.id", newID);
    prefs.setString("profile.secretID", newSecretID);

    hash = _hash();

    // Add context to logging
    DatadogSdk.instance.setUserInfo(id: newID, name: name);
  }

  String _hash() {
    // build long string
    String str = "Meta${name ?? ""}${id ?? ""}${avatarHash ?? ""}";

    // fold string into hash
    int hash = 0;
    for (int i = 0, len = str.length; i < len; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash &= 0xffffff;
    }
    return (hash < 0 ? hash * -2 : hash).toRadixString(16);
  }
}

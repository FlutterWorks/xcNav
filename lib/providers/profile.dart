import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class Profile with ChangeNotifier {
  String? name;
  String? id;
  String? secretID;
  Image avatar = Image.asset("assets/images/default_avatar.png");
  Uint8List? _avatarRaw;
  String? avatarHash;

  late String hash;

  Uint8List? get avatarRaw => _avatarRaw;

  late SharedPreferences prefs;

  Profile() {
    load();
    hash = _hash();
  }

  load() async {
    prefs = await SharedPreferences.getInstance();

    name = prefs.getString("profile.name");
    id = prefs.getString("profile.id");
    secretID = prefs.getString("profile.secretID");

    _avatarRaw = base64Decode(prefs.getString("profile.avatar") ?? "");
    if (_avatarRaw != null) {
      avatar = Image.memory(_avatarRaw!);
    } else {
      avatar = Image.asset("assets/images/default_avatar.png");
    }
    updateAvatarHash();

    debugPrint(
        "Loaded Profile: $name, $id, $secretID, avatar: ${_avatarRaw?.length ?? 0}");

    hash = _hash();
  }

  eraseIdentity() {
    prefs.remove("profile.name");
    prefs.remove("profile.id");
    prefs.remove("profile.secretID");
    prefs.remove("profile.avatar");
  }

  updateAvatarHash() {
    if (_avatarRaw != null) {
      avatarHash = md5.convert(_avatarRaw!).toString();
    } else {
      avatarHash = null;
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
    notifyListeners();
  }

  Future pushAvatar() async {
    return http
        .post(
            Uri.parse(
                "https://gx49w49rb4.execute-api.us-west-1.amazonaws.com/xcnav_avatar_service"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(
                {"pilot_id": id, "avatar": base64Encode(avatarRaw!)}))
        .then((http.Response response) {
      final int statusCode = response.statusCode;

      if (statusCode < 200 || statusCode > 400) {
        throw Exception("Error while pushing avatar");
      }
      return json.decode(response.body);
    });
  }

  updateID(String newID, String newSecretID) {
    id = newID;
    secretID = newSecretID;

    debugPrint("Profile Update: $newID, $secretID");

    prefs.setString("profile.id", newID);
    prefs.setString("profile.secretID", newSecretID);

    hash = _hash();

    // TODO: does this actually need to happen here?
    // notifyListeners();
  }

  String _hash() {
    // build long string
    String str = "Meta" +
        (name ?? "") +
        (id ?? "") +
        (_avatarRaw != null ? base64Encode(_avatarRaw!) : "");

    // fold string into hash
    int hash = 0;
    for (int i = 0, len = str.length; i < len; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash |= 0;
    }
    return (hash < 0 ? hash * -2 : hash).toRadixString(16);
  }
}

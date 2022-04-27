import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:xcnav/providers/group.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/widgets/avatar_round.dart';
import 'package:xcnav/widgets/map_marker.dart';

class WaypointCardReadOnly extends StatelessWidget {
  const WaypointCardReadOnly(
      {Key? key,
      required this.waypoint,
      required this.index,
      required this.onSelect,
      required this.onAdd,
      required this.isSelected})
      : super(key: key);

  final Waypoint waypoint;
  final int index;
  final bool isSelected;

  // callbacks
  final VoidCallback onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? Colors.blue[600] : Colors.grey[800],
      key: ValueKey(waypoint),
      margin: const EdgeInsets.all(1),
      child: ListTile(
          selected: isSelected,
          selectedColor: Colors.black,
          contentPadding: EdgeInsets.zero,
          leading: AspectRatio(
            aspectRatio: 1,
            child: Image.asset(
              "assets/images/wp" +
                  (waypoint.latlng.length > 1 ? "_path" : "") +
                  (waypoint.isOptional ? "_optional" : "") +
                  ".png",
              color: Color(waypoint.color ?? Colors.black.value),
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: TextButton(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(children: [
                          if (waypoint.icon != null)
                            WidgetSpan(
                              child: Icon(
                                iconOptions[waypoint.icon],
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          if (waypoint.icon != null) const TextSpan(text: " "),
                          TextSpan(
                            text: waypoint.name,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 20),
                          ),
                        ]),
                      )),
                  onPressed: onSelect,
                ),
              ),
            ],
          ),
          trailing: IconButton(
            onPressed: onAdd,
            icon: const Icon(
              Icons.add_circle,
              size: 24,
              color: Colors.green,
            ),
          )),
    );
  }
}

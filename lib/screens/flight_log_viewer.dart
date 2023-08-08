import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/dialogs/log_filters.dart';

// Models
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/widgets/basic_log_aggregate.dart';
import 'package:xcnav/widgets/chart_log_aggregate.dart';
import 'package:xcnav/widgets/chart_log_duration_hist.dart';
import 'package:xcnav/widgets/chart_log_fuel_insights.dart';

// Widgets
import 'package:xcnav/widgets/flight_log_card.dart';

class FlightLogViewer extends StatefulWidget {
  const FlightLogViewer({Key? key}) : super(key: key);

  @override
  State<FlightLogViewer> createState() => _FlightLogViewerState();
}

class _FlightLogViewerState extends State<FlightLogViewer> with TickerProviderStateMixin {
  Map<String, FlightLog> logs = {};
  late List<FlightLog> logsSlice;
  List<LogFilter>? logFilters;

  bool loaded = false;

  late final TabController mainTabController;
  final logListController = ScrollController();

  // Fuel Chart
  ChartFuelModeX chartFuelX = ChartFuelModeX.spd;
  ChartFuelModeY chartFuelY = ChartFuelModeY.rate;

  @override
  void initState() {
    super.initState();
    mainTabController = TabController(length: 2, vsync: this);
    refreshLogsFromDirectory();

    // --- Generate fake logs for debugging
    // final rand = Random();
    // for (int t = 0; t < 50; t++) {
    //   debugPrint("Gen fake log: $t");
    //   final startTime = DateTime.now().subtract(Duration(days: rand.nextInt(600), hours: rand.nextInt(24)));
    //   logs["$t"] = FlightLog.fromJson("$t", {
    //     "samples": [
    //       Geo.fromJson({
    //         "lat": 1,
    //         "lng": 1,
    //         "alt": 1,
    //         "time": startTime.millisecondsSinceEpoch,
    //         "hdg": 0,
    //         "spd": 0,
    //         "vario": 0
    //       }).toJson(),
    //       Geo.fromJson({
    //         "lat": 1,
    //         "lng": 2,
    //         "alt": 1,
    //         "time": startTime
    //             .add(Duration(minutes: (60 + pow(rand.nextDouble(), 1.2) * (rand.nextInt(2) * 2 - 1) * 50).round()))
    //             .millisecondsSinceEpoch,
    //         "hdg": 0,
    //         "spd": 0,
    //         "vario": 0
    //       }).toJson()
    //     ]
    //   });
    // }

    // loaded = true;
    // refreshSlice(sliceSize);
  }

  @override
  void dispose() {
    super.dispose();
    mainTabController.dispose();
  }

  void refreshLogsFromDirectory() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory appDocDirFolder = Directory("${appDocDir.path}/flight_logs/");
    if (await appDocDirFolder.exists()) {
      //if folder already exists return path
      setState(() {
        loaded = false;
      });

      logs.clear();

      // Async load in all the files
      var files = await appDocDirFolder.list(recursive: false, followLinks: false).toList();
      // debugPrint("${files.length} log files found.");
      List<Completer> completers = [];
      for (var each in files) {
        var completer = Completer();
        completers.add(completer);

        File.fromUri(each.uri).readAsString().then((value) {
          debugPrint("Loading log: ${each.uri}");
          try {
            logs[each.uri.path] = FlightLog.fromJson(each.path, jsonDecode(value), rawJson: value);
            // completer.complete();
          } catch (err, trace) {
            // This is reached if the error happens during json parsing
            // Create a "bad file" entry so user can opt to remove it
            logs[each.uri.path] = FlightLog.fromJson(each.path, {}, rawJson: value);
            debugPrint("Caught log loading error on file ${each.uri}: $err $trace");
            DatadogSdk.instance.logs?.error("Failed to load FlightLog",
                errorMessage: err.toString(), errorStackTrace: trace, attributes: {"filename": each.path});
          }
          completer.complete();
        });
      }
      // debugPrint("${completers.length} completers created.");
      Future.wait(completers.map((e) => e.future).toList()).then((value) {
        setState(() {
          loaded = true;
          refreshSlice();
        });
      });
    } else {
      debugPrint('"flight_logs" directory doesn\'t exist yet!');
    }
  }

  void refreshSlice() {
    if (logFilters?.isNotEmpty ?? false) {
      // Filter logs by search functions
      logsSlice = logs.values.where((element) => logFilters!.map((e) => e(element)).reduce((a, b) => a && b)).toList();
    } else {
      logsSlice = logs.values.toList();
    }
    logsSlice.sort((a, b) => (a.startTime?.millisecondsSinceEpoch ?? 0) - (b.startTime?.millisecondsSinceEpoch ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Flight Logs",
        ),
        bottom: TabBar(controller: mainTabController, tabs: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Padding(
                padding: EdgeInsets.all(12.0),
                child: Icon(Icons.list),
              ),
              Text("Entries")
            ],
          ),
          Row(mainAxisSize: MainAxisSize.min, children: const [
            Padding(
              padding: EdgeInsets.all(12.0),
              child: Icon(Icons.insights),
            ),
            Text("Stats")
          ]),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          editLogFilters(context).then((value) {
            setState(() {
              if (value != null) {
                logFilters = value;
                refreshSlice();
              }
            });
          });
        },
        child: const Icon(Icons.search),
      ),
      body: TabBarView(
        physics: const NeverScrollableScrollPhysics(),
        controller: mainTabController,
        children: [
          // --- Each
          !loaded
              ? const Center(
                  child: CircularProgressIndicator.adaptive(),
                )
              : ListView(
                  controller: logListController,
                  children: logsSlice
                      .map((e) => FlightLogCard(e, () {
                            setState(() {
                              logs.remove(e);
                              // logKeys.removeAt(i);
                              refreshSlice();
                            });
                          }))
                      .toList()
                      .reversed
                      .toList(),
                ),

          // --- Stats
          !loaded
              ? const Center(
                  child: CircularProgressIndicator.adaptive(),
                )
              : ListView(
                  children: [
                    Container(
                      height: 10,
                    ),

                    // --- Basic Aggregate
                    Text(
                      "Summary",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Card(
                        color: Colors.grey.shade800,
                        child: Padding(
                          padding: const EdgeInsets.all(10.0),
                          child: BasicLogAggregate(logs: logsSlice),
                        ),
                      ),
                    ),

                    Container(
                      height: 10,
                    ),

                    // --- Hist
                    Text(
                      "Flight Duration (histogram)",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(
                      // width: MediaQuery.of(context).size.width,
                      height: 200,
                      child: ClipRect(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20, top: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: ChartLogDurationHist(
                              logs: logsSlice,
                            ),
                          ),
                        ),
                      ),
                    ),

                    Container(
                      height: 10,
                    ),

                    // --- Monthly Aggregate
                    // if (sliceSize.index > SliceSize.month.index)
                    Text(
                      "Monthly Totals",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    // if (sliceSize.index > SliceSize.month.index)
                    SizedBox(
                      width: MediaQuery.of(context).size.width,
                      height: 200,
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: ChartLogAggregate(
                          logs: logsSlice,
                          mode: ChartLogAggregateMode.year,
                        ),
                      ),
                    ),

                    Container(
                      height: 10,
                    ),
                    Text(
                      "Fuel Insights",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),

                    Container(
                      height: 10,
                    ),

                    SizedBox(
                      width: MediaQuery.of(context).size.width,
                      height: 200,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 20, 10),
                        child: ChartLogFuelInsights(
                          logsSlice: logsSlice,
                          chartFuelModeX: chartFuelX,
                          chartFuelModeY: chartFuelY,
                        ),
                      ),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ToggleButtons(
                          isSelected: ChartFuelModeY.values.map((e) => e == chartFuelY).toList(),
                          onPressed: (index) {
                            setState(() {
                              chartFuelY = ChartFuelModeY.values[index];
                            });
                          },
                          children: const [
                            Text(
                              "Burn\nRate",
                              textAlign: TextAlign.center,
                            ),
                            Text("Eff.")
                          ],
                        ),
                        SizedBox(
                            width: MediaQuery.of(context).size.width / 10,
                            child: const Divider(
                              thickness: 2,
                            )),
                        ToggleButtons(
                          isSelected: ChartFuelModeX.values.map((e) => e == chartFuelX).toList(),
                          onPressed: (index) {
                            setState(() {
                              chartFuelX = ChartFuelModeX.values[index];
                            });
                          },
                          children: const [
                            Text("Alt."),
                            Text(
                              "Alt.\nGained",
                              textAlign: TextAlign.center,
                            ),
                            Text("Speed")
                          ],
                        )
                      ],
                    ),

                    Container(
                      height: 100,
                    ),
                  ],
                )
        ],
      ),
    );
  }
}

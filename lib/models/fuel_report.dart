import 'dart:math';

import 'package:xcnav/douglas_peucker.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/util.dart';

class FuelReport {
  late final DateTime time;

  /// Liters
  late final double amount;

  FuelReport(this.time, this.amount);
  FuelReport.fromJson(Map<String, dynamic> data) {
    time = DateTime.fromMillisecondsSinceEpoch(data["time"]);
    amount = parseAsDouble(data["amount"]) ?? 0;
  }

  dynamic toJson() {
    return {"time": time.millisecondsSinceEpoch, "amount": amount};
  }
}

class FuelStat {
  /// Liters burned
  late final double amount;
  late final Duration durationTime;
  late final double durationDist;

  /// Liters / Hour
  late final double rate;

  /// Mileage (meters / liter)
  late final double mpl;
  late final double meanAlt;
  late final double meanSpd;
  late double altGained;

  FuelStat(this.amount, this.durationTime, this.durationDist, this.rate, this.mpl, this.meanAlt, this.meanSpd,
      this.altGained);

  FuelStat.fromSamples(FuelReport start, FuelReport end, List<Geo> samples) {
    amount = start.amount - end.amount;
    durationTime = end.time.difference(start.time);
    rate = amount / (durationTime.inMilliseconds / const Duration(hours: 1).inMilliseconds);
    double tempDurationDist = 0;
    for (int i = 0; i < samples.length - 1; i++) {
      tempDurationDist = tempDurationDist + samples[i].distanceTo(samples[i + 1]);
    }
    durationDist = tempDurationDist;
    mpl = durationDist / amount;
    meanAlt = samples.map((e) => e.alt).reduce((a, b) => a + b) / samples.length;
    meanSpd = samples.map((e) => e.spd).reduce((a, b) => a + b) / samples.length;

    altGained = 0;
    final values = douglasPeucker(samples.map((e) => e.alt).toList(), 3);
    for (int t = 0; t < values.length - 1; t++) {
      altGained = altGained + max(0, values[t + 1] - values[t]);
    }
  }

  /// Stats are combined with weight; biasing towards the longest duration
  operator +(FuelStat other) {
    final ratio = durationTime.inMilliseconds / (durationTime.inMilliseconds + other.durationTime.inMilliseconds);
    double weight(a, b) {
      return a * ratio + (1 - ratio) * b;
    }

    final newAmount = amount + other.amount;
    final newDurationTime = durationTime + other.durationTime;
    final newDurationDist = durationDist + other.durationDist;
    final newRate = weight(rate, other.rate);
    final newMpL = weight(mpl, other.mpl);

    final newMeanAlt = weight(meanAlt, other.meanAlt);
    final newMeanSpd = weight(meanSpd, other.meanSpd);
    final newAltGained = altGained + other.altGained;
    return FuelStat(newAmount, newDurationTime, newDurationDist, newRate, newMpL, newMeanAlt, newMeanSpd, newAltGained);
  }
}

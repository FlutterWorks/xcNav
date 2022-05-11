import 'dart:math';
import 'package:flutter/material.dart';

class WindPlotPainter extends CustomPainter {
  late Paint _paint;
  final List<double> dataX;
  final List<double> dataY;
  final double maxValue;
  late Paint _paintGrid;

  late Offset circleCenter;
  late double circleRadius;
  late final Paint circlePaint;

  late Paint _barbPaint;

  WindPlotPainter(Color color, double width, this.dataX, this.dataY,
      this.maxValue, this.circleCenter, this.circleRadius) {
    _paint = Paint()..color = color;
    _paint.style = PaintingStyle.fill;

    _paintGrid = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    circlePaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    _barbPaint = Paint()
      ..color = Colors.redAccent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final maxSize = min(size.width, size.height) / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    // Paint grid
    const _pad = 0.9;
    canvas.drawLine(Offset(size.width * (1 - _pad), size.height / 2),
        Offset(size.width * _pad, size.height / 2), _paintGrid);
    canvas.drawLine(Offset(size.width / 2, size.height * (1 - _pad)),
        Offset(size.width / 2, size.height * _pad), _paintGrid);

    // Paint samples
    for (int i = 0; i < dataX.length; i++) {
      canvas.drawCircle(
          Offset(dataX[i], dataY[i]) * maxSize / maxValue + center, 3, _paint);
    }

    // Paint Wind fit
    final _circleCenter = circleCenter * maxSize / maxValue + center;
    canvas.drawCircle(
        _circleCenter, circleRadius * maxSize / maxValue, circlePaint);

    // Wind barb
    canvas.drawLine(center, _circleCenter, _barbPaint);
  }

  @override
  bool shouldRepaint(WindPlotPainter oldDelegate) {
    return true;
    //oldDelegate.maxValue != maxValue;
  }
}

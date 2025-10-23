import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/equalizer_settings.dart';
import 'package:aradia/resources/services/equalizer_service.dart';
import 'package:flutter/material.dart';

class EqualizerIcon extends StatefulWidget {
  final double size;

  const EqualizerIcon({
    super.key,
    this.size = 24.0,
  });

  @override
  State<EqualizerIcon> createState() => EqualizerIconState();
}

class EqualizerIconState extends State<EqualizerIcon> {
  late EqualizerService _equalizerService;
  EqualizerSettings _settings = EqualizerSettings.defaultSettings();

  @override
  void initState() {
    super.initState();
    _equalizerService = EqualizerService();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _equalizerService.init();
    if (mounted) {
      setState(() {
        _settings = _equalizerService.getActiveSettings();
      });
    }
  }

  // Refresh the icon when dialog is closed
  void refresh() {
    if (mounted) {
      setState(() {
        _settings = _equalizerService.getActiveSettings();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 5 bands: 60Hz, 230Hz, 910Hz, 4kHz, 14kHz
    final bands = [
      _settings.band60Hz,
      _settings.band230Hz,
      _settings.band910Hz,
      _settings.band4kHz,
      _settings.band14kHz,
    ];

    return CustomPaint(
      size: Size(widget.size, widget.size),
      painter: _EqualizerPainter(
        bands: bands,
        enabled: _settings.enabled,
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final List<double> bands;
  final bool enabled;

  _EqualizerPainter({
    required this.bands,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = enabled ? AppColors.primaryColor : Colors.white54;

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.primaryColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // 5 columns (one per band), 5 rows
    const columns = 5;
    const rows = 5;

    final columnWidth = size.width / columns;
    final rowHeight = size.height / rows;
    final padding = columnWidth * 0.15; // 15% padding between bars

    for (int col = 0; col < columns; col++) {
      final gain = bands[col]; // -15.0 to +15.0
      final normalizedGain = (gain + 15.0) / 30.0; // 0.0 to 1.0
      final filledBars = (normalizedGain * rows).round().clamp(0, rows);

      for (int row = rows - 1; row >= 0; row--) {
        final x = col * columnWidth + padding;
        final y = size.height - (row + 1) * rowHeight + padding;
        final width = columnWidth - padding * 2;
        final height = rowHeight - padding * 2;

        final rect = Rect.fromLTWH(x, y, width, height);

        final isFilled = row < filledBars;

        if (isFilled) {
          canvas.drawRect(rect, paint);
        } else {
          canvas.drawRect(rect, borderPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter oldDelegate) {
    return oldDelegate.bands != bands || oldDelegate.enabled != enabled;
  }
}

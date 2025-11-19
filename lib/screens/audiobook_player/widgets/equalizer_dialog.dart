import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/equalizer_settings.dart';
import 'package:aradia/resources/services/equalizer_service.dart';
import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:flutter/material.dart';

class EqualizerDialog extends StatefulWidget {
  final MyAudioHandler audioHandler;

  const EqualizerDialog({
    super.key,
    required this.audioHandler,
  });

  @override
  State<EqualizerDialog> createState() => _EqualizerDialogState();
}

class _EqualizerDialogState extends State<EqualizerDialog> {
  late EqualizerService _equalizerService;
  late EqualizerSettings _currentSettings;

  // Individual band values
  double _band60Hz = 0.0;
  double _band230Hz = 0.0;
  double _band910Hz = 0.0;
  double _band4kHz = 0.0;
  double _band14kHz = 0.0;
  double _balance = 0.0;
  double _pitch = 1.0;
  bool _isEnabled = true;

  @override
  void initState() {
    super.initState();
    _equalizerService = EqualizerService();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _equalizerService.init();
    await _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    _currentSettings = _equalizerService.getActiveSettings();
    setState(() {
      _band60Hz = _currentSettings.band60Hz;
      _band230Hz = _currentSettings.band230Hz;
      _band910Hz = _currentSettings.band910Hz;
      _band4kHz = _currentSettings.band4kHz;
      _band14kHz = _currentSettings.band14kHz;
      _balance = _currentSettings.balance;
      _pitch = _currentSettings.pitch;
      _isEnabled = _currentSettings.enabled;
    });
    await _applySettings();
  }

  Future<void> _applySettings() async {
    await widget.audioHandler.setEqualizerEnabled(_isEnabled);
    await widget.audioHandler.setEqualizerBand(0, _band60Hz);
    await widget.audioHandler.setEqualizerBand(1, _band230Hz);
    await widget.audioHandler.setEqualizerBand(2, _band910Hz);
    await widget.audioHandler.setEqualizerBand(3, _band4kHz);
    await widget.audioHandler.setEqualizerBand(4, _band14kHz);
    await widget.audioHandler.setBalance(_balance);
    await widget.audioHandler.setPitch(_pitch);
  }

  Future<void> _saveCurrentSettings() async {
    final settings = EqualizerSettings(
      band60Hz: _band60Hz,
      band230Hz: _band230Hz,
      band910Hz: _band910Hz,
      band4kHz: _band4kHz,
      band14kHz: _band14kHz,
      balance: _balance,
      pitch: _pitch,
      enabled: _isEnabled,
    );
    await _equalizerService.saveActiveSettings(settings);
    await _applySettings();
  }

  void _showSavePresetDialog() {
    final TextEditingController nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Preset'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Preset Name',
            hintText: 'Enter a name for this preset',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final settings = EqualizerSettings(
                  band60Hz: _band60Hz,
                  band230Hz: _band230Hz,
                  band910Hz: _band910Hz,
                  band4kHz: _band4kHz,
                  band14kHz: _band14kHz,
                  balance: _balance,
                  pitch: _pitch,
                  enabled: _isEnabled,
                  presetName: name,
                );
                await _equalizerService.savePreset(name, settings);
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Preset "$name" saved')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showLoadPresetDialog() {
    final userPresets = _equalizerService.getPresetNames();
    final builtInPresets = EqualizerService.getBuiltInPresets();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load Preset'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (builtInPresets.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Built-in Presets',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...builtInPresets.entries.map((entry) {
                  return ListTile(
                    title: Text(entry.key),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _loadPreset(entry.value);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
              if (userPresets.isNotEmpty) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Your Presets',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...userPresets.map((name) {
                  return ListTile(
                    title: Text(name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          onPressed: () async {
                            await _equalizerService.deletePreset(name);
                            Navigator.pop(context);
                            _showLoadPresetDialog(); // Refresh list
                          },
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () {
                      final preset = _equalizerService.loadPreset(name);
                      if (preset != null) {
                        _loadPreset(preset);
                        Navigator.pop(context);
                      }
                    },
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreset(EqualizerSettings preset) async {
    setState(() {
      _band60Hz = preset.band60Hz;
      _band230Hz = preset.band230Hz;
      _band910Hz = preset.band910Hz;
      _band4kHz = preset.band4kHz;
      _band14kHz = preset.band14kHz;
      _balance = preset.balance;
      _pitch = preset.pitch;
      _isEnabled = preset.enabled;
    });
    await _saveCurrentSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "${preset.presetName}" loaded')),
      );
    }
  }

  Future<void> _resetToDefault() async {
    setState(() {
      _band60Hz = 0.0;
      _band230Hz = 0.0;
      _band910Hz = 0.0;
      _band4kHz = 0.0;
      _band14kHz = 0.0;
      _balance = 0.0;
      _pitch = 1.0;
      _isEnabled = true;
    });
    await _saveCurrentSettings();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 700),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title and Enable Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Equalizer',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? AppColors.darkTextColor : AppColors.textColor,
                  ),
                ),
                Switch(
                  value: _isEnabled,
                  activeThumbColor: AppColors.primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _isEnabled = value;
                    });
                    _saveCurrentSettings();
                  },
                ),
              ],
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _showLoadPresetDialog,
                  child: const Text('Load'),
                ),
                TextButton(
                  onPressed: _showSavePresetDialog,
                  child: const Text('Save'),
                ),
                TextButton(
                  onPressed: _resetToDefault,
                  child: const Text('Reset'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Frequency Band Sliders (5 vertical sliders)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Scale labels on the left
                  _buildScaleLabels(),
                  const SizedBox(width: 8),
                  // Sliders
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildVerticalSlider(
                          label: '60\nHz',
                          value: _band60Hz,
                          onChanged: (value) {
                            setState(() => _band60Hz = value);
                            _saveCurrentSettings();
                          },
                        ),
                        _buildVerticalSlider(
                          label: '230\nHz',
                          value: _band230Hz,
                          onChanged: (value) {
                            setState(() => _band230Hz = value);
                            _saveCurrentSettings();
                          },
                        ),
                        _buildVerticalSlider(
                          label: '910\nHz',
                          value: _band910Hz,
                          onChanged: (value) {
                            setState(() => _band910Hz = value);
                            _saveCurrentSettings();
                          },
                        ),
                        _buildVerticalSlider(
                          label: '4\nkHz',
                          value: _band4kHz,
                          onChanged: (value) {
                            setState(() => _band4kHz = value);
                            _saveCurrentSettings();
                          },
                        ),
                        _buildVerticalSlider(
                          label: '14\nkHz',
                          value: _band14kHz,
                          onChanged: (value) {
                            setState(() => _band14kHz = value);
                            _saveCurrentSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Balance Control
            _buildHorizontalControl(
              label: 'Balance',
              value: _balance,
              min: -1.0,
              max: 1.0,
              divisions: 20,
              onChanged: (value) {
                setState(() => _balance = value);
                _saveCurrentSettings();
              },
              leftLabel: 'L',
              rightLabel: 'R',
              showMono: true,
            ),

            const SizedBox(height: 16),

            // Pitch Control
            _buildHorizontalControl(
              label: 'Pitch',
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              onChanged: (value) {
                setState(() => _pitch = value);
                _saveCurrentSettings();
              },
              valueLabel: '${_pitch.toStringAsFixed(2)}x',
            ),

            const SizedBox(height: 20),

            // close button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: TextStyle(
                    color: AppColors.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScaleLabels() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 8),
        Text(
          '+15 dB',
          style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Text(
          '0 dB',
          style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Text(
          '-15 dB',
          style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 44), // Account for label height below sliders
      ],
    );
  }

  Widget _buildVerticalSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: value,
                min: -15.0,
                max: 15.0,
                divisions: 60,
                activeColor: AppColors.primaryColor,
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? leftLabel,
    String? rightLabel,
    String? valueLabel,
    bool showMono = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            if (showMono)
              Row(
                children: [
                  Checkbox(
                    value: value == 0.0,
                    onChanged: (checked) {
                      if (checked == true) {
                        onChanged(0.0);
                      }
                    },
                  ),
                  const Text('Mono', style: TextStyle(fontSize: 12)),
                ],
              ),
            if (valueLabel != null)
              Text(
                valueLabel,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
          ],
        ),
        Row(
          children: [
            if (leftLabel != null)
              SizedBox(
                width: 20,
                child: Text(
                  leftLabel,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                activeColor: AppColors.primaryColor,
                onChanged: onChanged,
              ),
            ),
            if (rightLabel != null)
              SizedBox(
                width: 20,
                child: Text(
                  rightLabel,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

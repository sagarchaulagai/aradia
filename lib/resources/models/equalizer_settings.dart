class EqualizerSettings {
  final double band60Hz;
  final double band230Hz;
  final double band910Hz;
  final double band4kHz;
  final double band14kHz;
  final double balance;
  final double pitch;
  final String? presetName;
  final bool enabled;

  EqualizerSettings({
    this.band60Hz = 0.0,
    this.band230Hz = 0.0,
    this.band910Hz = 0.0,
    this.band4kHz = 0.0,
    this.band14kHz = 0.0,
    this.balance = 0.0,
    this.pitch = 1.0,
    this.presetName,
    this.enabled = true,
  });

  // Default/Reset settings
  factory EqualizerSettings.defaultSettings() {
    return EqualizerSettings();
  }

  // Convert to Map for Hive storage
  Map<String, dynamic> toMap() {
    return {
      'band60Hz': band60Hz,
      'band230Hz': band230Hz,
      'band910Hz': band910Hz,
      'band4kHz': band4kHz,
      'band14kHz': band14kHz,
      'balance': balance,
      'pitch': pitch,
      'presetName': presetName,
      'enabled': enabled,
    };
  }

  factory EqualizerSettings.fromMap(Map<String, dynamic> map) {
    return EqualizerSettings(
      band60Hz: (map['band60Hz'] as num?)?.toDouble() ?? 0.0,
      band230Hz: (map['band230Hz'] as num?)?.toDouble() ?? 0.0,
      band910Hz: (map['band910Hz'] as num?)?.toDouble() ?? 0.0,
      band4kHz: (map['band4kHz'] as num?)?.toDouble() ?? 0.0,
      band14kHz: (map['band14kHz'] as num?)?.toDouble() ?? 0.0,
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 1.0,
      presetName: map['presetName'] as String?,
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  EqualizerSettings copyWith({
    double? band60Hz,
    double? band230Hz,
    double? band910Hz,
    double? band4kHz,
    double? band14kHz,
    double? balance,
    double? pitch,
    String? presetName,
    bool? enabled,
  }) {
    return EqualizerSettings(
      band60Hz: band60Hz ?? this.band60Hz,
      band230Hz: band230Hz ?? this.band230Hz,
      band910Hz: band910Hz ?? this.band910Hz,
      band4kHz: band4kHz ?? this.band4kHz,
      band14kHz: band14kHz ?? this.band14kHz,
      balance: balance ?? this.balance,
      pitch: pitch ?? this.pitch,
      presetName: presetName ?? this.presetName,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() {
    return 'EqualizerSettings(60Hz: $band60Hz, 230Hz: $band230Hz, 910Hz: $band910Hz, '
        '4kHz: $band4kHz, 14kHz: $band14kHz, balance: $balance, pitch: $pitch, '
        'preset: $presetName, enabled: $enabled)';
  }

  List<double> getBands() {
    return [band60Hz, band230Hz, band910Hz, band4kHz, band14kHz];
  }

  static List<String> getBandLabels() {
    return ['60\nHz', '230\nHz', '910\nHz', '4\nkHz', '14\nkHz'];
  }
}

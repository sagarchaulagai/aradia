import 'package:aradia/resources/services/chromecast_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:permission_handler/permission_handler.dart';

class ChromeCastButton extends StatelessWidget {
  final ChromeCastService chromeCastService;

  const ChromeCastButton({
    super.key,
    required this.chromeCastService,
  });

  Future<void> _showDeviceDialog(BuildContext context) async {
    // Request location permission (required for WiFi scanning on Android 10+)
    final status = await Permission.location.request();
    
    if (!status.isGranted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission is required to discover ChromeCast devices'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    // Restart discovery to ensure devices are found after permission grant
    chromeCastService.stopDiscovery();
    await Future.delayed(const Duration(milliseconds: 500));
    chromeCastService.startDiscovery();
    
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => ChromeCastDeviceDialog(
          chromeCastService: chromeCastService,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GoogleCastSession?>(
      stream: chromeCastService.sessionStream,
      builder: (context, snapshot) {
        final isConnected = chromeCastService.isConnected;
        return IconButton(
          icon: Icon(
            isConnected ? Icons.cast_connected : Icons.cast,
            color: isConnected ? Colors.deepOrange : Colors.white,
          ),
          onPressed: () => _showDeviceDialog(context),
          tooltip: isConnected ? 'Connected to ChromeCast' : 'Cast to device',
        );
      },
    );
  }
}

class ChromeCastDeviceDialog extends StatelessWidget {
  final ChromeCastService chromeCastService;

  const ChromeCastDeviceDialog({
    super.key,
    required this.chromeCastService,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cast to Device'),
      content: SizedBox(
        width: double.maxFinite,
        child: StreamBuilder<List<GoogleCastDevice>>(
          stream: chromeCastService.devicesStream,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [];
            if (devices.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Searching for devices...'),
                  ],
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length + 1,
              itemBuilder: (context, index) {
                if (index == devices.length) {
                  return ListTile(
                    leading: const Icon(Icons.cancel),
                    title: const Text('Disconnect'),
                    onTap: () async {
                      await chromeCastService.disconnect();
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                }
                final device = devices[index];
                return ListTile(
                  leading: const Icon(Icons.cast),
                  title: Text(device.friendlyName),
                  subtitle: Text(device.modelName ?? 'Unknown model'),
                  onTap: () async {
                    try {
                      await chromeCastService.connectToDevice(device);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to connect: $e')),
                        );
                      }
                    }
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

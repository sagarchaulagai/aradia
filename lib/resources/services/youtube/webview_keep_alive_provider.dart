import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Provider class that manages the InAppWebViewKeepAlive instance
/// This ensures the WebView state is preserved across widget rebuilds
class WebViewKeepAliveProvider extends ChangeNotifier {
  late final InAppWebViewKeepAlive _keepAlive;

  WebViewKeepAliveProvider() {
    _keepAlive = InAppWebViewKeepAlive();
  }

  /// Get the InAppWebViewKeepAlive instance
  InAppWebViewKeepAlive get keepAlive => _keepAlive;

  @override
  void dispose() {
    // Clean up resources if needed
    super.dispose();
  }
}

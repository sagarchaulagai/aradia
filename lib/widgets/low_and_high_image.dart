import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class LowAndHighImage extends StatelessWidget {
  final String lowQImage;
  final String? highQImage;
  final double height;
  final double width;

  const LowAndHighImage({
    super.key,
    required this.lowQImage,
    required this.highQImage,
    this.height = 200,
    this.width = 200,
  });

  bool _isLocalPath(String path) {
    return path.startsWith('/storage/emulated');
  }

  @override
  Widget build(BuildContext context) {
    final String mainImage = lowQImage.contains('youtube') ? lowQImage : (highQImage ?? lowQImage);

    Widget _buildFallback() {
      if (_isLocalPath(lowQImage)) {
        return Image.file(
          File(lowQImage),
          fit: BoxFit.fill,
          height: height,
          width: width,
        );
      } else {
        return CachedNetworkImage(
          imageUrl: lowQImage,
          fit: BoxFit.fill,
          height: height,
          width: width,
        );
      }
    }

    Widget _buildImage(String path) {
      if (_isLocalPath(path)) {
        return Image.file(
          File(path),
          fit: BoxFit.fill,
          height: height,
          width: width,
        );
      } else {
        return CachedNetworkImage(
          imageUrl: path,
          fit: BoxFit.fill,
          height: height,
          width: width,
          errorWidget: (context, url, error) => _buildFallback(),
          placeholder: (context, url) => _buildFallback(),
        );
      }
    }

    return SizedBox(
      height: height,
      width: width,
      child: _buildImage(mainImage),
    );
  }
}

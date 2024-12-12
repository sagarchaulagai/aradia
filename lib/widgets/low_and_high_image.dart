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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: CachedNetworkImage(
        imageUrl: highQImage ?? lowQImage,
        fit: BoxFit.fill,
        errorWidget: (context, url, error) {
          return CachedNetworkImage(
            imageUrl: lowQImage,
            fit: BoxFit.fill,
          );
        },
        placeholder: ((context, url) {
          // TODO if the lowQ image was not already cached, then return SilverImage here
          return CachedNetworkImage(
            imageUrl: lowQImage,
            fit: BoxFit.fill,
          );
        }),
      ),
    );
  }
}

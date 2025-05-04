import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/widgets/rating_widget.dart';

class AudiobookItem extends StatelessWidget {
  final Audiobook audiobook;
  final double width;
  final double height;
  final void Function()? onLongPressed;

  const AudiobookItem({
    super.key,
    required this.audiobook,
    this.width = 175.0,
    this.height = 250.0,
    this.onLongPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Ink(
      width: width,
      height: height,
      child: Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(8),
          ),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(
            Radius.circular(8),
          ),
          splashColor: AppColors.primaryColor,
          splashFactory: InkRipple.splashFactory,
          onLongPress: onLongPressed,
          onTap: () {
            context.push(
              '/audiobook-details',
              extra: {
                'audiobook': audiobook,
                'isDownload': false,
                'isYoutube': false,
              },
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                child: CachedNetworkImage(
                  imageUrl: audiobook.lowQCoverImage,
                  width: width,
                  height: width,
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  bottom: 8,
                  left: 8,
                  right: 8,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: width,
                      child: Text(
                        audiobook.title,
                        style: GoogleFonts.ubuntu(
                          textStyle: const TextStyle(
                            overflow: TextOverflow.ellipsis,
                            fontSize: 14,
                          ),
                        ),
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      audiobook.author ?? 'Unknown',
                      style: GoogleFonts.ubuntu(
                        textStyle: const TextStyle(
                          overflow: TextOverflow.ellipsis,
                          fontSize: 12,
                        ),
                      ),
                      maxLines: 1,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RatingWidget(
                          rating: audiobook.rating ?? 0,
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.audiotrack,
                              size: 16,
                            ),
                            const SizedBox(
                              width: 5,
                            ),
                            Text(
                              audiobook.language ?? 'N/A',
                              style: GoogleFonts.ubuntu(
                                textStyle: const TextStyle(
                                  overflow: TextOverflow.ellipsis,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

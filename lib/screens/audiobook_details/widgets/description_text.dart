import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DescriptionText extends StatefulWidget {
  final String description;
  const DescriptionText({
    super.key,
    required this.description,
  });

  @override
  State<DescriptionText> createState() => _DescriptionTextState();
}

class _DescriptionTextState extends State<DescriptionText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: _isExpanded
          ? RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: widget.description,
                    style: GoogleFonts.ubuntu(
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: ' ... Tap to read less',
                    style: GoogleFonts.ubuntu(
                      fontSize: 13,
                      color: const Color.fromRGBO(204, 119, 34, 1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          : RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: <TextSpan>[
                  TextSpan(
                    text: widget.description.length > 150
                        ? widget.description.substring(0, 150)
                        : widget.description,
                    style: GoogleFonts.ubuntu(
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: ' ... Tap to read more',
                    style: GoogleFonts.ubuntu(
                      fontSize: 13,
                      color: const Color.fromRGBO(204, 119, 34, 1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

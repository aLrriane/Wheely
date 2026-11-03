import 'package:flutter/material.dart';

// the photo box used in the search results and the saves list.
// frontend only: Place has no photo field yet, so this draws the grey picture
// placeholder from the sketch.
// to connect: when places have photo urls, pass [url] and it will show the real image
class PlacePhoto extends StatelessWidget {
  const PlacePhoto({
    super.key,
    this.url,
    this.width = 120,
    this.height = 90,
  });

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: Colors.grey.shade300,
      child: const Icon(Icons.image_outlined, size: 32, color: Colors.black45),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

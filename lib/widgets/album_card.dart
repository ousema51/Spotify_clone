import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';

class AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback? onTap;

  const AlbumCard({super.key, required this.album, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 140,
                height: 140,
                child: album.coverUrl != null && album.coverUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: album.coverUrl!,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[800]),
                        errorWidget: (context, url, error) =>
                            Container(
                              color: const Color(0xFF282828),
                              child: const Icon(Icons.album_rounded,
                                  color: Colors.white54, size: 40),
                            ),
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: const Color(0xFF282828),
                        child: const Icon(Icons.album_rounded,
                            color: Colors.white54, size: 40),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            if (album.artist != null)
              Text(
                album.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
          ],
        ),
      ),
    );
  }
}

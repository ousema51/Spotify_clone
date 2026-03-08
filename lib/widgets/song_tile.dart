import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final bool? isLiked;
  final VoidCallback? onLike;
  final int? trackNumber;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.isLiked,
    this.onLike,
    this.trackNumber,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: song.coverUrl != null && song.coverUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: song.coverUrl!,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[800]),
                  errorWidget: (context, url, error) =>
                      Container(
                        color: const Color(0xFF282828),
                        child: const Icon(Icons.music_note,
                            color: Colors.white54, size: 24),
                      ),
                  fit: BoxFit.cover,
                )
              : Container(
                  color: const Color(0xFF282828),
                  child: const Icon(Icons.music_note,
                      color: Colors.white54, size: 24),
                ),
        ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        song.artist ?? 'Unknown Artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[400], fontSize: 12),
      ),
      trailing: onLike != null
          ? IconButton(
              icon: Icon(
                isLiked == true ? Icons.favorite : Icons.favorite_border,
                color: isLiked == true
                    ? const Color(0xFF1DB954)
                    : Colors.grey[400],
                size: 20,
              ),
              onPressed: onLike,
            )
          : null,
      onTap: onTap,
    );
  }
}

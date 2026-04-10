"""
YouTube Music backend search/metadata and stream resolution utilities.
"""

import logging
import os

logger = logging.getLogger(__name__)

ytmusic = None
try:
    from ytmusicapi import YTMusic

    ytmusic = YTMusic()
except Exception as e:
    logger.error("ytmusicapi failed: %s", e)

YoutubeDL = None
try:
    from yt_dlp import YoutubeDL
except Exception as e:
    logger.warning("yt-dlp not available: %s", e)


DEFAULT_STREAM_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 14; Pixel 7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/123.0.0.0 Mobile Safari/537.36"
    ),
    "Referer": "https://music.youtube.com/",
    "Origin": "https://music.youtube.com",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _safe_str(value):
    """Safely convert to string with UTF-8 encoding."""
    if value is None:
        return None
    if isinstance(value, str):
        try:
            value.encode("utf-8")
            return value
        except UnicodeEncodeError:
            return value.encode("utf-8", errors="replace").decode("utf-8")
    return str(value)


def _safe_int(value):
    if value is None:
        return None
    try:
        return int(float(value))
    except Exception:
        return None


def _extract_video_id(raw):
    value = _safe_str(raw)
    if not value:
        return None

    value = value.strip()
    if not value:
        return None

    # Fast path: already a likely video id.
    if len(value) == 11 and all(c.isalnum() or c in "_-" for c in value):
        return value

    # Query-based URL pattern.
    if "v=" in value:
        after = value.split("v=", 1)[1]
        candidate = after.split("&", 1)[0].strip()
        if len(candidate) == 11:
            return candidate

    # youtu.be short URL pattern.
    if "youtu.be/" in value:
        after = value.split("youtu.be/", 1)[1]
        candidate = after.split("?", 1)[0].split("/", 1)[0].strip()
        if len(candidate) == 11:
            return candidate

    # Last chance: scan for a token with valid charset and length.
    for token in value.replace("/", " ").replace("?", " ").replace("&", " ").split():
        token = token.strip()
        if len(token) == 11 and all(c.isalnum() or c in "_-" for c in token):
            return token

    return None


def _merged_stream_headers(raw_headers=None):
    merged = dict(DEFAULT_STREAM_HEADERS)
    if not isinstance(raw_headers, dict):
        return merged

    for key, value in raw_headers.items():
        k = (_safe_str(key) or "").strip()
        v = (_safe_str(value) or "").strip()
        if k and v:
            merged[k] = v
    return merged


def _get_thumbnail(r):
    """Extract thumbnail URL with fallback handling."""
    if r is None:
        return None

    thumbs = r.get("thumbnails")
    if isinstance(thumbs, list) and thumbs:
        url = thumbs[-1].get("url") if thumbs[-1] else None
        if url:
            url = _safe_str(url)
            if url and url.startswith("//"):
                return "https:{}".format(url)
            if url and url.startswith("http"):
                return url
            if url:
                return "https:{}".format(url)

    thumb_obj = r.get("thumbnail")
    if isinstance(thumb_obj, dict):
        inner = thumb_obj.get("thumbnails")
        if isinstance(inner, list) and inner:
            url = inner[-1].get("url") if inner[-1] else None
            if url:
                url = _safe_str(url)
                if url and url.startswith("http"):
                    return url
                if url:
                    return "https:{}".format(url)

    vid = r.get("videoId") or r.get("id")
    if vid:
        vid = _safe_str(vid)
        if vid:
            return "https://img.youtube.com/vi/{}/hqdefault.jpg".format(vid)

    return None


def _normalize(r):
    """Normalize song result from ytmusicapi with UTF-8 encoding."""
    if r is None:
        return None

    artists = r.get("artists") or []
    artist = None
    if artists:
        if isinstance(artists[0], dict):
            artist = artists[0].get("name")
        else:
            artist = artists[0]
    if not artist:
        artist = r.get("artist")

    artist = _safe_str(artist) or "Unknown Artist"

    return {
        "id": _safe_str(r.get("videoId") or r.get("id")),
        "title": _safe_str(r.get("title")) or "Unknown",
        "name": _safe_str(r.get("title")) or "Unknown",
        "artist": artist,
        "duration": r.get("duration"),
        "thumbnail": _get_thumbnail(r),
        "image": _get_thumbnail(r),
        "cover_url": _get_thumbnail(r),
    }


def _build_ytdlp_options():
    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
        "socket_timeout": 15,
        "extractor_retries": 2,
        "retries": 2,
        "format": "bestaudio[ext=m4a]/bestaudio/best",
    }

    cookie_file = (os.environ.get("YTDLP_COOKIEFILE") or "").strip()
    if cookie_file:
        opts["cookiefile"] = cookie_file

    # Format: browser[:profile[:keyring[:container]]]
    cookies_from_browser = (os.environ.get("YTDLP_COOKIES_FROM_BROWSER") or "").strip()
    if cookies_from_browser:
        parts = [p.strip() for p in cookies_from_browser.split(":") if p.strip()]
        if parts:
            opts["cookiesfrombrowser"] = tuple(parts)

    return opts


def _pick_best_format(info):
    formats = info.get("formats") or []
    best = None
    best_score = -1

    for fmt in formats:
        if not isinstance(fmt, dict):
            continue

        url = _safe_str(fmt.get("url"))
        if not url:
            continue

        acodec = (_safe_str(fmt.get("acodec")) or "").lower()
        if acodec == "none":
            continue

        vcodec = (_safe_str(fmt.get("vcodec")) or "").lower()
        ext = (_safe_str(fmt.get("ext")) or "").lower()
        bitrate = _safe_int(fmt.get("abr")) or _safe_int(fmt.get("tbr")) or 0

        score = bitrate
        if vcodec == "none":
            score += 40
        if ext in ("m4a", "mp4", "webm", "ogg"):
            score += 20

        if score > best_score:
            best_score = score
            best = fmt

    return best


def _build_stream_payload(info, selected, forced_video_id=None):
    stream_url = None
    extra_headers = None

    if isinstance(selected, dict):
        stream_url = _safe_str(selected.get("url"))
        extra_headers = selected.get("http_headers")

    if not stream_url and isinstance(info, dict):
        stream_url = _safe_str(info.get("url"))
        if not extra_headers:
            extra_headers = info.get("http_headers")

    if not stream_url:
        return None

    title = _safe_str(info.get("title") if isinstance(info, dict) else None)
    duration = _safe_int(info.get("duration") if isinstance(info, dict) else None)
    video_id = _safe_str(info.get("id") if isinstance(info, dict) else None)
    if not video_id:
        video_id = _safe_str(forced_video_id)

    return {
        "audio_url": stream_url,
        "headers": _merged_stream_headers(extra_headers),
        "video_id": video_id,
        "title": title,
        "duration": duration,
        "source": "yt-dlp",
    }


def _resolve_stream_from_yt_dlp(target, from_search=False):
    if not YoutubeDL:
        return {"success": False, "message": "yt-dlp not installed"}

    ydl_opts = _build_ytdlp_options()

    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(target, download=False)
    except Exception as e:
        logger.warning("yt-dlp extraction failed for %s: %s", target, e)
        return {"success": False, "message": str(e)}

    if from_search:
        if not isinstance(info, dict):
            return {"success": False, "message": "Invalid yt-dlp search response"}

        entries = info.get("entries") or []
        if not isinstance(entries, list):
            entries = []

        for entry in entries[:8]:
            if not isinstance(entry, dict):
                continue

            selected = _pick_best_format(entry)
            payload = _build_stream_payload(entry, selected)
            if payload:
                return {"success": True, "data": payload}

        return {"success": False, "message": "No playable search stream found"}

    if not isinstance(info, dict):
        return {"success": False, "message": "Invalid yt-dlp response"}

    selected = _pick_best_format(info)
    payload = _build_stream_payload(info, selected)
    if not payload:
        return {"success": False, "message": "No playable audio URL found"}

    return {"success": True, "data": payload}


# ---------------------------------------------------------------------------
# Public API - Search
# ---------------------------------------------------------------------------


def search_songs(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        query = _safe_str(query)
        start = (page - 1) * limit
        raw = ytmusic.search(query, filter="songs", limit=start + limit) or []
        songs = []
        for r in raw[start : start + limit]:
            if r.get("videoId"):
                normalized = _normalize(r)
                if normalized:
                    songs.append(normalized)
        return {"success": True, "data": songs}
    except Exception as e:
        logger.error("Search error: %s", e)
        return {"success": False, "message": str(e)}


def search_all(query=""):
    return search_songs(query)


def get_stream_url(video_id=""):
    resolved_id = _extract_video_id(video_id)
    if not resolved_id:
        return {"success": False, "message": "Invalid video_id"}

    target = "https://www.youtube.com/watch?v={}".format(resolved_id)
    result = _resolve_stream_from_yt_dlp(target, from_search=False)
    if result.get("success"):
        data = result.get("data") or {}
        if not data.get("video_id"):
            data["video_id"] = resolved_id
        result["data"] = data
    return result


def get_stream_from_search(query=""):
    query = (_safe_str(query) or "").strip()
    if not query:
        return {"success": False, "message": "No query provided"}

    ytdlp_result = _resolve_stream_from_yt_dlp(
        "ytsearch8:{}".format(query),
        from_search=True,
    )
    if ytdlp_result.get("success"):
        return ytdlp_result

    # Fallback: resolve first search hit by id.
    search_result = search_songs(query, page=1, limit=1)
    if search_result.get("success"):
        songs = search_result.get("data") or []
        if songs:
            first_id = _extract_video_id((songs[0] or {}).get("id"))
            if first_id:
                return get_stream_url(first_id)

    return {
        "success": False,
        "message": "Failed to resolve stream from search",
    }


def get_song_by_id(video_id=""):
    """Get song metadata with UTF-8 encoding and thumbnail fallback."""
    resolved_id = _extract_video_id(video_id)
    if not resolved_id:
        return {"success": False, "message": "Invalid video_id"}

    meta = {
        "title": None,
        "artist": "Unknown Artist",
        "duration": None,
        "thumbnail": "https://img.youtube.com/vi/{}/hqdefault.jpg".format(resolved_id),
    }

    if ytmusic:
        try:
            info = ytmusic.get_song(resolved_id)
            vd = info.get("videoDetails") or {}
            thumbs = vd.get("thumbnail", {}).get("thumbnails") or []

            meta["title"] = _safe_str(vd.get("title"))
            meta["artist"] = _safe_str(vd.get("author")) or meta["artist"]
            meta["duration"] = vd.get("lengthSeconds")

            if thumbs:
                turl = thumbs[-1].get("url") if thumbs[-1] else None
                if turl:
                    turl = _safe_str(turl)
                    if turl:
                        if turl.startswith("//"):
                            meta["thumbnail"] = "https:{}".format(turl)
                        else:
                            meta["thumbnail"] = turl
        except Exception as e:
            logger.error("Failed to fetch song metadata: %s", e)

    meta["title"] = meta["title"] or "Unknown Title ({})".format(resolved_id)
    meta["title"] = _safe_str(meta["title"])
    meta["artist"] = _safe_str(meta["artist"])

    return {
        "success": True,
        "data": {
            "id": resolved_id,
            "title": meta["title"],
            "artist": meta["artist"],
            "duration": meta["duration"],
            "thumbnail": meta["thumbnail"],
            "image": meta["thumbnail"],
            "cover_url": meta["thumbnail"],
        },
    }


# ---------------------------------------------------------------------------
# Albums / Artists / Trending
# ---------------------------------------------------------------------------


def search_albums(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        query = _safe_str(query)
        raw = ytmusic.search(query, filter="albums", limit=limit) or []
        start = (page - 1) * limit
        albums = []
        for r in raw[start : start + limit]:
            artists = r.get("artists") or [{}]
            artist_name = None
            if artists and isinstance(artists[0], dict):
                artist_name = artists[0].get("name")
            elif artists:
                artist_name = artists[0]

            album = {
                "id": _safe_str(r.get("browseId")),
                "title": _safe_str(r.get("title")) or "Unknown",
                "artist": _safe_str(artist_name) or "Unknown",
                "thumbnail": _get_thumbnail(r),
                "cover_url": _get_thumbnail(r),
                "image": _get_thumbnail(r),
            }
            albums.append(album)
        return {"success": True, "data": albums}
    except Exception as e:
        logger.error("Album search error: %s", e)
        return {"success": True, "data": []}


def search_artists(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        query = _safe_str(query)
        raw = ytmusic.search(query, filter="artists", limit=limit) or []
        start = (page - 1) * limit
        artists = []
        for r in raw[start : start + limit]:
            artist = {
                "id": _safe_str(r.get("browseId")),
                "name": _safe_str(r.get("artist")) or "Unknown",
                "thumbnail": _get_thumbnail(r),
                "image": _get_thumbnail(r),
            }
            artists.append(artist)
        return {"success": True, "data": artists}
    except Exception as e:
        logger.error("Artist search error: %s", e)
        return {"success": True, "data": []}


def get_album_by_id(album_id=""):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        album_id = _safe_str(album_id)
        album = ytmusic.get_album(album_id)

        artists = album.get("artists") or [{}]
        artist_name = None
        if artists and isinstance(artists[0], dict):
            artist_name = artists[0].get("name")
        elif artists:
            artist_name = artists[0]

        return {
            "success": True,
            "data": {
                "id": album_id,
                "title": _safe_str(album.get("title")) or "Unknown",
                "artist": _safe_str(artist_name) or "Unknown",
                "thumbnail": _get_thumbnail(album),
                "cover_url": _get_thumbnail(album),
                "image": _get_thumbnail(album),
                "tracks": [
                    _normalize(t) for t in (album.get("tracks") or []) if t
                ],
            },
        }
    except Exception as e:
        logger.error("Album get error: %s", e)
        return {"success": False, "message": str(e)}


def get_artist_by_id(artist_id=""):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        artist_id = _safe_str(artist_id)
        artist = ytmusic.get_artist(artist_id)

        songs = [
            _normalize(s) for s in (artist.get("songs", {}).get("results") or []) if s
        ]

        return {
            "success": True,
            "data": {
                "id": artist_id,
                "name": _safe_str(artist.get("name")) or "Unknown",
                "thumbnail": _get_thumbnail(artist),
                "image": _get_thumbnail(artist),
                "image_url": _get_thumbnail(artist),
                "songs": songs,
            },
        }
    except Exception as e:
        logger.error("Artist get error: %s", e)
        return {"success": False, "message": str(e)}


def get_trending():
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search("top hits USA", filter="songs", limit=40) or []
        songs = []
        for r in raw:
            if r.get("videoId"):
                normalized = _normalize(r)
                if normalized:
                    songs.append(normalized)
        return {"success": True, "data": songs[:20]}
    except Exception as e:
        logger.error("Trending error: %s", e)
        return {"success": True, "data": []}


def health_check():
    status = {
        "ytmusic": ytmusic is not None,
        "yt_dlp": YoutubeDL is not None,
        "search": False,
        "stream": YoutubeDL is not None,
        "cookiefile_configured": bool((os.environ.get("YTDLP_COOKIEFILE") or "").strip()),
        "cookies_from_browser_configured": bool(
            (os.environ.get("YTDLP_COOKIES_FROM_BROWSER") or "").strip()
        ),
    }
    if ytmusic:
        try:
            r = ytmusic.search("test", filter="songs", limit=1)
            status["search"] = bool(r)
            if r:
                thumb = _get_thumbnail(r[0])
                status["thumbnail_test"] = thumb if thumb else "null"
        except Exception as e:
            status["search_error"] = str(e)
    return {"success": True, "data": status}

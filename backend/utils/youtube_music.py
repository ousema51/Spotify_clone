"""
YouTube Music backend — search via ytmusicapi
"""

import logging
import os
from urllib.parse import urljoin

import requests

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Init ytmusicapi
# ---------------------------------------------------------------------------
ytmusic = None
try:
    from ytmusicapi import YTMusic
    ytmusic = YTMusic()
except Exception as e:
    logger.error("ytmusicapi failed: {}".format(e))

YoutubeDL = None
try:
    from yt_dlp import YoutubeDL
except Exception as e:
    logger.warning("yt-dlp not available: %s", e)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _safe_str(value):
    """Safely convert to string with UTF-8 encoding."""
    if value is None:
        return None
    if isinstance(value, str):
        # Ensure string is valid UTF-8
        try:
            value.encode('utf-8')
            return value
        except UnicodeEncodeError:
            # If encoding fails, encode with errors='replace'
            return value.encode('utf-8', errors='replace').decode('utf-8')
    return str(value)


def _get_thumbnail(r):
    """Extract thumbnail URL with fallback handling."""
    if r is None:
        return None
        
    thumbs = r.get("thumbnails")
    if isinstance(thumbs, list) and thumbs:
        url = thumbs[-1].get("url") if thumbs[-1] else None
        if url:
            url = _safe_str(url)
            # Ensure url is absolute and uses https
            if url and url.startswith("//"):
                return f"https:{url}"
            if url and url.startswith("http"):
                return url
            if url:
                return f"https:{url}"

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
                    return f"https:{url}"

    # Generate YouTube CDN thumbnail as fallback
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


# ---------------------------------------------------------------------------
# Public API — Search
# ---------------------------------------------------------------------------

def search_songs(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        query = _safe_str(query)
        start = (page - 1) * limit
        raw = ytmusic.search(query, filter="songs", limit=start + limit) or []
        songs = []
        for r in raw[start:start + limit]:
            if r.get("videoId"):
                normalized = _normalize(r)
                if normalized:
                    songs.append(normalized)
        return {"success": True, "data": songs}
    except Exception as e:
        logger.error("Search error: {}".format(e))
        return {"success": False, "message": str(e)}


def search_all(query=""):
    return search_songs(query)


# ---------------------------------------------------------------------------
# Public API — Stream URL
# ---------------------------------------------------------------------------

DEFAULT_STREAM_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 14; Pixel 7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/123.0.0.0 Mobile Safari/537.36"
    ),
    "Referer": "https://music.youtube.com/",
    "Origin": "https://music.youtube.com",
}

_DEFAULT_PIPED_INSTANCES = [
    "https://pipedapi.kavin.rocks",
    "https://pipedapi.adminforge.de",
    "https://api.piped.yt",
    "https://pipedapi.r4fo.com",
    "https://pipedapi.leptons.xyz",
]


def _load_piped_instances():
    raw = (os.environ.get("PIPED_INSTANCES") or "").strip()
    if not raw:
        return list(_DEFAULT_PIPED_INSTANCES)

    parts = [p.strip() for p in raw.split(",") if p.strip()]
    if not parts:
        return list(_DEFAULT_PIPED_INSTANCES)
    return parts


PIPED_INSTANCES = _load_piped_instances()


def _safe_int(value):
    if value is None:
        return None
    try:
        return int(float(value))
    except Exception:
        return None


def _merged_stream_headers(headers=None):
    merged = dict(DEFAULT_STREAM_HEADERS)
    if not isinstance(headers, dict):
        return merged

    for key, value in headers.items():
        if key is None or value is None:
            continue
        k = str(key).strip()
        v = str(value).strip()
        if k and v:
            merged[k] = v
    return merged


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

        acodec = _safe_str(fmt.get("acodec") or "") or ""
        if acodec.lower() == "none":
            continue

        vcodec = (_safe_str(fmt.get("vcodec") or "") or "").lower()
        ext = (_safe_str(fmt.get("ext") or "") or "").lower()
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


def _resolve_stream_from_yt_dlp(target, from_search=False):
    if not YoutubeDL:
        return {"success": False, "message": "yt-dlp not installed"}

    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
        "socket_timeout": 12,
        "format": "bestaudio[ext=m4a]/bestaudio/best",
    }

    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(target, download=False)
    except Exception as e:
        logger.warning("yt-dlp extraction failed for %s: %s", target, e)
        return {"success": False, "message": str(e)}

    if from_search and isinstance(info, dict):
        entries = info.get("entries") or []
        info = entries[0] if entries else None

    if not isinstance(info, dict):
        return {"success": False, "message": "Unable to extract stream info"}

    selected = _pick_best_format(info)
    stream_url = None
    extra_headers = None

    if selected:
        stream_url = _safe_str(selected.get("url"))
        extra_headers = selected.get("http_headers")

    if not stream_url:
        stream_url = _safe_str(info.get("url"))
        if not extra_headers:
            extra_headers = info.get("http_headers")

    if not stream_url:
        return {"success": False, "message": "No playable audio URL found"}

    video_id = _safe_str(info.get("id"))
    title = _safe_str(info.get("title"))
    duration = _safe_int(info.get("duration"))
    headers = _merged_stream_headers(extra_headers)

    return {
        "success": True,
        "data": {
            "audio_url": stream_url,
            "headers": headers,
            "video_id": video_id,
            "title": title,
            "duration": duration,
            "source": "yt-dlp",
        },
    }


def _resolve_stream_from_piped(video_id):
    if not video_id:
        return {"success": False, "message": "No video_id provided"}

    for instance in PIPED_INSTANCES:
        endpoint = "{}/streams/{}".format(instance.rstrip("/"), video_id)
        try:
            resp = requests.get(endpoint, timeout=7)
            if resp.status_code != 200:
                continue
            payload = resp.json()
        except Exception as e:
            logger.warning("Piped stream lookup failed for %s: %s", endpoint, e)
            continue

        streams = payload.get("audioStreams") or []
        best = None
        best_score = -1

        for item in streams:
            if not isinstance(item, dict):
                continue

            url = _safe_str(item.get("url") or item.get("audioProxyUrl"))
            if not url:
                continue
            if url.startswith("/"):
                url = urljoin(instance.rstrip("/") + "/", url.lstrip("/"))

            bitrate = _safe_int(item.get("bitrate")) or 0
            codec = (_safe_str(item.get("codec")) or "").lower()
            score = bitrate
            if "opus" in codec or "aac" in codec or "mp4a" in codec:
                score += 10

            if score > best_score:
                best_score = score
                best = item.copy()
                best["url"] = url

        if not best:
            continue

        stream_url = _safe_str(best.get("url"))
        if not stream_url:
            continue

        return {
            "success": True,
            "data": {
                "audio_url": stream_url,
                "headers": _merged_stream_headers(),
                "video_id": video_id,
                "title": _safe_str(payload.get("title")),
                "duration": _safe_int(payload.get("duration")),
                "source": "piped",
                "piped_instance": instance,
            },
        }

    return {"success": False, "message": "No playable stream found from Piped instances"}


def get_stream_url(video_id=""):
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = _safe_str(video_id.strip())
    if not video_id:
        return {"success": False, "message": "Invalid video_id"}

    yt_url = "https://www.youtube.com/watch?v={}".format(video_id)
    via_ytdlp = _resolve_stream_from_yt_dlp(yt_url)
    if via_ytdlp.get("success"):
        data = via_ytdlp.get("data") or {}
        if not data.get("video_id"):
            data["video_id"] = video_id
        return {"success": True, "data": data}

    via_piped = _resolve_stream_from_piped(video_id)
    if via_piped.get("success"):
        return via_piped

    ytdlp_error = via_ytdlp.get("message") or "unknown yt-dlp error"
    piped_error = via_piped.get("message") or "unknown piped error"
    return {
        "success": False,
        "message": "Failed to resolve stream URL (yt-dlp: {}; piped: {})".format(
            ytdlp_error,
            piped_error,
        ),
    }


def get_stream_from_search(query=""):
    query = _safe_str(query or "")
    if not query or not query.strip():
        return {"success": False, "message": "No query provided"}
    query = query.strip()

    via_ytdlp = _resolve_stream_from_yt_dlp("ytsearch1:{}".format(query), from_search=True)
    if via_ytdlp.get("success"):
        return via_ytdlp

    search_result = search_songs(query, page=1, limit=1)
    if search_result.get("success"):
        songs = search_result.get("data") or []
        if songs:
            video_id = _safe_str((songs[0] or {}).get("id"))
            if video_id:
                return get_stream_url(video_id)

    return {
        "success": False,
        "message": "Failed to resolve stream from search",
    }


def get_song_by_id(video_id=""):
    """Get song metadata with UTF-8 encoding and thumbnail fallback."""
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = _safe_str(video_id.strip())
    if not video_id:
        return {"success": False, "message": "Invalid video_id"}

    meta = {
        "title": None,
        "artist": "Unknown Artist",
        "duration": None,
        "thumbnail": f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg",
    }

    if ytmusic:
        try:
            info = ytmusic.get_song(video_id)
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
                            meta["thumbnail"] = f"https:{turl}"
                        else:
                            meta["thumbnail"] = turl
        except Exception as e:
            logger.error(f"Failed to fetch song metadata: {e}")

    # Ensure title fallback is meaningful
    meta["title"] = meta["title"] or f"Unknown Title ({video_id})"
    
    # Ensure all strings are UTF-8 safe
    meta["title"] = _safe_str(meta["title"])
    meta["artist"] = _safe_str(meta["artist"])

    data = {
        "id": video_id,
        "piped_instances": PIPED_INSTANCES,
        "resolve_on_client": True,
    }
    data.update(meta)
    return {"success": True, "data": data}


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
        for r in raw[start:start + limit]:
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
        logger.error("Album search error: {}".format(e))
        return {"success": True, "data": []}


def search_artists(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        query = _safe_str(query)
        raw = ytmusic.search(query, filter="artists", limit=limit) or []
        start = (page - 1) * limit
        artists = []
        for r in raw[start:start + limit]:
            artist = {
                "id": _safe_str(r.get("browseId")),
                "name": _safe_str(r.get("artist")) or "Unknown",
                "thumbnail": _get_thumbnail(r),
                "image": _get_thumbnail(r),
            }
            artists.append(artist)
        return {"success": True, "data": artists}
    except Exception as e:
        logger.error("Artist search error: {}".format(e))
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
        
        return {"success": True, "data": {
            "id": album_id,
            "title": _safe_str(album.get("title")) or "Unknown",
            "artist": _safe_str(artist_name) or "Unknown",
            "thumbnail": _get_thumbnail(album),
            "cover_url": _get_thumbnail(album),
            "image": _get_thumbnail(album),
            "tracks": [_normalize(t) for t in (album.get("tracks") or []) if t],
        }}
    except Exception as e:
        logger.error("Album get error: {}".format(e))
        return {"success": False, "message": str(e)}


def get_artist_by_id(artist_id=""):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        artist_id = _safe_str(artist_id)
        artist = ytmusic.get_artist(artist_id)
        
        songs = [_normalize(s) for s in (artist.get("songs", {}).get("results") or []) if s]
        
        return {"success": True, "data": {
            "id": artist_id,
            "name": _safe_str(artist.get("name")) or "Unknown",
            "thumbnail": _get_thumbnail(artist),
            "image": _get_thumbnail(artist),
            "image_url": _get_thumbnail(artist),
            "songs": songs,
        }}
    except Exception as e:
        logger.error("Artist get error: {}".format(e))
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
        logger.error("Trending error: {}".format(e))
        return {"success": True, "data": []}


def health_check():
    status = {
        "ytmusic": ytmusic is not None,
        "search": False,
        "stream_method": "client-side piped",
        "piped_instances": PIPED_INSTANCES,
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

"""
YouTube Music search and audio streaming backend.
Designed to run reliably on Vercel serverless functions.

Dependencies:
  - ytmusicapi  (music search — lightweight, no binary deps)
  - requests    (HTTP calls to streaming proxy)
"""

import logging
import requests as http_requests

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# ytmusicapi initialization (lightweight, works on Vercel)
# ---------------------------------------------------------------------------
ytmusic = None
_YT_AVAILABLE = False

try:
    from ytmusicapi import YTMusic

    ytmusic = YTMusic()
    _YT_AVAILABLE = True
    logger.info("ytmusicapi initialized")
except Exception as e:
    logger.warning(f"ytmusicapi init failed: {e}")

    # Retry with explicit locale
    try:
        from ytmusicapi import YTMusic

        ytmusic = YTMusic(language="en", location="US")
        _YT_AVAILABLE = True
        logger.info("ytmusicapi initialized (en/US fallback)")
    except Exception as e2:
        logger.error(f"ytmusicapi completely unavailable: {e2}")
        _YT_AVAILABLE = False


# ---------------------------------------------------------------------------
# Streaming proxy configuration
# ---------------------------------------------------------------------------
# These are public APIs that convert a YouTube video ID into a playable
# audio stream URL. They run on infrastructure that YouTube doesn't block.
# If one goes down, the next is tried automatically.

_STREAM_PROXIES = [
    # Cobalt API — returns direct download/stream URLs
    {
        "name": "cobalt",
        "url": "https://api.cobalt.tools/",
        "method": "POST",
        "headers": {
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        "body": lambda vid: {
            "url": f"https://music.youtube.com/watch?v={vid}",
            "audioFormat": "mp3",
            "isAudioOnly": True,
        },
        "extract": lambda r: r.json().get("url") or r.json().get("audio"),
    },
    # Invidious public instances — provides audio proxy
    {
        "name": "invidious",
        "url": "https://inv.nadeko.net/api/v1/videos/{vid}",
        "method": "GET",
        "headers": {},
        "body": lambda vid: None,
        "extract": lambda r: _extract_invidious_audio(r.json()),
    },
    # Piped API — another YouTube frontend with audio extraction
    {
        "name": "piped",
        "url": "https://pipedapi.kavin.rocks/streams/{vid}",
        "method": "GET",
        "headers": {},
        "body": lambda vid: None,
        "extract": lambda r: _extract_piped_audio(r.json()),
    },
]


def _extract_invidious_audio(data: dict) -> str | None:
    """Pull the best audio URL from an Invidious API response."""
    formats = data.get("adaptiveFormats") or []
    best_url = None
    best_bitrate = 0

    for f in formats:
        if f.get("type", "").startswith("audio/"):
            bitrate = f.get("bitrate") or 0
            if bitrate > best_bitrate and f.get("url"):
                best_bitrate = bitrate
                best_url = f["url"]

    return best_url


def _extract_piped_audio(data: dict) -> str | None:
    """Pull the best audio URL from a Piped API response."""
    streams = data.get("audioStreams") or []
    best_url = None
    best_bitrate = 0

    for s in streams:
        bitrate = s.get("bitrate") or 0
        if bitrate > best_bitrate and s.get("url"):
            best_bitrate = bitrate
            best_url = s["url"]

    return best_url


def _resolve_stream_url(video_id: str) -> dict | None:
    """Try each streaming proxy until one returns a valid audio URL.

    Returns dict with stream info or None if all fail.
    """
    errors = []

    for proxy in _STREAM_PROXIES:
        try:
            name = proxy["name"]
            url = proxy["url"].replace("{vid}", video_id)
            method = proxy["method"]
            headers = proxy.get("headers") or {}
            body = proxy["body"](video_id)

            logger.info(f"Trying stream proxy: {name}")

            if method == "POST":
                resp = http_requests.post(
                    url, json=body, headers=headers, timeout=12
                )
            else:
                resp = http_requests.get(url, headers=headers, timeout=12)

            if resp.status_code != 200:
                errors.append(f"{name}: HTTP {resp.status_code}")
                continue

            stream_url = proxy["extract"](resp)

            if stream_url and stream_url.startswith("http"):
                logger.info(f"Stream resolved via {name}")
                return {
                    "stream_url": stream_url,
                    "proxy": name,
                }

            errors.append(f"{name}: no URL in response")

        except Exception as e:
            errors.append(f"{name}: {str(e)[:100]}")
            logger.warning(f"Proxy {proxy['name']} failed: {e}")
            continue

    logger.error(
        f"All stream proxies failed for {video_id}: {'; '.join(errors)}"
    )
    return None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _safe_first(lst, key: str = "name"):
    if isinstance(lst, list) and len(lst) > 0 and isinstance(lst[0], dict):
        return lst[0].get(key)
    return None


def _best_thumbnail(thumbnails):
    if isinstance(thumbnails, list) and len(thumbnails) > 0:
        return thumbnails[-1].get("url")
    return None


def _normalize_song(raw: dict) -> dict:
    """Convert ytmusicapi result → flat frontend-ready dict."""
    return {
        "id": raw.get("videoId") or raw.get("id"),
        "title": raw.get("title") or "Unknown",
        "artist": (
            _safe_first(raw.get("artists"))
            or raw.get("artist")
            or "Unknown Artist"
        ),
        "duration": raw.get("duration") or raw.get("duration_seconds"),
        "thumbnail": (
            _best_thumbnail(raw.get("thumbnails")) or raw.get("thumbnail")
        ),
    }


# ---------------------------------------------------------------------------
# Public API — Search
# ---------------------------------------------------------------------------


def search_songs(query: str, page: int = 1, limit: int = 20) -> dict:
    """Search YouTube Music for songs. Returns {success, data: [...]}."""
    if not query or not query.strip():
        return {"success": False, "message": "Empty search query"}

    query = query.strip()

    if not _YT_AVAILABLE or ytmusic is None:
        return {
            "success": False,
            "message": "Music search is not available. ytmusicapi failed to initialize.",
        }

    try:
        start = max(0, (page - 1) * limit)
        end = start + limit

        raw = ytmusic.search(query, filter="songs", limit=end) or []
        songs = [_normalize_song(r) for r in raw[start:end]]
        songs = [s for s in songs if s.get("id")]

        return {"success": True, "data": songs}

    except Exception as e:
        logger.error(f"search_songs failed: {e}")
        return {"success": False, "message": f"Search failed: {str(e)}"}


def search_all(query: str):
    return search_songs(query)


# ---------------------------------------------------------------------------
# Public API — Stream URL
# ---------------------------------------------------------------------------


def get_stream_url(video_id: str) -> dict:
    """Return a playable audio stream URL for the given video ID.

    Response: {success: True, data: {stream_url: "..."}}
    """
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = video_id.strip()
    result = _resolve_stream_url(video_id)

    if result and result.get("stream_url"):
        return {"success": True, "data": result}

    return {
        "success": False,
        "message": f"Could not resolve a stream URL for {video_id}",
        "debug": {
            "video_id": video_id,
            "proxies_tried": [p["name"] for p in _STREAM_PROXIES],
            "hint": "All streaming proxies failed. They may be temporarily down.",
        },
    }


def get_song_by_id(video_id: str) -> dict:
    """Return metadata + stream URL for a single song."""
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = video_id.strip()

    # Get metadata from ytmusicapi if available
    metadata = {}
    if _YT_AVAILABLE and ytmusic:
        try:
            song_info = ytmusic.get_song(video_id)
            vd = song_info.get("videoDetails") or {}
            metadata = {
                "title": vd.get("title"),
                "artist": vd.get("author"),
                "duration": vd.get("lengthSeconds"),
                "thumbnail": (
                    _best_thumbnail(vd.get("thumbnail", {}).get("thumbnails"))
                ),
            }
        except Exception as e:
            logger.warning(f"get_song metadata failed: {e}")

    # Get stream URL
    result = _resolve_stream_url(video_id)

    if not result or not result.get("stream_url"):
        return {
            "success": False,
            "message": f"Could not resolve stream for {video_id}",
        }

    return {
        "success": True,
        "data": {
            "id": video_id,
            "title": metadata.get("title"),
            "artist": metadata.get("artist"),
            "duration": metadata.get("duration"),
            "thumbnail": metadata.get("thumbnail"),
            "stream_url": result["stream_url"],
        },
    }


def get_stream_from_search(query: str, index: int = 0) -> dict:
    """Search and return stream URL for the Nth result."""
    search_result = search_songs(query, page=1, limit=index + 5)

    if not search_result.get("success") or not search_result.get("data"):
        return {"success": False, "message": f"No results found for '{query}'"}

    songs = search_result["data"]
    chosen = songs[index] if index < len(songs) else songs[0]
    vid = chosen.get("id")

    if not vid:
        return {"success": False, "message": "No videoId for the chosen result"}

    stream_result = get_stream_url(vid)

    if stream_result.get("success"):
        stream_result["data"]["id"] = vid
        stream_result["data"]["title"] = (
            stream_result["data"].get("title") or chosen.get("title")
        )
        stream_result["data"]["artist"] = (
            stream_result["data"].get("artist") or chosen.get("artist")
        )
        stream_result["data"]["thumbnail"] = (
            stream_result["data"].get("thumbnail") or chosen.get("thumbnail")
        )

    return stream_result


# ---------------------------------------------------------------------------
# Albums / Artists / Trending
# ---------------------------------------------------------------------------


def search_albums(query: str, page: int = 1, limit: int = 20) -> dict:
    if not _YT_AVAILABLE or ytmusic is None:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search(query, filter="albums", limit=limit) or []
        start = max(0, (page - 1) * limit)
        return {
            "success": True,
            "data": [
                {
                    "id": r.get("browseId"),
                    "title": r.get("title"),
                    "artist": _safe_first(r.get("artists")),
                    "thumbnail": _best_thumbnail(r.get("thumbnails")),
                }
                for r in raw[start : start + limit]
            ],
        }
    except Exception:
        return {"success": True, "data": []}


def search_artists(query: str, page: int = 1, limit: int = 20) -> dict:
    if not _YT_AVAILABLE or ytmusic is None:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search(query, filter="artists", limit=limit) or []
        start = max(0, (page - 1) * limit)
        return {
            "success": True,
            "data": [
                {
                    "id": r.get("browseId"),
                    "name": r.get("artist"),
                    "thumbnail": _best_thumbnail(r.get("thumbnails")),
                }
                for r in raw[start : start + limit]
            ],
        }
    except Exception:
        return {"success": True, "data": []}


def get_album_by_id(album_id: str) -> dict:
    if not _YT_AVAILABLE or ytmusic is None:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        album = ytmusic.get_album(album_id)
        return {
            "success": True,
            "data": {
                "id": album_id,
                "title": album.get("title"),
                "artist": _safe_first(album.get("artists")),
                "thumbnail": _best_thumbnail(album.get("thumbnails")),
                "tracks": [
                    _normalize_song(t) for t in (album.get("tracks") or [])
                ],
            },
        }
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_artist_by_id(artist_id: str) -> dict:
    if not _YT_AVAILABLE or ytmusic is None:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        artist = ytmusic.get_artist(artist_id)
        return {
            "success": True,
            "data": {
                "id": artist_id,
                "name": artist.get("name"),
                "thumbnail": _best_thumbnail(artist.get("thumbnails")),
                "songs": [
                    _normalize_song(s)
                    for s in (
                        artist.get("songs", {}).get("results") or []
                    )
                ],
            },
        }
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_trending() -> dict:
    if not _YT_AVAILABLE or ytmusic is None:
        return {"success": True, "data": []}
    try:
        try:
            charts = ytmusic.get_charts(country="US")
            if isinstance(charts, dict):
                for key in ("songs", "trending", "videos"):
                    section = charts.get(key)
                    items = []
                    if isinstance(section, dict):
                        items = section.get("items") or []
                    elif isinstance(section, list):
                        items = section
                    if items:
                        songs = [_normalize_song(i) for i in items[:20]]
                        songs = [s for s in songs if s.get("id")]
                        if songs:
                            return {"success": True, "data": songs}
        except Exception:
            pass

        raw = ytmusic.search("top hits 2024", filter="songs", limit=20) or []
        songs = [_normalize_song(r) for r in raw[:20]]
        return {"success": True, "data": [s for s in songs if s.get("id")]}

    except Exception as e:
        return {"success": False, "message": str(e)}


# ---------------------------------------------------------------------------
# Health check endpoint
# ---------------------------------------------------------------------------


def health_check() -> dict:
    """Diagnose what's working on this deployment."""
    status = {
        "ytmusicapi_available": _YT_AVAILABLE,
        "ytmusicapi_initialized": ytmusic is not None,
        "stream_proxies": [p["name"] for p in _STREAM_PROXIES],
    }

    if ytmusic:
        try:
            r = ytmusic.search("hello", filter="songs", limit=1)
            status["search_works"] = bool(r and len(r) > 0)
        except Exception as e:
            status["search_works"] = False
            status["search_error"] = str(e)

    # Test first stream proxy
    try:
        test_result = _resolve_stream_url("dQw4w9WgXcQ")  # Rick Astley
        status["stream_works"] = bool(
            test_result and test_result.get("stream_url")
        )
        if test_result:
            status["stream_proxy_used"] = test_result.get("proxy")
    except Exception as e:
        status["stream_works"] = False
        status["stream_error"] = str(e)

    return {"success": True, "data": status}
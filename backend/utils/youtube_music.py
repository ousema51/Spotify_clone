import requests
import logging

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Init ytmusicapi
# ---------------------------------------------------------------------------
ytmusic = None
try:
    from ytmusicapi import YTMusic
    ytmusic = YTMusic()
except Exception as e:
    logger.error(f"ytmusicapi failed: {e}")


# ---------------------------------------------------------------------------
# Stream URL resolution — multiple strategies
# ---------------------------------------------------------------------------

def _get_stream_url(video_id: str) -> str | None:
    """Try multiple public APIs to get a playable audio URL."""

    # Strategy 1: Piped instances
    piped_instances = [
        "https://pipedapi.kavin.rocks",
        "https://pipedapi.adminforge.de",
        "https://api.piped.yt",
        "https://pipedapi.r4fo.com",
        "https://pipedapi.leptons.xyz",
    ]

    for base in piped_instances:
        try:
            resp = requests.get(
                f"{base}/streams/{video_id}",
                timeout=8,
                headers={"User-Agent": "Mozilla/5.0"}
            )
            if resp.status_code != 200:
                continue
            data = resp.json()

            # audioStreams is where Piped puts direct audio URLs
            audio_streams = data.get("audioStreams") or []
            if not audio_streams:
                continue

            # Filter to streams that have a URL and pick highest bitrate
            valid = [s for s in audio_streams if s.get("url")]
            if not valid:
                continue

            best = max(valid, key=lambda s: s.get("bitrate") or 0)
            if best.get("url"):
                return best["url"]

        except Exception as e:
            logger.warning(f"Piped {base} failed: {e}")
            continue

    # Strategy 2: Invidious instances
    invidious_instances = [
        "https://inv.nadeko.net",
        "https://invidious.fdn.fr",
        "https://vid.puffyan.us",
        "https://invidious.nerdvpn.de",
    ]

    for base in invidious_instances:
        try:
            resp = requests.get(
                f"{base}/api/v1/videos/{video_id}",
                timeout=8,
                headers={"User-Agent": "Mozilla/5.0"}
            )
            if resp.status_code != 200:
                continue
            data = resp.json()

            # adaptiveFormats contains audio-only streams
            formats = data.get("adaptiveFormats") or []
            audio_formats = [
                f for f in formats
                if f.get("type", "").startswith("audio/") and f.get("url")
            ]
            if not audio_formats:
                continue

            best = max(audio_formats, key=lambda f: f.get("bitrate") or 0)
            if best.get("url"):
                return best["url"]

        except Exception as e:
            logger.warning(f"Invidious {base} failed: {e}")
            continue

    # Strategy 3: Cobalt API
    try:
        resp = requests.post(
            "https://api.cobalt.tools/",
            json={
                "url": f"https://youtube.com/watch?v={video_id}",
                "audioFormat": "mp3",
                "isAudioOnly": True,
            },
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
            timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            url = data.get("url") or data.get("audio")
            if url:
                return url
    except Exception as e:
        logger.warning(f"Cobalt failed: {e}")

    return None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_thumbnail(r: dict) -> str | None:
    """Extract thumbnail URL from a ytmusicapi result, handling all formats."""
    # Direct thumbnail field
    thumbs = r.get("thumbnails")
    if isinstance(thumbs, list) and thumbs:
        # Get the largest one
        url = thumbs[-1].get("url")
        if url:
            # ytmusicapi sometimes returns w/ size params, clean URL works fine
            return url

    # Nested under "thumbnail" → "thumbnails"
    thumb_obj = r.get("thumbnail")
    if isinstance(thumb_obj, dict):
        inner = thumb_obj.get("thumbnails")
        if isinstance(inner, list) and inner:
            url = inner[-1].get("url")
            if url:
                return url

    # Fallback: construct from video ID
    vid = r.get("videoId") or r.get("id")
    if vid:
        return f"https://img.youtube.com/vi/{vid}/hqdefault.jpg"

    return None


def _normalize(r: dict) -> dict:
    artists = r.get("artists") or []
    artist = artists[0].get("name") if artists else r.get("artist")

    return {
        "id": r.get("videoId") or r.get("id"),
        "title": r.get("title"),
        "artist": artist or "Unknown Artist",
        "duration": r.get("duration"),
        "thumbnail": _get_thumbnail(r),
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def search_songs(query: str, page: int = 1, limit: int = 20) -> dict:
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        start = (page - 1) * limit
        raw = ytmusic.search(query, filter="songs", limit=start + limit) or []
        songs = [_normalize(r) for r in raw[start:start + limit] if r.get("videoId")]
        return {"success": True, "data": songs}
    except Exception as e:
        return {"success": False, "message": str(e)}


def search_all(query: str):
    return search_songs(query)


def get_stream_url(video_id: str) -> dict:
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = video_id.strip()
    url = _get_stream_url(video_id)

    if url:
        return {"success": True, "data": {"stream_url": url}}

    return {
        "success": False,
        "message": f"Could not get stream for {video_id}",
        "debug": {
            "video_id": video_id,
            "hint": "All proxy APIs failed. Try again in a moment.",
        },
    }


def get_song_by_id(video_id: str) -> dict:
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = video_id.strip()

    # Metadata
    meta = {
        "title": None,
        "artist": None,
        "duration": None,
        "thumbnail": f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg",
    }

    if ytmusic:
        try:
            info = ytmusic.get_song(video_id)
            vd = info.get("videoDetails") or {}
            thumbs = vd.get("thumbnail", {}).get("thumbnails") or []
            meta["title"] = vd.get("title")
            meta["artist"] = vd.get("author")
            meta["duration"] = vd.get("lengthSeconds")
            if thumbs:
                meta["thumbnail"] = thumbs[-1].get("url")
        except Exception:
            pass

    # Stream
    url = _get_stream_url(video_id)
    if not url:
        return {"success": False, "message": f"Could not get stream for {video_id}"}

    return {
        "success": True,
        "data": {
            "id": video_id,
            "stream_url": url,
            **meta,
        },
    }


def get_stream_from_search(query: str, index: int = 0) -> dict:
    result = search_songs(query, limit=index + 5)
    if not result.get("success") or not result.get("data"):
        return {"success": False, "message": "No results"}
    songs = result["data"]
    chosen = songs[index] if index < len(songs) else songs[0]
    stream = get_stream_url(chosen["id"])
    if stream.get("success"):
        stream["data"]["id"] = chosen["id"]
        stream["data"]["title"] = stream["data"].get("title") or chosen.get("title")
        stream["data"]["artist"] = stream["data"].get("artist") or chosen.get("artist")
        stream["data"]["thumbnail"] = stream["data"].get("thumbnail") or chosen.get("thumbnail")
    return stream


# ---------------------------------------------------------------------------
# Albums / Artists / Trending
# ---------------------------------------------------------------------------

def search_albums(query: str, page: int = 1, limit: int = 20) -> dict:
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search(query, filter="albums", limit=limit) or []
        start = (page - 1) * limit
        return {"success": True, "data": [
            {
                "id": r.get("browseId"),
                "title": r.get("title"),
                "artist": (r.get("artists") or [{}])[0].get("name"),
                "thumbnail": _get_thumbnail(r),
            }
            for r in raw[start:start + limit]
        ]}
    except Exception:
        return {"success": True, "data": []}


def search_artists(query: str, page: int = 1, limit: int = 20) -> dict:
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search(query, filter="artists", limit=limit) or []
        start = (page - 1) * limit
        return {"success": True, "data": [
            {
                "id": r.get("browseId"),
                "name": r.get("artist"),
                "thumbnail": _get_thumbnail(r),
            }
            for r in raw[start:start + limit]
        ]}
    except Exception:
        return {"success": True, "data": []}


def get_album_by_id(album_id: str) -> dict:
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        album = ytmusic.get_album(album_id)
        return {"success": True, "data": {
            "id": album_id,
            "title": album.get("title"),
            "artist": (album.get("artists") or [{}])[0].get("name"),
            "thumbnail": _get_thumbnail(album),
            "tracks": [_normalize(t) for t in (album.get("tracks") or [])],
        }}
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_artist_by_id(artist_id: str) -> dict:
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        artist = ytmusic.get_artist(artist_id)
        return {"success": True, "data": {
            "id": artist_id,
            "name": artist.get("name"),
            "thumbnail": _get_thumbnail(artist),
            "songs": [_normalize(s) for s in (artist.get("songs", {}).get("results") or [])],
        }}
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_trending() -> dict:
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search("top hits 2024", filter="songs", limit=20) or []
        return {"success": True, "data": [_normalize(r) for r in raw if r.get("videoId")]}
    except Exception:
        return {"success": True, "data": []}


def health_check() -> dict:
    """Test everything and report what works."""
    status = {
        "ytmusic": ytmusic is not None,
        "search": False,
        "stream": False,
        "stream_source": None,
        "thumbnail_test": None,
    }

    # Test search
    if ytmusic:
        try:
            r = ytmusic.search("test", filter="songs", limit=1)
            status["search"] = bool(r)
            if r:
                status["thumbnail_test"] = _get_thumbnail(r[0])
        except Exception as e:
            status["search_error"] = str(e)

    # Test stream with a known video
    test_url = _get_stream_url("dQw4w9WgXcQ")
    status["stream"] = bool(test_url)
    if test_url:
        status["stream_source"] = test_url[:60] + "..."

    return {"success": True, "data": status}
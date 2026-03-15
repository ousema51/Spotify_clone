"""
YouTube Music backend — search via ytmusicapi, streams via public APIs.
"""

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
# Stream URL resolution
# ---------------------------------------------------------------------------

def _get_stream_url(video_id):
    """Try multiple public APIs to get a playable audio URL."""

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

            audio_streams = data.get("audioStreams") or []
            if not audio_streams:
                continue

            valid = [s for s in audio_streams if s.get("url")]
            if not valid:
                continue

            best = max(valid, key=lambda s: s.get("bitrate") or 0)
            if best.get("url"):
                return best["url"]

        except Exception as e:
            logger.warning(f"Piped {base} failed: {e}")
            continue

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

def _get_thumbnail(r):
    """Extract thumbnail URL from a ytmusicapi result."""
    thumbs = r.get("thumbnails")
    if isinstance(thumbs, list) and thumbs:
        url = thumbs[-1].get("url")
        if url:
            return url

    thumb_obj = r.get("thumbnail")
    if isinstance(thumb_obj, dict):
        inner = thumb_obj.get("thumbnails")
        if isinstance(inner, list) and inner:
            url = inner[-1].get("url")
            if url:
                return url

    vid = r.get("videoId") or r.get("id")
    if vid:
        return "https://img.youtube.com/vi/{}/hqdefault.jpg".format(vid)

    return None


def _normalize(r):
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

def search_songs(query="", page=1, limit=20):
    if not ytmusic:
        import traceback
        return {"success": False, "message": "ytmusicapi not available", "traceback": traceback.format_exc()}
    try:
        start = (page - 1) * limit
        raw = ytmusic.search(query, filter="songs", limit=start + limit) or []
        songs = [_normalize(r) for r in raw[start:start + limit] if r.get("videoId")]
        return {"success": True, "data": songs}
    except Exception as e:
        import traceback
        return {"success": False, "message": str(e), "traceback": traceback.format_exc()}


def search_all(query=""):
    return search_songs(query)


def get_stream_url(video_id=""):
    import traceback
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided", "traceback": traceback.format_exc()}

    video_id = video_id.strip()
    try:
        url = _get_stream_url(video_id)
    except Exception as e:
        return {"success": False, "message": str(e), "traceback": traceback.format_exc()}

    if url:
        return {"success": True, "data": {"stream_url": url}}

    return {
        "success": False,
        "message": "Could not get stream for {}".format(video_id),
        "traceback": traceback.format_exc(),
    }


def get_song_by_id(video_id=""):
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = video_id.strip()

    meta = {
        "title": None,
        "artist": None,
        "duration": None,
        "thumbnail": "https://img.youtube.com/vi/{}/hqdefault.jpg".format(video_id),
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

    url = _get_stream_url(video_id)
    if not url:
        return {"success": False, "message": "Could not get stream for {}".format(video_id)}

    data = {"id": video_id, "stream_url": url}
    data.update(meta)
    return {"success": True, "data": data}


def get_stream_from_search(query="", index=0):
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

def search_albums(query="", page=1, limit=20):
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


def search_artists(query="", page=1, limit=20):
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


def get_album_by_id(album_id=""):
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


def get_artist_by_id(artist_id=""):
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


def get_trending():
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search("top hits 2024", filter="songs", limit=20) or []
        return {"success": True, "data": [_normalize(r) for r in raw if r.get("videoId")]}
    except Exception:
        return {"success": True, "data": []}


def health_check():
    """Test everything and report what works."""
    status = {
        "ytmusic": ytmusic is not None,
        "search": False,
        "stream": False,
    }

    if ytmusic:
        try:
            r = ytmusic.search("test", filter="songs", limit=1)
            status["search"] = bool(r)
            if r:
                status["thumbnail_test"] = _get_thumbnail(r[0])
        except Exception as e:
            status["search_error"] = str(e)

    test_url = _get_stream_url("dQw4w9WgXcQ")
    status["stream"] = bool(test_url)

    return {"success": True, "data": status}
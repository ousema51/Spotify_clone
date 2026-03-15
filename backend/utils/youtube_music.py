"""
youtube_music.py

Clean, test.py-style helpers for searching YouTube Music (via ytmusicapi)
and extracting a direct audio stream URL (via yt-dlp).

This implementation intentionally avoids cookie/auth logic and follows
these rules:
- Prefer `ytmusicapi` search(filter='songs') for music-only results.
- Use `yt-dlp` (yt_dlp) to extract a playable audio URL from a YouTube
  watch URL. Return the direct `info['url']` when available, else pick
  a best audio format from `formats`.
- Provide informative diagnostic details on failure to help debugging
  in deployed environments.
"""

import json
import traceback
import requests
import re
from yt_dlp.extractor.common import _InfoDict
# Optional dependencies
_YT_AVAILABLE = False
_YTDLP_AVAILABLE = False

YTMusic = None
ytmusic = None
try:
    from ytmusicapi import YTMusic
    _YT_AVAILABLE = True
except Exception as _e:
    YTMusic = None
    _YT_AVAILABLE = False

try:
    import yt_dlp
    _YTDLP_AVAILABLE = True
except Exception as _e:
    yt_dlp = None
    _YTDLP_AVAILABLE = False

# Initialize ytmusic client if available
if _YT_AVAILABLE:
    try:
        ytmusic = YTMusic()
    except Exception:
        ytmusic = None
        _YT_AVAILABLE = False


def _normalize_song_entry(r: dict) -> dict:
    return {
        "id": r.get("videoId") or r.get("browseId") or r.get("video_id") or r.get("id"),
        "title": r.get("title"),
        "artist": (r.get("artists") and len(r.get("artists")) > 0 and r.get("artists")[0].get("name"))
        or r.get("uploader") or None,
        "duration": r.get("duration"),
        "thumbnail": (r.get("thumbnails") and len(r.get("thumbnails")) > 0 and r.get("thumbnails")[-1].get("url"))
        or r.get("thumbnail") or None,
    }


def search_songs(query: str, page: int = 1, limit: int = 20) -> dict:
    """Return music-only search results as {success: True, data: [...] }.
    Falls back to yt-dlp search or HTML scrape if ytmusicapi is not available
    or returns no results.
    """
    try:
        results = []
        if ytmusic:
            results = ytmusic.search(query, filter="songs") or []
        start = max(0, (page - 1) * limit)
        end = start + limit
        songs = [ _normalize_song_entry(r) for r in (results[start:end] if results else []) ]

        # Fallback: use yt-dlp search
        if not songs and _YTDLP_AVAILABLE and yt_dlp is not None:
            try:
                q = f"ytsearch{limit}:{query}"
                with yt_dlp.YoutubeDL({"quiet": True, "skip_download": True}) as ydl:
                    info = ydl.extract_info(q, download=False)
                entries = info.get("entries") or []
                songs = []
                for e in entries[start:end]:
                    songs.append({
                        "id": e.get("id") or e.get("webpage_url") or e.get("url"),
                        "title": e.get("title"),
                        "artist": e.get("uploader") or e.get("artist"),
                        "duration": e.get("duration"),
                        "thumbnail": e.get("thumbnail"),
                    })
            except Exception:
                pass

        # Last-resort: minimal HTML scraping of youtube results page
        if not songs:
            try:
                url = f"https://www.youtube.com/results?search_query={requests.utils.requote_uri(query)}"
                resp = requests.get(url, timeout=6)
                html = resp.text
                m = re.search(r"var ytInitialData = (\{.*?\});", html)
                if not m:
                    m = re.search(r"window\[\"ytInitialData\"\] = (\{.*?\});", html)
                if m:
                    data = json.loads(m.group(1))

                    def find_video_renderers(obj):
                        results = []
                        if isinstance(obj, dict):
                            for k, v in obj.items():
                                if k == 'videoRenderer' and isinstance(v, dict):
                                    results.append(v)
                                else:
                                    results.extend(find_video_renderers(v))
                        elif isinstance(obj, list):
                            for item in obj:
                                results.extend(find_video_renderers(item))
                        return results

                    video_nodes = find_video_renderers(data)
                    for v in video_nodes[start:end]:
                        vid = v.get('videoId')
                        title_runs = v.get('title', {}).get('runs') or []
                        title = title_runs[0].get('text') if title_runs else v.get('title', {}).get('simpleText')
                        thumbnails = v.get('thumbnail', {}).get('thumbnails') if v.get('thumbnail') else None
                        thumbnail = thumbnails[-1].get('url') if thumbnails else None
                        owner_text = v.get('ownerText', {}).get('runs') if v.get('ownerText') else None
                        artist = owner_text[0].get('text') if owner_text else None
                        songs.append({
                            'id': vid,
                            'title': title,
                            'artist': artist,
                            'duration': None,
                            'thumbnail': thumbnail
                        })
            except Exception:
                pass

        return {"success": True, "data": songs}
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_song_by_id(video_id: str) -> dict:
    url = f"https://www.youtube.com/watch?v={video_id}"
    if _YTDLP_AVAILABLE and yt_dlp is not None:
        try:
            with yt_dlp.YoutubeDL({"format": "bestaudio", "quiet": True, "skip_download": True}) as ydl:
                info = ydl.extract_info(url, download=False)
        except Exception as e:
            return {"success": False, "message": str(e)}
    else:
        return {"success": False, "message": "yt_dlp not available on server"}

    return {
        "success": True,
        "data": {
            "id": video_id,
            "title": info.get("title"),
            "duration": info.get("duration"),
            "thumbnail": info.get("thumbnail"),
            "stream_url": info.get("url")
        }
    }


def get_stream_url(video_id: str) -> dict:
    """Return a playable audio stream URL for the given YouTube video id.

    Tries a few watch URL candidates and returns a dict with success/data or
    failure/message. On failure includes diagnostic `details` to help debug
    deployment issues (e.g. missing yt-dlp or network errors).
    """
    if not _YTDLP_AVAILABLE or yt_dlp is None:
        return {"success": False, "message": "yt_dlp not available on server", "details": {"yt_dlp_available": _YTDLP_AVAILABLE, "ytmusic_available": _YT_AVAILABLE}}

    candidates = [
        f"https://music.youtube.com/watch?v={video_id}",
        f"https://www.youtube.com/watch?v={video_id}",
    ]

    attempt_results = []
    for url in candidates:
        attempt = {"url": url, "success": False, "error": None, "formats_count": 0}
        try:
            with yt_dlp.YoutubeDL({"format": "bestaudio", "quiet": True, "skip_download": True}) as ydl:
                info = ydl.extract_info(url, download=False)

            # Prefer direct URL
            stream_url = info.get('url')
            if stream_url:
                attempt["success"] = True
                attempt["selected"] = "direct"
                attempt_results.append(attempt)
                return {"success": True, "data": {"stream_url": stream_url}}

            # Otherwise, inspect formats
            formats = info.get('formats') or info.get('requested_formats') or []
            attempt["formats_count"] = len(formats)
            best = None
            best_score = -1
            for f in formats:
                try:
                    abr = f.get('abr') or f.get('tbr') or 0
                    acodec = f.get('acodec')
                    vcodec = f.get('vcodec')
                    is_audio_only = (vcodec in (None, 'none', 'unknown') or vcodec == 'none') and acodec not in (None, 'none')
                    score = int(abr) if abr else 0
                    if is_audio_only:
                        score += 10000
                    if score > best_score:
                        best_score = score
                        best = f
                except Exception:
                    continue
            if best and best.get('url'):
                attempt["success"] = True
                attempt["selected"] = "format"
                attempt["selected_format"] = {"format_id": best.get('format_id'), "abr": best.get('abr')}
                attempt_results.append(attempt)
                return {"success": True, "data": {"stream_url": best.get('url')}}

            attempt_results.append(attempt)
        except Exception as e:
            attempt["error"] = str(e)
            attempt_results.append(attempt)

    # Fallback: if ytmusic available, try searching for the video id as a query
    if ytmusic:
        try:
            results = ytmusic.search(video_id, filter="songs") or []
            if results:
                first = results[0]
                vid = first.get('videoId')
                if vid:
                    return get_stream_url(vid) if vid != video_id else {"success": False, "message": "Could not resolve stream URL", "details": {"attempts": attempt_results, "yt_dlp_available": _YTDLP_AVAILABLE, "ytmusic_available": _YT_AVAILABLE}}
        except Exception:
            pass

    return {"success": False, "message": "Could not resolve stream URL", "details": {"attempts": attempt_results, "yt_dlp_available": _YTDLP_AVAILABLE, "ytmusic_available": _YT_AVAILABLE}}

def get_stream_from_search(query: str, index: int = 0) -> dict:
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        results = ytmusic.search(query, filter="songs") or []
        if not results:
            return {"success": False, "message": "No song results found"}
        chosen = results[index] if index < len(results) else results[0]
        vid = chosen.get('videoId')
        if not vid:
            return {"success": False, "message": "No videoId found for chosen song"}
        return get_stream_url(vid)
    except Exception as e:
        return {"success": False, "message": str(e)}


# Lightweight stubs for other APIs used by routes

def search_all(query: str):
    return search_songs(query)


def search_albums(query: str, page: int = 1, limit: int = 20):
    return {"success": True, "data": []}


def search_artists(query: str, page: int = 1, limit: int = 20):
    return {"success": True, "data": []}


def get_album_by_id(album_id: str):
    return {"success": True, "data": None}


def get_artist_by_id(artist_id: str):
    return {"success": True, "data": None}


def get_trending():
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        results = ytmusic.search("top hits", filter="songs") or []
        songs = []
        for r in results[:20]:
            songs.append({
                "id": r.get("videoId"),
                "title": r.get("title"),
                "artist": r.get("artists")[0].get("name") if r.get("artists") else None,
                "thumbnail": r.get("thumbnails")[-1].get("url") if r.get("thumbnails") else None,
            })
        return {"success": True, "data": songs}
    except Exception as e:
        return {"success": False, "message": str(e)}

try:
    from ytmusicapi import YTMusic
    _YT_AVAILABLE = True
except Exception as _e:
    print(f"[youtube_music] ytmusicapi not available: {_e}", flush=True)
    YTMusic = None
    _YT_AVAILABLE = False

try:
    import yt_dlp
    _YTDLP_AVAILABLE = True
except Exception as _e:
    print(f"[youtube_music] yt_dlp not available: {_e}", flush=True)
    yt_dlp = None
    _YTDLP_AVAILABLE = False

import requests
import re
import json

ytmusic = None
if _YT_AVAILABLE:
    try:
        ytmusic = YTMusic()
    except Exception as _e:
        print(f"[youtube_music] YTMusic() init failed: {_e}", flush=True)
        ytmusic = None
        _YT_AVAILABLE = False


def search_songs(query, page=1, limit=20):
    try:
        # ytmusic.search returns a list of results; use page/limit to slice
        if ytmusic:
            results = ytmusic.search(query, filter="songs") or []
        else:
            results = []
        start = max(0, (page - 1) * limit)
        end = start + limit

        songs = []
        for r in results[start:end]:
            songs.append({
                "id": r.get("videoId") or r.get("browseId") or r.get("video_id"),
                "title": r.get("title"),
                "artist": (r.get("artists") and len(r.get("artists")) > 0 and r.get("artists")[0].get("name")) or None,
                "duration": r.get("duration"),
                "thumbnail": (r.get("thumbnails") and len(r.get("thumbnails")) > 0 and r.get("thumbnails")[-1].get("url")) or None
            })

        # If ytmusic returned no results, try a lightweight fallback using yt_dlp
        if not songs and _YTDLP_AVAILABLE and yt_dlp is not None:
            try:
                query_str = f"ytsearch{limit}:{query}"
                ydl_opts = {"quiet": True, "skip_download": True}
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(query_str, download=False)
                entries = info.get('entries') or []
                songs = []
                for e in entries[start:end]:
                    songs.append({
                        "id": e.get("id") or e.get("webpage_url") or e.get("url"),
                        "title": e.get("title"),
                        "artist": (e.get("uploader") or e.get("artist")),
                        "duration": e.get("duration"),
                        "thumbnail": e.get("thumbnail")
                    })
            except Exception as _e:
                print(f"[youtube_music] yt_dlp fallback failed: {_e}", flush=True)
                # ignore fallback errors and return whatever we have
                pass

        # If still no songs, try scraping YouTube search results page (minimal, relies on public HTML)
        if not songs:
            try:
                url = f"https://www.youtube.com/results?search_query={requests.utils.requote_uri(query)}"
                resp = requests.get(url, timeout=6)
                html = resp.text
                # Extract the ytInitialData JSON blob
                m = re.search(r"var ytInitialData = (\{.*?\});", html)
                if not m:
                    m = re.search(r"window\[\"ytInitialData\"\] = (\{.*?\});", html)
                if m:
                    data = json.loads(m.group(1))
                    # Traverse to contents -> twoColumnSearchResultsRenderer -> primaryContents
                    contents = data.get('contents') or {}
                    # This structure can vary; try to find videoRenderer nodes
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
                    songs = []
                    for v in video_nodes[start:end]:
                        vid = v.get('videoId')
                        title_runs = v.get('title', {}).get('runs') or []
                        title = title_runs[0].get('text') if title_runs else v.get('title', {}).get('simpleText')
                        thumbnail = None
                        thumbnails = v.get('thumbnail', {}).get('thumbnails') if v.get('thumbnail') else None
                        if thumbnails:
                            thumbnail = thumbnails[-1].get('url')
                        artists = None
                        # uploader info
                        owner_text = v.get('ownerText', {}).get('runs') if v.get('ownerText') else None
                        artist = owner_text[0].get('text') if owner_text else None
                        songs.append({
                            'id': vid,
                            'title': title,
                            'artist': artist,
                            'duration': None,
                            'thumbnail': thumbnail
                        })
            except Exception as _e:
                print(f"[youtube_music] html fallback failed: {_e}", flush=True)
                pass

        return {"success": True, "data": songs}
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_song_by_id(video_id):
    url = f"https://www.youtube.com/watch?v={video_id}"

    ydl_opts = {
        "format": "bestaudio",
        "quiet": True
    }

    if _YTDLP_AVAILABLE and yt_dlp is not None:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
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


def get_stream_url(video_id):
    """Return a playable audio stream URL for the given YouTube video id.
    Uses yt_dlp on the server. Returns {'success': True, 'data': {'stream_url': url}} or error.
    """
    if _YTDLP_AVAILABLE and yt_dlp is not None:
        try:
            url = f"https://www.youtube.com/watch?v={video_id}"
            ydl_opts = {"format": "bestaudio", "quiet": True}
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
            stream_url = info.get('url')
            if stream_url:
                return {"success": True, "data": {"stream_url": stream_url}}
            return {"success": False, "message": "Could not resolve stream URL"}
        except Exception as e:
            return {"success": False, "message": str(e)}
    return {"success": False, "message": "yt_dlp not available on server"}


def search_all(query):
    return search_songs(query)


def search_albums(query, page=1, limit=20):
    return {"success": True, "data": []}


def search_artists(query, page=1, limit=20):
    return {"success": True, "data": []}


def get_album_by_id(album_id):
    return {"success": True, "data": None}


def get_artist_by_id(artist_id):
    return {"success": True, "data": None}


def get_trending():
    results = ytmusic.search("top hits", filter="songs")

    songs = []
    for r in results[:20]:
        songs.append({
            "id": r.get("videoId"),
            "title": r.get("title"),
            "artist": r["artists"][0]["name"] if r.get("artists") else None,
            "thumbnail": r["thumbnails"][-1]["url"] if r.get("thumbnails") else None
        })

    return {"success": True, "data": songs}
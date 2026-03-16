"""
YouTube Music backend — search via ytmusicapi, streams via client-side Piped.
"""

import logging
import yt_dlp

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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_thumbnail(r):
    thumbs = r.get("thumbnails")
    if isinstance(thumbs, list) and thumbs:
        url = thumbs[-1].get("url")
        if url:
            # ensure url is absolute and uses https
            if isinstance(url, str) and url.startswith("//"):
                return f"https:{url}"
            if isinstance(url, str) and url.startswith("http"):
                return url
            return f"https:{url}"

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
# Public API — Search
# ---------------------------------------------------------------------------

def search_songs(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        start = (page - 1) * limit
        raw = ytmusic.search(query, filter="songs", limit=start + limit) or []
        songs = [_normalize(r) for r in raw[start:start + limit] if r.get("videoId")]
        return {"success": True, "data": songs}
    except Exception as e:
        return {"success": False, "message": str(e)}


def search_all(query=""):
    return search_songs(query)


# ---------------------------------------------------------------------------
# Public API — Stream URL
# ---------------------------------------------------------------------------

PIPED_INSTANCES = [
    "https://pipedapi.kavin.rocks",
    "https://pipedapi.adminforge.de",
    "https://api.piped.yt",
    "https://pipedapi.r4fo.com",
    "https://pipedapi.leptons.xyz",
]


def get_stream_url(video_id=""):
    """Return a static audio URL for testing purposes."""
    return {
        "success": True,
        "data": {
            "audio_url": "https://rr2---sn-hpa7kn76.googlevideo.com/videoplayback?expire=1773699065&ei=mSu4aa7zEKe9mLAPq7b6wAs&ip=197.240.203.174&id=o-AA6tk2KdcuP51aUaPDos5xEEVXwAMu09C651jk9nwwU7&itag=251&source=youtube&requiressl=yes&xpc=EgVo2aDSNQ%3D%3D&cps=584&rms=au%2Cau&gcr=tn&bui=AVNa5-xrKhPGa5F9TxtBq-hF6imStB90Fh3uvSgWNxXXDh3FY42V7lEWogD5N5MvAGFm-_BTvcxYvNRa&spc=6dlaFMqtgR6GRoEkFhq5AZuVJL9Aa1R0HryXiGYtYxSw&vprv=1&svpuc=1&mime=audio%2Fwebm&rqh=1&gir=yes&clen=3753925&dur=223.081&lmt=1762575443296119&keepalive=yes&fexp=51565116,51565682,51791334&c=ANDROID_VR&txp=5532534&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cxpc%2Cgcr%2Cbui%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Crqh%2Cgir%2Cclen%2Cdur%2Clmt&sig=AHEqNM4wRQIhALMptMY8l7mA4TzBHJ7r_DpW37eP3vfJ06aXpXyvTa4bAiBNvG-2TWc23lF0AROmJnW4C8YjzfjQ1cUesgM1oYP3cw%3D%3D&redirect_counter=1&cm2rm=sn-u0opnpxuxa-u0oz7l&rrc=191&req_id=640afe1eea60a3ee&cms_redirect=yes&cmsv=e&met=1773677474,&mh=vb&mm=29&mn=sn-hpa7kn76&ms=rdu&mt=1773676889&mv=m&mvi=2&pl=21&lsparams=cps,met,mh,mm,mn,ms,mv,mvi,pl,rms&lsig=APaTxxMwRQIhALu8c27D_17mgdq4n07pFF7LpBXgfd7yyG78PYYNubbdAiAhWCkHXHTYFBI28ZfpEWcpti-SK7Mpw_sBmFzmKARdTw%3D%3D",
        },
    }

    video_id = video_id.strip()

    try:
        ydl_opts = {
            'format': 'bestaudio/best',
            'quiet': True,
            'noplaylist': True,
        }
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(f"https://www.youtube.com/watch?v={video_id}", download=False)
            audio_url = info.get('url')

        if not audio_url:
            return {"success": False, "message": "Failed to extract audio URL"}

        return {
            "success": True,
            "data": {
                "audio_url": audio_url,
            },
        }

    except Exception as e:
        return {"success": False, "message": f"Error: {str(e)}"}


def get_song_by_id(video_id=""):
    if not video_id or not video_id.strip():
        return {"success": False, "message": "No video_id provided"}

    video_id = video_id.strip()

    meta = {
        "title": None,  # Start with None to ensure fallback logic
        "artist": "Unknown Artist",
        "duration": None,
        "thumbnail": f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg",
    }

    if ytmusic:
        try:
            info = ytmusic.get_song(video_id)
            vd = info.get("videoDetails") or {}
            thumbs = vd.get("thumbnail", {}).get("thumbnails") or []
            meta["title"] = vd.get("title") or meta["title"]
            meta["artist"] = vd.get("author") or meta["artist"]
            meta["duration"] = vd.get("lengthSeconds") or meta["duration"]
            if thumbs:
                turl = thumbs[-1].get("url")
                if turl:
                    if isinstance(turl, str) and turl.startswith("//"):
                        meta["thumbnail"] = f"https:{turl}"
                    else:
                        meta["thumbnail"] = turl
        except Exception as e:
            logger.error(f"Failed to fetch song metadata: {e}")

    # Ensure title fallback is meaningful
    meta["title"] = meta["title"] or f"Unknown Title ({video_id})"

    data = {
        "id": video_id,
        "piped_instances": PIPED_INSTANCES,
        "resolve_on_client": True,
    }
    data.update(meta)
    return {"success": True, "data": data}


def get_stream_from_search(query="", index=0):
    result = search_songs(query, limit=index + 5)
    if not result.get("success") or not result.get("data"):
        return {"success": False, "message": "No results"}
    songs = result["data"]
    chosen = songs[index] if index < len(songs) else songs[0]
    return get_stream_url(chosen["id"])


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
                "cover_url": _get_thumbnail(r),
                "image": _get_thumbnail(r),
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
            "cover_url": _get_thumbnail(album),
            "image": _get_thumbnail(album),
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
            "image": _get_thumbnail(artist),
            "image_url": _get_thumbnail(artist),
            "songs": [_normalize(s) for s in (artist.get("songs", {}).get("results") or [])],
        }}
    except Exception as e:
        return {"success": False, "message": str(e)}


def get_trending():
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        # Prefer US-focused trending results
        raw = ytmusic.search("top hits USA", filter="songs", limit=40) or []
        songs = [r for r in raw if r.get("videoId")]
        # normalize and return up to 20
        return {"success": True, "data": [_normalize(r) for r in songs[:20]]}
    except Exception:
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
                status["thumbnail_test"] = _get_thumbnail(r[0])
        except Exception as e:
            status["search_error"] = str(e)
    return {"success": True, "data": status}
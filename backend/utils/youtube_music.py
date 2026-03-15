from ytmusicapi import YTMusic
import yt_dlp

ytmusic = YTMusic()


def search_songs(query, page=1, limit=20):
    try:
        # ytmusic.search returns a list of results; use page/limit to slice
        results = ytmusic.search(query, filter="songs") or []
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
        if not songs:
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
            except Exception:
                # ignore fallback errors and return whatever we have
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

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)

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
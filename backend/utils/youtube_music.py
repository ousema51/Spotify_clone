from ytmusicapi import YTMusic
import yt_dlp

ytmusic = YTMusic()

def search_songs(query, page=1, limit=20):
    results = ytmusic.search(query, filter="songs")

    songs = []
    for r in results[:limit]:
        songs.append({
            "id": r.get("videoId"),
            "title": r.get("title"),
            "artist": r["artists"][0]["name"] if r.get("artists") else None,
            "duration": r.get("duration"),
            "thumbnail": r["thumbnails"][-1]["url"] if r.get("thumbnails") else None
        })

    return {"success": True, "data": songs}


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
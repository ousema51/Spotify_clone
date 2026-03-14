import os

import requests

JIOSAAVN_BASE = os.environ.get("JIOSAAVN_API_BASE", "https://saavn.sumit.co/api")


def _get(path, params=None):
    """Make a GET request to the JioSaavn API and return the JSON body."""
    url = f"{JIOSAAVN_BASE}{path}"
    try:
        resp = requests.get(url, params=params, timeout=10)
        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.Timeout:
        return {"success": False, "message": "JioSaavn API request timed out"}
    except requests.exceptions.HTTPError as exc:
        return {"success": False, "message": f"JioSaavn API error: {exc}"}
    except requests.exceptions.RequestException as exc:
        return {"success": False, "message": f"Request failed: {exc}"}
    except ValueError:
        return {"success": False, "message": "Invalid JSON response from JioSaavn API"}


def search_songs(query):
    return _get("/search", {"query": query})


def search_albums(query, page=1, limit=20):
    return _get("/search/albums", {"query": query, "page": page, "limit": limit})


def search_artists(query, page=1, limit=20):
    return _get("/search/artists", {"query": query, "page": page, "limit": limit})


def search_all(query):
    return _get("/search", {"query": query})


def get_song_by_id(song_id):
    return _get(f"/songs/{song_id}")


def get_album_by_id(album_id):
    return _get(f"/albums", {"id": album_id})


def get_artist_by_id(artist_id):
    return _get(f"/artists/{artist_id}")


def get_trending():
    """Return trending/popular songs using the charts or trending endpoint."""
    result = _get("/charts")
    if not result.get("success") or not result.get("data"):
        # Fall back to a broad search for popular content
        result = _get("/search/songs", {"query": "top hits 2024", "limit": 20})
    return result

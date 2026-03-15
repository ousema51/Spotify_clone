from flask import Blueprint, jsonify, request

from utils import youtube_music

music_bp = Blueprint("music", __name__)


@music_bp.route("/search", methods=["GET"])
def search():
    query = (request.args.get("q") or "").strip()
    search_type = (request.args.get("type") or "all").lower()
    page = int(request.args.get("page", 1))
    limit = int(request.args.get("limit", 20))

    if not query:
        return jsonify({"success": False, "message": "Query parameter 'q' is required"}), 400

    try:
            print(f"[search] q={query!r} type={search_type} page={page} limit={limit}", flush=True)
        if search_type == "songs":
            result = youtube_music.search_songs(query, page=page, limit=limit)
        elif search_type == "albums":
            result = youtube_music.search_albums(query, page=page, limit=limit)
        elif search_type == "artists":
            result = youtube_music.search_artists(query, page=page, limit=limit)
        else:
            result = youtube_music.search_all(query)

        # Normalize result: if a list is returned, wrap it; if dict with success, return as-is
        if isinstance(result, list):
            return jsonify({"success": True, "data": result}), 200
        if isinstance(result, dict):
            if result.get("success") is False:
                    print(f"[search] error: {result.get('message')}", flush=True)
                return jsonify({"success": False, "message": result.get("message", "Search failed")}), 502
            # Ensure data key exists
            data = result.get("data", None)
                # Log number of results
                try:
                    count = len(data) if data is not None else 0
                except Exception:
                    count = 1
                print(f"[search] returned {count} result(s)", flush=True)
            return jsonify({"success": True, "data": data}), 200

        # Fallback
        return jsonify({"success": True, "data": result}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@music_bp.route("/song/<song_id>", methods=["GET"])
def get_song(song_id):
    result = youtube_music.get_song_by_id(song_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/album/<album_id>", methods=["GET"])
def get_album(album_id):
    result = youtube_music.get_album_by_id(album_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/artist/<artist_id>", methods=["GET"])
def get_artist(artist_id):
    result = youtube_music.get_artist_by_id(artist_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/trending", methods=["GET"])
def trending():
    result = youtube_music.get_trending()
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200

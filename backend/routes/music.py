from flask import Blueprint, jsonify, request

from utils import jiosaavn

music_bp = Blueprint("music", __name__)


@music_bp.route("/search", methods=["GET"])
def search():
    query = (request.args.get("q") or "").strip()
    search_type = (request.args.get("type") or "all").lower()
    page = int(request.args.get("page", 1))
    limit = int(request.args.get("limit", 20))

    if not query:
        return jsonify({"success": False, "message": "Query parameter 'q' is required"}), 400

    result = jiosaavn.search_all(query)

    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502

    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/song/<song_id>", methods=["GET"])
def get_song(song_id):
    result = jiosaavn.get_song_by_id(song_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/album/<album_id>", methods=["GET"])
def get_album(album_id):
    result = jiosaavn.get_album_by_id(album_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/artist/<artist_id>", methods=["GET"])
def get_artist(artist_id):
    result = jiosaavn.get_artist_by_id(artist_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/trending", methods=["GET"])
def trending():
    result = jiosaavn.get_trending()
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200

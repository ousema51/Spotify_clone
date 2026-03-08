from datetime import datetime, timezone

from bson import ObjectId
from flask import Blueprint, g, jsonify, request

import models.db as db
from middleware.auth_middleware import token_required

library_bp = Blueprint("library", __name__)

_DEFAULT_LIMIT = 20


def _song_doc_to_dict(doc):
    doc = dict(doc)
    doc["_id"] = str(doc["_id"])
    for key, value in doc.items():
        if isinstance(value, datetime):
            doc[key] = value.isoformat()
    return doc


@library_bp.route("/liked", methods=["GET"])
@token_required
def get_liked():
    user_id = g.current_user["_id"]
    page = int(request.args.get("page", 1))
    limit = int(request.args.get("limit", _DEFAULT_LIMIT))
    skip = (page - 1) * limit

    cursor = db.liked_songs.find({"user_id": user_id}).sort("liked_at", -1).skip(skip).limit(limit)
    songs = [_song_doc_to_dict(s) for s in cursor]
    total = db.liked_songs.count_documents({"user_id": user_id})

    return jsonify({"success": True, "data": {"songs": songs, "total": total, "page": page, "limit": limit}}), 200


@library_bp.route("/like/<song_id>", methods=["POST"])
@token_required
def like_song(song_id):
    user_id = g.current_user["_id"]
    data = request.get_json(silent=True) or {}

    existing = db.liked_songs.find_one({"user_id": user_id, "song_id": song_id})
    if existing:
        return jsonify({"success": False, "message": "Song is already liked"}), 400

    doc = {
        "user_id": user_id,
        "song_id": song_id,
        "title": data.get("title"),
        "artist": data.get("artist"),
        "cover_url": data.get("cover_url"),
        "duration": data.get("duration"),
        "liked_at": datetime.now(tz=timezone.utc),
    }
    db.liked_songs.insert_one(doc)
    return jsonify({"success": True, "message": "Song liked successfully"}), 201


@library_bp.route("/like/<song_id>", methods=["DELETE"])
@token_required
def unlike_song(song_id):
    user_id = g.current_user["_id"]
    result = db.liked_songs.delete_one({"user_id": user_id, "song_id": song_id})
    if result.deleted_count == 0:
        return jsonify({"success": False, "message": "Song not found in liked songs"}), 404
    return jsonify({"success": True, "message": "Song unliked successfully"}), 200


@library_bp.route("/liked/check/<song_id>", methods=["GET"])
@token_required
def check_liked(song_id):
    user_id = g.current_user["_id"]
    exists = db.liked_songs.find_one({"user_id": user_id, "song_id": song_id}) is not None
    return jsonify({"success": True, "data": {"liked": exists}}), 200

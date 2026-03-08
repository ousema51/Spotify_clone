from datetime import datetime, timezone

from flask import Blueprint, g, jsonify, request

import models.db as db
from middleware.auth_middleware import token_required

users_bp = Blueprint("users", __name__)


@users_bp.route("/profile", methods=["PUT"])
@token_required
def update_profile():
    data = request.get_json(silent=True) or {}
    updates = {}

    if "display_name" in data:
        display_name = (data["display_name"] or "").strip()
        if not display_name:
            return jsonify({"success": False, "message": "display_name cannot be empty"}), 400
        updates["display_name"] = display_name

    if "profile_picture_url" in data:
        updates["profile_picture_url"] = data["profile_picture_url"]

    if not updates:
        return jsonify({"success": False, "message": "No fields to update"}), 400

    updates["updated_at"] = datetime.now(tz=timezone.utc)

    from bson import ObjectId

    db.users.update_one({"_id": ObjectId(g.current_user["_id"])}, {"$set": updates})
    user = db.users.find_one({"_id": ObjectId(g.current_user["_id"])})
    user["_id"] = str(user["_id"])
    user.pop("password_hash", None)

    return jsonify({"success": True, "data": user}), 200


@users_bp.route("/search", methods=["GET"])
def search_users():
    query = (request.args.get("q") or "").strip()
    if not query:
        return jsonify({"success": False, "message": "Query parameter 'q' is required"}), 400

    cursor = db.users.find(
        {"username": {"$regex": query, "$options": "i"}},
        {"password_hash": 0},
    ).limit(20)

    results = []
    for user in cursor:
        user["_id"] = str(user["_id"])
        results.append(user)

    return jsonify({"success": True, "data": results}), 200

import os
from functools import wraps

import jwt
from flask import g, jsonify, request

import models.db as db


def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"success": False, "message": "Authorization token is missing"}), 401

        token = auth_header.split(" ", 1)[1].strip()
        if not token:
            return jsonify({"success": False, "message": "Authorization token is missing"}), 401

        try:
            secret = os.environ.get("JWT_SECRET", "changeme")
            payload = jwt.decode(token, secret, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return jsonify({"success": False, "message": "Token has expired"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"success": False, "message": "Invalid token"}), 401

        # Check if the session is still valid (not logged out)
        session = db.sessions.find_one({"token": token, "is_active": True})
        if not session:
            return jsonify({"success": False, "message": "Session is invalid or has been revoked"}), 401

        from bson import ObjectId

        user = db.users.find_one({"_id": ObjectId(payload["user_id"])})
        if not user:
            return jsonify({"success": False, "message": "User not found"}), 401

        user["_id"] = str(user["_id"])
        user.pop("password_hash", None)
        g.current_user = user
        g.token = token
        return f(*args, **kwargs)

    return decorated

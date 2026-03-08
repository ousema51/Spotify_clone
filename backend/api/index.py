import sys
import os

# Make the backend root importable when running from api/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from flask import Flask, jsonify
from flask_cors import CORS

import models.db as db
from routes.auth import auth_bp
from routes.music import music_bp
from routes.library import library_bp
from routes.playlists import playlists_bp
from routes.listening import listening_bp
from routes.social import social_bp
from routes.users import users_bp

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})

# Register blueprints
app.register_blueprint(auth_bp, url_prefix="/api/auth")
app.register_blueprint(music_bp, url_prefix="/api/music")
app.register_blueprint(library_bp, url_prefix="/api/library")
app.register_blueprint(playlists_bp, url_prefix="/api/playlists")
app.register_blueprint(listening_bp, url_prefix="/api")
app.register_blueprint(social_bp, url_prefix="/api/users")
app.register_blueprint(users_bp, url_prefix="/api/users")

# Initialize MongoDB connection
try:
    db.init_db()
except Exception as exc:
    print(f"[WARNING] Could not connect to MongoDB at startup: {exc}", flush=True)


@app.before_request
def ensure_db():
    """Ensure MongoDB is connected before processing any request."""
    try:
        db._ensure_initialized()
    except Exception as exc:
        return jsonify({"success": False, "message": f"Database connection error: {str(exc)}"}), 503


@app.route("/api/health", methods=["GET"])
def health():
    try:
        db._ensure_initialized()
        # Quick ping to verify DB connection
        db.get_db().command("ping")
        return jsonify({"success": True, "message": "OK", "db": "connected"}), 200
    except Exception as exc:
        return jsonify({"success": True, "message": "OK", "db": f"error: {str(exc)}"}), 200


@app.errorhandler(404)
def not_found(e):
    return jsonify({"success": False, "message": "Resource not found"}), 404


@app.errorhandler(500)
def internal_error(e):
    import traceback
    traceback.print_exc()
    message = f"Internal server error: {str(e)}" if app.debug else "Internal server error"
    return jsonify({"success": False, "message": message}), 500


@app.errorhandler(Exception)
def handle_exception(e):
    import traceback
    traceback.print_exc()
    message = f"Unexpected error: {str(e)}" if app.debug else "Unexpected error; try again later"
    return jsonify({"success": False, "message": message}), 500


if __name__ == "__main__":
    debug = os.environ.get("FLASK_DEBUG", "0") == "1"
    app.run(debug=debug)

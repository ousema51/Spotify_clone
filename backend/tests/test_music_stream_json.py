import os
import sys
import unittest
from unittest.mock import patch

from flask import Flask


BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from routes.music import music_bp
from routes import music as music_routes


class MusicStreamJsonRouteTests(unittest.TestCase):
    def setUp(self):
        app = Flask(__name__)
        app.register_blueprint(music_bp, url_prefix="/api/music")
        app.testing = True
        self.client = app.test_client()

    def test_stream_by_video_id_normalizes_payload(self):
        mocked = {
            "success": True,
            "data": {
                "url": "https://audio.example.com/stream.m4a",
                "headers": {"X-Test": 123},
                "duration": "189.6",
                "title": "Example Song",
            },
        }

        with patch.object(music_routes.youtube_music, "get_stream_url", return_value=mocked):
            response = self.client.get("/api/music/stream/dQw4w9WgXcQ")

        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(body["success"], True)
        self.assertEqual(body["data"]["audio_url"], "https://audio.example.com/stream.m4a")
        self.assertEqual(body["data"]["headers"]["X-Test"], "123")
        self.assertEqual(body["data"]["video_id"], "dQw4w9WgXcQ")
        self.assertEqual(body["data"]["duration"], 189)
        self.assertEqual(body["data"]["source"], "yt-dlp")

    def test_stream_by_video_id_rejects_invalid_payload(self):
        mocked = {
            "success": True,
            "data": {
                "headers": {"X-Test": "ok"},
            },
        }

        with patch.object(music_routes.youtube_music, "get_stream_url", return_value=mocked):
            response = self.client.get("/api/music/stream/dQw4w9WgXcQ")

        self.assertEqual(response.status_code, 502)
        body = response.get_json()
        self.assertEqual(body["success"], False)
        self.assertIn("Invalid stream payload", body["message"])

    def test_stream_by_query_returns_normalized_payload(self):
        mocked = {
            "success": True,
            "data": {
                "audio_url": "https://audio.example.com/query-stream.webm",
                "video_id": "abc123def45",
                "headers": {"Authorization": "token"},
                "source": "yt-dlp",
            },
        }

        with patch.object(
            music_routes.youtube_music,
            "get_stream_from_search",
            return_value=mocked,
        ):
            response = self.client.get("/api/music/stream?q=My%20Song")

        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(body["success"], True)
        self.assertEqual(body["data"]["audio_url"], "https://audio.example.com/query-stream.webm")
        self.assertEqual(body["data"]["video_id"], "abc123def45")
        self.assertEqual(body["data"]["headers"]["Authorization"], "token")

    def test_stream_query_requires_q(self):
        response = self.client.get("/api/music/stream")
        self.assertEqual(response.status_code, 400)
        body = response.get_json()
        self.assertEqual(body["success"], False)
        self.assertIn("Query parameter 'q' is required", body["message"])


if __name__ == "__main__":
    unittest.main()

import os
import sys
import unittest
from unittest.mock import patch


BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from utils import youtube_music


class YoutubeMusicFallbackTests(unittest.TestCase):
    def setUp(self):
        youtube_music._STREAM_CACHE.clear()
        self._env_patcher = patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "",
                "YTDLP_RAPIDAPI_KEY": "",
                "RAPIDAPI_KEY": "",
                "YTDLP_ALLOW_LOCAL_FALLBACK": "",
            },
            clear=False,
        )
        self._env_patcher.start()

    def tearDown(self):
        self._env_patcher.stop()

    def test_get_stream_url_uses_piped_when_yt_dlp_bot_challenge(self):
        ytdlp_failure = {
            "success": False,
            "error_code": "bot_challenge",
            "message": "YouTube bot challenge detected",
        }
        piped_success = {
            "success": True,
            "data": {
                "audio_url": "https://piped.example/stream.webm",
                "headers": {"Referer": "https://music.youtube.com/"},
                "video_id": "GwrLUr01NOY",
                "source": "piped",
            },
        }

        with patch.object(youtube_music, "_resolve_stream_from_yt_dlp", return_value=ytdlp_failure):
            with patch.object(youtube_music, "_resolve_stream_from_piped", return_value=piped_success):
                result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["source"], "piped")
        self.assertEqual(result["data"]["video_id"], "GwrLUr01NOY")

    def test_get_stream_url_reports_combined_error_when_all_extractors_fail(self):
        ytdlp_failure = {
            "success": False,
            "error_code": "bot_challenge",
            "message": "YouTube bot challenge detected",
        }
        piped_failure = {
            "success": False,
            "message": "Piped fallback failed to resolve stream",
        }

        with patch.object(youtube_music, "_resolve_stream_from_yt_dlp", return_value=ytdlp_failure):
            with patch.object(youtube_music, "_resolve_stream_from_piped", return_value=piped_failure):
                result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertFalse(result["success"])
        self.assertEqual(result.get("error_code"), "bot_challenge")
        self.assertIn("piped fallback error", result.get("message", "").lower())

    def test_get_stream_url_uses_external_api_when_enabled(self):
        external_success = {
            "success": True,
            "data": {
                "audio_url": "https://rapidapi.example/stream.webm",
                "headers": {},
                "video_id": "GwrLUr01NOY",
                "source": "rapidapi-yt-dlp",
            },
        }

        with patch.dict(os.environ, {"YTDLP_PROVIDER": "rapidapi", "YTDLP_RAPIDAPI_KEY": "key"}, clear=False):
            with patch.object(youtube_music, "_resolve_stream_from_external_api", return_value=external_success):
                with patch.object(youtube_music, "_resolve_stream_from_yt_dlp") as mocked_local:
                    with patch.object(youtube_music, "_resolve_stream_from_piped") as mocked_piped:
                        result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["source"], "rapidapi-yt-dlp")
        mocked_local.assert_not_called()
        mocked_piped.assert_not_called()

    def test_get_stream_url_uses_piped_when_external_fails_and_local_disabled(self):
        external_failure = {
            "success": False,
            "error_code": "external_http_error",
            "message": "RapidAPI yt-dlp returned status 500",
        }
        piped_success = {
            "success": True,
            "data": {
                "audio_url": "https://piped.example/stream.webm",
                "headers": {},
                "video_id": "GwrLUr01NOY",
                "source": "piped",
            },
        }

        with patch.dict(os.environ, {"YTDLP_PROVIDER": "rapidapi", "YTDLP_RAPIDAPI_KEY": "key"}, clear=False):
            with patch.object(youtube_music, "_resolve_stream_from_external_api", return_value=external_failure):
                with patch.object(youtube_music, "_resolve_stream_from_piped", return_value=piped_success):
                    with patch.object(youtube_music, "_resolve_stream_from_yt_dlp") as mocked_local:
                        result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["source"], "piped")
        mocked_local.assert_not_called()

    def test_get_stream_url_uses_local_when_external_fails_and_local_enabled(self):
        external_failure = {
            "success": False,
            "error_code": "external_http_error",
            "message": "RapidAPI yt-dlp returned status 500",
        }
        local_success = {
            "success": True,
            "data": {
                "audio_url": "https://local.example/stream.webm",
                "headers": {},
                "video_id": "GwrLUr01NOY",
                "source": "yt-dlp",
            },
        }

        with patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "rapidapi",
                "YTDLP_RAPIDAPI_KEY": "key",
                "YTDLP_ALLOW_LOCAL_FALLBACK": "1",
            },
            clear=False,
        ):
            with patch.object(youtube_music, "_resolve_stream_from_external_api", return_value=external_failure):
                with patch.object(youtube_music, "_resolve_stream_from_yt_dlp", return_value=local_success) as mocked_local:
                    result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["source"], "yt-dlp")
        mocked_local.assert_called_once()


if __name__ == "__main__":
    unittest.main()

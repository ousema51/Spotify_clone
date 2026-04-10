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
                "YTDLP_DISABLE_EMBEDDED_RAPIDAPI_KEY": "1",
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

    def test_get_stream_url_forces_local_fallback_on_external_conversion_error(self):
        external_failure = {
            "success": False,
            "error_code": "external_conversion_error",
            "message": "RapidAPI conversion failed",
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

        with patch.dict(os.environ, {"YTDLP_PROVIDER": "rapidapi", "YTDLP_RAPIDAPI_KEY": "key"}, clear=False):
            with patch.object(youtube_music, "_resolve_stream_from_external_api", return_value=external_failure):
                with patch.object(youtube_music, "_resolve_stream_from_yt_dlp", return_value=local_success) as mocked_local:
                    result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["source"], "yt-dlp")
        mocked_local.assert_called_once()

    def test_resolve_stream_from_external_api_download_post_flow(self):
        class FakeResponse:
            def __init__(self, status_code, payload):
                self.status_code = status_code
                self._payload = payload
                self.text = str(payload)

            def json(self):
                return self._payload

        post_payload = {
            "id": "req-123",
            "downloadUrl": "https://cdn.example.com/audio.mp3",
            "status": "CONVERTING",
            "format": "MP3",
        }
        poll_payload = {
            "id": "req-123",
            "downloadUrl": "https://cdn.example.com/audio.mp3",
            "status": "COMPLETED",
            "format": "MP3",
        }

        with patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "rapidapi",
                "YTDLP_RAPIDAPI_KEY": "key",
                "YTDLP_RAPIDAPI_HOST": "youtube-to-mp315.p.rapidapi.com",
                "YTDLP_RAPIDAPI_URL": "https://youtube-to-mp315.p.rapidapi.com/download",
                "YTDLP_RAPIDAPI_STATUS_POLL_ATTEMPTS": "1",
            },
            clear=False,
        ):
            with patch.object(youtube_music.requests, "post", return_value=FakeResponse(200, post_payload)) as mocked_post:
                with patch.object(youtube_music.requests, "get", return_value=FakeResponse(200, poll_payload)) as mocked_get:
                    result = youtube_music._resolve_stream_from_external_api("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["audio_url"], "https://cdn.example.com/audio.mp3")
        self.assertEqual(result["data"]["external_method"], "POST")

        _, kwargs = mocked_post.call_args
        self.assertIn("youtube.com/watch?v=GwrLUr01NOY", kwargs.get("params", {}).get("url", ""))
        self.assertEqual(kwargs.get("json", {}).get("format"), "mp3")
        self.assertEqual(kwargs.get("json", {}).get("quality"), 0)

        self.assertTrue(mocked_get.called)
        status_url = mocked_get.call_args[0][0]
        self.assertIn("/status/req-123", status_url)

    def test_resolve_stream_from_external_api_get_mp3_download_link_flow(self):
        class FakeResponse:
            def __init__(self, status_code, payload):
                self.status_code = status_code
                self._payload = payload
                self.text = str(payload)

            def json(self):
                return self._payload

        payload = {
            "comment": "The file will soon be ready",
            "file": "https://cdn.example.com/out.mp3",
            "reserved_file": "https://cdn.example.com/reserved-out.mp3",
        }

        with patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "rapidapi",
                "YTDLP_RAPIDAPI_KEY": "key",
                "YTDLP_RAPIDAPI_HOST": "youtube-mp3-audio-video-downloader.p.rapidapi.com",
                "YTDLP_RAPIDAPI_URL": "https://youtube-mp3-audio-video-downloader.p.rapidapi.com/get_mp3_download_link/{id}?quality=low&wait_until_the_file_is_ready=false",
            },
            clear=False,
        ):
            with patch.object(youtube_music.requests, "get", return_value=FakeResponse(200, payload)) as mocked_get:
                result = youtube_music._resolve_stream_from_external_api("https://www.youtube.com/watch?v=Ckom3gf57Yw")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["audio_url"], "https://cdn.example.com/out.mp3")
        self.assertEqual(result["data"]["external_method"], "GET")

        called_url = mocked_get.call_args[0][0]
        self.assertIn("/get_mp3_download_link/Ckom3gf57Yw", called_url)
        self.assertIn("quality=low", called_url)


if __name__ == "__main__":
    unittest.main()

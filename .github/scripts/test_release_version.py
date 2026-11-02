"""Check release decisions without publishing, pushing tags, or using the network."""
import io
import unittest
from urllib.error import HTTPError, URLError

from release_version import release_candidate


class ReleaseVersionTest(unittest.TestCase):
    source = "name: dep_sync\nversion: 0.2.0\n"

    def test_published_version_is_skipped(self):
        def fetch(url, timeout):
            self.assertEqual(url, "https://pub.dev/api/packages/dep_sync/versions/0.2.0")
            self.assertEqual(timeout, 30)
            return io.StringIO('{"version":"0.2.0"}')
        self.assertIsNone(release_candidate(self.source, fetch))

    def test_only_404_creates_a_tag(self):
        def fetch(url, timeout):
            raise HTTPError(url, 404, "Not found", {}, None)
        self.assertEqual(release_candidate(self.source, fetch), "v0.2.0")

    def test_server_error_does_not_trigger_release(self):
        def fetch(url, timeout):
            raise HTTPError(url, 500, "Server error", {}, None)
        with self.assertRaises(HTTPError):
            release_candidate(self.source, fetch)

    def test_network_failure_does_not_trigger_release(self):
        def fetch(url, timeout):
            raise URLError("offline")
        with self.assertRaises(URLError):
            release_candidate(self.source, fetch)

    def test_malformed_version_fails_before_network(self):
        with self.assertRaises(ValueError):
            release_candidate("name: dep_sync\nversion: nope\n", None)

    def test_unexpected_response_fails(self):
        def fetch(url, timeout):
            return io.StringIO('{"version":"0.1.0"}')
        with self.assertRaises(ValueError):
            release_candidate(self.source, fetch)


if __name__ == "__main__":
    unittest.main()

"""Report an unpublished package version to GitHub Actions without changing Git."""
import json
import os
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.request import urlopen


def release_candidate(pubspec, fetch):
    """Return a version tag only when pub.dev confirms the version is absent."""
    name = re.search(r"^name: ([a-z][a-z0-9_]*)\s*$", pubspec, re.MULTILINE)
    version = re.search(
        r"^version: ([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)\s*$",
        pubspec,
        re.MULTILINE,
    )
    if not name or not version:
        raise ValueError("Expected unquoted package name and semantic version in pubspec.yaml")
    package, value = name[1], version[1]
    url = f"https://pub.dev/api/packages/{package}/versions/{value}"
    try:
        with fetch(url, timeout=30) as response:
            result = json.load(response)
        if result.get("version") != value:
            raise ValueError("pub.dev returned an unexpected version response")
        return None
    except HTTPError as error:
        if error.code == 404:
            return f"v{value}"
        raise  # Network/auth/server failures must never be treated as absence.


if __name__ == "__main__":
    tag = release_candidate(Path("pubspec.yaml").read_text(), urlopen)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"tag={tag or ''}\n")
    print(f"Unpublished version: {tag}" if tag else "Version already published; no release needed.")

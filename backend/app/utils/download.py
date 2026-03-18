from pathlib import Path

import requests


def download_url_to_file(url: str, destination: Path, max_size_bytes: int) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)

    with requests.get(url, stream=True, timeout=30) as response:
        response.raise_for_status()
        total = 0
        with destination.open("wb") as output:
            for chunk in response.iter_content(chunk_size=8192):
                if not chunk:
                    continue
                total += len(chunk)
                if total > max_size_bytes:
                    raise ValueError("Image exceeds allowed size")
                output.write(chunk)

    return destination
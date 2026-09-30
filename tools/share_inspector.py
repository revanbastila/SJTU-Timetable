"""Interactive, secret-safe inspector for 传承·交大.

Install with ``pip install playwright`` and ``playwright install chromium``.
Authentication is completed in the official browser page. The output contains
only same-origin JSON responses with authentication fields redacted; cookies,
headers and form values are never exported.
"""

from __future__ import annotations

import argparse
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


SITE = "https://share.dyweb.sjtu.cn/"
SECRET_KEY = re.compile(
    r"password|passwd|secret|token|cookie|session|authorization|credential",
    re.IGNORECASE,
)


def safe_url(value: str) -> str:
    parts = urlsplit(value)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def redact(value, depth: int = 0):
    if depth > 8:
        return "<depth-limit>"
    if isinstance(value, dict):
        return {
            str(key): "<redacted>"
            if SECRET_KEY.search(str(key))
            else redact(item, depth + 1)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item, depth + 1) for item in value[:100]]
    if isinstance(value, str) and len(value) > 4000:
        return value[:4000] + "<truncated>"
    return value


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Inspect authenticated 传承·交大 JSON without exporting secrets."
    )
    parser.add_argument("--output", default="share-diagnostic.json")
    args = parser.parse_args()

    try:
        from playwright.sync_api import sync_playwright
    except ImportError as error:
        raise SystemExit(
            "Missing Playwright. Run: pip install playwright && playwright install chromium"
        ) from error

    captured: list[dict] = []
    with tempfile.TemporaryDirectory(prefix="sjtu-share-inspector-") as profile:
        with sync_playwright() as playwright:
            context = playwright.chromium.launch_persistent_context(
                profile,
                headless=False,
                accept_downloads=False,
            )
            page = context.pages[0] if context.pages else context.new_page()

            def inspect_response(response) -> None:
                try:
                    url = urlsplit(response.url)
                    content_type = response.headers.get("content-type", "")
                    if url.hostname != "share.dyweb.sjtu.cn" or "json" not in content_type:
                        return
                    captured.append(
                        {
                            "url": safe_url(response.url),
                            "status": response.status,
                            "data": redact(response.json()),
                        }
                    )
                except Exception:
                    # A failed or non-JSON response is diagnostic noise, not a
                    # reason to expose its raw body or interrupt inspection.
                    return

            page.on("response", inspect_response)
            page.goto(SITE, wait_until="domcontentloaded", timeout=45_000)
            print("请在浏览器中完成官方登录和必要验证，并浏览需要检查的页面。")
            input("完成后按 Enter 生成脱敏 JSON：")
            context.close()

    unique: dict[tuple[str, int], dict] = {}
    for item in captured:
        unique[(item["url"], item["status"])] = item
    output = {
        "site": SITE,
        "responses": list(unique.values()),
        "security": "No passwords, cookies, tokens, authorization headers or query strings exported.",
    }
    target = Path(args.output).resolve()
    target.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"已生成脱敏诊断：{target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

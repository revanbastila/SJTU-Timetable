"""Inspect the authenticated 我的计划 profile endpoint without storing secrets.

The school's page calls GET /sys/wdpyjhapp/modules/wdpyjh/wdxx.do with no
parameters and renders reMapData.XSXX.{XM,XH,YXDM_DISPLAY}. The Android app
uses the same endpoint in its existing WebView session; this optional Python
tool accepts a captured response or an SJTU_PORTAL_COOKIE environment variable.
No password, Cookie or token is ever included in its JSON output or logs.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


PROFILE_URL = (
    "https://yjsxk.sjtu.edu.cn/yjsxkapp/sys/wdpyjhapp/"
    "modules/wdpyjh/wdxx.do"
)


class SameHostRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        destination = urlsplit(newurl)
        if destination.scheme != "https" or destination.hostname != "yjsxk.sjtu.edu.cn":
            raise ValueError("authentication_redirect")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def _value(profile: dict, key: str) -> str:
    value = profile.get(key)
    return str(value).strip() if isinstance(value, (str, int)) else ""


def parse_profile(body: str) -> dict:
    data = json.loads(body)
    if not isinstance(data, dict):
        raise ValueError("response_not_object")
    if not data.get("success"):
        raise ValueError("api_not_successful")
    wrapper = data.get("reMapData")
    profile = wrapper.get("XSXX") if isinstance(wrapper, dict) else None
    if not isinstance(profile, dict):
        raise ValueError("missing_XSXX")

    number = _value(profile, "XH")
    name = _value(profile, "XM")
    college = re.sub(r"^\s*\(\d+\)\s*", "", _value(profile, "YXDM_DISPLAY"))
    if not re.fullmatch(r"\d{8,15}", number) or re.fullmatch(r"1[3-9]\d{9}", number):
        number = ""
    if not re.fullmatch(r"[\u4e00-\u9fff·]{2,12}", name):
        name = ""
    if not re.fullmatch(r"[\u4e00-\u9fff·（）()A-Za-z0-9\s-]{2,40}", college):
        college = ""
    return {
        "studentName": name,
        "studentNumber": number,
        "studentCollege": college,
        "diagnostics": {
            "stage": "complete",
            "responseType": "object",
            "fields": [key for key in ("XM", "XH", "YXDM_DISPLAY") if key in profile],
            "profileKeys": list(profile)[:40],
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--input", type=Path, help="captured JSON response")
    source.add_argument("--fetch-profile", action="store_true")
    args = parser.parse_args()
    status = None
    response_type = ""
    try:
        if args.input:
            body = args.input.read_text(encoding="utf-8")
        else:
            cookie = os.environ.get("SJTU_PORTAL_COOKIE", "")
            if not cookie:
                raise ValueError("missing_session")
            request = Request(
                PROFILE_URL,
                headers={"Accept": "application/json", "Cookie": cookie},
                method="GET",
            )
            with build_opener(SameHostRedirect()).open(request, timeout=15) as response:
                status = response.status
                response_type = response.headers.get("Content-Type", "")
                if "json" not in response_type.lower():
                    raise ValueError("authentication_or_non_json_response")
                body = response.read(2_000_000).decode("utf-8", "replace")
        result = parse_profile(body)
        result["diagnostics"].update({"httpStatus": status, "contentType": response_type})
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (HTTPError, URLError, OSError, ValueError, json.JSONDecodeError) as error:
        stage = "auth" if str(error) in {
            "missing_session", "authentication_redirect",
            "authentication_or_non_json_response",
        } else "request" if isinstance(error, (HTTPError, URLError, OSError)) else "parse"
        if isinstance(error, HTTPError):
            status = error.code
            if status in (401, 403):
                stage = "auth"
        print(json.dumps({
            "studentName": "", "studentNumber": "", "studentCollege": "",
            "diagnostics": {"stage": stage, "httpStatus": status,
                            "contentType": response_type},
        }, ensure_ascii=False))
        print(f"Portal profile inspection: {stage} ({type(error).__name__})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

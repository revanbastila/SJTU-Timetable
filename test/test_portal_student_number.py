"""Tests for the standalone, credential-free profile parser."""

import sys
import unittest
from pathlib import Path
from urllib.request import Request

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from portal_student_number import (  # noqa: E402
    PROFILE_URL,
    SameHostRedirect,
    parse_student_number,
)


class StudentNumberParserTest(unittest.TestCase):
    def test_my_selection_name_prefix(self):
        self.assertEqual(
            parse_student_number(
                "<section><h2>我的选课</h2><div>123456789012 张三</div></section>"
            ),
            "123456789012",
        )

    def test_profile_json(self):
        self.assertEqual(
            parse_student_number(
                '{"loginUserId":"jaccount-name",'
                '"studentInfo":{"xh":"123456789012"}}'
            ),
            "123456789012",
        )

    def test_no_placeholder_or_mobile_number(self):
        self.assertEqual(parse_student_number("我的选课\n张三"), "")
        self.assertEqual(parse_student_number("我的选课\n13812345678 张三"), "")

    def test_session_cookie_cannot_follow_external_redirect(self):
        with self.assertRaises(ValueError):
            SameHostRedirect().redirect_request(
                Request(PROFILE_URL), None, 302, "redirect", {},
                "https://example.org/login",
            )


if __name__ == "__main__":
    unittest.main()

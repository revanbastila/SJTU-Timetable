"""Offline tests for the verified 我的计划 profile response shape."""

import json
import unittest

from portal_student_number import parse_profile


class PortalPlanProfileTest(unittest.TestCase):
    def test_verified_fields(self):
        body = json.dumps({"success": True, "reMapData": {"XSXX": {
            "XM": "张三", "XH": "123456789012",
            "YXDM_DISPLAY": "(190)法学院",
        }}})
        result = parse_profile(body)
        self.assertEqual(result["studentName"], "张三")
        self.assertEqual(result["studentNumber"], "123456789012")
        self.assertEqual(result["studentCollege"], "法学院")
        self.assertEqual(result["diagnostics"]["fields"],
                         ["XM", "XH", "YXDM_DISPLAY"])

    def test_missing_fields_do_not_become_guesses(self):
        body = json.dumps({"success": True, "reMapData": {"XSXX": {
            "COURSE_ID": "987654321012", "DISPLAY_NAME": "张三",
        }}})
        result = parse_profile(body)
        self.assertEqual(result["studentNumber"], "")
        self.assertEqual(result["studentName"], "")
        self.assertEqual(result["studentCollege"], "")

    def test_non_plan_payload_fails(self):
        with self.assertRaisesRegex(ValueError, "missing_XSXX"):
            parse_profile(json.dumps({"success": True, "reMapData": {}}))


if __name__ == "__main__":
    unittest.main()

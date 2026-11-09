from decimal import Decimal
from pathlib import Path
from tempfile import TemporaryDirectory

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from .models import Report


User = get_user_model()

JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01" + b"\x00" * 32
PNG_BYTES = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" + b"\x00" * 32
WEBP_BYTES = b"RIFF\x24\x00\x00\x00WEBPVP8 " + b"\x00" * 32


class ReportApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.citizen = User.objects.create_user(
            username="citizen", password="safe-password-123"
        )
        self.unapproved_official = User.objects.create_user(
            username="unapproved-official", password="safe-password-123", role="OFFICIAL"
        )
        self.approved_official = User.objects.create_user(
            username="approved-official",
            password="safe-password-123",
            role="OFFICIAL",
            is_official_approved=True,
        )
        self.report = Report.objects.create(
            citizen=self.citizen,
            title="Broken streetlight",
            description="The light is out.",
            issue_type=Report.IssueType.STREETLIGHT,
            latitude=12.972,
            longitude=74.856,
        )

    def test_my_reports_are_private_to_the_authenticated_citizen(self):
        self.client.force_authenticate(user=self.approved_official)
        response = self.client.get("/api/reports/my/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [])

    def test_authenticated_citizen_can_create_report_with_expected_payload(self):
        self.client.force_authenticate(user=self.citizen)
        response = self.client.post(
            "/api/reports/",
            {
                "title": "New pothole",
                "description": "A deep pothole near the crossing.",
                "issue_type": "POTHOLE",
                "latitude": 12.973123,
                "longitude": 74.857456,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        created = Report.objects.get(id=response.data["id"])
        self.assertEqual(created.citizen, self.citizen)
        self.assertEqual(created.issue_type, Report.IssueType.POTHOLE)
        self.assertEqual(created.status, Report.Status.PENDING)

    def _upload(self, name, content, content_type):
        self.client.force_authenticate(user=self.citizen)
        return self.client.post(
            "/api/reports/upload-photo/",
            {"photo": SimpleUploadedFile(name, content, content_type)},
            format="multipart",
            HTTP_HOST="127.0.0.1:8000",
        )

    def test_valid_images_are_stored_whatever_the_client_labels_them(self):
        cases = [
            ("a.jpg", JPEG_BYTES, "image/jpeg", ".jpg"),
            ("a.jpeg", JPEG_BYTES, "image/jpeg", ".jpg"),
            ("a.png", PNG_BYTES, "image/png", ".png"),
            ("a.webp", WEBP_BYTES, "image/webp", ".webp"),
            ("a.jpg", JPEG_BYTES, "application/octet-stream", ".jpg"),
            ("scaled_1000.heic", JPEG_BYTES, "image/heic", ".jpg"),
        ]
        for name, content, content_type, extension in cases:
            with self.subTest(name=name, content_type=content_type):
                with TemporaryDirectory() as media_root, override_settings(
                    MEDIA_ROOT=media_root
                ):
                    response = self._upload(name, content, content_type)

                    self.assertEqual(response.status_code, 201, response.data)
                    self.assertTrue(response.data["photo"].endswith(extension))
                    stored = response.data["photo"].split("/media/")[1]
                    self.assertEqual((Path(media_root) / stored).read_bytes(), content)

    def test_files_that_are_not_images_are_rejected(self):
        cases = [
            ("fake.jpg", b"this is not an image", "image/jpeg"),
            ("page.png", b"<html></html>", "image/png"),
            ("riff.webp", b"RIFF\x00\x00\x00\x00WAVEfmt ", "image/webp"),
            ("empty.jpg", b"", "image/jpeg"),
        ]
        for name, content, content_type in cases:
            with self.subTest(name=name):
                with TemporaryDirectory() as media_root, override_settings(
                    MEDIA_ROOT=media_root
                ):
                    response = self._upload(name, content, content_type)

                    self.assertEqual(response.status_code, 400)
                    self.assertEqual(list(Path(media_root).rglob("*.*")), [])

    def test_upload_requires_authentication(self):
        response = self.client.post(
            "/api/reports/upload-photo/",
            {"photo": SimpleUploadedFile("a.jpg", JPEG_BYTES, "image/jpeg")},
            format="multipart",
        )

        self.assertEqual(response.status_code, 401)

    def test_uploaded_photo_is_saved_on_report_with_all_fields(self):
        with TemporaryDirectory() as media_root, override_settings(
            MEDIA_ROOT=media_root
        ):
            photo_url = self._upload("a.jpg", JPEG_BYTES, "image/jpeg").data["photo"]
            response = self.client.post(
                "/api/reports/",
                {
                    "title": "Blocked drain",
                    "description": "Water is pooling on the road.",
                    "issue_type": "DRAINAGE",
                    "latitude": 12.973123,
                    "longitude": 74.857456,
                    "photo": photo_url,
                },
                format="json",
            )

        self.assertEqual(response.status_code, 201, response.data)
        created = Report.objects.get(id=response.data["id"])
        self.assertEqual(created.title, "Blocked drain")
        self.assertEqual(created.description, "Water is pooling on the road.")
        self.assertEqual(created.issue_type, Report.IssueType.DRAINAGE)
        self.assertEqual(created.latitude, Decimal("12.973123"))
        self.assertEqual(created.longitude, Decimal("74.857456"))
        self.assertEqual(created.photo, photo_url)

        mine = self.client.get("/api/reports/my/")
        public = self.client.get("/api/reports/all/")
        self.assertIn(created.id, [report["id"] for report in mine.data])
        self.assertIn(created.id, [report["id"] for report in public.data])

    def _create_report_at(self, latitude, longitude):
        self.client.force_authenticate(user=self.citizen)
        return self.client.post(
            "/api/reports/",
            {
                "title": "Located issue",
                "description": "Coordinates under test.",
                "issue_type": "OTHER",
                "latitude": latitude,
                "longitude": longitude,
            },
            format="json",
        )

    def test_coordinates_with_six_decimal_places_are_accepted(self):
        cases = [
            (12.973123, 74.857457),
            (-33.868812, -151.2093),
            (0.000001, -0.000001),
            (90.0, 180.0),
        ]
        for latitude, longitude in cases:
            with self.subTest(latitude=latitude, longitude=longitude):
                response = self._create_report_at(latitude, longitude)

                self.assertEqual(response.status_code, 201, response.data)
                created = Report.objects.get(id=response.data["id"])
                self.assertEqual(created.latitude, Decimal(str(latitude)))
                self.assertEqual(created.longitude, Decimal(str(longitude)))

    def test_coordinates_with_more_than_six_decimal_places_are_rejected(self):
        before = Report.objects.count()

        response = self._create_report_at(12.973123456789, 74.857456789012)

        self.assertEqual(response.status_code, 400)
        self.assertIn("latitude", response.data)
        self.assertIn("longitude", response.data)
        self.assertEqual(Report.objects.count(), before)

    def _make_report(self, report_status, **fields):
        return Report.objects.create(
            citizen=self.citizen,
            title="Public report",
            description="Public details.",
            issue_type=Report.IssueType.POTHOLE,
            latitude=Decimal("12.973123"),
            longitude=Decimal("74.857456"),
            status=report_status,
            **fields,
        ).id

    def _submit_as(self, user, title, issue_type):
        self.client.force_authenticate(user=user)
        response = self.client.post(
            "/api/reports/",
            {
                "title": title,
                "description": f"{title} description",
                "issue_type": issue_type,
                "latitude": 12.999583,
                "longitude": 74.795826,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response.data["id"]

    def test_public_list_has_every_citizens_reports_and_my_list_only_own(self):
        second_citizen = User.objects.create_user(
            username="second-citizen", password="safe-password-123"
        )
        first_id = self._submit_as(self.citizen, "Potholes", "POTHOLE")
        second_id = self._submit_as(second_citizen, "Light", "STREETLIGHT")
        all_ids = {self.report.id, first_id, second_id}

        for viewer in (self.citizen, second_citizen):
            self.client.force_authenticate(user=viewer)
            response = self.client.get("/api/reports/all/")
            self.assertEqual({r["id"] for r in response.data}, all_ids)

        self.client.force_authenticate(user=self.citizen)
        mine = self.client.get("/api/reports/my/")
        self.assertEqual({r["id"] for r in mine.data}, {self.report.id, first_id})

        self.client.force_authenticate(user=second_citizen)
        mine = self.client.get("/api/reports/my/")
        self.assertEqual({r["id"] for r in mine.data}, {second_id})
        self.assertEqual(mine.data[0]["citizen"], "second-citizen")

    def test_anonymous_visitors_see_only_verified_reports(self):
        verified_id = self._make_report(Report.Status.VERIFIED)
        self._make_report(Report.Status.REJECTED)

        response = self.client.get("/api/reports/all/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual([r["id"] for r in response.data], [verified_id])

    def test_anonymous_details_are_approximate_and_hide_identities(self):
        self._make_report(
            Report.Status.VERIFIED,
            photo="http://127.0.0.1:8000/media/report_photos/a.jpg",
            verified_by=self.approved_official,
        )

        report = self.client.get("/api/reports/all/").data[0]

        self.assertEqual(report["latitude"], "12.973")
        self.assertEqual(report["longitude"], "74.857")
        self.assertEqual(report["issue_type"], "POTHOLE")
        self.assertEqual(report["description"], "Public details.")
        self.assertEqual(
            report["photo"], "http://127.0.0.1:8000/media/report_photos/a.jpg"
        )
        self.assertNotIn("citizen", report)
        self.assertNotIn("verified_by", report)

    def test_anonymous_response_contains_only_the_public_fields(self):
        self._make_report(Report.Status.VERIFIED, verified_by=self.approved_official)

        report = self.client.get("/api/reports/all/").data[0]

        self.assertEqual(
            set(report),
            {
                "id",
                "title",
                "description",
                "issue_type",
                "latitude",
                "longitude",
                "photo",
                "status",
                "created_at",
            },
        )

    def test_anonymous_coordinates_round_to_three_decimals(self):
        cases = [
            ("12.999600", "74.000400", "13.000", "74.000"),
            ("-33.868812", "-151.209296", "-33.869", "-151.209"),
        ]
        for latitude, longitude, expected_latitude, expected_longitude in cases:
            with self.subTest(latitude=latitude):
                Report.objects.all().delete()
                Report.objects.create(
                    citizen=self.citizen,
                    title="Rounded",
                    description="Rounding under test.",
                    issue_type=Report.IssueType.OTHER,
                    latitude=Decimal(latitude),
                    longitude=Decimal(longitude),
                    status=Report.Status.VERIFIED,
                )

                report = self.client.get("/api/reports/all/").data[0]

                self.assertEqual(report["latitude"], expected_latitude)
                self.assertEqual(report["longitude"], expected_longitude)

    def test_logged_in_users_still_see_all_statuses_with_exact_details(self):
        rejected_id = self._make_report(Report.Status.REJECTED)
        for viewer in (self.citizen, self.approved_official):
            self.client.force_authenticate(user=viewer)
            reports = self.client.get("/api/reports/all/").data

            self.assertEqual(
                {r["id"] for r in reports}, {self.report.id, rejected_id}
            )
            pending = next(r for r in reports if r["id"] == self.report.id)
            self.assertEqual(pending["status"], Report.Status.PENDING)
            self.assertEqual(pending["citizen"], "citizen")
            self.assertEqual(pending["latitude"], "12.972000")

    def test_anonymous_cannot_submit_a_report(self):
        before = Report.objects.count()

        response = self.client.post(
            "/api/reports/",
            {
                "title": "Anonymous",
                "description": "Should be refused.",
                "issue_type": "OTHER",
                "latitude": 12.97,
                "longitude": 74.85,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(Report.objects.count(), before)

    def test_anonymous_and_citizens_cannot_verify_or_reject(self):
        for decision in ("VERIFIED", "REJECTED"):
            with self.subTest(decision=decision):
                self.client.force_authenticate(user=None)
                anonymous = self.client.post(
                    f"/api/reports/{self.report.id}/verify/",
                    {"decision": decision},
                    format="json",
                )
                self.client.force_authenticate(user=self.citizen)
                citizen = self.client.post(
                    f"/api/reports/{self.report.id}/verify/",
                    {"decision": decision},
                    format="json",
                )

                self.assertEqual(anonymous.status_code, 401)
                self.assertEqual(citizen.status_code, 403)
                self.report.refresh_from_db()
                self.citizen.refresh_from_db()
                self.assertEqual(self.report.status, Report.Status.PENDING)
                self.assertEqual(self.citizen.points, 0)

    def test_my_reports_require_authentication(self):
        response = self.client.get("/api/reports/my/")

        self.assertEqual(response.status_code, 401)

    def test_unapproved_official_cannot_verify(self):
        self.client.force_authenticate(user=self.unapproved_official)
        response = self.client.post(
            f"/api/reports/{self.report.id}/verify/",
            {"decision": "VERIFIED"},
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.report.refresh_from_db()
        self.assertEqual(self.report.status, Report.Status.PENDING)

    def test_approved_official_verification_awards_server_points(self):
        self.client.force_authenticate(user=self.approved_official)
        response = self.client.post(
            f"/api/reports/{self.report.id}/verify/",
            {"decision": "VERIFIED"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.report.refresh_from_db()
        self.citizen.refresh_from_db()
        self.assertEqual(self.report.status, Report.Status.VERIFIED)
        self.assertEqual(self.report.verified_by, self.approved_official)
        self.assertEqual(self.citizen.points, 10)

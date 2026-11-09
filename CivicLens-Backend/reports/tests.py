import json
import os
import subprocess
import sys
from decimal import Decimal
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

from cloudinary.exceptions import Error as CloudinaryError
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, TestCase, override_settings
from PIL import ExifTags, Image, ImageChops, JpegImagePlugin
from rest_framework.test import APIClient

from .images import strip_image_metadata
from .models import Report


User = get_user_model()


def image_bytes(image_format, image=None, **options):
    output = BytesIO()
    (image or Image.new("RGB", (16, 16), (40, 120, 200))).save(
        output, format=image_format, **options
    )
    return output.getvalue()


JPEG_BYTES = image_bytes("JPEG")
PNG_BYTES = image_bytes("PNG")
WEBP_BYTES = image_bytes("WEBP")
CORRUPT_JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01" + b"\x00" * 32

ORIENTATION_TAG = 0x0112
MAKE_TAG = 0x010F
EXIF_MARKER = "PRIVATE-CAMERA-MARKER"


def exif_with_gps(orientation=1):
    exif = Image.Exif()
    exif[ORIENTATION_TAG] = orientation
    exif[MAKE_TAG] = EXIF_MARKER
    gps = exif.get_ifd(ExifTags.IFD.GPSInfo)
    gps[ExifTags.GPS.GPSLatitudeRef] = "N"
    gps[ExifTags.GPS.GPSLatitude] = (12.0, 58.0, 19.0)
    gps[ExifTags.GPS.GPSLongitudeRef] = "E"
    gps[ExifTags.GPS.GPSLongitude] = (74.0, 51.0, 22.0)
    return exif


CLOUDINARY_URL = (
    "https://res.cloudinary.com/demo/image/upload/v1700000000/"
    "report_photos/0123456789abcdef0123456789abcdef.jpg"
)


@override_settings(
    REPORT_PHOTO_BACKEND="cloudinary",
    CLOUDINARY_CLOUD_NAME="demo",
    CLOUDINARY_API_KEY="dummy-key",
    CLOUDINARY_API_SECRET="dummy-secret",
)
class CloudinaryPhotoUploadTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.citizen = User.objects.create_user(
            username="citizen", password="safe-password-123"
        )
        self.client.force_authenticate(user=self.citizen)

    def _upload(self, content=JPEG_BYTES):
        return self.client.post(
            "/api/reports/upload-photo/",
            {"photo": SimpleUploadedFile("client-name.jpg", content, "image/jpeg")},
            format="multipart",
        )

    @patch("reports.views.cloudinary.uploader.upload")
    def test_upload_returns_https_url_in_existing_response_shape(self, upload):
        received = {}

        def fake_upload(file, **options):
            received["content"] = file.read()
            received["options"] = options
            return {"secure_url": CLOUDINARY_URL, "url": "http://insecure.example/a.jpg"}

        upload.side_effect = fake_upload

        response = self._upload()

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data, {"photo": CLOUDINARY_URL})
        self.assertEqual(Image.open(BytesIO(received["content"])).format, "JPEG")
        self.assertEqual(received["options"]["resource_type"], "image")
        self.assertEqual(received["options"]["folder"], "report_photos")
        self.assertNotIn("client-name", received["options"]["public_id"])

    @patch("reports.views.cloudinary.uploader.upload")
    def test_gps_never_reaches_cloudinary(self, upload):
        sent = {}

        def fake_upload(file, **options):
            sent["content"] = file.read()
            return {"secure_url": CLOUDINARY_URL}

        upload.side_effect = fake_upload
        original = image_bytes("JPEG", exif=exif_with_gps())
        self.assertIn(EXIF_MARKER.encode(), original)

        response = self._upload(original)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertNotIn(EXIF_MARKER.encode(), sent["content"])
        self.assertEqual(len(Image.open(BytesIO(sent["content"])).getexif()), 0)

    @patch("reports.views.cloudinary.uploader.upload")
    def test_undecodable_image_with_valid_signature_is_not_uploaded(self, upload):
        response = self._upload(CORRUPT_JPEG_BYTES)

        self.assertEqual(response.status_code, 400)
        upload.assert_not_called()

    @patch("cloudinary.uploader._http.request")
    def test_real_sdk_signs_request_without_sending_the_secret(self, http_request):
        http_request.return_value = Mock(
            status=200, data=json.dumps({"secure_url": CLOUDINARY_URL}).encode()
        )

        response = self._upload()

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["photo"], CLOUDINARY_URL)
        call = http_request.call_args.kwargs
        self.assertIn("/demo/image/upload", call["url"])
        self.assertTrue(call["url"].startswith("https://"))
        fields = dict(call["fields"])
        self.assertEqual(fields["api_key"], "dummy-key")
        self.assertIn("signature", fields)
        self.assertNotIn("dummy-secret", repr(call))

    @patch("reports.views.cloudinary.uploader.upload")
    def test_cloudinary_url_can_be_saved_on_a_report(self, upload):
        upload.return_value = {"secure_url": CLOUDINARY_URL}
        photo_url = self._upload().data["photo"]

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
        self.assertEqual(Report.objects.get(id=response.data["id"]).photo, CLOUDINARY_URL)

    @patch("reports.views.cloudinary.uploader.upload")
    def test_non_images_are_rejected_before_reaching_cloudinary(self, upload):
        response = self._upload(b"this is not an image")

        self.assertEqual(response.status_code, 400)
        upload.assert_not_called()

    @patch("reports.views.cloudinary.uploader.upload")
    def test_cloudinary_failure_does_not_expose_error_details(self, upload):
        upload.side_effect = CloudinaryError("bad signature fake-secret-value")

        with self.assertLogs("reports.views", level="ERROR") as logs:
            response = self._upload()

        self.assertEqual(response.status_code, 502)
        self.assertNotIn("fake-secret-value", str(response.data))
        self.assertNotIn("fake-secret-value", "\n".join(logs.output))

    @override_settings(REPORT_PHOTO_BACKEND=None)
    @patch("reports.views.cloudinary.uploader.upload")
    def test_upload_is_refused_when_production_storage_is_missing(self, upload):
        with TemporaryDirectory() as media_root, override_settings(
            MEDIA_ROOT=media_root
        ), self.assertLogs("reports.views", level="ERROR"):
            response = self._upload()

            self.assertEqual(response.status_code, 503)
            self.assertEqual(list(Path(media_root).rglob("*.*")), [])
        upload.assert_not_called()


class ImageMetadataTests(SimpleTestCase):
    def _clean(self, content, extension):
        upload = SimpleUploadedFile(f"a{extension}", content)
        return strip_image_metadata(upload, extension).read()

    def test_exif_and_gps_are_removed_from_every_format(self):
        for image_format, extension in [
            ("JPEG", ".jpg"),
            ("PNG", ".png"),
            ("WEBP", ".webp"),
        ]:
            with self.subTest(image_format):
                original = image_bytes(image_format, exif=exif_with_gps())
                self.assertIn(EXIF_MARKER.encode(), original)
                source_exif = Image.open(BytesIO(original)).getexif()
                self.assertTrue(source_exif.get_ifd(ExifTags.IFD.GPSInfo))

                cleaned = self._clean(original, extension)

                self.assertNotIn(EXIF_MARKER.encode(), cleaned)
                result = Image.open(BytesIO(cleaned))
                self.assertEqual(result.format, image_format)
                self.assertEqual(len(result.getexif()), 0)
                self.assertFalse(result.getexif().get_ifd(ExifTags.IFD.GPSInfo))

    def test_xmp_and_comments_are_removed(self):
        original = image_bytes(
            "JPEG", xmp=b"<x>PRIVATE-XMP</x>", comment=b"PRIVATE-COMMENT"
        )
        self.assertIn(b"PRIVATE-XMP", original)
        self.assertIn(b"PRIVATE-COMMENT", original)

        cleaned = self._clean(original, ".jpg")

        self.assertNotIn(b"PRIVATE-XMP", cleaned)
        self.assertNotIn(b"PRIVATE-COMMENT", cleaned)

    def test_data_appended_after_the_image_is_removed(self):
        original = image_bytes("JPEG") + b"PRIVATE-MOTION-PHOTO"

        self.assertNotIn(b"PRIVATE-MOTION-PHOTO", self._clean(original, ".jpg"))

    def test_multi_picture_jpeg_keeps_only_a_clean_first_picture(self):
        second = Image.new("RGB", (16, 16), (1, 2, 3))
        original = image_bytes(
            "MPO", save_all=True, append_images=[second], exif=exif_with_gps()
        )
        self.assertEqual(Image.open(BytesIO(original)).format, "MPO")

        cleaned = self._clean(original, ".jpg")

        self.assertNotIn(EXIF_MARKER.encode(), cleaned)
        result = Image.open(BytesIO(cleaned))
        self.assertEqual(result.format, "JPEG")
        self.assertEqual(getattr(result, "n_frames", 1), 1)

    def test_orientation_is_applied_to_the_pixels(self):
        # Red on the left; orientation 6 means "rotate 90 degrees clockwise to view".
        image = Image.new("RGB", (40, 20), (0, 0, 255))
        image.paste((255, 0, 0), (0, 0, 20, 20))
        original = image_bytes("PNG", image=image, exif=exif_with_gps(orientation=6))

        result = Image.open(BytesIO(self._clean(original, ".png"))).convert("RGB")

        self.assertEqual(result.size, (20, 40))
        self.assertEqual(result.getpixel((10, 5)), (255, 0, 0))
        self.assertEqual(result.getpixel((10, 35)), (0, 0, 255))
        self.assertNotIn(ORIENTATION_TAG, result.getexif())

    def test_png_pixels_are_unchanged(self):
        image = Image.effect_noise((64, 64), 60).convert("RGB")
        cleaned = Image.open(
            BytesIO(self._clean(image_bytes("PNG", image=image), ".png"))
        ).convert("RGB")

        self.assertIsNone(ImageChops.difference(image, cleaned).getbbox())

    def test_jpeg_keeps_its_compression_settings(self):
        image = Image.effect_noise((64, 64), 60).convert("RGB")
        original = image_bytes("JPEG", image=image, quality=92, subsampling=0)

        source = Image.open(BytesIO(original))
        result = Image.open(BytesIO(self._clean(original, ".jpg")))

        self.assertEqual(result.quantization, source.quantization)
        self.assertEqual(
            JpegImagePlugin.get_sampling(result), JpegImagePlugin.get_sampling(source)
        )

    def test_transparency_survives(self):
        image = Image.new("RGBA", (8, 8), (255, 0, 0, 128))

        result = Image.open(BytesIO(self._clean(image_bytes("PNG", image=image), ".png")))

        self.assertEqual(result.mode, "RGBA")
        self.assertEqual(result.getpixel((0, 0)), (255, 0, 0, 128))

    def test_images_with_too_many_pixels_are_rejected(self):
        with patch("reports.images.MAX_IMAGE_PIXELS", 100):
            with self.assertRaises(ValueError):
                self._clean(JPEG_BYTES, ".jpg")


class ReportPhotoStorageSettingsTests(SimpleTestCase):
    """Loads settings in a fresh process, with dummy values only."""

    def _load(self, debug, **cloudinary_values):
        env = {
            **os.environ,
            "SECRET_KEY": "dummy",
            "JWT_SIGNING_KEY": "dummy",
            "DATABASE_URL": "postgres://user:pass@localhost:5432/dummy",
            "DEBUG": str(debug),
            "CLOUDINARY_CLOUD_NAME": "",
            "CLOUDINARY_API_KEY": "",
            "CLOUDINARY_API_SECRET": "",
            **cloudinary_values,
        }
        env["DJANGO_SETTINGS_MODULE"] = "config.settings"
        code = (
            "import django; django.setup();"
            "from django.conf import settings as s;"
            "import reports.views;"
            "print(s.REPORT_PHOTO_BACKEND)"
        )
        result = subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True,
            text=True,
            env=env,
            cwd=settings.BASE_DIR,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.split()

    def test_complete_credentials_select_cloudinary(self):
        backend = self._load(
            False,
            CLOUDINARY_CLOUD_NAME="demo",
            CLOUDINARY_API_KEY="dummy-key",
            CLOUDINARY_API_SECRET="dummy-secret",
        )[0]
        self.assertEqual(backend, "cloudinary")

    def test_local_development_needs_no_credentials(self):
        self.assertEqual(self._load(True)[0], "local")

    def test_production_without_credentials_has_no_disk_fallback(self):
        self.assertEqual(self._load(False)[0], "None")

    def test_partial_credentials_do_not_enable_cloudinary(self):
        backend = self._load(True, CLOUDINARY_CLOUD_NAME="demo")[0]
        self.assertEqual(backend, "local")


@override_settings(REPORT_PHOTO_BACKEND="local")
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
                    expected = Image.open(BytesIO(content))
                    with Image.open(Path(media_root) / stored) as saved:
                        self.assertEqual(saved.format, expected.format)
                        self.assertEqual(saved.size, expected.size)

    def test_files_that_are_not_images_are_rejected(self):
        cases = [
            ("fake.jpg", b"this is not an image", "image/jpeg"),
            ("page.png", b"<html></html>", "image/png"),
            ("riff.webp", b"RIFF\x00\x00\x00\x00WAVEfmt ", "image/webp"),
            ("empty.jpg", b"", "image/jpeg"),
            ("corrupt.jpg", CORRUPT_JPEG_BYTES, "image/jpeg"),
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

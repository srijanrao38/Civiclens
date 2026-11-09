
import logging
from uuid import uuid4

import cloudinary.uploader
from cloudinary.exceptions import Error as CloudinaryError
from django.conf import settings
from django.core.files.storage import default_storage
from rest_framework import generics, permissions
from rest_framework.parsers import MultiPartParser, FormParser
from .images import strip_image_metadata
from .models import Report
from .serializers import PublicReportSerializer, ReportSerializer
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from .permissions import IsApprovedOfficial

logger = logging.getLogger(__name__)


def detect_image_extension(upload):
    """Return the extension for the upload's actual format, or None.

    Reads the file signature because the client's filename and Content-Type
    are unverified labels.
    """
    upload.seek(0)
    header = upload.read(12)
    upload.seek(0)

    if header.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if header.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if header[:4] == b"RIFF" and header[8:12] == b"WEBP":
        return ".webp"
    return None


class ReportCreateView(generics.CreateAPIView):
    serializer_class = ReportSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        serializer.save(citizen=self.request.user)


class ReportListView(generics.ListAPIView):
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        reports = Report.objects.order_by("-created_at")
        if self.request.user.is_authenticated:
            return reports
        return reports.filter(status=Report.Status.VERIFIED)

    def get_serializer_class(self):
        if self.request.user.is_authenticated:
            return ReportSerializer
        return PublicReportSerializer


class MyReportsView(generics.ListAPIView):
    serializer_class = ReportSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Report.objects.filter(
            citizen=self.request.user
        ).order_by("-created_at")


class ReportPhotoUploadView(APIView):
    """Store a report photo and return a server URL for the report serializer."""

    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        photo = request.FILES.get("photo")
        if photo is None:
            return Response(
                {"detail": "Attach an image in the photo field."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if photo.size > 10 * 1024 * 1024:
            return Response(
                {"detail": "Photo must be 10 MB or smaller."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        extension = detect_image_extension(photo)
        if extension is None:
            return Response(
                {"detail": "Only JPG, PNG, and WebP images are supported."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            photo = strip_image_metadata(photo, extension)
        except Exception:
            # Decoders raise many types on bad input. Never store the original.
            return Response(
                {"detail": "This image could not be processed."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if settings.REPORT_PHOTO_BACKEND == "cloudinary":
            try:
                result = cloudinary.uploader.upload(
                    photo,
                    cloud_name=settings.CLOUDINARY_CLOUD_NAME,
                    api_key=settings.CLOUDINARY_API_KEY,
                    api_secret=settings.CLOUDINARY_API_SECRET,
                    resource_type="image",
                    folder="report_photos",
                    public_id=uuid4().hex,
                    overwrite=False,
                    timeout=20,
                )
            except CloudinaryError as error:
                # Only the type: the SDK's messages can echo request details.
                logger.error("Cloudinary upload failed: %s", type(error).__name__)
                return Response(
                    {"detail": "Could not store the photo. Please try again."},
                    status=status.HTTP_502_BAD_GATEWAY,
                )
            url = result["secure_url"]
        elif settings.REPORT_PHOTO_BACKEND == "local":
            filename = default_storage.save(
                f"report_photos/{uuid4().hex}{extension}", photo
            )
            url = request.build_absolute_uri(settings.MEDIA_URL + filename)
        else:
            logger.error("Report photo upload rejected: Cloudinary is not configured.")
            return Response(
                {"detail": "Photo storage is not available."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        return Response({"photo": url}, status=status.HTTP_201_CREATED)


class ReportVerificationView(APIView):
    permission_classes = [IsApprovedOfficial]

    def post(self, request, pk):
        try:
            report = Report.objects.get(pk=pk)
        except Report.DoesNotExist:
            return Response(
                {"detail": "Report not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        decision = request.data.get("decision")

        if decision not in ["VERIFIED", "REJECTED"]:
            return Response(
                {"detail": "Decision must be VERIFIED or REJECTED."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if report.status != Report.Status.PENDING:
            return Response(
                {"detail": "This report has already been reviewed."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        report.status = decision
        report.verified_by = request.user
        report.save(update_fields=["status", "verified_by"])

        if decision == Report.Status.VERIFIED:
            report.citizen.points += 10
            report.citizen.save(update_fields=["points"])

        return Response({
            "message": f"Report {decision.lower()} successfully.",
            "report_id": report.id,
            "status": report.status,
            "points_awarded": 10 if decision == "VERIFIED" else 0,
        })

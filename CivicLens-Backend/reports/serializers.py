
from decimal import Decimal

from rest_framework import serializers
from .models import Report


class PublicReportSerializer(serializers.ModelSerializer):
    """What logged-out visitors see: no identities, coordinates to about 110 m."""

    latitude = serializers.SerializerMethodField()
    longitude = serializers.SerializerMethodField()

    class Meta:
        model = Report
        fields = [
            "id",
            "title",
            "description",
            "issue_type",
            "latitude",
            "longitude",
            "photo",
            "status",
            "created_at",
        ]

    def get_latitude(self, report):
        return str(report.latitude.quantize(Decimal("0.001")))

    def get_longitude(self, report):
        return str(report.longitude.quantize(Decimal("0.001")))


class ReportSerializer(serializers.ModelSerializer):
    citizen = serializers.ReadOnlyField(source="citizen.username")
    verified_by = serializers.ReadOnlyField(
        source="verified_by.username"
    )

    class Meta:
        model = Report
        fields = [
            "id",
            "citizen",
            "title",
            "description",
            "issue_type",
            "latitude",
            "longitude",
            "photo",
            "status",
            "verified_by",
            "created_at",
        ]
        read_only_fields = [
            "id",
            "citizen",
            "status",
            "verified_by",
            "created_at",
        ]

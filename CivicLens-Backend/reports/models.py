
from django.conf import settings
from django.db import models


class Report(models.Model):
    class IssueType(models.TextChoices):
        POTHOLE = "POTHOLE", "Pothole"
        GARBAGE = "GARBAGE", "Overflowing Garbage"
        STREETLIGHT = "STREETLIGHT", "Broken Streetlight"
        DRAINAGE = "DRAINAGE", "Drainage Issue"
        OTHER = "OTHER", "Other"

    class Status(models.TextChoices):
        PENDING = "PENDING", "Pending Verification"
        VERIFIED = "VERIFIED", "Verified"
        REJECTED = "REJECTED", "Rejected"

    citizen = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="reports",
    )

    title = models.CharField(max_length=200)
    description = models.TextField()
    issue_type = models.CharField(
        max_length=20,
        choices=IssueType.choices,
    )

    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)

    photo = models.URLField(blank=True)

    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.PENDING,
    )

    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="verified_reports",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.title} - {self.status}"

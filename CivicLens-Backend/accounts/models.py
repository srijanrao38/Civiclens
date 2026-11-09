from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    class Role(models.TextChoices):
        CITIZEN = "CITIZEN", "Citizen"
        OFFICIAL = "OFFICIAL", "Official"

    role = models.CharField(
        max_length=10,
        choices=Role.choices,
        default=Role.CITIZEN,
    )

    points = models.PositiveIntegerField(default=0)

    is_official_approved = models.BooleanField(default=False)

    def __str__(self):
        return f"{self.username} ({self.role})"

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import User


@admin.register(User)
class CustomUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (
        ("CivicLens Details", {
            "fields": ("role", "points", "is_official_approved"),
        }),
    )

    add_fieldsets = UserAdmin.add_fieldsets + (
        ("CivicLens Details", {
            "fields": ("role", "points", "is_official_approved"),
        }),
    )

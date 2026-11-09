
from rest_framework.permissions import BasePermission


class IsApprovedOfficial(BasePermission):
    message = "Only approved officials can perform this action."

    def has_permission(self, request, view):
        user = request.user

        return (
            user.is_authenticated
            and user.role == "OFFICIAL"
            and user.is_official_approved
        )

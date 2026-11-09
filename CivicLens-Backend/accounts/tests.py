from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient


User = get_user_model()


class AccountApiTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_registration_always_creates_a_citizen(self):
        response = self.client.post(
            "/api/auth/register/",
            {
                "username": "new-citizen",
                "email": "citizen@example.com",
                "password": "safe-password-123",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        user = User.objects.get(username="new-citizen")
        self.assertEqual(user.role, User.Role.CITIZEN)
        self.assertFalse(user.is_official_approved)

    def test_profile_requires_authentication(self):
        response = self.client.get("/api/auth/me/")

        self.assertEqual(response.status_code, 401)


from rest_framework import generics, permissions
from rest_framework.views import APIView
from rest_framework.response import Response

from .serializers import (
    CitizenRegistrationSerializer,
    UserProfileSerializer,
)


class CitizenRegistrationView(generics.CreateAPIView):
    serializer_class = CitizenRegistrationSerializer
    permission_classes = [permissions.AllowAny]


class MyProfileView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        serializer = UserProfileSerializer(request.user)
        return Response(serializer.data)

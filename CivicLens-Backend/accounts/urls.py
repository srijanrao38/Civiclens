
from django.urls import path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .views import CitizenRegistrationView, MyProfileView

urlpatterns = [
    path(
        "register/",
        CitizenRegistrationView.as_view(),
        name="citizen-register",
    ),
    path(
        "login/",
        TokenObtainPairView.as_view(),
        name="token-obtain-pair",
    ),
    path(
        "login/refresh/",
        TokenRefreshView.as_view(),
        name="token-refresh",
    ),
    path(
        "me/",
        MyProfileView.as_view(),
        name="my-profile",
    ),
]

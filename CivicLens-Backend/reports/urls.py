
from django.urls import path
from .views import (
    ReportCreateView,
    ReportListView,
    MyReportsView,
    ReportPhotoUploadView,
    ReportVerificationView,
)

urlpatterns = [
    path("", ReportCreateView.as_view(), name="report-create"),
    path("all/", ReportListView.as_view(), name="report-list"),
    path("my/", MyReportsView.as_view(), name="my-reports"),
    path("upload-photo/", ReportPhotoUploadView.as_view(), name="report-photo-upload"),
    path(
        "<int:pk>/verify/",
        ReportVerificationView.as_view(),
        name="report-verify",
    ),
]

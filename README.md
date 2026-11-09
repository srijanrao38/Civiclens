# CivicLens — Smart Civic Issue Reporting Platform

**Your City, Your Voice. Report Problems. Track Progress. Create Change.**

CivicLens is a mobile-based civic engagement platform that enables citizens to report public infrastructure problems using photographs and GPS coordinates. It helps communities report issues such as potholes, garbage accumulation, damaged streetlights, and drainage problems while allowing authorized officials to review and verify submitted reports.

## Key Features

### Citizen Features
- **User Authentication:** Secure registration and login using JWT authentication.
- **Issue Reporting:** Submit civic complaints with photographs, descriptions, issue categories, and GPS coordinates.
- **Public Map:** View verified civic issues geographically using OpenStreetMap.
- **Report Tracking:** Monitor submitted reports and their verification status.
- **Reward System:** Earn 10 reward points when a submitted report is verified.

### Official Features
- Dedicated official authentication and role-based access.
- Review submitted civic complaints.
- Verify or reject reported issues.
- Support community participation through report verification and rewards.

### Image and Location Processing
- Cloudinary integration for image storage.
- Image processing designed to remove EXIF metadata, including embedded GPS information, before uploading.
- GPS-based report location capture.
- Interactive maps powered by OpenStreetMap.

## Technology Stack

| Component | Technologies |
|---|---|
| Mobile application | Flutter, Dart |
| Backend | Python, Django REST Framework |
| Database | PostgreSQL |
| Authentication | JWT |
| Image storage | Cloudinary |
| Maps | OpenStreetMap, flutter_map |
| Location services | Geolocator |
| Deployment | Render |
| Version control | Git, GitHub |

## System Architecture

```text
             Flutter Mobile Application
                       |
                       | HTTPS / REST API
                       |
                       v
              Django REST Framework
                       |
          +------------+------------+
          |            |            |
          v            v            v
      PostgreSQL   Cloudinary   JWT Auth
          |
          v
    Reports & Users
          |
          v
   Official Verification
          |
          v
     Reward Points
```

## Live Deployment

**Backend URL:**  
https://civiclens-backend-ewbp.onrender.com

**Django Admin:**  
https://civiclens-backend-ewbp.onrender.com/admin/

**Public Reports API:**  
https://civiclens-backend-ewbp.onrender.com/api/reports/all/

> Note: The backend is hosted on Render's free instance, which may spin down after inactivity. The free database also has a limited availability period.

## Running the Project Locally

### Prerequisites
- Flutter SDK
- Python
- PostgreSQL
- Git

### 1. Clone the repository

```bash
git clone https://github.com/srijanrao38/Civiclens.git
cd Civiclens
```

### 2. Set up the Django backend

```bash
cd CivicLens-Backend

python -m venv venv
```

Activate the virtual environment:

**Windows:**
```bash
venv\Scripts\activate
```

Install dependencies:

```bash
pip install -r requirements.txt
```

Configure your environment variables using `.env.example`. Set the required database, Django secret, JWT, and Cloudinary credentials.

Run migrations:

```bash
python manage.py migrate
```

Start the backend:

```bash
python manage.py runserver
```

### 3. Set up the Flutter application

Open a new terminal:

```bash
cd CivicLens
flutter pub get
flutter run
```

Configure the API base URL in `lib/api_client.dart` if you are running the backend locally.

## Android APK

A release APK has been generated successfully.

**Build command:**

```bash
flutter build apk --release
```

APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Project Highlights

- Mobile-first civic issue reporting.
- Role-based citizen and official workflows.
- GPS-enabled issue reporting.
- RESTful backend architecture.
- Cloud-based image storage.
- Community participation through report verification and reward points.

## Future Enhancements

- Push notifications for report status updates.
- Analytics dashboard for civic authorities.
- AI-based automatic classification of reported issues.
- Integration with municipal complaint management systems.
- Improved report prioritization based on severity and location.

## Author

**Srijan S Rao**

- GitHub: https://github.com/srijanrao38
- LinkedIn: https://linkedin.com/in/srijan-s-rao
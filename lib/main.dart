import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'models.dart';

const green = Color(0xFF167D57);

void main() => runApp(const CivicLensApp());

class CivicLensApp extends StatefulWidget {
  final AuthService? authService;

  const CivicLensApp({super.key, this.authService});

  @override
  State<CivicLensApp> createState() => _CivicLensAppState();
}

class _CivicLensAppState extends State<CivicLensApp> {
  late final AuthService _authService = widget.authService ?? AuthService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  void _openDashboard(UserProfile profile) {
    final isApprovedOfficial =
        profile.role == 'OFFICIAL' && profile.isOfficialApproved;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('Dashboard navigation skipped: navigator is not ready.');
      return;
    }
    // Clears everything, so Back can't return to the login or guest map.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => isApprovedOfficial
            ? OfficialDashboard(
                authService: _authService,
                profile: profile,
                onLoginSuccess: _openDashboard,
              )
            : HomeScreen(
                authService: _authService,
                profile: profile,
                onLoginSuccess: _openDashboard,
              ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'CivicLens',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: green),
        scaffoldBackgroundColor: const Color(0xFFF6F8F6),
        useMaterial3: true,
      ),
      home: LoginScreen(
        authService: _authService,
        onLoginSuccess: _openDashboard,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final UserProfile profile;
  final void Function(UserProfile profile) onLoginSuccess;

  const HomeScreen({
    super.key,
    required this.authService,
    required this.profile,
    required this.onLoginSuccess,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  int tab = 0;
  String filter = 'All';
  List<CivicReport> publicReports = [];
  List<CivicReport> myReports = [];
  UserProfile? profile;
  bool loading = true;
  String? errorMessage;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    profile = widget.profile;
    _loadData();
  }

  Future<void> _loadData() async {
    // Tab switches can overlap; only the newest request may update the screen.
    final generation = ++_loadGeneration;
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final results = await Future.wait([
        widget.authService.getPublicReports(),
        widget.authService.getMyReports(),
        widget.authService.getProfile(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        publicReports = results[0] as List<CivicReport>;
        myReports = results[1] as List<CivicReport>;
        profile = results[2] as UserProfile;
        loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        loading = false;
        errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        loading = false;
        errorMessage = 'Could not load reports. Check your connection and retry.';
      });
    }
  }

  void _selectTab(int index) {
    setState(() => tab = index);
    _loadData();
  }

  Future<Position> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Please enable Location on your phone.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission was not granted.');
    }
    return Geolocator.getCurrentPosition();
  }

  Future<File?> _pickPhoto(ImageSource source) async {
    final photo = await _imagePicker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
    );
    return photo == null ? null : File(photo.path);
  }

  Future<void> _showReportForm() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String issueType = 'POTHOLE';
    File? selectedPhoto;
    Position? position;
    bool submitting = false;
    String? formError;
    String progressText = 'The report will be submitted to CivicLens.';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Report a civic issue'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final photo =
                                      await _pickPhoto(ImageSource.camera);
                                  if (photo != null) {
                                    setDialogState(() => selectedPhoto = photo);
                                  }
                                },
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final photo =
                                      await _pickPhoto(ImageSource.gallery);
                                  if (photo != null) {
                                    setDialogState(() => selectedPhoto = photo);
                                  }
                                },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  ),
                  if (selectedPhoto != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Image.file(selectedPhoto!,
                          height: 130,
                          width: double.infinity,
                          fit: BoxFit.cover),
                    ),
                  OutlinedButton.icon(
                    onPressed: submitting
                        ? null
                        : () async {
                            try {
                              final captured = await _getCurrentLocation();
                              setDialogState(() => position = captured);
                            } catch (error) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.toString())));
                              }
                            }
                          },
                    icon: const Icon(Icons.my_location),
                    label: Text(position == null
                        ? 'Capture GPS location'
                        : 'GPS captured ✓'),
                  ),
                  if (position != null)
                    Text(
                        '${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    enabled: !submitting,
                    onChanged: (_) {
                      if (formError != null) {
                        setDialogState(() => formError = null);
                      }
                    },
                    decoration: const InputDecoration(
                        labelText: 'Short title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    enabled: !submitting,
                    maxLines: 3,
                    onChanged: (_) {
                      if (formError != null) {
                        setDialogState(() => formError = null);
                      }
                    },
                    decoration: const InputDecoration(
                        labelText: 'Describe the issue',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: issueType,
                    decoration: const InputDecoration(
                        labelText: 'Issue type', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'POTHOLE', child: Text('Pothole')),
                      DropdownMenuItem(value: 'GARBAGE', child: Text('Garbage')),
                      DropdownMenuItem(
                          value: 'STREETLIGHT', child: Text('Broken streetlight')),
                      DropdownMenuItem(
                          value: 'DRAINAGE', child: Text('Drainage')),
                      DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                    ],
                    onChanged: submitting
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => issueType = value);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  if (submitting) const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  if (formError != null)
                    Text(formError!,
                        style: const TextStyle(color: Colors.red)),
                  if (formError != null) const SizedBox(height: 6),
                  Text(progressText,
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final title = titleController.text.trim();
                      final description = descriptionController.text.trim();
                      if (title.isEmpty || description.isEmpty) {
                        setDialogState(() {
                          formError = title.isEmpty && description.isEmpty
                              ? 'Enter a title and description.'
                              : title.isEmpty
                                  ? 'Enter a title.'
                                  : 'Enter a description.';
                        });
                        return;
                      }
                      if (position == null) {
                        setDialogState(() =>
                            formError = 'Capture GPS before submitting.');
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        formError = null;
                        progressText = selectedPhoto == null
                            ? 'Submitting report...'
                            : 'Uploading photo and submitting report...';
                      });
                      try {
                        await widget.authService.createReport(
                          title: title,
                          description: description,
                          issueType: issueType,
                          latitude: position!.latitude,
                          longitude: position!.longitude,
                          photo: selectedPhoto,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        await _loadData();
                        if (mounted) {
                          setState(() {
                            tab = 0;
                            filter = 'All';
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Report submitted successfully.')));
                        }
                      } on ApiException catch (error) {
                        setDialogState(() {
                          submitting = false;
                          formError = _reportSubmissionError(error);
                        });
                      } on SocketException catch (error, stackTrace) {
                        debugPrint('Report submission network error: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        setDialogState(() {
                          submitting = false;
                          formError =
                              'Could not reach CivicLens. Check the server and try again.';
                        });
                      } on TimeoutException catch (error, stackTrace) {
                        debugPrint('Report submission timeout: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        setDialogState(() {
                          submitting = false;
                          formError =
                              'The report request timed out. Please try again.';
                        });
                      } catch (error, stackTrace) {
                        debugPrint('Unexpected report submission error: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        setDialogState(() {
                          submitting = false;
                          formError =
                              'The report could not be submitted. Please try again.';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
  }

  void _showReportDetails(CivicReport report) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ReportDetails(
        report: report,
        showActions: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = tab == 2 ? myReports : publicReports;
    final visibleReports = reports.where((report) {
      return filter == 'All' || issueLabel(report.issueType) == filter;
    }).toList();
    final points = profile?.points ?? widget.profile.points;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.location_city, color: green, size: 30),
          SizedBox(width: 8),
          Text('CivicLens', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          Chip(
              avatar: const Icon(Icons.stars, color: green),
              label: Text('$points pts')),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'refresh') await _loadData();
              if (value == 'logout') await _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Refresh data')),
              PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: _body(visibleReports, points),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showReportForm,
        backgroundColor: green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Report issue'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Public Map'),
          NavigationDestination(
              icon: Icon(Icons.assignment_ind_outlined),
              selectedIcon: Icon(Icons.assignment_ind),
              label: 'My Reports'),
        ],
      ),
    );
  }

  Widget _body(List<CivicReport> visibleReports, int points) {
    if (tab == 1) return _buildMap();
    if (loading && publicReports.isEmpty && myReports.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (tab == 0) ...[
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                  color: green, borderRadius: BorderRadius.circular(22)),
              child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR CITY, YOUR VOICE',
                        style: TextStyle(
                            color: Colors.white70,
                            letterSpacing: 1.3,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Text('Make your city\nbetter for everyone.',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            height: 1.2,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    Text('Report problems. Track progress. Create change.',
                        style: TextStyle(color: Colors.white)),
                  ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              _statCard('Total reports', '${publicReports.length}',
                  Icons.assignment_outlined),
              const SizedBox(width: 12),
              _statCard(
                  'Verified',
                  '${publicReports.where((r) => r.status == 'VERIFIED').length}',
                  Icons.check_circle_outline),
            ]),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFFE5F3EB),
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.emoji_events, color: green),
                title: const Text('Civic rewards',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Your points: $points • Earn 10 points when your report is verified.'),
              ),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Community issues',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              TextButton(
                  onPressed: () => _selectTab(1),
                  child: const Text('View map')),
            ]),
          ] else ...[
            const Text('My Reports',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Reward points: $points',
                style: const TextStyle(
                    color: green, fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 8),
          _filterChips(),
          const SizedBox(height: 12),
          if (errorMessage != null && visibleReports.isEmpty)
            _errorState(errorMessage!),
          ...visibleReports.map(_reportCard),
          if (!loading && errorMessage == null && visibleReports.isEmpty)
            Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tab == 2
                    ? 'You have not submitted any reports yet.'
                    : 'No public issues in this category yet.')),
        ],
      ),
    );
  }

  Widget _filterChips() {
    const categories = ['All', 'Roads', 'Garbage', 'Lighting', 'Drainage', 'Other'];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => ChoiceChip(
          label: Text(categories[index]),
          selected: filter == categories[index],
          onSelected: (_) => setState(() => filter = categories[index]),
        ),
      ),
    );
  }

  Widget _statCard(String title, String count, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: green, size: 26),
            const SizedBox(height: 12),
            Text(count,
                style:
                    const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(color: Colors.black54)),
          ]),
        ),
      );

  Widget _reportCard(CivicReport report) {
    final color = statusColor(report.status);
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => _showReportDetails(report),
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
            backgroundColor: const Color(0xFFE5F3EB),
            child: Icon(issueIcon(report.issueType), color: green)),
        title: Text(report.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '${issueLabel(report.issueType)} • ${formatDate(report.createdAt)}')),
        trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text(statusLabel(report.status),
                style: TextStyle(color: color, fontSize: 10))),
      ),
    );
  }

  Widget _buildMap() => _ReportMapView(
        reports: publicReports,
        loading: loading,
        onRefresh: _loadData,
        onReportTap: _showReportDetails,
        emptyMessage: 'No reports with valid coordinates yet.',
      );

  Widget _errorState(String message) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: Text(message),
          trailing: IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ),
      );

  Future<void> _logout() async {
    await widget.authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => LoginScreen(
              authService: widget.authService,
              onLoginSuccess: widget.onLoginSuccess)),
      (_) => false,
    );
  }
}

/// The map for logged-out visitors. The server limits it to verified reports.
class PublicMapScreen extends StatefulWidget {
  final AuthService authService;

  const PublicMapScreen({super.key, required this.authService});

  @override
  State<PublicMapScreen> createState() => _PublicMapScreenState();
}

class _PublicMapScreenState extends State<PublicMapScreen> {
  List<CivicReport> reports = [];
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final data = await widget.authService.getGuestReports();
      if (!mounted) return;
      setState(() {
        reports = data;
        loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'Could not load reports. Check your connection and retry.';
      });
    }
  }

  void _showDetails(CivicReport report) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReportDetails(
        report: report,
        showActions: false,
        approximateLocation: true,
      ),
    );
  }

  /// The login screen is always directly beneath this one.
  void _goToLogin() => Navigator.of(context).pop();

  void _goToRegister() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => RegistrationScreen(authService: widget.authService),
    ));
  }

  Future<void> _promptForAccount(String feature) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log in to continue'),
        content: Text('Please log in or create a free account to $feature.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Not now')),
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('register'),
              child: const Text('Register')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('login'),
              child: const Text('Log in')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'login') _goToLogin();
    if (choice == 'register') _goToRegister();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Row(children: [
          Icon(Icons.location_city, color: green, size: 30),
          SizedBox(width: 8),
          Text('CivicLens', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          TextButton(onPressed: _goToLogin, child: const Text('Log in')),
        ],
      ),
      body: _ReportMapView(
        reports: reports,
        loading: loading,
        onRefresh: _loadReports,
        onReportTap: _showDetails,
        emptyMessage: errorMessage ?? 'No verified reports yet.',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _promptForAccount('submit a report'),
        backgroundColor: green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Report issue'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) _promptForAccount('see your reports');
          if (index == 2) _promptForAccount('earn reward points');
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Public Map'),
          NavigationDestination(
              icon: Icon(Icons.assignment_ind_outlined),
              label: 'My Reports'),
          NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined), label: 'Rewards'),
        ],
      ),
    );
  }
}

class _ReportMapView extends StatelessWidget {
  final List<CivicReport> reports;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function(CivicReport report) onReportTap;
  final String emptyMessage;

  const _ReportMapView({
    required this.reports,
    required this.loading,
    required this.onRefresh,
    required this.onReportTap,
    required this.emptyMessage,
  });

  void _showGroup(BuildContext context, List<CivicReport> group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('${group.length} reports in this area',
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...group.map((report) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(issueIcon(report.issueType),
                      color: statusColor(report.status)),
                  title: Text(report.title),
                  subtitle: Text([
                    issueLabel(report.issueType),
                    statusLabel(report.status),
                    if (report.citizen.isNotEmpty) report.citizen,
                  ].join(' • ')),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onReportTap(report);
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading && reports.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final mapped = reports
        .where((report) => report.latitude != 0 && report.longitude != 0)
        .toList();
    final center = mapped.isEmpty
        ? const LatLng(12.9720, 74.8560)
        : LatLng(mapped.first.latitude, mapped.first.longitude);
    return Stack(children: [
      FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 13),
        children: [
          TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.civiclens'),
          _ReportMarkerLayer(
            reports: mapped,
            onReportTap: onReportTap,
            onGroupTap: (group) => _showGroup(context, group),
          ),
          RichAttributionWidget(attributions: const [
            TextSourceAttribution('© OpenStreetMap contributors'),
          ]),
        ],
      ),
      Positioned(
        right: 16,
        top: 16,
        child: FloatingActionButton.small(
            heroTag: 'map-refresh',
            onPressed: onRefresh,
            backgroundColor: Colors.white,
            child: const Icon(Icons.refresh)),
      ),
      if (mapped.isEmpty)
        Center(
            child: Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(emptyMessage)))),
    ]);
  }
}

/// Draws one pin per on-screen location, so reports whose pins would cover each
/// other stay reachable. Groups are recomputed as the map zooms.
class _ReportMarkerLayer extends StatelessWidget {
  static const _overlapDistance = 40.0;

  final List<CivicReport> reports;
  final void Function(CivicReport report) onReportTap;
  final void Function(List<CivicReport> reports) onGroupTap;

  const _ReportMarkerLayer({
    required this.reports,
    required this.onReportTap,
    required this.onGroupTap,
  });

  List<List<CivicReport>> _groupOverlapping(MapCamera camera) {
    final groups = <({Offset position, List<CivicReport> reports})>[];
    for (final report in reports) {
      final position =
          camera.projectAtZoom(LatLng(report.latitude, report.longitude));
      final matches = groups.where((group) =>
          (group.position - position).distance < _overlapDistance);
      if (matches.isEmpty) {
        groups.add((position: position, reports: [report]));
      } else {
        matches.first.reports.add(report);
      }
    }
    return groups.map((group) => group.reports).toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupOverlapping(MapCamera.of(context));
    return MarkerLayer(
      markers: groups.map((group) {
        final first = group.first;
        return Marker(
          key: ValueKey('report-marker-${first.id}'),
          point: LatLng(first.latitude, first.longitude),
          width: 55,
          height: 55,
          child: GestureDetector(
            onTap: () =>
                group.length == 1 ? onReportTap(first) : onGroupTap(group),
            child: Stack(alignment: Alignment.center, children: [
              Icon(Icons.location_pin,
                  color: statusColor(first.status), size: 45),
              if (group.length > 1)
                Positioned(
                  top: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: green,
                    child: Text('${group.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class OfficialDashboard extends StatefulWidget {
  final AuthService authService;
  final UserProfile profile;
  final void Function(UserProfile profile) onLoginSuccess;

  const OfficialDashboard({
    super.key,
    required this.authService,
    required this.profile,
    required this.onLoginSuccess,
  });

  @override
  State<OfficialDashboard> createState() => _OfficialDashboardState();
}

class _OfficialDashboardState extends State<OfficialDashboard> {
  List<CivicReport> reports = [];
  bool loading = true;
  int? reviewingId;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final data = await widget.authService.getPublicReports();
      if (mounted) {
        setState(() {
          reports = data;
          loading = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          errorMessage = error.message;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          errorMessage = 'Could not load public reports.';
          loading = false;
        });
      }
    }
  }

  Future<void> _review(CivicReport report, String decision) async {
    setState(() => reviewingId = report.id);
    try {
      final result =
          await widget.authService.verifyReport(report.id, decision);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']?.toString() ?? 'Report updated.')));
      await _loadReports();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => reviewingId = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => reviewingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification request failed.')));
      }
    }
  }

  void _showDetails(CivicReport report) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReportDetails(
        report: report,
        showActions: report.status == 'PENDING',
        busy: reviewingId == report.id,
        onDecision: (decision) => _review(report, decision),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = reports.where((r) => r.status == 'PENDING').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Official dashboard'),
        actions: [
          IconButton(onPressed: _loadReports, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'logout') {
                await widget.authService.logout();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => LoginScreen(
                            authService: widget.authService,
                            onLoginSuccess: widget.onLoginSuccess)),
                    (_) => false);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        child: loading && reports.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: const Color(0xFFE5F3EB),
                    child: ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: green,
                          child: Icon(Icons.verified_user, color: Colors.white)),
                      title: Text(widget.profile.username,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'Approved official • $pending report${pending == 1 ? '' : 's'} pending review'),
                    ),
                  ),
                  if (errorMessage != null) _errorCard(errorMessage!),
                  const SizedBox(height: 8),
                  ...reports.map((report) => Card(
                        child: ListTile(
                          onTap: () => _showDetails(report),
                          leading: Icon(issueIcon(report.issueType), color: green),
                          title: Text(report.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              '${report.citizen} • ${issueLabel(report.issueType)} • ${formatDate(report.createdAt)}'),
                          trailing: Chip(label: Text(statusLabel(report.status))),
                        ),
                      )),
                  if (!loading && reports.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No public reports have been submitted yet.')),
                ],
              ),
      ),
    );
  }

  Widget _errorCard(String message) => Card(
        child: ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: Text(message),
            trailing: IconButton(
                onPressed: _loadReports, icon: const Icon(Icons.refresh))),
      );
}

class _ReportDetails extends StatelessWidget {
  final CivicReport report;
  final bool showActions;
  final bool busy;
  final ValueChanged<String>? onDecision;
  final bool approximateLocation;

  const _ReportDetails({
    required this.report,
    required this.showActions,
    this.busy = false,
    this.onDecision,
    this.approximateLocation = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(report.title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(report.description),
            const SizedBox(height: 14),
            Text('Category: ${issueLabel(report.issueType)}'),
            Text('Status: ${statusLabel(report.status)}'),
            Text('Submitted: ${formatDate(report.createdAt)}'),
            Text(approximateLocation
                ? 'Approximate location: ${report.latitude.toStringAsFixed(3)}, ${report.longitude.toStringAsFixed(3)}'
                : 'Location: ${report.latitude.toStringAsFixed(6)}, ${report.longitude.toStringAsFixed(6)}'),
            if (report.citizen.isNotEmpty) Text('Submitted by: ${report.citizen}'),
            if (report.verifiedBy != null) Text('Reviewed by: ${report.verifiedBy}'),
            if (report.photo != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(report.photo!,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Photo could not be loaded.'))),
              ),
            ],
            if (showActions) ...[
              const SizedBox(height: 20),
              if (busy) const LinearProgressIndicator(),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: busy ? null : () => onDecision?.call('REJECTED'),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                      onPressed:
                          busy ? null : () => onDecision?.call('VERIFIED'),
                      icon: const Icon(Icons.check),
                      label: const Text('Verify')),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

String issueLabel(String value) {
  switch (value) {
    case 'POTHOLE':
      return 'Roads';
    case 'GARBAGE':
      return 'Garbage';
    case 'STREETLIGHT':
      return 'Lighting';
    case 'DRAINAGE':
      return 'Drainage';
    default:
      return 'Other';
  }
}

IconData issueIcon(String value) {
  switch (value) {
    case 'POTHOLE':
      return Icons.construction;
    case 'GARBAGE':
      return Icons.delete_outline;
    case 'STREETLIGHT':
      return Icons.lightbulb_outline;
    case 'DRAINAGE':
      return Icons.water_drop_outlined;
    default:
      return Icons.report_problem_outlined;
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'VERIFIED':
      return green;
    case 'REJECTED':
      return Colors.red;
    default:
      return Colors.orange;
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'VERIFIED':
      return 'Verified';
    case 'REJECTED':
      return 'Rejected';
    default:
      return 'Pending verification';
  }
}

String formatDate(DateTime? date) {
  if (date == null) return 'Date unavailable';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _reportSubmissionError(ApiException error) {
  if (error.statusCode == 401) return 'Your session expired. Please log in again.';
  if (error.statusCode != null && error.statusCode! >= 500) {
    return 'CivicLens encountered a server error. Please try again.';
  }
  return error.message;
}

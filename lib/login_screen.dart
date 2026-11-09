import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'main.dart' show PublicMapScreen;
import 'models.dart';

const Color civicGreen = Color(0xFF167D57);

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final void Function(UserProfile profile) onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _restoreExistingSession();
  }

  Future<void> _restoreExistingSession() async {
    final profile = await widget.authService.restoreSession();
    if (profile != null && mounted) widget.onLoginSuccess(profile);
  }

  Future<void> _login() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final profile = await widget.authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (mounted) widget.onLoginSuccess(profile);
    } on ApiException catch (error) {
      debugPrint(
          'Login API error (${error.statusCode ?? 'unknown'}): ${error.message}');
      if (mounted) {
        setState(() => _errorMessage = _apiErrorMessage(error));
      }
    } on AuthStorageException catch (error) {
      debugPrint('Login storage error: ${error.message}');
      if (mounted) setState(() => _errorMessage = error.message);
    } on SocketException catch (error, stackTrace) {
      debugPrint('Login network error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _errorMessage =
            'Could not reach CivicLens. Check the server address and connection.');
      }
    } on TimeoutException catch (error, stackTrace) {
      debugPrint('Login timeout: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _errorMessage =
            'The server took too long to respond. Please try again.');
      }
    } on FormatException catch (error, stackTrace) {
      debugPrint('Login response parsing error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _errorMessage =
            'CivicLens returned an invalid response. Check the server logs.');
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _errorMessage =
            'Login completed, but the app could not open your dashboard.');
      }
      debugPrint('Unexpected login flow error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _apiErrorMessage(ApiException error) {
    if (error.statusCode == 401) return 'Invalid username or password.';
    if (error.statusCode != null && error.statusCode! >= 500) {
      return 'CivicLens encountered a server error. Please try again.';
    }
    return error.message;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.location_city, size: 64, color: civicGreen),
                    const SizedBox(height: 12),
                    const Text('CivicLens',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: civicGreen)),
                    const SizedBox(height: 8),
                    const Text('Sign in to make your community better.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder()),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Enter your username'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter your password'
                          : null,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: civicGreen,
                            foregroundColor: Colors.white),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Login', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => RegistrationScreen(
                                  authService: widget.authService,
                                ),
                              )),
                      child: const Text('New to CivicLens? Create a citizen account'),
                    ),
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => PublicMapScreen(
                                  authService: widget.authService,
                                ),
                              )),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Browse the map without logging in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegistrationScreen extends StatefulWidget {
  final AuthService authService;

  const RegistrationScreen({super.key, required this.authService});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;
  String? _message;
  bool _success = false;

  Future<void> _register() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await widget.authService.register(
        username: _username.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _message = 'Account created. You can now sign in as a citizen.';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Registration could not reach the server.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create citizen account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Join your community',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Public registration creates a citizen account. Official access is approved separately.'),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                          labelText: 'Username', border: OutlineInputBorder()),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Enter a username'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: 'Email', border: OutlineInputBorder()),
                      validator: (value) => value == null || !value.contains('@')
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Password (8+ characters)',
                          border: OutlineInputBorder()),
                      validator: (value) => value == null || value.length < 8
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmation,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          border: OutlineInputBorder()),
                      validator: (value) => value != _password.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(_message!,
                          style: TextStyle(
                              color: _success ? civicGreen : Colors.red)),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading || _success ? null : _register,
                      child: _loading
                          ? const CircularProgressIndicator()
                          : const Text('Create account'),
                    ),
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(_success ? 'Return to login' : 'Back to login')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

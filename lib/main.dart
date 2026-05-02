import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/app_theme_mode.dart';
import 'package:infaq/screens/home_screen.dart';
import 'package:infaq/screens/login_screen.dart';

const String _kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://omdppfnhxtzayvpxdlbm.supabase.co',
);

const String _kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_XsViN4uolUNEJWenMUS3wQ_4b9wEjOb',
);

/// How long to wait for [Supabase.initialize] before showing an error (slow DNS, VPN, or bad network).
const Duration _kSupabaseInitTimeout = Duration(seconds: 25);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _StartupShell());
}

class _StartupShell extends StatefulWidget {
  const _StartupShell();

  @override
  State<_StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<_StartupShell> {
  static const Color _primary = Color(0xFF3F5F4A);
  static const Color _surface = Color(0xFFF4F6F4);

  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      await AppThemeMode.instance.load();
      await Supabase.initialize(
        url: _kSupabaseUrl,
        anonKey: _kSupabaseAnonKey,
      ).timeout(_kSupabaseInitTimeout);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'Connection timed out while starting. Check internet, VPN, firewall, and Supabase URL.');
      return;
    } catch (e, st) {
      debugPrint('Supabase init failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e);
      return;
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: _surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Text(
                    'Could not connect',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1B1B1B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.65), height: 1.35),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _prepare,
                    style: FilledButton.styleFrom(backgroundColor: _primary),
                    child: const Text('Retry'),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: _surface,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: _primary),
                const SizedBox(height: 20),
                Text(
                  'Starting…',
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const MainApp();
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  static const Color _primary = Color(0xFF3F5F4A);
  static const Color _surface = Color(0xFFF4F6F4);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeMode.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: AppThemeMode.instance.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _primary,
              primary: _primary,
              surface: _surface,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: ColorScheme.fromSeed(
              seedColor: _primary,
              primary: _primary,
              surface: _surface,
              brightness: Brightness.light,
            ).surface,
            textTheme: const TextTheme(
              headlineSmall: TextStyle(fontWeight: FontWeight.w700),
              titleMedium: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _primary,
              primary: const Color(0xFF8BC4A0),
              secondary: const Color(0xFF6B9B7E),
              surface: const Color(0xFF1E2422),
              surfaceContainerHighest: const Color(0xFF2A302E),
              onSurface: const Color(0xFFE8ECEA),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF121816),
            textTheme: const TextTheme(
              headlineSmall: TextStyle(fontWeight: FontWeight.w700),
              titleMedium: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        supabase.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? supabase.auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        return const HomeScreen();
      },
    );
  }
}

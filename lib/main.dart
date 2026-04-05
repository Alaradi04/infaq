import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/app_theme_mode.dart';
import 'package:infaq/screens/home_screen.dart';
import 'package:infaq/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://omdppfnhxtzayvpxdlbm.supabase.co',
  );

  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_XsViN4uolUNEJWenMUS3wQ_4b9wEjOb',
  );

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  await AppThemeMode.instance.load();

  runApp(const MainApp());
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

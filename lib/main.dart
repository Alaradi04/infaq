import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:infaq/screens/home_screen.dart';
import 'package:infaq/screens/login_screen.dart';

// this is newest version
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `String.fromEnvironment('name')` reads a *compile-time* env var named `name`, not the URL/key string.
  // The previous code passed the URL as the variable name, so both resolved to '' → 404 on auth requests.
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
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF3F5F4A);
    const surface = Color(0xFFF4F6F4);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          surface: surface,
        ),
        scaffoldBackgroundColor: Colors.white,
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      home: const AuthGate(),
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

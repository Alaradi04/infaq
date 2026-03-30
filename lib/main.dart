import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        return const HomePlaceholder();
      },
    );
  }
}

class HomePlaceholder extends StatefulWidget {
  const HomePlaceholder({super.key});

  @override
  State<HomePlaceholder> createState() => _HomePlaceholderState();
}

class _HomePlaceholderState extends State<HomePlaceholder> {
  bool _loading = true;
  String? _name;
  String? _username;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrCreateProfile();
  }

  Future<void> _loadOrCreateProfile() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final profile = await supabase
          .from('users')
          .select('name,username')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null) {
        if (!mounted) return;
        setState(() {
          _name = (profile['name'] as String?)?.trim();
          _username = (profile['username'] as String?)?.trim();
          _loading = false;
        });
        return;
      }

      // Fallback: if DB trigger isn't configured yet, create the profile here.
      final meta = (user.userMetadata ?? const <String, dynamic>{});
      final rawUsername = (meta['username'] ?? '').toString().trim();
      final rawName = (meta['name'] ?? meta['full_name'] ?? '').toString().trim();
      final email = (user.email ?? '').toString().trim();

      final derivedUsername = rawUsername.isNotEmpty
          ? rawUsername
          : (email.contains('@') ? email.split('@').first : email);
      final derivedName = rawName.isNotEmpty ? rawName : email;

      // Ensure username is non-empty & unique-ish.
      final safeUsername =
          derivedUsername.isNotEmpty ? derivedUsername : 'user_${user.id.substring(0, 6)}';

      await supabase.from('users').insert(<String, Object?>{
        'id': user.id,
        'name': derivedName,
        'username': safeUsername,
      });

      final created = await supabase
          .from('users')
          .select('name,username')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _name = (created?['name'] as String?)?.trim();
        _username = (created?['username'] as String?)?.trim();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _name?.isNotEmpty == true ? _name! : 'INFAQ';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Failed to load profile: $_error'))
              : Center(
                  child: Text(
                    'Signed in${_username != null && _username!.isNotEmpty ? ' as $_username' : ''}',
                  ),
                ),
    );
  }
}

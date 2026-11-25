import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = 'https://uhoukwltqmsiichiooxo.supabase.co';
  const supabaseKey = 'sb_publishable_QdW9hoUilS5Mr75MUwvg_9xV26tMj';

  String? initError;
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );
  } catch (e) {
    initError = e.toString();
  }

  runApp(VendaFacilApp(initError: initError));
}

class VendaFacilApp extends StatelessWidget {
  final String? initError;
  const VendaFacilApp({super.key, this.initError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VendaFácil ERP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
      home: initError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Erro ao conectar no Supabase:\n$initError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            )
          : const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const HomeScreen();
        }
        return const AuthScreen();
      },
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_environment.dart';
import 'firebase_options.dart';
import 'firebase_options_prod.dart';
import 'pages/auth_gate_page.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'services/ai_service.dart';
import 'services/order_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: isProduction
        ? ProductionFirebaseOptions.currentPlatform
        : DefaultFirebaseOptions.currentPlatform,
  );
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser?.isAnonymous == true) {
    await FirebaseAuth.instance.signOut();
  }

  runApp(const AppAlmacenApp());
}

class AppAlmacenApp extends StatelessWidget {
  const AppAlmacenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: const BorderSide(color: Colors.black),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.black12),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Colors.black12),
      fontFamily: 'Roboto',
    );

    return MultiProvider(
      providers: [
        Provider<AiService>(create: (_) => AiService()),
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<FirebaseService>(create: (_) => FirebaseService()),
        ProxyProvider<FirebaseService, OrderService>(
          update: (_, firebaseService, _) => OrderService(firebaseService),
        ),
      ],
      child: MaterialApp(
        title: 'appalmacen',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: const AuthGatePage(),
      ),
    );
  }
}

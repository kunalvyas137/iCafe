import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/cart_provider.dart';
import 'providers/printer_provider.dart';
import 'screens/auth_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? firebaseInitError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    firebaseInitError = e.toString();
    debugPrint('Firebase initialization failed: $e');
  }
  runApp(ICafeApp(firebaseInitError: firebaseInitError));
}

class ICafeApp extends StatelessWidget {
  final String? firebaseInitError;

  const ICafeApp({super.key, this.firebaseInitError});

  @override
  Widget build(BuildContext context) {
    if (firebaseInitError != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Firebase initialization failed:\n$firebaseInitError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => PrinterProvider()),
      ],
      child: MaterialApp(
        title: 'iCafe POS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.amber,
          textTheme: GoogleFonts.latoTextTheme(),
          appBarTheme: const AppBarTheme(centerTitle: false),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

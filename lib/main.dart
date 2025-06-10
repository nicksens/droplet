// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart'; // Your Firebase options

// Import your screen files
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart'; // Assuming you have a splash screen

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Droplet - Water Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Poppins', // Or your desired font
      ),
      home: const SplashScreen(), // Set the AuthWrapper as the home
    );
  }
}

// This is the new "manager" widget
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // Listen to the authentication state stream
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. While waiting for connection, show a loading/splash screen
        if (snapshot.connectionState == ConnectionState.waiting) {
          // You can use your existing splash_screen.dart or a simple loading indicator
          return const SplashScreen(); // Or const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. If the snapshot has data, it means a user is logged in
        if (snapshot.hasData) {
          // Navigate to the HomeScreen
          return const HomeScreen();
        }

        // 3. If the snapshot has no data, no user is logged in
        // Navigate to the LoginScreen
        return const LoginScreen(); // Make sure you have a LoginScreen widget
      },
    );
  }
}
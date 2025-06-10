import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:droplet/firebase_options.dart'; // Import konfigurasi Firebase
import 'package:droplet/screens/splash_screen.dart'; // Import splash screen Anda

void main() async {
  // Pastikan semua binding Flutter sudah siap sebelum menjalankan kode async
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi Firebase dengan konfigurasi platform yang benar
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
        fontFamily:
            'Roboto', // Pastikan Anda sudah menambahkan font ini jika diperlukan
      ),
      // Aplikasi selalu dimulai dari SplashScreen
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

import 'dart:async';
import 'package:droplet/auth/auth_wrapper.dart';
import 'package:droplet/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    // Dapatkan instance SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    // Cek apakah 'hasSeenOnboarding' ada dan bernilai true. Default-nya false.
    final bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

    // Tunggu 3 detik agar splash screen terlihat
    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      // Navigasi berdasarkan status onboarding
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder:
              (context) =>
                  hasSeenOnboarding
                      ? const AuthWrapper() // Jika sudah lihat, langsung ke AuthWrapper
                      : const OnboardingScreen(), // Jika belum, tampilkan OnboardingScreen
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF81C7F5), Color(0xFF3C8CE7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.water_drop_rounded, size: 100, color: Colors.white),
              SizedBox(height: 20),
              Text(
                'Droplet',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

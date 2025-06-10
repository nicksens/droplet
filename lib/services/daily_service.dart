import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class DailyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Fungsi utama yang bisa memproses hari manapun
  static Future<void> _processDay(DateTime dateToProcess) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final dateString = DateFormat('yyyy-MM-dd').format(dateToProcess);
    final profileRef = _firestore.collection('users').doc(user.uid);
    final dayProgressRef = profileRef
        .collection('dailyProgress')
        .doc(dateString);

    try {
      final profileDoc = await profileRef.get();
      final dayProgressDoc = await dayProgressRef.get();

      // Keluar jika tidak ada data progres untuk hari yang akan diproses
      if (!dayProgressDoc.exists) {
        debugPrint(
          'Tidak ada progres untuk diproses pada tanggal $dateString.',
        );
        // Jika tidak ada progres, streak harus direset jika hari itu bukan hari ini
        if (dateString != DateFormat('yyyy-MM-dd').format(DateTime.now())) {
          await profileRef.update({'currentStreak': 0});
        }
        return;
      }

      final progressData = dayProgressDoc.data()!;
      // Keluar jika hari ini sudah pernah diproses sebelumnya
      if (progressData['processed'] == true) {
        debugPrint('Progres untuk $dateString sudah diproses sebelumnya.');
        return;
      }

      final profileData = profileDoc.data() as Map<String, dynamic>?;
      final dailyGoal = profileData?['dailyGoal'] ?? 8;
      int currentStreak = profileData?['currentStreak'] ?? 0;

      final waterIntake = progressData['waterIntake'] ?? 0;
      final targetAchieved = waterIntake >= dailyGoal;

      if (targetAchieved) {
        // Target tercapai: Tambah streak & panen tanaman
        currentStreak++;
        debugPrint(
          'Target tercapai pada $dateString. Streak baru: $currentStreak',
        );
        await _savePlantToGarden(
          userId: user.uid,
          plantLevel: progressData['plantLevel'] ?? 0,
          waterIntake: waterIntake,
          targetAchieved: dailyGoal,
          streakWhenCompleted: currentStreak,
          completedDate: dateToProcess,
        );
      } else {
        // Target tidak tercapai: Reset streak
        currentStreak = 0;
        debugPrint('Target tidak tercapai pada $dateString. Streak direset.');
      }

      // Update profil dengan streak baru
      await profileRef.update({'currentStreak': currentStreak});
      // Tandai hari ini sebagai sudah diproses
      await dayProgressRef.update({'processed': true});
    } catch (e) {
      debugPrint('Error in _processDay for $dateString: $e');
    }
  }

  // Fungsi yang dipanggil saat app dibuka, hanya proses HARI KEMARIN
  static Future<void> checkEndOfDay() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await _processDay(yesterday);
  }

  // Fungsi yang dipanggil oleh tombol DEBUG, hanya proses HARI INI
  static Future<void> triggerEndOfDayForToday() async {
    await _processDay(DateTime.now());
  }

  // Fungsi untuk menyimpan tanaman ke taman (tidak berubah)
  static Future<void> _savePlantToGarden({
    required String userId,
    required int plantLevel,
    required int waterIntake,
    required int targetAchieved,
    required int streakWhenCompleted,
    required DateTime completedDate,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('myGarden')
          .add({
            'plantLevel': plantLevel,
            'waterIntake': waterIntake,
            'targetAchieved': targetAchieved,
            'streakWhenCompleted': streakWhenCompleted,
            'completedDate': Timestamp.fromDate(completedDate),
          });
    } catch (e) {
      debugPrint('Error saving plant to garden: $e');
    }
  }

  // Fungsi untuk mendapatkan streak saat ini (tidak berubah)
  static Future<int> getCurrentStreak() async {
    final user = _auth.currentUser;
    if (user == null) return 0;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      return userDoc.data()?['currentStreak'] ?? 0;
    } catch (e) {
      debugPrint('Error getting current streak: $e');
      return 0;
    }
  }

  // Logika untuk hari yang terlewat (tidak berubah)
  static Future<void> processMissedDays() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final lastUpdate = userData?['lastStreakUpdate'] as String?;

      if (lastUpdate != null) {
        final lastUpdateDate = DateFormat('yyyy-MM-dd').parse(lastUpdate);
        final today = DateTime.now();
        final daysDifference = today.difference(lastUpdateDate).inDays;

        // If more than 1 day has passed, we might have missed some days
        if (daysDifference > 1) {
          // Process each missed day
          for (int i = 1; i < daysDifference; i++) {
            final missedDate = lastUpdateDate.add(Duration(days: i));
            final missedDateString = DateFormat(
              'yyyy-MM-dd',
            ).format(missedDate);

            final missedDoc =
                await _firestore
                    .collection('users')
                    .doc(user.uid)
                    .collection('dailyProgress')
                    .doc(missedDateString)
                    .get();

            // If no progress recorded for missed day, reset streak
            if (!missedDoc.exists) {
              await _firestore.collection('users').doc(user.uid).update({
                'currentStreak': 0,
                'lastStreakUpdate': missedDateString,
              });
              break; // Stop processing further days
            }
          }
        }
      }
    } catch (e) {
      print('Error processing missed days: $e');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/daily_service.dart';
import 'my_garden_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final List<String> plantEmojis = ['🌱', '🌿', '🌳', '🌲'];
  int currentStreak = 0;
  bool targetAchievedToday = false;
  late AnimationController _celebrationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.elasticOut),
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.1).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DailyService.checkEndOfDay();
    });
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  Future<void> _initializeDay() async {
    // Check for end of day processing and missed days
    await DailyService.processMissedDays();
    await DailyService.checkEndOfDay();

    // Get current streak
    final streak = await DailyService.getCurrentStreak();

    // Check if target was already achieved today
    final achieved = await _checkIfTargetAchievedToday();

    setState(() {
      currentStreak = streak;
      targetAchievedToday = achieved;
    });
  }

  Future<bool> _checkIfTargetAchievedToday() async {
    final user = FirebaseAuth.instance.currentUser!;
    final todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // Get user's daily goal
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final dailyGoal = userData?['dailyGoal'] ?? 8;

      // Get today's progress
      final todayDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('dailyProgress')
              .doc(todayDate)
              .get();

      if (todayDoc.exists) {
        final todayData = todayDoc.data() as Map<String, dynamic>;
        final waterIntake = todayData['waterIntake'] ?? 0;
        return waterIntake >= dailyGoal;
      }

      return false;
    } catch (e) {
      print('Error checking target achievement: $e');
      return false;
    }
  }

  Future<DocumentSnapshot> _getUserProfile() {
    final user = FirebaseAuth.instance.currentUser!;
    return FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  }

  Future<void> _showUpdateGoalDialog(int currentGoal) async {
    final goalController = TextEditingController(text: currentGoal.toString());
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Ubah Target Minum Harian',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: goalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Jumlah Gelas',
                prefixIcon: Icon(Icons.local_drink),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3C8CE7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Simpan'),
              onPressed: () {
                final user = FirebaseAuth.instance.currentUser!;
                final newGoal =
                    int.tryParse(goalController.text) ?? currentGoal;
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .set({'dailyGoal': newGoal}, SetOptions(merge: true));
                Navigator.of(context).pop();
                setState(() {});
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> addWater(int dailyGoal) async {
    final user = FirebaseAuth.instance.currentUser!;
    final String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('dailyProgress')
        .doc(todayDate);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      int newIntake = snapshot.exists ? snapshot.data()!['waterIntake'] + 1 : 1;

      double progress = newIntake / dailyGoal;
      int newPlantLevel = 0;
      if (progress >= 1.0) {
        newPlantLevel = 3;
      } else if (progress >= 0.75) {
        newPlantLevel = 2;
      } else if (progress >= 0.4) {
        newPlantLevel = 1;
      }

      transaction.set(docRef, {
        'waterIntake': newIntake,
        'plantLevel': newPlantLevel,
        'date': todayDate,
        'processed': false,
      }, SetOptions(merge: true));

      // Check if target just achieved
      if (newIntake >= dailyGoal && !targetAchievedToday) {
        // Target just achieved! Process immediately
        await _processTargetAchievement(newIntake, newPlantLevel, dailyGoal);
      }
    });

    setState(() {});
  }

  Future<void> _processTargetAchievement(
    int waterIntake,
    int plantLevel,
    int dailyGoal,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final today = DateTime.now();

      // Get current streak
      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final oldStreak = userData?['currentStreak'] ?? 0;
      final newStreak = oldStreak + 1;

      // Save plant to garden immediately
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('myGarden')
          .add({
            'plantLevel': plantLevel,
            'waterIntake': waterIntake,
            'targetAchieved': dailyGoal,
            'streakWhenCompleted': newStreak,
            'completedDate': Timestamp.fromDate(today),
            'createdAt': FieldValue.serverTimestamp(),
          });

      // Update streak immediately
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'currentStreak': newStreak,
            'lastStreakUpdate': DateFormat('yyyy-MM-dd').format(today),
          });

      // Update local state
      setState(() {
        currentStreak = newStreak;
        targetAchievedToday = true;
      });

      // Show celebration
      _showCelebration(plantLevel, newStreak);
    } catch (e) {
      print('Error processing target achievement: $e');
    }
  }

  void _showCelebration(int plantLevel, int newStreak) {
    final plantNames = ['Benih', 'Tunas', 'Pohon Muda', 'Pohon Dewasa'];

    _celebrationController.forward();

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (BuildContext context) {
        return AnimatedBuilder(
          animation: _celebrationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Transform.rotate(
                angle: _rotationAnimation.value,
                child: Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF4CAF50),
                          Color(0xFF81C784),
                          Color(0xFFA5D6A7),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header with confetti effect
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(30),
                              topRight: Radius.circular(30),
                            ),
                            gradient: LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA726)],
                            ),
                          ),
                          child: Column(
                            children: [
                              // Animated confetti emojis
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildFloatingEmoji('🎉', 0.5),
                                  _buildFloatingEmoji('✨', 1.0),
                                  _buildFloatingEmoji('🎊', 0.7),
                                  _buildFloatingEmoji('🌟', 1.2),
                                  _buildFloatingEmoji('🎉', 0.8),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'SELAMAT!',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(2, 2),
                                      blurRadius: 4,
                                      color: Colors.black26,
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        // Main content
                        Container(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              // Plant with glow effect
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.3),
                                      Colors.transparent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.5),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    plantEmojis[plantLevel],
                                    style: const TextStyle(fontSize: 80),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Achievement text
                              Text(
                                'Target Harian Tercapai!',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      offset: const Offset(1, 1),
                                      blurRadius: 2,
                                      color: Colors.black.withOpacity(0.3),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),

                              Text(
                                '${plantNames[plantLevel]} telah ditambahkan\nke taman Anda!',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),

                              // Streak display with fire animation
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(25),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Animated fire emoji
                                    AnimatedBuilder(
                                      animation: _celebrationController,
                                      builder: (context, child) {
                                        return Transform.scale(
                                          scale:
                                              1.0 +
                                              (0.2 * _scaleAnimation.value),
                                          child: const Text(
                                            '🔥',
                                            style: TextStyle(fontSize: 28),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'STREAK BARU!',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        Text(
                                          '$newStreak Hari Berturut-turut',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Motivational message
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Text(
                                  _getMotivationalMessage(newStreak),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontStyle: FontStyle.italic,
                                    height: 1.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Action buttons
                        Container(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(25),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: TextButton(
                                    onPressed: () {
                                      _celebrationController.reset();
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text(
                                      'Lanjutkan',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 50,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Colors.white, Colors.white],
                                    ),
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                    ),
                                    onPressed: () {
                                      _celebrationController.reset();
                                      Navigator.of(context).pop();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  const MyGardenScreen(),
                                        ),
                                      );
                                    },
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.park,
                                          color: Color(0xFF4CAF50),
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Lihat Taman',
                                          style: TextStyle(
                                            color: Color(0xFF4CAF50),
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingEmoji(String emoji, double delay) {
    return AnimatedBuilder(
      animation: _celebrationController,
      builder: (context, child) {
        final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _celebrationController,
            curve: Interval(delay * 0.2, 1.0, curve: Curves.bounceOut),
          ),
        );
        return Transform.translate(
          offset: Offset(0, -20 * animation.value),
          child: Transform.rotate(
            angle: 0.5 * animation.value,
            child: Opacity(
              opacity: animation.value,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
        );
      },
    );
  }

  String _getMotivationalMessage(int streak) {
    if (streak >= 30) return "Luar biasa! Anda adalah master hidrasi! 🏆";
    if (streak >= 21)
      return "Kebiasaan sehat sudah terbentuk! Terus pertahankan! 💪";
    if (streak >= 14) return "Dua minggu berturut-turut! Anda hebat! 🌟";
    if (streak >= 7)
      return "Seminggu penuh! Tubuh Anda pasti berterima kasih! 🙏";
    if (streak >= 3) return "Konsistensi adalah kunci! Terus semangat! 🚀";
    return "Awal yang bagus! Mari bangun kebiasaan sehat! 💚";
  }

  // Manual trigger for end of day (for testing)
  Future<void> _triggerEndOfDay() async {
    // GANTI PANGGILAN DI SINI
    await DailyService.triggerEndOfDayForToday();

    // Ambil ulang streak terbaru untuk update UI
    final streak = await DailyService.getCurrentStreak();
    if (mounted) {
      setState(() {
        currentStreak = streak;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Proses untuk HARI INI telah dijalankan!'),
          backgroundColor: Colors.green.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      return const Scaffold(
        body: Center(child: Text("Sesi berakhir, silakan login kembali.")),
      );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF81C7F5), Color(0xFF3C8CE7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          // --- FIX BUG #1: Ganti FutureBuilder menjadi StreamBuilder ---
          child: StreamBuilder<DocumentSnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
            builder: (context, userProfileSnapshot) {
              if (!userProfileSnapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final userData =
                  userProfileSnapshot.data!.data() as Map<String, dynamic>?;
              final int dailyGoal = userData?['dailyGoal'] ?? 8;
              final int currentStreak = userData?['currentStreak'] ?? 0;

              return Column(
                children: [
                  _buildAppBar(
                    context,
                    currentStreak,
                  ), // Pass streak yang sudah live
                  Expanded(child: _buildMainContent(dailyGoal)),
                  _buildWeeklyStreak(dailyGoal),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, int currentStreak) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const MyGardenScreen(),
                  ),
                ),
            child: Row(
              children: const [
                Icon(Icons.park, color: Colors.white, size: 28),
                SizedBox(width: 8),
                Text(
                  'Taman Saya',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 4),
                    Text(
                      '$currentStreak',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  tooltip: 'Logout',
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(int dailyGoal) {
    final user = FirebaseAuth.instance.currentUser!;
    final String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('dailyProgress')
              .doc(todayDate)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        int waterIntake = 0;
        int plantLevel = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          var data = snapshot.data!.data() as Map<String, dynamic>;
          waterIntake = data['waterIntake'] ?? 0;
          plantLevel = data['plantLevel'] ?? 0;
        }

        double progress = (waterIntake / dailyGoal).clamp(0.0, 1.0);
        bool isTargetMet = waterIntake >= dailyGoal;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Progress indicator
              Container(
                width: double.infinity,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isTargetMet ? Colors.green : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Water intake display
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$waterIntake',
                    style: TextStyle(
                      color: isTargetMet ? Colors.green.shade100 : Colors.white,
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    ' / $dailyGoal Gelas',
                    style: TextStyle(
                      color:
                          isTargetMet ? Colors.green.shade200 : Colors.white70,
                      fontSize: 20,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => _showUpdateGoalDialog(dailyGoal),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Plant visualization
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color:
                      isTargetMet
                          ? Colors.green.withOpacity(0.2)
                          : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(60),
                  border:
                      isTargetMet
                          ? Border.all(color: Colors.green.shade300, width: 2)
                          : null,
                ),
                child: Center(
                  child: Text(
                    plantEmojis[plantLevel],
                    style: const TextStyle(fontSize: 64),
                    key: ValueKey(plantLevel),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Progress message
              Text(
                _getProgressMessage(progress, isTargetMet),
                style: TextStyle(
                  color: isTargetMet ? Colors.green.shade100 : Colors.white70,
                  fontSize: 16,
                  fontWeight: isTargetMet ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Add water button
              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: isTargetMet ? Colors.green : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => addWater(dailyGoal),
                  icon: Icon(isTargetMet ? Icons.check : Icons.add, size: 24),
                  label: Text(
                    isTargetMet ? 'Target Tercapai!' : 'Tambah 1 Gelas',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor:
                        isTargetMet ? Colors.white : const Color(0xFF3C8CE7),
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Debug button for testing end of day (remove in production)
              TextButton(
                onPressed: _triggerEndOfDay,
                child: const Text(
                  'Simulasi Akhir Hari (Debug)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getProgressMessage(double progress, bool isTargetMet) {
    if (isTargetMet) return "🎉 Target tercapai! Tanaman sudah masuk taman!";
    if (progress >= 0.75) return "💪 Hampir selesai! Terus semangat!";
    if (progress >= 0.4) return "🌱 Bagus! Terus lanjutkan!";
    return "💧 Ayo mulai minum air hari ini!";
  }

  Widget _buildWeeklyStreak(int dailyGoal) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          const Text(
            'Progress Mingguan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<int, bool?>>(
            future: _getWeeklyProgress(dailyGoal),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(height: 50);
              }

              final weeklyProgress = snapshot.data!;
              final days = ['S', 'S', 'R', 'K', 'J', 'S', 'M'];

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (index) {
                  final isTargetMet = weeklyProgress[index + 1];
                  return Column(
                    children: [
                      Text(
                        days[index],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              isTargetMet == null
                                  ? Colors.white.withOpacity(0.2)
                                  : isTargetMet
                                  ? Colors.orange
                                  : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child:
                              isTargetMet == null
                                  ? const Icon(
                                    Icons.circle,
                                    color: Colors.white24,
                                    size: 16,
                                  )
                                  : isTargetMet
                                  ? const Text(
                                    '🔥',
                                    style: TextStyle(fontSize: 16),
                                  )
                                  : const Icon(
                                    Icons.water_drop,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                        ),
                      ),
                    ],
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<Map<int, bool?>> _getWeeklyProgress(int dailyGoal) async {
    final user = FirebaseAuth.instance.currentUser!;
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    Map<int, bool?> progressMap = {};

    for (int i = 0; i < 7; i++) {
      final day = startOfWeek.add(Duration(days: i));
      if (day.isAfter(today)) {
        progressMap[day.weekday] = null;
        continue;
      }

      final dateString = DateFormat('yyyy-MM-dd').format(day);
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('dailyProgress')
              .doc(dateString)
              .get();

      if (doc.exists) {
        final intake = doc.data()!['waterIntake'] ?? 0;
        progressMap[day.weekday] = intake >= dailyGoal;
      } else {
        progressMap[day.weekday] = false;
      }
    }
    return progressMap;
  }
}

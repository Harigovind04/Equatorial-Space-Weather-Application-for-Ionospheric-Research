import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import 'main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      checkUserLoggedIn();
    });
  }

  void checkUserLoggedIn() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        String userName = userDoc['name'] ?? 'User'; // Use 'User' if the name is null

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomePage(userName: userName)),
        );
      } catch (error) {
        log("Error fetching user data: $error");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const Login1()),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const Login1()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFAAA8A5),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Image.asset("assets/splash_logo.png", width: 200), // Adjust size
          ),
          const SizedBox(height: 20),
          const SpinKitFadingCircle(
            color: Colors.white, // Adjust color as needed
            size: 50.0,
          ),
        ],
      ),
    );
  }
}

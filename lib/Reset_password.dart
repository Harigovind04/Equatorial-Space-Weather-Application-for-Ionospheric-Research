import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login.dart'; // Import your Login screen

class Reset extends StatefulWidget {
  const Reset({super.key});

  @override
  State<Reset> createState() => _ResetState();
}

class _ResetState extends State<Reset> {
  final emailController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> passwordReset() async {
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: emailController.text);

      // Show success dialog and navigate to login after a delay
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: const Text('Password Reset Link Sent! Check your email'),
            actions: [
              TextButton(
                onPressed: () {
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const Login1()),
                    );
                  }
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } on FirebaseAuthException catch (e) {
      // Show error dialog with specific message based on error code
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            content: Text(handleFirebaseAuthError(e)), // Define a function to handle specific errors
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAF8),
      appBar: AppBar(
        backgroundColor: Colors.blue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white), // Set the color to white
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const Login1()),
            );
          },
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
            child: Text(
              'Reset Password',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 5.0, horizontal: 20.0),
            child: Text(
              'Email',
              style: TextStyle(
                fontSize: 18.0,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding:
            const EdgeInsets.symmetric(vertical: 0.0, horizontal: 10.0),
            child: TextField(
              controller: emailController,
              style: const TextStyle(fontFamily: 'Poppins'),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                hintText: 'Enter email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20.0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: ElevatedButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all<Color>(Colors.blue), // Set to blue
                shape: WidgetStateProperty.all<OutlinedBorder>(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                ),
                animationDuration: const Duration(milliseconds: 300),
                elevation: WidgetStateProperty.resolveWith<double>(
                      (Set<WidgetState> states) {
                    if (states.contains(WidgetState.pressed)) {
                      return 10.0; // Increase the elevation when pressed
                    }
                    return 0.0; // Normal elevation
                  },
                ),
              ),

              onPressed: passwordReset,
              child: const Text(
                "Reset Password",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
String handleFirebaseAuthError(FirebaseAuthException e) {
  switch (e.code) {
    case 'user-not-found':
      return 'The email address you entered does not belong to an existing account.';
    case 'invalid-email':
      return 'The email address you entered is invalid.';
    case 'weak-password':
      return 'Reset password is not supported for this type of account.'; // Consider a more informative message
    default:
      return 'An error occurred while resetting your password. Please try again later.';
  }
}

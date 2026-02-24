import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';

class Registration extends StatelessWidget {
  const Registration({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Organization Registration',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const OrganizationRegistrationScreen(),
    );
  }
}

class OrganizationRegistrationScreen extends StatefulWidget {
  const OrganizationRegistrationScreen({super.key});

  @override
  _OrganizationRegistrationScreenState createState() =>
      _OrganizationRegistrationScreenState();
}

class _OrganizationRegistrationScreenState
    extends State<OrganizationRegistrationScreen> {
  final _orgNameController = TextEditingController();
  final _orgAddressController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool isPasswordVisible = false;
  bool isConfirmPasswordVisible = false;
  String? emailErrorText;
  String? passwordErrorText;
  String? confirmPasswordErrorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _orgNameController.dispose();
    _orgAddressController.dispose();
    _contactNumberController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> addUserDetails(User user) async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      "name": _orgNameController.text,
      "email": _emailController.text,
      "address": _orgAddressController.text,
      "contact": _contactNumberController.text,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Organization Registration',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        centerTitle: true,
      ),
      body: Container(
        color: Colors.grey[200],
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Card(
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.business,
                      size: 80,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 16.0),
                    Text(
                      'Register Your Organization',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    _buildTextField(
                      controller: _orgNameController,
                      label: 'Organization Name',
                      icon: Icons.business,
                    ),
                    const SizedBox(height: 12.0),
                    _buildTextField(
                      controller: _orgAddressController,
                      label: 'Organization Address',
                      icon: Icons.location_on,
                    ),
                    const SizedBox(height: 12.0),
                    _buildTextField(
                      controller: _contactNumberController,
                      label: 'Contact Number',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12.0),
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      errorText: emailErrorText,
                    ),
                    const SizedBox(height: 12.0),
                    _buildTextField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock,
                      obscureText: !isPasswordVisible,
                      errorText: passwordErrorText,
                      suffixIcon: IconButton(
                        icon: Icon(
                          isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            isPasswordVisible = !isPasswordVisible;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    _buildTextField(
                      controller: _confirmPasswordController,
                      label: 'Confirm Password',
                      icon: Icons.lock,
                      obscureText: !isConfirmPasswordVisible,
                      errorText: confirmPasswordErrorText,
                      suffixIcon: IconButton(
                        icon: Icon(
                          isConfirmPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            isConfirmPasswordVisible = !isConfirmPasswordVisible;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Center(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue, // Button color
                          ),
                          onPressed: () async {
                            setState(() {
                              emailErrorText = null;
                              passwordErrorText = null;
                              confirmPasswordErrorText = null;
                            });

                            if (_passwordController.text !=
                                _confirmPasswordController.text) {
                              setState(() {
                                confirmPasswordErrorText =
                                'Passwords do not match';
                              });
                              return;
                            }

                            try {
                              UserCredential userCredential = await FirebaseAuth.instance
                                  .createUserWithEmailAndPassword(
                                email: _emailController.text,
                                password: _passwordController.text,
                              );
                              //print('User signed up: ${userCredential.user!.email}');
                              await addUserDetails(userCredential.user!);
                              if (context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => const Login1()),
                                );
                              }
                            } catch (e) {
                              //print('Error signing up: $e');
                              if (e is FirebaseAuthException) {
                                if (e.code == 'email-already-in-use') {
                                  setState(() {
                                    emailErrorText = 'Email is already in use';
                                  });
                                } else if (e.code ==
                                    'invalid-email') {
                                  setState(() {
                                    emailErrorText =
                                    'Email is badly formatted';
                                  });
                                } else if (e.code == 'weak-password') {
                                  setState(() {
                                    passwordErrorText = 'Password is too weak';
                                  });
                                } else {
                                  setState(() {
                                    emailErrorText =
                                    'An error occurred. Please try again later';
                                  });
                                }
                              }
                            }
                          },
                          child: const Text(
                            'Register',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              fontFamily: 'Poppins',
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const Login1()),
                        );
                      },
                      child: const Text(
                        'Already a user? Login',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blue),
        labelText: label,
        errorText: errorText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.blue, width: 2.0),
          borderRadius: BorderRadius.circular(8.0),
        ),
        suffixIcon: suffixIcon,
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
    );
  }
}

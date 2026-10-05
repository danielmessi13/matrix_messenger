import 'package:flutter/material.dart';

class RestoringScreen extends StatelessWidget {
  const RestoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

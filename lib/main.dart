import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/role_selection_screen.dart';

void main() {
  runApp(const InfinityWashApp());
}

class InfinityWashApp extends StatelessWidget {
  const InfinityWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinity Wash',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const RoleSelectionScreen(),
    );
  }
}


//hello
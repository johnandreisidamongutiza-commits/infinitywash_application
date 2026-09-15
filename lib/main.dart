import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/role_selection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
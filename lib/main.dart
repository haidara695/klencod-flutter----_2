import 'package:flutter/material.dart';

import 'screens/school_bell_app.dart';
import 'theme/app_theme.dart';

void main() => runApp(const SchoolBellApp());

class SchoolBellApp extends StatelessWidget {
  const SchoolBellApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'جرس المدرسة',
        theme: buildBellTheme(),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const SchoolBellShell(),
      );
}
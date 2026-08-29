import 'package:flutter/material.dart';

class MurmurApp extends StatelessWidget {
  const MurmurApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Murmur',
      home: Scaffold(body: Center(child: Text('Murmur'))),
    );
  }
}

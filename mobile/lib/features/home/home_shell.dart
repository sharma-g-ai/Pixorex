import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

/// Signed-in frame: Home and Profile tabs (design 13-15). My Scans and Queue join the bar
/// when those screens are built.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  /// Set after a unit switch: Home then says which unit new scans go to (design 25).
  String? _switchedTo;

  void _onSwitched(String unitName) => setState(() {
        _switchedTo = unitName;
        _tab = 0;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(switchedTo: _switchedTo),
          ProfileScreen(onSwitched: _onSwitched),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: Brand.info,
        height: 64,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Brand.navy),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Brand.navy),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'pos_screen.dart';
import 'inventory_screen.dart';
import 'orders_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../models/user.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  UserRole? _userRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        setState(() {
          _userRole = doc.data()?['role'] == 'admin'
              ? UserRole.admin
              : UserRole.staff;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isAdmin = _userRole == UserRole.admin;

    final destinations = [
      const NavigationRailDestination(
        icon: Icon(Icons.point_of_sale_outlined),
        selectedIcon: Icon(Icons.point_of_sale),
        label: Text('POS'),
      ),
      if (isAdmin)
        const NavigationRailDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: Text('Inventory'),
        ),
      const NavigationRailDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: Text('Orders'),
      ),
      if (isAdmin)
        const NavigationRailDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: Text('Reports'),
        ),
      if (isAdmin)
        const NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('iCafe POS'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Sidebar for Navigation
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main Content Area
          Expanded(child: _buildMainContent(isAdmin)),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isAdmin) {
    // Determine screen based on visible destinations
    // POS (0), [Inventory], Orders, [Reports], [Settings]
    if (isAdmin) {
      switch (_selectedIndex) {
        case 0:
          return const PosScreen();
        case 1:
          return const InventoryScreen();
        case 2:
          return const OrdersScreen(canCancel: true);
        case 3:
          return const ReportsScreen();
        case 4:
          return const SettingsScreen();
        default:
          return const Center(child: Text('Unknown Screen'));
      }
    } else {
      switch (_selectedIndex) {
        case 0:
          return const PosScreen();
        case 1:
          return const OrdersScreen();
        default:
          return const Center(child: Text('Unknown Screen'));
      }
    }
  }
}

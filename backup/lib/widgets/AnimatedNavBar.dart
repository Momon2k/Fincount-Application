import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AnimatedNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const AnimatedNavBar({
    Key? key,
    required this.selectedIndex,
    required this.onItemTapped,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onItemTapped,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1976D2),
        unselectedItemColor: Colors.grey[400],
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        items: List.generate(
          4,
          (index) => _buildNavItem(index),
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(int index) {
    final List<IconData> icons = [
      Icons.dashboard,
      Icons.inventory_2,
      Icons.history,
      Icons.person,
    ];

    final List<String> labels = [
      'Dashboard',
      'Batches',
      'History',
      'User',
    ];

    return BottomNavigationBarItem(
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(selectedIndex == index ? 12 : 8),
        decoration: BoxDecoration(
          color: selectedIndex == index
              ? const Color(0xFF1976D2).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icons[index],
          size: selectedIndex == index ? 24 : 22,
        ),
      ),
      label: labels[index],
    );
  }
} 
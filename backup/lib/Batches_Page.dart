import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'Dashboard_Page.dart';
import 'History_Page.dart';
import 'User_Page.dart';
import 'Session_Page.dart';
import 'constants/theme_constants.dart';
import 'widgets/AnimatedNavBar.dart';
import 'models/session_model.dart';

class BatchesPage extends StatefulWidget {
  const BatchesPage({super.key});

  @override
  State<BatchesPage> createState() => _BatchesPageState();
}

class _BatchesPageState extends State<BatchesPage> {
  int _selectedIndex = 1;
  int totalFingerlings = 0;
  int activeBatches = 0;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  void _loadStatistics() {
    final sessionsBox = Hive.box<SessionModel>('sessions');
    final sessions = sessionsBox.values.toList();
    
    setState(() {
      // Calculate total fingerlings
      totalFingerlings = sessions.fold(0, (sum, session) => sum + session.count);
      
      // Get unique batches
      final uniqueBatches = sessions.map((session) => session.batchId).toSet();
      activeBatches = uniqueBatches.length;
    });
  }

  void _onItemTapped(int index) {
    if (index != _selectedIndex) {
      if (index == 0) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const DashboardPage(initialIndex: 0),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      } else if (index == 2) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const HistoryPage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      } else if (index == 3) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const ProfilePage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: ValueListenableBuilder<Box<SessionModel>>(
        valueListenable: Hive.box<SessionModel>('sessions').listenable(),
        builder: (context, box, _) {
          final sessions = box.values.toList();
          
          // Update statistics
          totalFingerlings = sessions.fold(0, (sum, session) => sum + session.count);
          final uniqueBatches = sessions.map((session) => session.batchId).toSet();
          activeBatches = uniqueBatches.length;

          return Column(
            children: [
              // Blue Header Section
              Container(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.paddingLarge,
                  AppTheme.paddingXLarge * 2,
                  AppTheme.paddingLarge,
                  AppTheme.paddingXLarge
                ),
                decoration: AppTheme.headerDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Batches",
                      style: AppTheme.headerLarge,
                    ),
                    SizedBox(height: AppTheme.paddingSmall),
                    Text(
                      "Manage and track your fingerling batches",
                      style: AppTheme.subtitle,
                    ),
                    SizedBox(height: AppTheme.paddingLarge),

                    // Count Fingerlings Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SessionPage()),
                          );
                        },
                        style: AppTheme.secondaryButtonStyle,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow, size: 20, color: AppTheme.primaryColor),
                            SizedBox(width: AppTheme.paddingSmall),
                            Text(
                              "Count Fingerlings",
                              style: AppTheme.buttonText.copyWith(color: AppTheme.primaryColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content Section
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(AppTheme.paddingLarge),
                  child: Column(
                    children: [
                      _buildStatCard(
                        title: "Active Batches",
                        value: activeBatches.toString(),
                        subtitle: "Current active batches",
                        icon: Icons.layers_outlined,
                      ),
                      SizedBox(height: AppTheme.paddingMedium),

                      _buildStatCard(
                        title: "Total Fingerlings",
                        value: totalFingerlings.toString(),
                        subtitle: "Total fingerlings you've counted",
                        icon: Icons.calculate_outlined,
                      ),
                      SizedBox(height: AppTheme.paddingMedium),

                      if (sessions.isNotEmpty) ...[
                        _buildBatchesList(sessions),
                      ] else ...[
                        _buildEmptyState(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: AnimatedNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildBatchesList(List<SessionModel> sessions) {
    // Group sessions by batchId
    final batchGroups = <String, List<SessionModel>>{};
    for (var session in sessions) {
      if (!batchGroups.containsKey(session.batchId)) {
        batchGroups[session.batchId] = [];
      }
      batchGroups[session.batchId]!.add(session);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.paddingLarge),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Recent Batches",
            style: AppTheme.headerSmall,
          ),
          SizedBox(height: AppTheme.paddingMedium),
          ...batchGroups.entries.take(5).map((entry) {
            final totalCount = entry.value.fold(0, (sum, session) => sum + session.count);
            final lastSession = entry.value.last;
            
            return Container(
              margin: EdgeInsets.only(bottom: AppTheme.paddingMedium),
              padding: EdgeInsets.all(AppTheme.paddingMedium),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(AppTheme.paddingSmall),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.set_meal,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: AppTheme.paddingMedium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: AppTheme.bodyLarge,
                        ),
                        Text(
                          lastSession.species,
                          style: AppTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.paddingMedium,
                      vertical: AppTheme.paddingSmall,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "$totalCount fish",
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.paddingLarge),
      decoration: AppTheme.cardDecoration,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          SizedBox(height: AppTheme.paddingMedium),
          Text(
            "No batches yet",
            style: AppTheme.bodyLarge.copyWith(
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: AppTheme.paddingSmall),
          Text(
            "Start counting to create batches",
            style: AppTheme.bodySmall.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.paddingLarge),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.bodyLarge,
                ),
                SizedBox(height: AppTheme.paddingSmall),
                Text(
                  value,
                  style: AppTheme.headerMedium,
                ),
                SizedBox(height: AppTheme.paddingSmall / 2),
                Text(
                  subtitle,
                  style: AppTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(AppTheme.paddingMedium),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: AppTheme.primaryColor,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}
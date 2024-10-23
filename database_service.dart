import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final CollectionReference userCollection =
      FirebaseFirestore.instance.collection('user_attendance');

  // User registration with embeddings
  Future<void> registerUser({
    required String employeeId,
    required String name,
    required List<List<double>> faceEmbeddings,
  }) async {
    try {
      // Check if employee ID already exists
      DocumentSnapshot existingUser =
          await userCollection.doc(employeeId).get();
      if (existingUser.exists) {
        throw Exception('Employee ID already registered');
      }

      // Convert nested List<List<double>> to List<Map<String, dynamic>>
      List<Map<String, dynamic>> convertedEmbeddings = faceEmbeddings
          .map((embedding) => {
                'values':
                    embedding, // Convert inner List<double> to a single array
              })
          .toList();

      // Create registration data
      final registrationData = {
        'name': name,
        'employeeId': employeeId,
        'embeddings': convertedEmbeddings, // Store as array of maps
        'registrationDate': FieldValue.serverTimestamp(),
        'attendance': false,
        'lastSuccessfulMatch': 0.0,
        'failedAttempts': 0,
        'registrationImages': faceEmbeddings.length,
        'active': true,
        'lastUpdated': FieldValue.serverTimestamp(),
        'punchInTime': null,
        'punchOutTime': null,
        'attendanceHistory': [],
      };

      await userCollection.doc(employeeId).set(registrationData);
      print('User registered successfully: $employeeId');

      // Add first attendance history entry
      await addAttendanceHistoryEntry(employeeId, 'Registration completed');
    } catch (e) {
      print('Error registering user: $e');
      rethrow;
    }
  }

  // Get all active users
  Future<QuerySnapshot> getAllUsers() async {
    try {
      return await userCollection.where('active', isEqualTo: true).get();
    } catch (e) {
      print('Error getting all users: $e');
      rethrow;
    }
  }

  // Update attendance with timestamp and match confidence
  Future<void> updateAttendance({
    required String employeeId,
    required bool isCheckIn,
    double? matchConfidence,
  }) async {
    try {
      final userDoc = await userCollection.doc(employeeId).get();
      if (!userDoc.exists) {
        throw Exception('User not found');
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final currentTime = FieldValue.serverTimestamp();

      Map<String, dynamic> updateData = {
        'attendance': isCheckIn,
        'lastUpdated': currentTime,
      };

      if (isCheckIn) {
        updateData['punchInTime'] = currentTime;
        updateData['punchOutTime'] = null;
      } else {
        updateData['punchOutTime'] = currentTime;

        // Calculate duration if punch in time exists
        if (userData['punchInTime'] != null) {
          final punchInTime = (userData['punchInTime'] as Timestamp).toDate();
          final duration = DateTime.now().difference(punchInTime);

          await addAttendanceHistoryEntry(
            employeeId,
            'Worked for ${duration.inHours} hours ${duration.inMinutes % 60} minutes',
          );
        }
      }

      if (matchConfidence != null) {
        updateData['lastSuccessfulMatch'] = matchConfidence;
      }

      await userCollection.doc(employeeId).update(updateData);

      // Log the attendance event
      await addAttendanceHistoryEntry(
        employeeId,
        isCheckIn ? 'Checked In' : 'Checked Out',
        matchConfidence: matchConfidence,
      );

      print(
          'Attendance updated for user: $employeeId (${isCheckIn ? 'Check-In' : 'Check-Out'})');
    } catch (e) {
      print('Error updating attendance: $e');
      rethrow;
    }
  }

  // Add entry to attendance history
  Future<void> addAttendanceHistoryEntry(
    String employeeId,
    String event, {
    double? matchConfidence,
  }) async {
    try {
      Map<String, dynamic> historyEntry = {
        'timestamp': FieldValue.serverTimestamp(),
        'event': event,
      };

      if (matchConfidence != null) {
        historyEntry['matchConfidence'] = matchConfidence;
      }

      await userCollection.doc(employeeId).update({
        'attendanceHistory': FieldValue.arrayUnion([historyEntry]),
      });
    } catch (e) {
      print('Error adding attendance history entry: $e');
    }
  }

  // Get user details with attendance history
  Future<Map<String, dynamic>> getUserDetails(String employeeId) async {
    try {
      final doc = await userCollection.doc(employeeId).get();
      if (!doc.exists) {
        throw Exception('User not found');
      }

      Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;

      // Get today's attendance records
      final today = DateTime.now().startOfDay;
      final attendanceHistory =
          List<Map<String, dynamic>>.from(userData['attendanceHistory'] ?? []);
      final todayAttendance = attendanceHistory.where((entry) {
        final timestamp = (entry['timestamp'] as Timestamp).toDate();
        return timestamp.isAfter(today);
      }).toList();

      userData['todayAttendance'] = todayAttendance;
      return userData;
    } catch (e) {
      print('Error getting user details: $e');
      rethrow;
    }
  }

  // Update face embeddings
  Future<void> updateFaceEmbeddings(
    String employeeId,
    List<List<double>> newEmbeddings,
  ) async {
    try {
      // Convert embeddings to storable format
      List<Map<String, dynamic>> convertedEmbeddings = newEmbeddings
          .map((embedding) => {
                'values': embedding,
              })
          .toList();

      await userCollection.doc(employeeId).update({
        'embeddings': convertedEmbeddings,
        'lastUpdated': FieldValue.serverTimestamp(),
        'registrationImages': newEmbeddings.length,
      });

      await addAttendanceHistoryEntry(
        employeeId,
        'Face embeddings updated',
      );

      print('Face embeddings updated for user: $employeeId');
    } catch (e) {
      print('Error updating face embeddings: $e');
      rethrow;
    }
  }

  // Get attendance report
  Future<Map<String, dynamic>> getAttendanceReport(
    String employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final userData = await getUserDetails(employeeId);
      final attendanceHistory =
          List<Map<String, dynamic>>.from(userData['attendanceHistory'] ?? []);

      // Filter attendance records within date range
      final filteredHistory = attendanceHistory.where((entry) {
        final timestamp = (entry['timestamp'] as Timestamp).toDate();
        return timestamp.isAfter(startDate) && timestamp.isBefore(endDate);
      }).toList();

      // Calculate attendance statistics
      Map<DateTime, List<Map<String, dynamic>>> dailyRecords = {};
      for (var entry in filteredHistory) {
        final date = (entry['timestamp'] as Timestamp).toDate().startOfDay;
        dailyRecords[date] ??= [];
        dailyRecords[date]!.add(entry);
      }

      int totalDays = dailyRecords.length;
      double totalHours = 0;
      int lateCheckins = 0;

      for (var records in dailyRecords.values) {
        // Add your business logic here for calculating statistics
        // Example: Calculate work hours, check for late check-ins, etc.
      }

      return {
        'employeeId': employeeId,
        'name': userData['name'],
        'startDate': startDate,
        'endDate': endDate,
        'totalDays': totalDays,
        'totalHours': totalHours,
        'lateCheckins': lateCheckins,
        'attendanceRecords': filteredHistory,
      };
    } catch (e) {
      print('Error generating attendance report: $e');
      rethrow;
    }
  }

  // Deactivate user
  Future<void> deactivateUser(String employeeId) async {
    try {
      await userCollection.doc(employeeId).update({
        'active': false,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      await addAttendanceHistoryEntry(
        employeeId,
        'User deactivated',
      );

      print('User deactivated: $employeeId');
    } catch (e) {
      print('Error deactivating user: $e');
      rethrow;
    }
  }

  // Get all attendance records
  Future<List<Map<String, dynamic>>> getAllAttendanceRecords(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final users = await getAllUsers();
      List<Map<String, dynamic>> allRecords = [];

      for (var doc in users.docs) {
        final userData = doc.data() as Map<String, dynamic>;
        final records = await getAttendanceReport(
          userData['employeeId'],
          startDate,
          endDate,
        );
        allRecords.add(records);
      }

      return allRecords;
    } catch (e) {
      print('Error getting all attendance records: $e');
      rethrow;
    }
  }
}

// Helper extension
extension DateTimeExtension on DateTime {
  DateTime get startOfDay => DateTime(year, month, day);
}

// lib/realtime/realtime_events.dart

class RealtimeEvents {
  // ---- Core protocol keys ----
  static const String eventType = 'event_type';
  static const String data = 'data';
  static const String branchId = 'branchId';
  static const String timestamp = 'timestamp';
  static const String clientId = 'client_id';
  static const String senderId = 'sender_id';
  static const String senderRole = '_senderRole';

  // ---- Event types ----
  static const String savePatient = 'save_patient';
  static const String deletePatient = 'delete_patient';

  static const String saveEntry = 'save_entry';
  static const String deleteEntry = 'delete_entry';

  static const String saveUser = 'save_user';
  static const String deleteUser = 'delete_user';

  static const String savePrescription = 'save_prescription';
  static const String deletePrescription = 'delete_prescription';

  static const String saveStockItem = 'save_stock_item';
  static const String deleteStockItem = 'delete_stock_item';

  static const String saveBranch = 'save_branch';
  static const String deleteBranch = 'delete_branch';

  // ---- Additional events ----
  static const String tokenCreated = 'token_created';
  static const String tokenUpdated = 'token_updated';
  static const String tokenStatusChanged = 'token_status_changed';
  static const String prescriptionCreated = 'prescription_created';
  static const String dispenseCompleted = 'dispense_completed';

  // ---- Connection events ----
  static const String clientConnected = 'client_connected';
  static const String clientDisconnected = 'client_disconnected';
  static const String clientListUpdate = 'client_list_update';
  static const String clientCountUpdate = 'client_count_update';
  static const String identify = 'identify';
  static const String identified = 'identified';
  static const String identifyRequest = 'identify_request';

  /// CRITICAL: Creates payload with branchId ONLY at top level
  /// This prevents routing confusion where branchId appears in multiple places
  static Map<String, dynamic> payload({
    required String type,
    required Map<String, dynamic> data,
    String? branchId,
    String? senderId,
  }) {
    // Make a clean copy of data WITHOUT branchId to avoid duplicates
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('branchId'); // Remove if accidentally included in data
    
    final map = {
      eventType: type,
      RealtimeEvents.data: cleanData,
      RealtimeEvents.timestamp: DateTime.now().toIso8601String(),
    };

    // Add branchId ONLY at top level if provided
    if (branchId != null && branchId.isNotEmpty) {
      map[RealtimeEvents.branchId] = branchId;
    }

    if (senderId != null) {
      map[RealtimeEvents.senderId] = senderId;
    }

    return map;
  }

  /// Creates a complete prescription payload with ALL required fields
  /// This ensures no data loss during transmission
  static Map<String, dynamic> prescriptionPayload({
    required String prescriptionId,
    required String serial,
    required String patientId,
    required String patientName,
    required String patientAge,
    required String patientGender,
    required String doctorId,
    required String doctorName,
    required String complaint,
    required String diagnosis,
    required List<Map<String, dynamic>> medicines,
    required List<Map<String, dynamic>> labTests,
    String? notes,
    required String tokenNumber,
    required String branchId,
    String status = 'completed',
    Map<String, dynamic>? vitals,
    String? queueType,
  }) {
    return {
      'id': prescriptionId,
      'serial': serial,
      'patientId': patientId,
      'patientName': patientName,
      'patientAge': patientAge,
      'patientGender': patientGender,
      'patientCnic': patientId, // Usually CNIC is used as patientId
      'doctorId': doctorId,
      'doctorName': doctorName,
      'complaint': complaint,
      'condition': complaint, // Include both for compatibility
      'diagnosis': diagnosis,
      'prescriptions': medicines.map((med) => {
        'name': med['name'],
        'quantity': med['quantity'],
        'type': med['type'] ?? 'Tablet',
        'timing': med['timing'] ?? '',
        'meal': med['meal'] ?? '',
        'dosage': med['dosage'] ?? '',
        'inventoryId': med['inventoryId'],
      }).toList(),
      'labResults': labTests.map((lab) => {
        'name': lab['name'],
      }).toList(),
      'notes': notes,
      'tokenNumber': tokenNumber,
      'status': status,
      'createdAt': DateTime.now().toIso8601String(),
      'completedAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': doctorName,
      if (vitals != null) 'vitals': vitals,
      if (queueType != null) 'queueType': queueType,
    };
  }

  /// Creates a complete token/entry payload
  static Map<String, dynamic> tokenPayload({
    required String serial,
    required String patientId,
    required String patientName,
    required String branchId,
    String? patientCnic,
    String? guardianCnic,
    required String queueType,
    required Map<String, dynamic> vitals,
    required String createdBy,
    required String createdByName,
    String status = 'waiting',
  }) {
    final dateKey = serial.split('-')[0];
    
    return {
      'serial': serial,
      'patientId': patientId,
      'patientName': patientName,
      'patientCnic': patientCnic ?? guardianCnic ?? '',
      if (patientCnic != null && patientCnic.isNotEmpty) 'cnic': patientCnic,
      if (guardianCnic != null && guardianCnic.isNotEmpty) 'guardianCnic': guardianCnic,
      'queueType': queueType,
      'vitals': vitals,
      'status': status,
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': createdBy,
      'createdByName': createdByName,
      'dateKey': dateKey,
    };
  }

  /// Validation helper
  static bool isValid(Map<String, dynamic> message) {
    return message.containsKey(eventType) && message[eventType] != null;
  }

  /// Extract branchId from message (checks both top level and data)
  static String? branchIdOf(Map<String, dynamic> message) {
    // Priority: top level first, then data
    return message[branchId]?.toString() ?? 
           (message[data] as Map<String, dynamic>?)?[branchId]?.toString();
  }

  /// Extract sender ID from message
  static String? senderIdOf(Map<String, dynamic> message) {
    return message[senderId]?.toString() ?? 
           message[senderRole]?.toString();
  }
}
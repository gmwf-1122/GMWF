// lib/models/donation_box_models.dart
//
// Data models for the Donation Box collection system.
// A DonationBox is a physical collection box placed at a location.
// A BoxOpening records each time a box is opened and its contents collected.

class DonationBox {
  final String id;           // Hive key / Firestore doc ID
  final String boxNumber;    // e.g. "BOX-001"
  final String holderName;   // Person who keeps the box
  final String holderPhone;  // Contact number
  final String holderAddress;// Full address
  final String branchId;
  final String branchName;
  final String registeredDate; // yyyy-MM-dd
  final bool isActive;
  final String notes;
  final String syncStatus;   // 'pending', 'synced'
  final String? firestoreId;
  final String? lastOpenedDate; // yyyy-MM-dd — last time box was opened
  final double? lastOpenedAmount;

  const DonationBox({
    required this.id,
    required this.boxNumber,
    required this.holderName,
    this.holderPhone = '',
    this.holderAddress = '',
    required this.branchId,
    required this.branchName,
    required this.registeredDate,
    this.isActive = true,
    this.notes = '',
    this.syncStatus = 'pending',
    this.firestoreId,
    this.lastOpenedDate,
    this.lastOpenedAmount,
  });

  factory DonationBox.fromMap(Map<dynamic, dynamic> map, String key) {
    return DonationBox(
      id:               key,
      boxNumber:        map['boxNumber']        ?? '',
      holderName:       map['holderName']       ?? '',
      holderPhone:      map['holderPhone']      ?? '',
      holderAddress:    map['holderAddress']     ?? '',
      branchId:         map['branchId']         ?? '',
      branchName:       map['branchName']       ?? '',
      registeredDate:   map['registeredDate']   ?? '',
      isActive:         map['isActive']         as bool? ?? true,
      notes:            map['notes']            ?? '',
      syncStatus:       map['syncStatus']       ?? 'pending',
      firestoreId:      map['firestoreId']      as String?,
      lastOpenedDate:   map['lastOpenedDate']   as String?,
      lastOpenedAmount: (map['lastOpenedAmount'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'boxNumber':        boxNumber,
      'holderName':       holderName,
      'holderPhone':      holderPhone,
      'holderAddress':    holderAddress,
      'branchId':         branchId,
      'branchName':       branchName,
      'registeredDate':   registeredDate,
      'isActive':         isActive,
      'notes':            notes,
      'syncStatus':       syncStatus,
      if (firestoreId != null) 'firestoreId': firestoreId,
      if (lastOpenedDate != null) 'lastOpenedDate': lastOpenedDate,
      if (lastOpenedAmount != null) 'lastOpenedAmount': lastOpenedAmount,
    };
  }

  DonationBox copyWith({
    String? boxNumber,
    String? holderName,
    String? holderPhone,
    String? holderAddress,
    bool? isActive,
    String? notes,
    String? syncStatus,
    String? firestoreId,
    String? lastOpenedDate,
    double? lastOpenedAmount,
  }) {
    return DonationBox(
      id:               id,
      boxNumber:        boxNumber        ?? this.boxNumber,
      holderName:       holderName       ?? this.holderName,
      holderPhone:      holderPhone      ?? this.holderPhone,
      holderAddress:    holderAddress    ?? this.holderAddress,
      branchId:         branchId,
      branchName:       branchName,
      registeredDate:   registeredDate,
      isActive:         isActive         ?? this.isActive,
      notes:            notes            ?? this.notes,
      syncStatus:       syncStatus       ?? this.syncStatus,
      firestoreId:      firestoreId      ?? this.firestoreId,
      lastOpenedDate:   lastOpenedDate   ?? this.lastOpenedDate,
      lastOpenedAmount: lastOpenedAmount ?? this.lastOpenedAmount,
    );
  }

  /// Days since the box was last opened. Returns null if never opened.
  int? get daysSinceLastOpened {
    if (lastOpenedDate == null || lastOpenedDate!.isEmpty) return null;
    final last = DateTime.tryParse(lastOpenedDate!);
    if (last == null) return null;
    return DateTime.now().difference(last).inDays;
  }

  /// Whether the box is overdue (not opened for > 30 days)
  bool get isOverdue {
    final days = daysSinceLastOpened;
    if (days == null) {
      // Never opened — check if registered > 30 days ago
      final reg = DateTime.tryParse(registeredDate);
      if (reg == null) return false;
      return DateTime.now().difference(reg).inDays > 30;
    }
    return days > 30;
  }
}

class BoxOpening {
  final String id;          // Hive key / Firestore doc ID
  final String boxId;       // Reference to DonationBox.id
  final String boxNumber;   // Denormalized for display
  final String openDate;    // yyyy-MM-dd
  final double amount;
  final String collectedBy;
  final String branchId;
  final String branchName;
  final String notes;
  final String syncStatus;  // 'pending', 'synced'
  final String? firestoreId;
  final String? timestamp;

  const BoxOpening({
    required this.id,
    required this.boxId,
    required this.boxNumber,
    required this.openDate,
    required this.amount,
    required this.collectedBy,
    required this.branchId,
    required this.branchName,
    this.notes = '',
    this.syncStatus = 'pending',
    this.firestoreId,
    this.timestamp,
  });

  factory BoxOpening.fromMap(Map<dynamic, dynamic> map, String key) {
    return BoxOpening(
      id:           key,
      boxId:        map['boxId']        ?? '',
      boxNumber:    map['boxNumber']    ?? '',
      openDate:     map['openDate']     ?? '',
      amount:       (map['amount'] as num?)?.toDouble() ?? 0.0,
      collectedBy:  map['collectedBy']  ?? '',
      branchId:     map['branchId']     ?? '',
      branchName:   map['branchName']   ?? '',
      notes:        map['notes']        ?? '',
      syncStatus:   map['syncStatus']   ?? 'pending',
      firestoreId:  map['firestoreId']  as String?,
      timestamp:    map['timestamp']    as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'boxId':        boxId,
      'boxNumber':    boxNumber,
      'openDate':     openDate,
      'amount':       amount,
      'collectedBy':  collectedBy,
      'branchId':     branchId,
      'branchName':   branchName,
      'notes':        notes,
      'syncStatus':   syncStatus,
      if (firestoreId != null) 'firestoreId': firestoreId,
      if (timestamp != null) 'timestamp': timestamp,
    };
  }

  BoxOpening copyWith({
    String? syncStatus,
    String? firestoreId,
  }) {
    return BoxOpening(
      id:           id,
      boxId:        boxId,
      boxNumber:    boxNumber,
      openDate:     openDate,
      amount:       amount,
      collectedBy:  collectedBy,
      branchId:     branchId,
      branchName:   branchName,
      notes:        notes,
      syncStatus:   syncStatus   ?? this.syncStatus,
      firestoreId:  firestoreId  ?? this.firestoreId,
      timestamp:    timestamp,
    );
  }
}

/// Yearly report data for a single month
class BoxMonthlyReport {
  final int month;           // 1-12
  final String monthName;    // "January", "February", etc.
  final bool wasOpened;
  final String? openDate;    // Date within the month it was opened
  final double amount;       // 0 if not opened
  final String? collectedBy;
  final String? notes;

  const BoxMonthlyReport({
    required this.month,
    required this.monthName,
    required this.wasOpened,
    this.openDate,
    this.amount = 0.0,
    this.collectedBy,
    this.notes,
  });
}

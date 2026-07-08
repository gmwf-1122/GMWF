import 'package:gmwf/pages/donations/donations_shared.dart';

class DonationStatus {
  static const String pending  = 'pending';
  static const String received = 'received';
}

class DonationRecord {
  final String hiveKey;
  final String localId;
  final String? firestoreId;
  final String branchId;
  final String branchName;

  final String donorId;
  final String donorName;
  final String phone;
  final String date;
  final String? timestamp;
  final String? lastUpdatedAt; // Added for conflict resolution
  final double amount;

  final String categoryId;
  final String? subtypeId;
  final String? gmwfSubCategoryId;

  final String entryType; // 'cash' or 'goods'
  final String? goodsItem;
  final String? unit;
  final double? probableAmount;

  final String paymentMethod;
  final String receiptNo;
  final String? bookReceiptNo;
  final String notes;

  final String status;
  final String syncStatus; // 'pending', 'synced'

  // Splitting & Anonymity
  final String? transactionId;
  final bool isAnonymous;
  final String? bankAccountNumber;

  // Audit Trail
  final String recordedBy;
  final String? collectorId;
  final String? forwardedBy;
  final String? forwardedByName;
  final String? recordedByRole;

  final bool?   submitted;
  final String? submissionId;

  // ── Edit tracking ────────────────────────────────────────────────────────
  final String? donorHomeBranch;    // branch where donor was originally registered
  final String? collectedAtBranch;  // branch where this donation was collected

  final bool isEdited;
  final String? editReason;
  final String? editedBy;
  final String? editedAt;
  final List<Map<String, dynamic>>? editHistory;

  const DonationRecord({
    required this.hiveKey,
    required this.localId,
    this.firestoreId,
    required this.branchId,
    required this.branchName,
    required this.donorId,
    required this.donorName,
    required this.phone,
    required this.date,
    this.timestamp,
    this.lastUpdatedAt,
    required this.amount,
    required this.categoryId,
    this.subtypeId,
    this.gmwfSubCategoryId,
    required this.entryType,
    this.goodsItem,
    this.unit,
    this.probableAmount,
    required this.paymentMethod,
    required this.receiptNo,
    this.bookReceiptNo,
    required this.notes,
    required this.status,
    required this.syncStatus,
    required this.recordedBy,
    this.transactionId,
    this.isAnonymous = false,
    this.bankAccountNumber,
    this.collectorId,
    this.forwardedBy,
    this.forwardedByName,
    this.recordedByRole,
    this.submitted,
    this.submissionId,
    this.isEdited = false,
    this.donorHomeBranch,
    this.collectedAtBranch,
    this.editReason,
    this.editedBy,
    this.editedAt,
    this.editHistory,
  });

  factory DonationRecord.fromMap(Map<dynamic, dynamic> map, String key) {
    // Parse editHistory safely — Hive stores it as List<dynamic>
    List<Map<String, dynamic>>? parseEditHistory(dynamic raw) {
      if (raw == null) return null;
      if (raw is! List) return null;
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return DonationRecord(
      hiveKey:            key,
      localId:            map['localId']            ?? '',
      firestoreId:        map['firestoreId'],
      branchId:           map['branchId']            ?? '',
      branchName:         map['branchName']           ?? '',
      donorId:            map['donorId']             ?? '',
      donorName:          map['donorName']            ?? '',
      phone:              map['phone']               ?? '',
      date:               map['date']                ?? '',
      timestamp:          map['timestamp'],
      lastUpdatedAt:      map['lastUpdatedAt'],
      amount:             (map['amount']             as num?)?.toDouble() ?? 0.0,
      categoryId:         map['categoryId']          ?? '',
      subtypeId:          map['subtypeId'],
      gmwfSubCategoryId:  map['gmwfSubCategoryId'],
      entryType:          map['entryType']           ?? 'cash',
      goodsItem:          map['goodsItem'],
      unit:               map['unit'],
      probableAmount:     (map['probableAmount']     as num?)?.toDouble(),
      paymentMethod:      map['paymentMethod']       ?? 'Cash',
      receiptNo:          map['receiptNo']           ?? '',
      bookReceiptNo:      map['bookReceiptNo']       as String?,
      notes:              map['notes']               ?? '',
      status:             map['status']              ?? kStatusPending,
      syncStatus:         map['syncStatus']          ?? 'pending',
      recordedBy:         map['recordedBy']          ?? '',
      transactionId:      map['transactionId'],
      isAnonymous:        map['isAnonymous']         as bool? ?? false,
      bankAccountNumber:  map['bankAccountNumber'],
      collectorId:        map['collectorId'],
      forwardedBy:        map['forwardedBy'],
      forwardedByName:    map['forwardedByName'],
      recordedByRole:     map['recordedByRole'],
      submitted:          map['submitted']           as bool?,
      submissionId:       map['submissionId']        as String?,
      isEdited:           map['isEdited']            as bool? ?? false,
      editReason:         map['editReason']          as String?,
      editedBy:           map['editedBy']            as String?,
      editedAt:           map['editedAt']            as String?,
      donorHomeBranch:    map['donorHomeBranch']    as String?,
      collectedAtBranch:  map['collectedAtBranch']  as String?,
      editHistory:        parseEditHistory(map['editHistory']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'localId':            localId,
      'firestoreId':        firestoreId,
      'branchId':           branchId,
      'branchName':         branchName,
      'donorId':            donorId,
      'donorName':          donorName,
      'phone':              phone,
      'date':               date,
      'timestamp':          timestamp,
      'lastUpdatedAt':      lastUpdatedAt,
      'amount':             amount,
      'categoryId':         categoryId,
      'subtypeId':          subtypeId,
      'gmwfSubCategoryId':  gmwfSubCategoryId,
      'entryType':          entryType,
      'goodsItem':          goodsItem,
      'unit':               unit,
      'probableAmount':     probableAmount,
      'paymentMethod':      paymentMethod,
      'receiptNo':          receiptNo,
      if (bookReceiptNo != null) 'bookReceiptNo': bookReceiptNo,
      'notes':              notes,
      'status':             status,
      'syncStatus':         syncStatus,
      'recordedBy':         recordedBy,
      'transactionId':      transactionId,
      'isAnonymous':        isAnonymous,
      'bankAccountNumber':  bankAccountNumber,
      'collectorId':        collectorId,
      'forwardedBy':        forwardedBy,
      'forwardedByName':    forwardedByName,
      'recordedByRole':     recordedByRole,
      'submitted':          submitted,
      'submissionId':       submissionId,
      'isEdited':           isEdited,
      'editReason':         editReason,
      'editedBy':           editedBy,
      'editedAt':           editedAt,
      'editHistory':        editHistory,
      if (donorHomeBranch   != null) 'donorHomeBranch':   donorHomeBranch,
      if (collectedAtBranch != null) 'collectedAtBranch': collectedAtBranch,
    };
  }

  DonationRecord copyWith({
    String? status,
    String? syncStatus,
    String? firestoreId,
    bool?   submitted,
    String? submissionId,
    String? collectorId,
    String? forwardedBy,
    String? forwardedByName,
    String? recordedByRole,
    bool?   isEdited,
    String? editReason,
    String? editedBy,
    String? editedAt,
    String? lastUpdatedAt,
    List<Map<String, dynamic>>? editHistory,
    String? date,
    String? bookReceiptNo,
  }) {
    return DonationRecord(
      hiveKey:            hiveKey,
      localId:            localId,
      firestoreId:        firestoreId            ?? this.firestoreId,
      branchId:           branchId,
      branchName:         branchName,
      donorId:            donorId,
      donorName:          donorName,
      phone:              phone,
      date:               date                   ?? this.date,
      timestamp:          this.timestamp,
      lastUpdatedAt:      lastUpdatedAt          ?? this.lastUpdatedAt,
      amount:             amount,
      categoryId:         categoryId,
      subtypeId:          subtypeId,
      gmwfSubCategoryId:  gmwfSubCategoryId,
      entryType:          entryType,
      goodsItem:          goodsItem,
      unit:               unit,
      probableAmount:     probableAmount,
      paymentMethod:      paymentMethod,
      receiptNo:          receiptNo,
      bookReceiptNo:      bookReceiptNo          ?? this.bookReceiptNo,
      notes:              notes,
      status:             status             ?? this.status,
      syncStatus:         syncStatus         ?? this.syncStatus,
      recordedBy:         recordedBy,
      submitted:          submitted          ?? this.submitted,
      submissionId:       submissionId       ?? this.submissionId,
      collectorId:        collectorId        ?? this.collectorId,
      forwardedBy:        forwardedBy        ?? this.forwardedBy,
      forwardedByName:    forwardedByName    ?? this.forwardedByName,
      recordedByRole:     recordedByRole     ?? this.recordedByRole,
      isEdited:           isEdited           ?? this.isEdited,
      donorHomeBranch:    this.donorHomeBranch,
      collectedAtBranch:  this.collectedAtBranch,
      editReason:         editReason         ?? this.editReason,
      editedBy:           editedBy           ?? this.editedBy,
      editedAt:           editedAt           ?? this.editedAt,
      editHistory:        editHistory        ?? this.editHistory,
    );
  }
}

class AuditLogEntry {
  final String id;
  final String collection; // 'donations', 'donors', etc.
  final String documentId;
  final String action; // 'create', 'update', 'delete'
  final String userId;
  final String username;
  final String timestamp;
  final String branchId;   // which office performed this action
  final String branchName; // human-readable branch name
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final String? reason;

  AuditLogEntry({
    required this.id,
    required this.collection,
    required this.documentId,
    required this.action,
    required this.userId,
    required this.username,
    required this.timestamp,
    this.branchId = '',
    this.branchName = '',
    this.oldData,
    this.newData,
    this.reason,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'collection': collection,
      'documentId': documentId,
      'action': action,
      'userId': userId,
      'username': username,
      'timestamp': timestamp,
      'branchId': branchId,
      'branchName': branchName,
      if (oldData != null) 'oldData': oldData,
      if (newData != null) 'newData': newData,
      if (reason != null) 'reason': reason,
    };
  }

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] ?? '',
      collection: map['collection'] ?? '',
      documentId: map['documentId'] ?? '',
      action: map['action'] ?? '',
      userId: map['userId'] ?? '',
      username: map['username'] ?? '',
      timestamp: map['timestamp'] ?? '',
      branchId: map['branchId'] ?? '',
      branchName: map['branchName'] ?? map['branchId'] ?? '',
      oldData: map['oldData'] != null ? Map<String, dynamic>.from(map['oldData']) : null,
      newData: map['newData'] != null ? Map<String, dynamic>.from(map['newData']) : null,
      reason: map['reason'],
    );
  }
}

extension DonationRecordX on DonationRecord {
  DonationCategory get category =>
      DonationCategory.values.firstWhere(
          (c) => c.name == categoryId,
          orElse: () => DonationCategory.gmwf);

  DonationSubtype? get subtype =>
      subtypeId != null
          ? DonationSubtype.values.firstWhere(
              (s) => s.name == subtypeId,
              orElse: () => DonationSubtype.general)
          : null;

  GmwfSubCategory? get gmwfSubCategory =>
      gmwfSubCategoryId != null
          ? GmwfSubCategory.values.firstWhere(
              (s) => s.name == gmwfSubCategoryId,
              orElse: () => GmwfSubCategory.general)
          : null;

  bool get isCash  => entryType == 'cash';
  bool get isGoods => entryType == 'goods';

  bool get isPending  => status == DonationStatus.pending;
  bool get isReceived => status == DonationStatus.received;
}
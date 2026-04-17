import '../Pages/donations/donations_shared.dart';

class DonationStatus {
  static const String pending           = 'pending';
  static const String approvedByManager = 'approved_by_manager';
  static const String approved          = 'approved';
  static const String rejected          = 'rejected';
}

class DonationRecord {
  final String hiveKey;
  final String localId;
  final String? firestoreId;
  final String branchId;
  final String branchName;

  final String donorName;
  final String phone;
  final String date;
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
  final String notes;

  final String status;
  final String syncStatus; // 'pending', 'synced'

  // Audit Trail
  final String recordedBy;
  final String? approvedByManager;
  final String? approvedByManagerId;
  final String? managerApprovalTimestamp;

  final String? approvedByChairman;
  final String? approvedByChairmanId;
  final String? chairmanApprovalTimestamp;

  final String? rejectedBy;
  final String? rejectionReason;

  // Submission / forwarding fields
  final bool?   submitted;
  final String? submissionId;
  final String? collectorId;
  final String? forwardedBy;
  final String? forwardedByName;

  DonationRecord({
    required this.hiveKey,
    required this.localId,
    this.firestoreId,
    required this.branchId,
    required this.branchName,
    required this.donorName,
    required this.phone,
    required this.date,
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
    required this.notes,
    required this.status,
    required this.syncStatus,
    required this.recordedBy,
    this.approvedByManager,
    this.approvedByManagerId,
    this.managerApprovalTimestamp,
    this.approvedByChairman,
    this.approvedByChairmanId,
    this.chairmanApprovalTimestamp,
    this.rejectedBy,
    this.rejectionReason,
    this.submitted,
    this.submissionId,
    this.collectorId,
    this.forwardedBy,
    this.forwardedByName,
  });

  factory DonationRecord.fromMap(Map<dynamic, dynamic> map, String key) {
    return DonationRecord(
      hiveKey:                   key,
      localId:                   map['localId']                  ?? '',
      firestoreId:               map['firestoreId'],
      branchId:                  map['branchId']                 ?? '',
      branchName:                map['branchName']               ?? '',
      donorName:                 map['donorName']                ?? '',
      phone:                     map['phone']                    ?? '',
      date:                      map['date']                     ?? '',
      amount:                    (map['amount']                  as num?)?.toDouble() ?? 0.0,
      categoryId:                map['categoryId']               ?? '',
      subtypeId:                 map['subtypeId'],
      gmwfSubCategoryId:         map['gmwfSubCategoryId'],
      entryType:                 map['entryType']                ?? 'cash',
      goodsItem:                 map['goodsItem'],
      unit:                      map['unit'],
      probableAmount:            (map['probableAmount']          as num?)?.toDouble(),
      paymentMethod:             map['paymentMethod']            ?? 'Cash',
      receiptNo:                 map['receiptNo']                ?? '',
      notes:                     map['notes']                    ?? '',
      status:                    map['status']                   ?? DonationStatus.pending,
      syncStatus:                map['syncStatus']               ?? 'pending',
      recordedBy:                map['recordedBy']               ?? '',
      approvedByManager:         map['approvedByManager'],
      approvedByManagerId:       map['approvedByManagerId'],
      managerApprovalTimestamp:  map['managerApprovalTimestamp'],
      approvedByChairman:        map['approvedByChairman'],
      approvedByChairmanId:      map['approvedByChairmanId'],
      chairmanApprovalTimestamp: map['chairmanApprovalTimestamp'],
      rejectedBy:                map['rejectedBy'],
      rejectionReason:           map['rejectionReason'],
      submitted:                 map['submitted']                as bool?,
      submissionId:              map['submissionId']             as String?,
      collectorId:               map['collectorId']              as String?,
      forwardedBy:               map['forwardedBy']              as String?,
      forwardedByName:           map['forwardedByName']          as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'localId':                  localId,
      'firestoreId':              firestoreId,
      'branchId':                 branchId,
      'branchName':               branchName,
      'donorName':                donorName,
      'phone':                    phone,
      'date':                     date,
      'amount':                   amount,
      'categoryId':               categoryId,
      'subtypeId':                subtypeId,
      'gmwfSubCategoryId':        gmwfSubCategoryId,
      'entryType':                entryType,
      'goodsItem':                goodsItem,
      'unit':                     unit,
      'probableAmount':           probableAmount,
      'paymentMethod':            paymentMethod,
      'receiptNo':                receiptNo,
      'notes':                    notes,
      'status':                   status,
      'syncStatus':               syncStatus,
      'recordedBy':               recordedBy,
      'approvedByManager':        approvedByManager,
      'approvedByManagerId':      approvedByManagerId,
      'managerApprovalTimestamp': managerApprovalTimestamp,
      'approvedByChairman':       approvedByChairman,
      'approvedByChairmanId':     approvedByChairmanId,
      'chairmanApprovalTimestamp': chairmanApprovalTimestamp,
      'rejectedBy':               rejectedBy,
      'rejectionReason':          rejectionReason,
      'submitted':                submitted,
      'submissionId':             submissionId,
      'collectorId':              collectorId,
      'forwardedBy':              forwardedBy,
      'forwardedByName':          forwardedByName,
    };
  }

  DonationRecord copyWith({
    String? status,
    String? syncStatus,
    String? firestoreId,
    String? approvedByManager,
    String? approvedByManagerId,
    String? managerApprovalTimestamp,
    String? approvedByChairman,
    String? approvedByChairmanId,
    String? chairmanApprovalTimestamp,
    String? rejectedBy,
    String? rejectionReason,
    bool?   submitted,
    String? submissionId,
    String? collectorId,
    String? forwardedBy,
    String? forwardedByName,
  }) {
    return DonationRecord(
      hiveKey:                   hiveKey,
      localId:                   localId,
      firestoreId:               firestoreId               ?? this.firestoreId,
      branchId:                  branchId,
      branchName:                branchName,
      donorName:                 donorName,
      phone:                     phone,
      date:                      date,
      amount:                    amount,
      categoryId:                categoryId,
      subtypeId:                 subtypeId,
      gmwfSubCategoryId:         gmwfSubCategoryId,
      entryType:                 entryType,
      goodsItem:                 goodsItem,
      unit:                      unit,
      probableAmount:            probableAmount,
      paymentMethod:             paymentMethod,
      receiptNo:                 receiptNo,
      notes:                     notes,
      status:                    status                    ?? this.status,
      syncStatus:                syncStatus                ?? this.syncStatus,
      recordedBy:                recordedBy,
      approvedByManager:         approvedByManager         ?? this.approvedByManager,
      approvedByManagerId:       approvedByManagerId       ?? this.approvedByManagerId,
      managerApprovalTimestamp:  managerApprovalTimestamp  ?? this.managerApprovalTimestamp,
      approvedByChairman:        approvedByChairman        ?? this.approvedByChairman,
      approvedByChairmanId:      approvedByChairmanId      ?? this.approvedByChairmanId,
      chairmanApprovalTimestamp: chairmanApprovalTimestamp ?? this.chairmanApprovalTimestamp,
      rejectedBy:                rejectedBy                ?? this.rejectedBy,
      rejectionReason:           rejectionReason           ?? this.rejectionReason,
      submitted:                 submitted                 ?? this.submitted,
      submissionId:              submissionId              ?? this.submissionId,
      collectorId:               collectorId               ?? this.collectorId,
      forwardedBy:               forwardedBy               ?? this.forwardedBy,
      forwardedByName:           forwardedByName           ?? this.forwardedByName,
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

  bool get isPending           => status == DonationStatus.pending;
  bool get isApproved          => status == DonationStatus.approved;
  bool get isRejected          => status == DonationStatus.rejected;
  bool get isApprovedByManager =>
      status == DonationStatus.approvedByManager ||
      status == DonationStatus.approved;
}
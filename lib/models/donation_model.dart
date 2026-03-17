// ============================================================
// donation_model.dart
// Unified Donation model — all fields, enums, serialization
// ============================================================

enum DonationType { jamia, general, goods }

enum PaymentMethod { cash, online, bankDeposit, other }

enum DonationStatus {
  collected,
  submittedToManager,
  receivedByManager,
  submittedToChairman,
  receivedByChairman,
}

enum CollectorRole { officeBoy, manager, chairman }

enum GeneralPurpose { zakat, sadqaat, atiyaat }

// ─────────────────────────────────────────────────────────────────────────────

class Donation {
  // Core identity
  final String id;
  final String receiptNumber; // e.g. GRT-241226-001

  // Donor info
  final String donorName;
  final String donorPhone;

  // Classification
  final DonationType donationType;
  final String purpose; // free-text purpose / jamia purpose
  final GeneralPurpose? generalPurpose; // only for DonationType.general

  // Financial
  final double amount;
  final PaymentMethod paymentMethod;

  // Goods (only when donationType == goods)
  final String? goodsName;
  final int? goodsQuantity;
  final double? goodsValue;

  // Collection chain
  final String collectorId;
  final CollectorRole collectorRole;
  final String branchId;
  final String cityCode;

  // Batch & status
  final String? batchId; // null until submitted into a batch
  final DonationStatus status;

  // Timestamps
  final DateTime createdAt;
  final DateTime? submittedAt;

  const Donation({
    required this.id,
    required this.receiptNumber,
    required this.donorName,
    required this.donorPhone,
    required this.donationType,
    required this.purpose,
    this.generalPurpose,
    required this.amount,
    required this.paymentMethod,
    this.goodsName,
    this.goodsQuantity,
    this.goodsValue,
    required this.collectorId,
    required this.collectorRole,
    required this.branchId,
    required this.cityCode,
    this.batchId,
    required this.status,
    required this.createdAt,
    this.submittedAt,
  });

  // ── Computed helpers ────────────────────────────────────────────────────────

  /// A donation is locked once it belongs to a batch.
  bool get isLocked => batchId != null;

  bool get isGoods => donationType == DonationType.goods;

  /// For goods donations use estimated value; otherwise use amount.
  double get effectiveValue => isGoods ? (goodsValue ?? 0) : amount;

  // ── copyWith ────────────────────────────────────────────────────────────────

  Donation copyWith({
    String? batchId,
    DonationStatus? status,
    DateTime? submittedAt,
  }) {
    return Donation(
      id: id,
      receiptNumber: receiptNumber,
      donorName: donorName,
      donorPhone: donorPhone,
      donationType: donationType,
      purpose: purpose,
      generalPurpose: generalPurpose,
      amount: amount,
      paymentMethod: paymentMethod,
      goodsName: goodsName,
      goodsQuantity: goodsQuantity,
      goodsValue: goodsValue,
      collectorId: collectorId,
      collectorRole: collectorRole,
      branchId: branchId,
      cityCode: cityCode,
      batchId: batchId ?? this.batchId,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      createdAt: createdAt,
    );
  }

  // ── Serialization ────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'receiptNumber': receiptNumber,
        'donorName': donorName,
        'donorPhone': donorPhone,
        'donationType': donationType.name,
        'purpose': purpose,
        'generalPurpose': generalPurpose?.name,
        'amount': amount,
        'paymentMethod': paymentMethod.name,
        'goodsName': goodsName,
        'goodsQuantity': goodsQuantity,
        'goodsValue': goodsValue,
        'collectorId': collectorId,
        'collectorRole': collectorRole.name,
        'branchId': branchId,
        'cityCode': cityCode,
        'batchId': batchId,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'submittedAt': submittedAt?.toIso8601String(),
      };

  factory Donation.fromJson(Map<String, dynamic> j) => Donation(
        id: j['id'] as String,
        receiptNumber: j['receiptNumber'] as String,
        donorName: j['donorName'] as String,
        donorPhone: j['donorPhone'] as String,
        donationType:
            DonationType.values.byName(j['donationType'] as String),
        purpose: j['purpose'] as String,
        generalPurpose: j['generalPurpose'] != null
            ? GeneralPurpose.values
                .byName(j['generalPurpose'] as String)
            : null,
        amount: (j['amount'] as num).toDouble(),
        paymentMethod:
            PaymentMethod.values.byName(j['paymentMethod'] as String),
        goodsName: j['goodsName'] as String?,
        goodsQuantity: j['goodsQuantity'] as int?,
        goodsValue: j['goodsValue'] != null
            ? (j['goodsValue'] as num).toDouble()
            : null,
        collectorId: j['collectorId'] as String,
        collectorRole:
            CollectorRole.values.byName(j['collectorRole'] as String),
        branchId: j['branchId'] as String,
        cityCode: j['cityCode'] as String,
        batchId: j['batchId'] as String?,
        status: DonationStatus.values.byName(j['status'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        submittedAt: j['submittedAt'] != null
            ? DateTime.parse(j['submittedAt'] as String)
            : null,
      );

  @override
  String toString() =>
      'Donation(id: $id, receipt: $receiptNumber, donor: $donorName, '
      'status: ${status.name}, locked: $isLocked)';
}
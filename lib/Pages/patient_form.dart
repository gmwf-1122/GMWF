// lib/pages/patient_form.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'patient_form_helper.dart';

class PatientForm extends StatefulWidget {
  final String branchId;
  final String cnic;
  final String serial;
  final VoidCallback? onDispensed;
  const PatientForm({
    super.key,
    required this.branchId,
    required this.cnic,
    required this.serial,
    this.onDispensed,
  });
  @override
  State<PatientForm> createState() => _PatientFormState();
}

class _PatientFormState extends State<PatientForm> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _patientData;
  bool _isLoading = false;
  bool _isDispensed = false;
  bool _isPrinting = false;
  String? _gender;
  String? _age;
  String? _branchName;
  final GlobalKey _fullKey = GlobalKey();
  final GlobalKey _slipKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.cnic.isNotEmpty && widget.serial.isNotEmpty) {
      _fetchPrescriptionData();
    }
  }

  @override
  void didUpdateWidget(covariant PatientForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cnic != widget.cnic || oldWidget.serial != widget.serial) {
      _fetchPrescriptionData();
    }
  }

  Future<void> _fetchPrescriptionData() async {
    setState(() => _isLoading = true);
    try {
      final fs = FirebaseFirestore.instance;
      final branchDoc =
          await fs.collection('branches').doc(widget.branchId).get();
      final doc = await fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('prescriptions')
          .doc(widget.cnic)
          .collection('prescriptions')
          .doc(widget.serial)
          .get();

      if (!doc.exists) {
        setState(() => _data = null);
        return;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(doc.data() ?? {});
      final status = (data['status'] ?? '').toString().toLowerCase();
      String? gender = data['gender'];
      String? age = data['age']?.toString();
      Map<String, dynamic>? patientData;

      if (gender == null || age == null) {
        final pdoc = await fs
            .collection('branches')
            .doc(widget.branchId)
            .collection('patients')
            .doc(widget.cnic)
            .get();
        if (pdoc.exists) {
          patientData = Map<String, dynamic>.from(pdoc.data() ?? {});
          gender ??= patientData['gender'];
          age ??= patientData['age']?.toString();
        }
      }

      setState(() {
        _branchName = branchDoc.data()?['name'] ?? widget.branchId;
        _data = data;
        _patientData = patientData;
        _isDispensed = status == 'dispensed';
        _gender = gender;
        _age = age;
      });
    } catch (e) {
      debugPrint('Fetch error: $e');
      setState(() => _data = null);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool get _hasPrintableContent {
    final lab = (_data?['labResults'] ?? []) as List;
    final custom = (_data?['prescriptions'] ?? [])
        .where((m) =>
            m['inventoryId'] == null && (m['type'] ?? 'medicine') == 'medicine')
        .toList();
    final injects = (_data?['prescriptions'] ?? [])
        .where((m) => PatientFormHelper.isInjectable(m))
        .toList();
    return lab.isNotEmpty || custom.isNotEmpty || injects.isNotEmpty;
  }

  Future<void> _printOnly() async {
    if (!_hasPrintableContent) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nothing to print')));
      return;
    }
    setState(() => _isPrinting = true);
    try {
      final pdfBytes = await PatientFormHelper.generatePrintPdf(
          _data!, _gender ?? '', _age ?? '');
      await Printing.layoutPdf(
          onLayout: (_) => pdfBytes, name: 'Slip_${widget.serial}.pdf');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Slip printed!')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Print error: $e')));
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<void> _dispenseOnly() async {
    if (_isDispensed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Already dispensed')));
      return;
    }
    setState(() => _isLoading = true);
    final fs = FirebaseFirestore.instance;
    final branchRef = fs.collection('branches').doc(widget.branchId);
    final ddmmyy = widget.serial.split('-').first;

    try {
      final batch = fs.batch();
      for (final type in ['zakat', 'non-zakat']) {
        final col =
            branchRef.collection('serials').doc(ddmmyy).collection(type);
        final snap = await col
            .where(FieldPath.documentId, isEqualTo: widget.serial)
            .get();
        for (final d in snap.docs) {
          batch.update(d.reference, {'status': 'dispensed'});
        }
      }

      final meds = (_data?['prescriptions'] ?? []) as List;
      for (final med in meds) {
        if (med['inventoryId'] == null) continue;
        final timing = med['timing']?.toString() ?? '';
        final qty = int.tryParse(med['quantity']?.toString() ?? '1') ?? 1;
        final totalPerDayVal = PatientFormHelper.totalPerDay(timing);
        final total = totalPerDayVal > 0 ? totalPerDayVal * qty : qty;

        final invRef = branchRef
            .collection('inventory')
            .doc(med['inventoryId'].toString());
        final snap = await invRef.get();
        if (snap.exists) {
          final cur = (snap.data()?['quantity'] ?? 0).toDouble();
          batch.update(invRef, {'quantity': cur - total < 0 ? 0 : cur - total});
        }
      }

      final Map<String, dynamic> safe = {};
      _data?.forEach((k, v) => safe[k] = v);
      final logRef = branchRef.collection('dispensary').doc(ddmmyy);
      final recRef = logRef.collection(ddmmyy).doc(widget.serial);
      batch.set(recRef, {
        ...safe,
        'status': 'dispensed',
        'serial': widget.serial,
        'cnic': widget.cnic,
        'age': _age,
        'gender': _gender,
        'dispensedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      setState(() => _isDispensed = true);
      widget.onDispensed?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispensed!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, st) {
      debugPrint('Dispense error: $e\n$st');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _sectionTitle(String title, {bool withIcon = false}) => withIcon
      ? Row(
          children: [
            Icon(Icons.medical_services, color: PatientFormHelper.primaryGreen),
            const SizedBox(width: 8),
            Text(
              title,
              style: PatientFormHelper.robotoBold(
                  size: 18, color: PatientFormHelper.primaryGreen),
            ),
          ],
        )
      : Text(
          title,
          style: PatientFormHelper.robotoBold(
              size: 18, color: PatientFormHelper.primaryGreen),
        );

  Widget _linedList(
    List items, {
    bool isLab = false,
    bool isInjectable = false,
  }) {
    if (isLab) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          final name = item['name']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '- $name',
              style: PatientFormHelper.robotoBold(size: 16),
            ),
          );
        }).toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        final name = item['name']?.toString() ?? '';
        final meal = item['meal']?.toString() ?? '';
        final timing = item['timing']?.toString() ?? '';
        final quantity = item['quantity'] ?? 1;
        final total = PatientFormHelper.totalPerDay(timing);
        final timingDisp = PatientFormHelper.formatTimingDisplay(timing);
        final urdu = PatientFormHelper.timingToUrdu(timing);
        final showTiming = !isInjectable && total > 0;
        final showQuantity = isInjectable;
        final mealText = PatientFormHelper.getMealText(meal);
        final mealUrdu = PatientFormHelper.getMealUrdu(meal);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      '- $name',
                      style: PatientFormHelper.robotoBold(size: 16),
                    ),
                  ),
                  if (showTiming)
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: timingDisp,
                                style: PatientFormHelper.robotoBold(
                                  size: 16,
                                  color: PatientFormHelper.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (showQuantity)
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Qty: $quantity',
                          style: PatientFormHelper.robotoBold(
                            size: 16,
                            color: PatientFormHelper.primaryGreen,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 4,
                    child: Directionality(
                      textDirection: ui.TextDirection.rtl,
                      child: Text(
                        urdu,
                        textAlign: TextAlign.right,
                        style: PatientFormHelper.nooriRegular(
                          size: 16,
                          color: PatientFormHelper.textBlack,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (meal.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        mealText,
                        style: PatientFormHelper.robotoRegular(
                          size: 14,
                          color: PatientFormHelper.textBlack,
                        ),
                      ),
                    ),
                    const Expanded(flex: 3, child: SizedBox()),
                    Expanded(
                      flex: 4,
                      child: Directionality(
                        textDirection: ui.TextDirection.rtl,
                        child: Text(
                          mealUrdu,
                          textAlign: TextAlign.right,
                          style: PatientFormHelper.nooriRegular(
                            size: 14,
                            color: PatientFormHelper.textBlack,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHeader(String doctorName) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Transform.rotate(
              angle: -0.55,
              child: Image.asset(
                'assets/images/moon.png',
                width: 80,
                height: 80,
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'ہو الشافی',
                    style: PatientFormHelper.nooriRegular(
                      size: 28,
                      color: PatientFormHelper.primaryRed,
                    ),
                  ),
                  Text(
                    'Gulzar-e-Madina Welfare Foundation',
                    style: PatientFormHelper.robotoBold(
                      size: 26,
                      color: PatientFormHelper.primaryGreen,
                    ),
                  ),
                  Text(
                    'Free Dispensary',
                    style: PatientFormHelper.robotoBold(
                      size: 24,
                      color: PatientFormHelper.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            Image.asset('assets/logo/gmwf.png', width: 85, height: 85),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              doctorName.isNotEmpty ? 'Dr. $doctorName' : 'Dr. ____________',
              style: PatientFormHelper.robotoBold(
                size: 22,
                color: PatientFormHelper.primaryRed,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _verticalDivider() => Container(
        width: 1,
        color: Colors.grey,
        margin: const EdgeInsets.symmetric(horizontal: 20),
      );

  Widget _buildLabColumn(List labTests) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Lab Tests'),
          const SizedBox(height: 8),
          _linedList(labTests, isLab: true),
        ],
      );

  Widget _buildRightColumn(
    String patientName,
    String diagnosis,
    List inventoryMeds,
    List inventoryInjectables,
    List customMeds,
    List customInjectables,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 16),
          child: RichText(
            text: TextSpan(
              style: PatientFormHelper.robotoBold(size: 18),
              children: [
                TextSpan(
                  text: 'Patient: ',
                  style: PatientFormHelper.robotoBold(
                    color: PatientFormHelper.primaryGreen,
                    size: 18,
                  ),
                ),
                TextSpan(
                  text: patientName,
                  style: PatientFormHelper.robotoBold(
                    size: 20,
                  ),
                ),
                const TextSpan(text: '   '),
                TextSpan(
                  text: 'Gender: ',
                  style: PatientFormHelper.robotoBold(
                    color: PatientFormHelper.primaryGreen,
                    size: 18,
                  ),
                ),
                TextSpan(
                  text: _gender ?? '',
                  style: PatientFormHelper.robotoBold(
                    size: 20,
                  ),
                ),
                const TextSpan(text: '   '),
                TextSpan(
                  text: 'Age: ',
                  style: PatientFormHelper.robotoBold(
                    color: PatientFormHelper.primaryGreen,
                    size: 18,
                  ),
                ),
                TextSpan(
                  text: _age ?? '',
                  style: PatientFormHelper.robotoBold(
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (diagnosis.isNotEmpty) ...[
          const SizedBox(height: 20),
          Image.asset(
            'assets/images/rx.png',
            width: 40,
            height: 40,
            color: PatientFormHelper.primaryGreen,
          ),
          _sectionTitle('Diagnosis'),
          Text(diagnosis, style: PatientFormHelper.robotoRegular(size: 16)),
        ],
        if (inventoryMeds.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionTitle('Inventory Medicines'),
          _linedList(inventoryMeds),
        ],
        if (customMeds.isNotEmpty || customInjectables.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionTitle('Custom Medicines'),
          _linedList(customMeds),
          if (customInjectables.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Injectables',
              style: PatientFormHelper.robotoBold(
                size: 18,
                color: PatientFormHelper.primaryGreen,
              ),
            ),
            _linedList(customInjectables, isInjectable: true),
          ],
        ],
        if (inventoryInjectables.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionTitle('Inventory Injectables'),
          _linedList(inventoryInjectables, isInjectable: true),
        ],
      ],
    );
  }

  Widget _buildFooter() => Center(
        child: Column(
          children: [
            Text(
              'Gulzar e Madina $_branchName',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
                fontFamily: 'Roboto',
              ),
            ),
            const Text(
              'Website: gulzarmadina.com',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return const Center(
        child: Text(
          'No prescription found',
          style: TextStyle(color: Colors.grey, fontFamily: 'Roboto'),
        ),
      );
    }

    final d = _data!;
    final doctorName = d['doctorName']?.toString() ?? '';
    final patientName = d['patientName']?.toString() ?? '';
    final diagnosis = d['diagnosis']?.toString() ?? '';
    final labTests = (d['labResults'] ?? []) as List;
    final prescriptions = (d['prescriptions'] ?? []) as List;

    final inventoryMeds = prescriptions
        .where((m) =>
            m['inventoryId'] != null && !PatientFormHelper.isInjectable(m))
        .toList();
    final inventoryInjectables = prescriptions
        .where((m) =>
            m['inventoryId'] != null && PatientFormHelper.isInjectable(m))
        .toList();
    final customMeds = prescriptions
        .where((m) =>
            m['inventoryId'] == null && !PatientFormHelper.isInjectable(m))
        .toList();
    final customInjectables = prescriptions
        .where((m) =>
            m['inventoryId'] == null && PatientFormHelper.isInjectable(m))
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildHeader(doctorName),
                      const SizedBox(height: 20),
                      const Divider(thickness: 1.5),
                      const SizedBox(height: 20),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: labTests.isNotEmpty
                                  ? _buildLabColumn(labTests)
                                  : const SizedBox(),
                            ),
                            if (labTests.isNotEmpty) _verticalDivider(),
                            Expanded(
                              flex: 8,
                              child: _buildRightColumn(
                                patientName,
                                diagnosis,
                                inventoryMeds,
                                inventoryInjectables,
                                customMeds,
                                customInjectables,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      const Divider(color: Colors.grey),
                      const SizedBox(height: 10),
                      _buildFooter(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _hasPrintableContent && !_isPrinting
                          ? _printOnly
                          : null,
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.print),
                      label: Text(_isPrinting ? 'Printing…' : 'Print'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasPrintableContent
                            ? Colors.blue[700]
                            : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed:
                          !_isDispensed && !_isLoading ? _dispenseOnly : null,
                      icon: const Icon(Icons.check_circle),
                      label: Text(_isDispensed ? 'Dispensed' : 'Dispense'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isDispensed ? Colors.grey[600] : Colors.green[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

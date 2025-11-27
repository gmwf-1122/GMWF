// lib/pages/token_screen.dart
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class TokenScreen extends StatefulWidget {
  final String branchId;
  final String receptionistId;
  final Function(String cnic)? onPatientNotFound;
  final String? initialCnic;

  const TokenScreen({
    super.key,
    required this.branchId,
    required this.receptionistId,
    this.onPatientNotFound,
    this.initialCnic,
  });

  @override
  State<TokenScreen> createState() => TokenScreenState();
}

class TokenScreenState extends State<TokenScreen> {
  final TextEditingController cnicController = TextEditingController();
  final FocusNode _cnicFocusNode = FocusNode();
  bool _isLoading = false;
  String? _nextToken;
  Map<String, dynamic>? _patientData;
  List<Map<String, dynamic>> _patientsList = [];
  bool _hasTokenToday = false;

  @override
  void initState() {
    super.initState();
    _fetchNextTokenNumber();

    if (widget.initialCnic != null && widget.initialCnic!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusAndFillCnic(widget.initialCnic!);
      });
    }
  }

  @override
  void didUpdateWidget(covariant TokenScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCnic != null &&
        widget.initialCnic != oldWidget.initialCnic) {
      focusAndFillCnic(widget.initialCnic!);
    }
  }

  void focusAndFillCnic(String cnic) {
    final formatted = _formatCnic(cnic);
    cnicController.text = formatted;
    cnicController.selection = TextSelection.fromPosition(
      TextPosition(offset: formatted.length),
    );
    _searchPatient();
    _cnicFocusNode.requestFocus();
  }

  String _formatCnic(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9]'), '');
    final b = StringBuffer();
    for (int i = 0; i < d.length; i++) {
      b.write(d[i]);
      if (i == 4 || i == 11) if (i != d.length - 1) b.write('-');
    }
    return b.toString();
  }

  String _formatBP(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '';
    if (d.length <= 3) return d;
    return '${d.substring(0, 3)}/${d.substring(3)}';
  }

  Future<bool> _checkTokenExistsToday(String cnic) async {
    final today = DateFormat('ddMMyy').format(DateTime.now());
    final baseRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(today);

    final zakatSnap = await baseRef
        .collection('zakat')
        .where('patientCNIC', isEqualTo: cnic)
        .limit(1)
        .get();
    if (zakatSnap.docs.isNotEmpty) return true;

    final nonZakatSnap = await baseRef
        .collection('non-zakat')
        .where('patientCNIC', isEqualTo: cnic)
        .limit(1)
        .get();
    return nonZakatSnap.docs.isNotEmpty;
  }

  Future<void> _fetchNextTokenNumber() async {
    try {
      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyy').format(now);
      final baseRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey);

      final zakatSnap = await baseRef.collection('zakat').get();
      final nonZakatSnap = await baseRef.collection('non-zakat').get();

      final used = <int>{};
      for (var doc in [...zakatSnap.docs, ...nonZakatSnap.docs]) {
        final id = doc.id;
        if (id.contains('-')) {
          final n = int.tryParse(id.split('-').last);
          if (n != null) used.add(n);
        }
      }

      int next = 1;
      while (used.contains(next)) next++;
      final formatted = next.toString().padLeft(3, '0');
      if (mounted) setState(() => _nextToken = "$dateKey-$formatted");
    } catch (_) {}
  }

  Future<void> _searchPatient() async {
    final input = cnicController.text.trim();
    final cnicR = RegExp(r'^\d{5}-\d{7}-\d{1}$');
    final phoneR = RegExp(r'^03\d{9}$');

    if (!cnicR.hasMatch(input) && !phoneR.hasMatch(input)) {
      setState(() {
        _isLoading = false;
        _patientData = null;
        _patientsList.clear();
        _hasTokenToday = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _patientData = null;
      _patientsList.clear();
      _hasTokenToday = false;
    });

    try {
      final patientsRef = FirebaseFirestore.instance
          .collection("branches")
          .doc(widget.branchId)
          .collection("patients");

      if (cnicR.hasMatch(input)) {
        final doc = await patientsRef.doc(input).get();
        if (doc.exists) {
          _patientData = doc.data();
          _patientData!['cnic'] = input;
        }
      } else {
        final q = await patientsRef.where('phone', isEqualTo: input).get();
        _patientsList = q.docs.map((e) {
          final data = e.data();
          data['cnic'] = e.id;
          return data;
        }).toList();
        if (_patientsList.length == 1) {
          _patientData = _patientsList.first;
          _patientsList.clear();
        }
      }

      if (_patientData == null && _patientsList.isEmpty) {
        widget.onPatientNotFound?.call(input);
        setState(() {
          _isLoading = false;
          cnicController.clear();
        });
        return;
      }

      final cnic = _patientData!['cnic'] ?? input;
      final alreadyHas = await _checkTokenExistsToday(cnic);
      setState(() => _hasTokenToday = alreadyHas);

      if (!alreadyHas) await _fetchNextTokenNumber();
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestEditPatient() async {
    if (_patientData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No patient selected to edit!")),
      );
      return;
    }

    final cnicCtrl = TextEditingController(text: _patientData!['cnic'] ?? '');
    final nameCtrl = TextEditingController(text: _patientData!['name'] ?? '');
    final phoneCtrl = TextEditingController(text: _patientData!['phone'] ?? '');
    final ageCtrl =
        TextEditingController(text: _patientData!['age']?.toString() ?? '');
    final dobCtrl = TextEditingController(text: _patientData!['dob'] ?? '');
    final bloodGroupCtrl =
        TextEditingController(text: _patientData!['bloodGroup'] ?? '');

    String selectedStatus = (_patientData!['status'] ?? 'Zakat').toString();
    String selectedGender = (_patientData!['gender'] ?? 'Male').toString();

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: Colors.green.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:
              const Text("Edit Patient", style: TextStyle(color: Colors.green)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: cnicCtrl,
                    decoration: const InputDecoration(
                        labelText: "CNIC (xxxxx-xxxxxxx-x)")),
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: "Name")),
                TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: "Phone")),
                TextField(
                    controller: ageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Age")),
                TextField(
                  controller: dobCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _formatDobLive(dobCtrl),
                  decoration: const InputDecoration(
                      labelText: "DOB (dd-MM-yyyy)", hintText: "01-01-1990"),
                ),
                TextField(
                    controller: bloodGroupCtrl,
                    decoration:
                        const InputDecoration(labelText: "Blood Group")),
                const SizedBox(height: 16),
                const Text("Status",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text("Zakat"),
                        value: "Zakat",
                        groupValue: selectedStatus,
                        onChanged: (v) =>
                            setStateDialog(() => selectedStatus = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text("Non-Zakat"),
                        value: "Non-Zakat",
                        groupValue: selectedStatus,
                        onChanged: (v) =>
                            setStateDialog(() => selectedStatus = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text("Gender",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text("Male"),
                        value: "Male",
                        groupValue: selectedGender,
                        onChanged: (v) =>
                            setStateDialog(() => selectedGender = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text("Female"),
                        value: "Female",
                        groupValue: selectedGender,
                        onChanged: (v) =>
                            setStateDialog(() => selectedGender = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text("Other"),
                        value: "Other",
                        groupValue: selectedGender,
                        onChanged: (v) =>
                            setStateDialog(() => selectedGender = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  "Changes will be applied immediately and sent for supervisor approval.\nIf rejected, they will be rolled back.",
                  style: TextStyle(color: Colors.red, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text("Cancel", style: TextStyle(color: Colors.green)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Update & Request",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    final newData = {
      'cnic': cnicCtrl.text.trim(),
      'name': nameCtrl.text.trim(),
      'phone': phoneCtrl.text.trim(),
      'status': selectedStatus,
      'bloodGroup': bloodGroupCtrl.text.trim(),
      'age': int.tryParse(ageCtrl.text.trim()) ?? 0,
      'gender': selectedGender,
      'dob': dobCtrl.text.trim(),
    };

    final patientRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('patients')
        .doc(_patientData!['cnic']);

    try {
      await patientRef.update(newData);

      await FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('edit_requests')
          .add({
        'requestType': 'patient_edit',
        'status': 'pending',
        'patientCNIC': _patientData!['cnic'],
        'originalData': _patientData,
        'proposedData': newData,
        'requestedBy': widget.receptionistId,
        'requestedAt': FieldValue.serverTimestamp(),
        'targetRole': 'supervisor',
      });

      setState(() => _patientData = {..._patientData!, ...newData});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Edit applied & request sent for approval."),
            backgroundColor: Colors.orange),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Failed: $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _generateToken({
    required String bp,
    required String temp,
    required String sugar,
    required String weight,
  }) async {
    if (_patientData == null) return;

    final cnic = _patientData!['cnic'] ?? '';
    if (await _checkTokenExistsToday(cnic)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Token already issued today!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyy').format(now);
      final status = (_patientData!['status'] ?? 'Zakat').toString().trim();
      final queueType = status.toLowerCase() == 'zakat' ? 'zakat' : 'non-zakat';

      final baseRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('serials')
          .doc(dateKey);

      final totalSnap =
          await baseRef.collection('zakat').get().then((z) => z.docs.length) +
              await baseRef
                  .collection('non-zakat')
                  .get()
                  .then((nz) => nz.docs.length);

      final nextNum = totalSnap + 1;
      final serial = nextNum.toString().padLeft(3, '0');
      final entryId = "$dateKey-$serial";

      await baseRef.collection(queueType).doc(entryId).set({
        'branchId': widget.branchId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': widget.receptionistId,
        'patientCNIC': cnic,
        'patientName': _patientData!['name'],
        'phone': _patientData!['phone'] ?? '',
        'serial': entryId,
        'queueType': queueType,
        'vitals': {
          'bp': bp,
          'sugar': sugar,
          'temp': temp,
          'tempUnit': 'C',
          'weight': weight
        },
        'status': 'waiting',
      });

      await _fetchNextTokenNumber();

      setState(() {
        _patientData = null;
        _patientsList.clear();
        cnicController.clear();
        _hasTokenToday = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Token $entryId issued!"),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showVitalsDialog() {
    final bpCtrl = TextEditingController();
    final tempCtrl = TextEditingController();
    final sugarCtrl = TextEditingController();
    final weightCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: Colors.green.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.monitor_heart, color: Colors.green),
              SizedBox(width: 8),
              Text("Enter Vitals",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: bpCtrl,
                  maxLength: 7,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    TextInputFormatter.withFunction((_, nv) {
                      final f = _formatBP(nv.text);
                      return TextEditingValue(
                          text: f,
                          selection: TextSelection.collapsed(offset: f.length));
                    })
                  ],
                  decoration: const InputDecoration(
                    labelText: "BP (80/120)",
                    counterText: "",
                    prefixIcon: Icon(Icons.favorite, color: Colors.green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.green, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  maxLength: 5, // max: XXX.X or XX.X = 4 chars + optional dot
                  onChanged: (_) => _formatTempLive(tempCtrl),

                  onEditingComplete: () {
                    // Auto add .0 if user didn't type decimal
                    _formatTempLive(tempCtrl, finalize: true);
                  },

                  decoration: const InputDecoration(
                    labelText: "Temperature (°C)",
                    hintText: "98.6",
                    counterText: "",
                    prefixIcon: Icon(Icons.thermostat, color: Colors.green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sugarCtrl,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Blood Sugar (mg/dL)",
                    counterText: "",
                    prefixIcon: Icon(Icons.bloodtype, color: Colors.green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.green, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weightCtrl,
                  maxLength: 3,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: "Weight (kg)",
                    counterText: "",
                    prefixIcon: Icon(Icons.monitor_weight, color: Colors.green),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.green, width: 2)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text("Cancel", style: TextStyle(color: Colors.green)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final bp = bpCtrl.text.trim();
                final temp = tempCtrl.text.trim();
                final sugar = sugarCtrl.text.trim();
                final weight = weightCtrl.text.trim();

                if (bp.isEmpty ||
                    temp.isEmpty ||
                    sugar.isEmpty ||
                    weight.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Please fill all fields!"),
                        backgroundColor: Colors.red),
                  );
                  return;
                }

                final tempVal = double.tryParse(temp);
                if (tempVal == null || tempVal < 90.0 || tempVal > 107.0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Temperature must be between 90.0 and 107.0 °C"),
                        backgroundColor: Colors.red),
                  );
                  return;
                }

                if (!RegExp(r'^\d{2,3}\.\d$').hasMatch(temp)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Enter valid temperature (e.g., 98.6)"),
                        backgroundColor: Colors.red),
                  );
                  return;
                }

                Navigator.pop(context);
                _generateToken(
                    bp: bp, temp: temp, sugar: sugar, weight: weight);
              },
              icon: const Icon(Icons.local_hospital),
              label: const Text("Issue Token"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _formatDobLive(TextEditingController controller) {
    final original = controller.text;
    final cursor = controller.selection.baseOffset;

    String cleaned = original.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length > 8) cleaned = cleaned.substring(0, 8);

    final buffer = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      if (i == 2 || i == 4) buffer.write('-');
      buffer.write(cleaned[i]);
    }

    final newText = buffer.toString();
    final newCursor = cursor + (newText.length - original.length);

    if (newText != original) {
      controller.value = TextEditingValue(
        text: newText,
        selection:
            TextSelection.collapsed(offset: newCursor.clamp(0, newText.length)),
      );
    }
  }

  void _formatTempLive(TextEditingController controller,
      {bool finalize = false}) {
    final original = controller.text;
    final cursor = controller.selection.baseOffset;

    // digits only
    String cleaned = original.replaceAll(RegExp(r'[^0-9]'), '');

    // Allow clearing field
    if (cleaned.isEmpty) {
      controller.value = const TextEditingValue(
        text: "",
        selection: TextSelection.collapsed(offset: 0),
      );
      return;
    }

    // Must start with 1 or 9
    if (!(cleaned.startsWith('1') || cleaned.startsWith('9'))) {
      controller.value = const TextEditingValue(
        text: "",
        selection: TextSelection.collapsed(offset: 0),
      );
      return;
    }

    // Required digits before decimal
    int maxInt = cleaned.startsWith('9') ? 2 : 3;

    // Maximum allowed digits = maxInt + 1 decimal digit
    int maxTotal = maxInt + 1;
    if (cleaned.length > maxTotal) {
      cleaned = cleaned.substring(0, maxTotal);
    }

    // Split
    String intPart;
    String decPart = "";

    if (cleaned.length > maxInt) {
      intPart = cleaned.substring(0, maxInt);
      decPart = cleaned.substring(maxInt);
    } else {
      intPart = cleaned;
    }

    // If user leaves field AND no decimal → add .0
    if (finalize && decPart.isEmpty) {
      decPart = "0";
    }

    // Build final text
    String newText = decPart.isEmpty ? intPart : "$intPart.$decPart";

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  Widget _nextTokenLiveWidget() {
    final now = DateTime.now();
    final dateKey = DateFormat('ddMMyy').format(now);
    final baseRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('serials')
        .doc(dateKey);

    return StreamBuilder<List<QuerySnapshot>>(
      stream: CombineLatestStream.list([
        baseRef.collection('zakat').snapshots(),
        baseRef.collection('non-zakat').snapshots(),
      ]),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Text("Loading…",
              style: TextStyle(color: Colors.white70));

        final used = <int>{};
        for (var doc in [...snap.data![0].docs, ...snap.data![1].docs]) {
          final id = doc.id;
          if (id.contains('-')) {
            final n = int.tryParse(id.split('-').last);
            if (n != null) used.add(n);
          }
        }

        int next = 1;
        while (used.contains(next)) next++;
        final formatted = next.toString().padLeft(3, '0');
        final token = "$dateKey-$formatted";

        if (_nextToken != token) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _nextToken = token);
          });
        }

        return Text("Next Token: $token",
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 20));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final containerWidth = isMobile ? double.infinity : 460.0;

    return Container(
      color: Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: containerWidth,
            margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _nextTokenLiveWidget(),
                const SizedBox(height: 20),
                const Text("Issue Token",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 30),

                // Search Field
                TextField(
                  controller: cnicController,
                  focusNode: _cnicFocusNode,
                  maxLength: 15,
                  keyboardType: TextInputType.number,
                  cursorColor: Colors.white, // White caret
                  onChanged: (v) {
                    final d = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (d.startsWith('03') && d.length <= 11) {
                      cnicController.value = TextEditingValue(
                          text: d,
                          selection: TextSelection.collapsed(offset: d.length));
                    } else if (d.length <= 13) {
                      final f = _formatCnic(d);
                      cnicController.value = TextEditingValue(
                          text: f,
                          selection: TextSelection.collapsed(offset: f.length));
                    }
                  },
                  onSubmitted: (_) => _searchPatient(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "CNIC or Phone",
                    counterText: "",
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.badge, color: Colors.white),
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.search, color: Colors.white),
                        onPressed: _searchPatient),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white70)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Colors.white, width: 2)),
                  ),
                ),
                const SizedBox(height: 15),

                if (_patientsList.isNotEmpty)
                  ..._patientsList.map((p) => Card(
                        color: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          title: Text(p['name'] ?? '—',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              "CNIC: ${p['cnic'] ?? '-'} | Phone: ${p['phone'] ?? '-'}",
                              style: const TextStyle(color: Colors.white70)),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white),
                            onPressed: () async {
                              setState(() {
                                _patientData = p;
                                _patientsList.clear();
                                _hasTokenToday = false;
                              });
                              final cnic = p['cnic'] ?? '';
                              final hasToken =
                                  await _checkTokenExistsToday(cnic);
                              if (mounted)
                                setState(() => _hasTokenToday = hasToken);
                            },
                            child: const Text("Select"),
                          ),
                        ),
                      )),

                if (_patientData != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white54),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(_patientData!['name'] ?? '—',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.edit, color: Colors.orange),
                              tooltip: "Edit Patient Data",
                              onPressed: _requestEditPatient,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text("CNIC: ${_patientData!['cnic'] ?? '-'}",
                            style: const TextStyle(color: Colors.white70)),
                        Text("Phone: ${_patientData!['phone'] ?? '-'}",
                            style: const TextStyle(color: Colors.white70)),
                        Text("Status: ${_patientData!['status'] ?? '-'}",
                            style: const TextStyle(color: Colors.amber)),
                        const SizedBox(height: 12),
                        if (_hasTokenToday)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text("Warning: Token already issued today!",
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold)),
                          ),
                        const SizedBox(height: 12),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed:
                                _hasTokenToday ? null : _showVitalsDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _hasTokenToday ? Colors.grey : Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 30),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.local_hospital),
                            label: Text(_hasTokenToday
                                ? "Token Already Issued"
                                : "Enter Vitals & Issue Token"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 25),
                if (_isLoading)
                  const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

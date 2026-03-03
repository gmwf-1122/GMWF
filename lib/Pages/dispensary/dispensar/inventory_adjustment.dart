import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class InventoryAdjustmentPage extends StatefulWidget {
  final String branchId;
  const InventoryAdjustmentPage({super.key, required this.branchId});

  @override
  State<InventoryAdjustmentPage> createState() => _InventoryAdjustmentPageState();
}

class _InventoryAdjustmentPageState extends State<InventoryAdjustmentPage>
    with TickerProviderStateMixin {
  // ── Palette ───────────────────────────────────────────────────────────────
  static const _teal      = Color(0xFF00695C);
  static const _bg        = Color(0xFFF1F8F6);
  static const _white     = Colors.white;
  static const _green50   = Color(0xFFE8F5E9);
  static const _green100  = Color(0xFFC8E6C9);
  static const _green600  = Color(0xFF43A047);
  static const _red       = Color(0xFFC62828);
  static const _redLight  = Color(0xFFFFEBEE);
  static const _orange    = Color(0xFFE65100);
  static const _textDark  = Color(0xFF1B2631);
  static const _textMid   = Color(0xFF4A5568);
  static const _textLight = Color(0xFF718096);
  static const _border    = Color(0xFFB2DFDB);
  static const _shadow    = Color(0x1800695C);

  List<Map<String, dynamic>> inventoryItems = [];
  List<Map<String, dynamic>> searchResults  = [];

  final searchCtrl         = TextEditingController();
  final nameCtrl           = TextEditingController();
  final doseCtrl           = TextEditingController();
  final quantityCtrl       = TextEditingController();
  final priceCtrl          = TextEditingController();
  final expiryCtrl         = TextEditingController();
  final classificationCtrl = TextEditingController();
  final reasonCtrl         = TextEditingController();

  Map<String, dynamic>? selectedItem;
  String?               selectedType;
  String?               _branchName;
  String?               _selectedDose;

  late AnimationController _slideCtrl;
  late Animation<Offset>   _slideAnim;

  final List<String> medicineTypes = [
    'Tablet','Capsule','Syrup','Injection',
    'Drip','Drip Set','Syringe','Nebulization','Others',
  ];

  final Map<String, List<String>> _doseOptions = {
    'Capsule':   ['5 mg','10 mg','20 mg','50 mg','100 mg','250 mg','500 mg'],
    'Syrup':     ['5 ml','10 ml','15 ml','20 ml','30 ml','60 ml','90 ml','120 ml','250 ml'],
    'Injection': ['1cc','2cc','3cc','5cc','10cc'],
    'Drip':      ['100 ml','250 ml','450 ml','500 ml','1000 ml'],
  };

  bool _hasDd(String? t)   => _doseOptions.containsKey(t);
  bool _hasFree(String? t) =>
      t != null && !_doseOptions.containsKey(t) && t != 'Drip Set' && t != 'Syringe';

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _loadBranchName();
    _loadInventory();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    searchCtrl.dispose(); nameCtrl.dispose(); doseCtrl.dispose();
    quantityCtrl.dispose(); priceCtrl.dispose(); expiryCtrl.dispose();
    classificationCtrl.dispose(); reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranchName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).get();
      if (doc.exists && mounted) setState(() => _branchName = doc['name'] ?? 'Branch');
    } catch (_) {}
  }

  Future<void> _loadInventory() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).collection('inventory').get();
      final items = snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // FIX: real Firestore doc ID
        return data;
      }).toList();
      setState(() { inventoryItems = items; searchResults = List.from(items); });
    } catch (e) { _snack('Failed to load inventory', err: true); }
  }

  void _filterSearch(String query) => setState(() {
    searchResults = query.trim().isEmpty
        ? List.from(inventoryItems)
        : inventoryItems.where((item) =>
            (item['name'] ?? '').toString().toLowerCase().contains(query.toLowerCase())).toList();
  });

  void _selectItem(Map<String, dynamic> item) {
    final type = item['type'] ?? 'Others';
    final dose = (item['dose'] ?? '').toString().trim();
    setState(() {
      selectedItem         = Map.from(item);
      selectedType         = type;
      nameCtrl.text        = item['name'] ?? '';
      quantityCtrl.text    = (item['quantity'] ?? 0).toString();
      priceCtrl.text       = (item['price'] ?? 0).toString();
      expiryCtrl.text      = item['expiryDate'] ?? '';
      classificationCtrl.text = item['classification'] ?? '';
      reasonCtrl.clear();
      if (_hasDd(type)) {
        _selectedDose = _doseOptions[type]!.contains(dose) ? dose : null;
        doseCtrl.clear();
      } else if (_hasFree(type)) {
        doseCtrl.text = dose;
        _selectedDose = null;
      } else {
        doseCtrl.clear(); _selectedDose = null;
      }
    });
    _slideCtrl.forward(from: 0);
  }

  void _clearSelection() => setState(() {
    selectedItem = null; selectedType = null; _selectedDose = null;
    nameCtrl.clear(); doseCtrl.clear(); quantityCtrl.clear();
    priceCtrl.clear(); expiryCtrl.clear(); classificationCtrl.clear(); reasonCtrl.clear();
  });

  // ── Submit edit ───────────────────────────────────────────────────────────
  Future<void> _submitAdjustment() async {
    if (selectedItem == null) return;
    final newName  = nameCtrl.text.trim();
    final newType  = selectedType!;
    final newQty   = int.tryParse(quantityCtrl.text.trim());
    final newPrice = int.tryParse(priceCtrl.text.trim());
    final reason   = reasonCtrl.text.trim();
    if (newName.isEmpty || newQty == null || newPrice == null || reason.isEmpty) {
      _snack('Please fill all required fields', err: true); return;
    }
    String newDose = '';
    if (_hasDd(newType))   newDose = _selectedDose ?? '';
    if (_hasFree(newType)) newDose = doseCtrl.text.trim();

    final confirmed = await _showConfirmDialog(newName, newType, newQty, newPrice, newDose, reason);
    if (!confirmed) return;

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).collection('users').doc(user.uid).get();
      final username = userDoc.data()?['username'] ?? user.email ?? 'Unknown';

      await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).collection('edit_requests').add({
        'requestType':   'edit_medicine',
        'requester':     user.uid,
        'requesterName': username,
        'requestedAt':   FieldValue.serverTimestamp(),
        'status':        'pending',
        'reason':        reason,
        'items': [{
          'id':             selectedItem!['id'],
          'name':           newName,
          'name_lower':     newName.toLowerCase(),
          'type':           newType,
          'dose':           newDose,
          'quantity':       newQty,
          'price':          newPrice,
          'expiryDate':     expiryCtrl.text.trim(),
          'classification': classificationCtrl.text.trim(),
        }],
      });
      _snack('Edit request sent for approval!');
      if (mounted) Navigator.pop(context);
    } catch (e) { _snack('Error: $e', err: true); }
  }

  // ── Submit delete ─────────────────────────────────────────────────────────
  Future<void> _submitDelete() async {
    if (selectedItem == null) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) { _snack('Reason is required for deletion', err: true); return; }
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).collection('users').doc(user.uid).get();
      final username = userDoc.data()?['username'] ?? user.email ?? 'Unknown';

      await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).collection('edit_requests').add({
        'requestType':   'delete_medicine',
        'requester':     user.uid,
        'requesterName': username,
        'requestedAt':   FieldValue.serverTimestamp(),
        'status':        'pending',
        'reason':        reason,
        'items': [{
          'id':             selectedItem!['id'],
          'name':           selectedItem!['name'] ?? '',
          'name_lower':     (selectedItem!['name'] ?? '').toString().toLowerCase(),
          'type':           selectedItem!['type'] ?? '',
          'dose':           selectedItem!['dose'] ?? '',
          'quantity':       selectedItem!['quantity'] ?? 0,
          'price':          selectedItem!['price'] ?? 0,
          'expiryDate':     selectedItem!['expiryDate'] ?? '',
          'classification': selectedItem!['classification'] ?? '',
        }],
      });
      _snack('Delete request sent for approval!');
      if (mounted) Navigator.pop(context);
    } catch (e) { _snack('Error: $e', err: true); }
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────
  Future<bool> _showConfirmDialog(String name, String type, int qty,
      int price, String dose, String reason) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: _white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: _teal,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.fact_check_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    const Text('Confirm Edit Request',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  ]),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _confirmRow('Medicine', name),
                    _confirmRow('Type', type),
                    if (dose.isNotEmpty) _confirmRow('Dose', dose),
                    _confirmRow('Quantity', qty.toString()),
                    _confirmRow('Price', 'PKR $price'),
                    _confirmRow('Reason', reason),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _green50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _green100),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: _teal, size: 16),
                        const SizedBox(width: 8),
                        const Expanded(child: Text(
                          'This will be sent to your supervisor for approval.',
                          style: TextStyle(color: _teal, fontSize: 12),
                        )),
                      ]),
                    ),
                  ]),
                ),
                // Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _teal),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Back', style: TextStyle(color: _teal, fontWeight: FontWeight.w600)),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('Submit',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )),
                  ]),
                ),
              ]),
            ),
          ),
        ) ??
        false;
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _redLight, shape: BoxShape.circle),
              child: const Icon(Icons.delete_forever_rounded, color: _red, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Delete Medicine?',
                style: TextStyle(color: _textDark, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '${selectedItem?['name'] ?? ''} will be permanently removed after supervisor approval.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textMid, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel', style: TextStyle(color: _textMid, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () { Navigator.pop(ctx); _submitDelete(); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  void _snack(String msg, {bool err = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: err ? _red : _teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));

  IconData _typeIcon(String? t) => switch (t) {
    'Tablet'       => FontAwesomeIcons.tablets,
    'Capsule'      => FontAwesomeIcons.capsules,
    'Syrup'        => FontAwesomeIcons.bottleDroplet,
    'Injection'    => FontAwesomeIcons.syringe,
    'Drip'         => FontAwesomeIcons.bottleDroplet,
    'Drip Set'     => FontAwesomeIcons.kitMedical,
    'Syringe'      => FontAwesomeIcons.syringe,
    'Nebulization' => FontAwesomeIcons.wind,
    _              => FontAwesomeIcons.pills,
  };

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: _buildAppBar(),
    body: AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: selectedItem == null
          ? _buildSearchView()
          : SlideTransition(position: _slideAnim, child: _buildForm()),
    ),
  );

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: _teal,
    elevation: 4,
    shadowColor: _shadow,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
      onPressed: selectedItem != null ? _clearSelection : () => Navigator.pop(context),
    ),
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Adjust Inventory',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      Text(_branchName ?? 'Loading...',
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
  );

  // ── Search view ───────────────────────────────────────────────────────────
  Widget _buildSearchView() => Column(
    key: const ValueKey('search'),
    children: [
      Container(
        color: _white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: TextField(
          controller: searchCtrl,
          onChanged: _filterSearch,
          cursorColor: _teal,
          style: const TextStyle(color: _textDark, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search medicine to adjust...',
            hintStyle: const TextStyle(color: _textLight),
            prefixIcon: const Icon(Icons.search_rounded, color: _teal, size: 20),
            filled: true, fillColor: _green50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
      ),
      Expanded(
        child: searchResults.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 12),
                const Text('No medicines found',
                    style: TextStyle(color: _textLight, fontSize: 15)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: searchResults.length,
                itemBuilder: (ctx, i) {
                  final item   = searchResults[i];
                  final qty    = item['quantity'] ?? 0;
                  final type   = item['type'] ?? '';
                  final lowStk = (type == 'Big Bottle' ? qty < 3 : qty < 10);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: _white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: lowStk ? _red.withOpacity(0.3) : _green100),
                      boxShadow: [BoxShadow(color: _shadow, blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: InkWell(
                      onTap: () => _selectItem(item),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: _green50, borderRadius: BorderRadius.circular(10)),
                            child: Icon(_typeIcon(type), color: _teal, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item['name'] ?? 'Unknown',
                                style: const TextStyle(color: _textDark, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 4),
                            Row(children: [
                              _chip(type, _teal),
                              const SizedBox(width: 6),
                              if ((item['dose'] ?? '').toString().isNotEmpty)
                                _chip(item['dose'].toString(), _textMid),
                            ]),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Row(children: [
                              if (lowStk) const Icon(Icons.warning_rounded, color: _red, size: 14),
                              const SizedBox(width: 4),
                              Text('Qty: $qty', style: TextStyle(
                                  color: lowStk ? _red : _green600,
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                            ]),
                            const SizedBox(height: 4),
                            const Icon(Icons.chevron_right_rounded, color: _teal, size: 20),
                          ]),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );

  // ── Adjustment form ───────────────────────────────────────────────────────
  Widget _buildForm() {
    final hasDd   = _hasDd(selectedType);
    final hasFree = _hasFree(selectedType);
    final doseList = _doseOptions[selectedType] ?? [];

    return SingleChildScrollView(
      key: const ValueKey('form'),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Selected item banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _green50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _green100),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _green100)),
              child: Icon(_typeIcon(selectedItem?['type']), color: _teal, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selectedItem?['name'] ?? '',
                  style: const TextStyle(color: _teal, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text('Original: Qty ${selectedItem?['quantity'] ?? 0} • PKR ${selectedItem?['price'] ?? 0}',
                  style: const TextStyle(color: _textMid, fontSize: 12)),
            ])),
            const Icon(Icons.edit_note_rounded, color: _teal, size: 20),
          ]),
        ),
        const SizedBox(height: 20),

        _sectionLabel('Edit Fields'),
        const SizedBox(height: 12),

        _field(nameCtrl, 'Medicine Name *', Icons.medication_rounded),
        const SizedBox(height: 13),

        // Type dropdown
        DropdownButtonFormField<String>(
          value: selectedType,
          dropdownColor: _white,
          style: const TextStyle(color: _textDark, fontSize: 14),
          decoration: _inputDec('Type *', FontAwesomeIcons.capsules),
          items: medicineTypes.map((t) => DropdownMenuItem(value: t,
              child: Row(children: [
                Icon(_typeIcon(t), size: 13, color: _teal),
                const SizedBox(width: 8), Text(t),
              ]))).toList(),
          onChanged: (v) { if (v != null) setState(() { selectedType = v; _selectedDose = null; doseCtrl.clear(); }); },
        ),
        const SizedBox(height: 13),

        if (hasDd) ...[
          DropdownButtonFormField<String>(
            value: _selectedDose,
            dropdownColor: _white,
            style: const TextStyle(color: _textDark, fontSize: 14),
            decoration: _inputDec('Dose *', Icons.science_rounded),
            hint: const Text('Select dose', style: TextStyle(color: _textLight)),
            items: doseList.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
            onChanged: (v) => setState(() => _selectedDose = v),
          ),
          const SizedBox(height: 13),
        ],
        if (hasFree) ...[
          _field(doseCtrl, selectedType == 'Nebulization' ? 'Dose per session *' : 'Dose / Variant',
              Icons.science_rounded),
          const SizedBox(height: 13),
        ],

        Row(children: [
          Expanded(child: _field(quantityCtrl, 'Quantity *', Icons.inventory_2_rounded,
              keyboard: TextInputType.number)),
          const SizedBox(width: 12),
          Expanded(child: _field(priceCtrl, 'Price (PKR) *', Icons.currency_rupee_rounded,
              keyboard: TextInputType.number)),
        ]),
        const SizedBox(height: 13),
        _field(expiryCtrl, 'Expiry Date', Icons.calendar_today_rounded),
        const SizedBox(height: 13),
        _field(classificationCtrl, 'Classification', Icons.label_rounded),
        const SizedBox(height: 20),

        _sectionLabel('Reason for Adjustment *', color: _orange),
        const SizedBox(height: 10),
        TextField(
          controller: reasonCtrl,
          maxLines: 4, cursorColor: _teal,
          style: const TextStyle(color: _textDark, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Explain why you are making this adjustment...',
            hintStyle: const TextStyle(color: _textLight, fontSize: 13),
            filled: true, fillColor: _green50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _teal, width: 1.5)),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _submitAdjustment,
            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            label: const Text('Submit Edit Request',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showDeleteConfirmation,
            icon: const Icon(Icons.delete_forever_rounded, color: _red, size: 18),
            label: const Text('Request Deletion',
                style: TextStyle(color: _red, fontWeight: FontWeight.bold, fontSize: 15)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _red.withOpacity(0.6), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  InputDecoration _inputDec(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _textLight, fontSize: 13),
    prefixIcon: Icon(icon, color: _teal, size: 18),
    filled: true, fillColor: _green50,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _teal, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
  );

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard}) =>
      TextField(
        controller: ctrl, keyboardType: keyboard, cursorColor: _teal,
        style: const TextStyle(color: _textDark, fontSize: 15),
        decoration: _inputDec(label, icon),
      );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _sectionLabel(String text, {Color? color}) => Row(children: [
    Container(width: 4, height: 18,
        decoration: BoxDecoration(color: color ?? _teal, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 10),
    Text(text, style: TextStyle(color: color ?? _teal, fontSize: 15, fontWeight: FontWeight.bold)),
  ]);

  Widget _confirmRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: _textLight, fontSize: 13))),
      Expanded(child: Text(value,
          style: const TextStyle(color: _textDark, fontWeight: FontWeight.w600, fontSize: 13))),
    ]),
  );
}
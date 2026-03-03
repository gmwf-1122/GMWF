import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class InventoryUpdatePage extends StatefulWidget {
  final String branchId;
  const InventoryUpdatePage({super.key, required this.branchId});

  @override
  State<InventoryUpdatePage> createState() => _InventoryUpdatePageState();
}

class _InventoryUpdatePageState extends State<InventoryUpdatePage>
    with TickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _qtyCtrl   = TextEditingController(text: '1');
  final _expCtrl   = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _doseCtrl  = TextEditingController();

  String  _type         = 'Tablet';
  String? _selectedDose;
  bool    _isSearching  = false;
  List<Map<String, dynamic>> _searchResults = [];
  final   List<Map<String, dynamic>> _itemsToAdd = [];

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _teal       = Color(0xFF00695C);
  static const _tealDark   = Color(0xFF004D40);
  static const _bg         = Color(0xFFF1F8F6);
  static const _white      = Colors.white;
  static const _green50    = Color(0xFFE8F5E9);
  static const _green100   = Color(0xFFC8E6C9);
  static const _green600   = Color(0xFF43A047);
  static const _red        = Color(0xFFC62828);
  static const _orange     = Color(0xFFE65100);
  static const _textDark   = Color(0xFF1B2631);
  static const _textMid    = Color(0xFF4A5568);
  static const _textLight  = Color(0xFF718096);
  static const _border     = Color(0xFFB2DFDB);
  static const _shadow     = Color(0x1800695C);

  final List<String> _allTypes = [
    'Tablet','Capsule','Syrup','Injection',
    'Drip','Drip Set','Syringe','Nebulization','Others',
  ];

  final Map<String, List<String>> _doseOptions = {
    'Capsule':   ['5 mg','10 mg','20 mg','50 mg','100 mg','250 mg','500 mg'],
    'Syrup':     ['5 ml','10 ml','15 ml','20 ml','30 ml','60 ml','90 ml','120 ml','250 ml'],
    'Injection': ['1cc','2cc','3cc','5cc','10cc'],
    'Drip':      ['100 ml','250 ml','450 ml','500 ml','1000 ml'],
  };

  bool get _hasDoseDropdown  => _doseOptions.containsKey(_type);
  bool get _usesFreeTextDose =>
      !_doseOptions.containsKey(_type) && _type != 'Drip Set' && _type != 'Syringe';

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _nameCtrl.dispose(); _qtyCtrl.dispose(); _expCtrl.dispose();
    _priceCtrl.dispose(); _doseCtrl.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────────
  void _searchMedicine(String query) async {
    if (query.trim().isEmpty) { setState(() => _searchResults = []); return; }
    setState(() => _isSearching = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).collection('inventory')
          .where('name_lower', isGreaterThanOrEqualTo: query.toLowerCase())
          .where('name_lower', isLessThanOrEqualTo: '${query.toLowerCase()}\uf8ff')
          .limit(6).get();
      setState(() {
        _searchResults = snap.docs.map((d) => d.data()).toList();
        _isSearching   = false;
      });
    } catch (_) { setState(() => _isSearching = false); }
  }

  void _selectMedicine(Map<String, dynamic> med) {
    final newType = med['type'] ?? 'Tablet';
    setState(() {
      _nameCtrl.text  = med['name'] ?? '';
      _type           = newType;
      _selectedDose   = null;
      _doseCtrl.clear();
      _priceCtrl.text = (med['price'] ?? '').toString();
      _searchResults  = [];
      if (_hasDoseDropdown) {
        final d    = med['dose']?.toString().trim();
        final list = _doseOptions[_type] ?? [];
        _selectedDose = (d != null && list.contains(d)) ? d : null;
      } else if (_usesFreeTextDose) {
        _doseCtrl.text = med['dose']?.toString() ?? '';
      }
    });
  }

  // ── Add / edit / remove ───────────────────────────────────────────────────
  void _addItem() {
    if (!_formKey.currentState!.validate()) return;
    final name  = _nameCtrl.text.trim();
    final qty   = int.tryParse(_qtyCtrl.text) ?? 1;
    final price = int.tryParse(_priceCtrl.text) ?? 0;
    final exp   = _expCtrl.text.trim();
    final dose  = _hasDoseDropdown
        ? (_selectedDose ?? '')
        : (_usesFreeTextDose ? _doseCtrl.text.trim() : '');

    final newItem = {'name': name, 'type': _type, 'dose': dose,
        'quantity': qty, 'price': price, 'expiryDate': exp};
    final isDupe = _itemsToAdd.any((i) =>
        i['name'] == name && i['type'] == _type &&
        i['dose'] == dose && i['expiryDate'] == exp);
    if (isDupe) { _snack('Already added!', err: true); return; }
    setState(() { _itemsToAdd.add(newItem); _resetForm(); });
  }

  void _resetForm() {
    _nameCtrl.clear(); _qtyCtrl.text = '1'; _expCtrl.clear();
    _priceCtrl.clear(); _doseCtrl.clear();
    _type = 'Tablet'; _selectedDose = null; _searchResults = [];
  }

  void _removeItem(int i) => setState(() => _itemsToAdd.removeAt(i));

  void _editItem(int index) {
    final item         = Map<String, dynamic>.from(_itemsToAdd[index]);
    final eNameCtrl    = TextEditingController(text: item['name']);
    final eQtyCtrl     = TextEditingController(text: item['quantity'].toString());
    final ePriceCtrl   = TextEditingController(text: item['price'].toString());
    final eExpCtrl     = TextEditingController(text: item['expiryDate']);
    final eDoseCtrl    = TextEditingController(text: item['dose'] ?? '');
    String eType       = item['type'];
    String? eDose      = item['dose'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final hasDd   = _doseOptions.containsKey(eType);
        final hasFree = !_doseOptions.containsKey(eType) && eType != 'Drip Set' && eType != 'Syringe';
        return Dialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                decoration: const BoxDecoration(
                  color: _teal,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 19),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Edit Item',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              // Fields
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  _dlgField(eNameCtrl, 'Medicine Name', Icons.medication_rounded),
                  const SizedBox(height: 13),
                  _dlgDropdown<String>(label: 'Type', value: eType, items: _allTypes,
                      onChanged: (v) { if (v != null) setS(() { eType = v; eDose = null; eDoseCtrl.clear(); }); }),
                  if (hasDd) ...[
                    const SizedBox(height: 13),
                    _dlgDropdown<String>(label: 'Dose', value: eDose,
                        items: _doseOptions[eType]!, hint: 'Select dose',
                        onChanged: (v) => setS(() => eDose = v)),
                  ],
                  if (hasFree) ...[
                    const SizedBox(height: 13),
                    _dlgField(eDoseCtrl, 'Dose / Description', Icons.science_rounded),
                  ],
                  const SizedBox(height: 13),
                  Row(children: [
                    Expanded(child: _dlgField(eQtyCtrl, 'Quantity', Icons.inventory_2_rounded,
                        keyboard: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly])),
                    const SizedBox(width: 12),
                    Expanded(child: _dlgField(ePriceCtrl, 'Price (PKR)', Icons.currency_rupee_rounded,
                        keyboard: TextInputType.number,
                        formatters: [FilteringTextInputFormatter.digitsOnly])),
                  ]),
                  const SizedBox(height: 13),
                  _dlgField(eExpCtrl, 'Expiry (dd-MM-yyyy)', Icons.calendar_today_rounded,
                      keyboard: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly, ExpiryDateFormatter()]),
                ]),
              ),
              // Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _teal),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: _teal, fontWeight: FontWeight.w600)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                    onPressed: () {
                      final err = ExpiryDateFormatter.validate(eExpCtrl.text);
                      if (err != null) { _snack(err, err: true); return; }
                      setState(() {
                        _itemsToAdd[index] = {
                          'name': eNameCtrl.text.trim(), 'type': eType,
                          'dose': hasDd ? (eDose ?? '') : eDoseCtrl.text.trim(),
                          'quantity': int.tryParse(eQtyCtrl.text) ?? 1,
                          'price': int.tryParse(ePriceCtrl.text) ?? 0,
                          'expiryDate': eExpCtrl.text,
                        };
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('Save Changes',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _addToInventory() async {
    if (_itemsToAdd.isEmpty) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { _snack('Not authenticated', err: true); return; }
      final userDoc = await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId)
          .collection('users').doc(user.uid).get();
      final username = userDoc.data()?['username'] ?? user.email ?? 'Unknown';

      await FirebaseFirestore.instance
          .collection('branches').doc(widget.branchId).collection('edit_requests')
          .add({
        'requestType':   'add_stock',
        'requester':     user.uid,
        'requesterName': username,
        'requestedAt':   FieldValue.serverTimestamp(),
        'status':        'pending',
        'items': _itemsToAdd.map((item) {
          final d = Map<String, dynamic>.from(item);
          d['name_lower'] = item['name'].toString().toLowerCase();
          return d;
        }).toList(),
      });
      _snack('Request sent for approval!');
      setState(() => _itemsToAdd.clear());
      if (mounted) Navigator.pop(context);
    } catch (e) { _snack('Error: $e', err: true); }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _snack(String msg, {bool err = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: err ? _red : _teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));

  Color _expColor(String exp) {
    if (ExpiryDateFormatter.validate(exp) != null) return _red;
    try {
      final p    = exp.split('-');
      final date = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      final diff = date.difference(DateTime.now()).inDays;
      if (diff <= 30) return _red;
      if (diff <= 90) return _orange;
      return _green600;
    } catch (_) { return _red; }
  }

  IconData _typeIcon(String t) => switch (t) {
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

  InputDecoration _inputDec(String label, IconData icon, {Widget? suffix, String? hint}) =>
      InputDecoration(
        labelText: label, hintText: hint,
        labelStyle: const TextStyle(color: _textLight, fontSize: 13),
        hintStyle:  const TextStyle(color: _textLight, fontSize: 13),
        prefixIcon: Icon(icon, color: _teal, size: 18),
        suffixIcon: suffix != null
            ? Padding(padding: const EdgeInsets.all(13), child: suffix) : null,
        filled: true, fillColor: _green50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _teal, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _red)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _red)),
        errorStyle: const TextStyle(color: _red, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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

  Widget _iconBtn(IconData icon, Color color, VoidCallback fn) => InkWell(
    onTap: fn, borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 16),
    ),
  );

  Widget _dlgField(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboard, List<TextInputFormatter>? formatters}) =>
      TextField(
        controller: ctrl, keyboardType: keyboard,
        inputFormatters: formatters, cursorColor: _teal,
        style: const TextStyle(color: _textDark, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _textLight, fontSize: 13),
          prefixIcon: Icon(icon, color: _teal, size: 17),
          filled: true, fillColor: _green50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _teal, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );

  Widget _dlgDropdown<T>({required String label, required T? value,
      required List<T> items, required ValueChanged<T?> onChanged, String? hint}) =>
      DropdownButtonFormField<T>(
        value: value, dropdownColor: _white,
        style: const TextStyle(color: _textDark, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _textLight, fontSize: 13),
          filled: true, fillColor: _green50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _border)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        hint: hint != null ? Text(hint, style: const TextStyle(color: _textLight)) : null,
        items: items.map((i) => DropdownMenuItem<T>(value: i, child: Text(i.toString()))).toList(),
        onChanged: onChanged,
      );

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final doseList = _doseOptions[_type] ?? [];
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(children: [
            _buildFormCard(doseList),
            if (_itemsToAdd.isNotEmpty) ...[const SizedBox(height: 20), _buildItemsList()],
            const SizedBox(height: 20),
            _buildSubmitBtn(),
          ]),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: _teal,
    elevation: 4,
    shadowColor: _shadow,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
      onPressed: () => Navigator.pop(context),
    ),
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Request Stock Update',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      const Text('Pending supervisor approval',
          style: TextStyle(color: Colors.white70, fontSize: 11)),
    ]),
    actions: [
      if (_itemsToAdd.isNotEmpty)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
          child: Text('${_itemsToAdd.length} items',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
    ],
  );

  Widget _buildFormCard(List<String> doseList) => Container(
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _green100),
      boxShadow: [BoxShadow(color: _shadow, blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionLabel('Medicine Details'),
          const SizedBox(height: 18),
          // Name with search
          TextFormField(
            controller: _nameCtrl,
            style: const TextStyle(color: _textDark, fontSize: 15),
            cursorColor: _teal,
            decoration: _inputDec('Medicine Name', Icons.medication_rounded,
                suffix: _isSearching
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                    : null),
            onChanged: _searchMedicine,
            validator: (v) => v?.trim().isEmpty ?? true ? 'Name is required' : null,
          ),
          if (_searchResults.isNotEmpty) _buildSuggestions(),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              value: _type,
              dropdownColor: _white,
              style: const TextStyle(color: _textDark, fontSize: 14),
              decoration: _inputDec('Type', FontAwesomeIcons.capsules),
              items: _allTypes.map((t) => DropdownMenuItem(value: t,
                  child: Row(children: [
                    Icon(_typeIcon(t), size: 13, color: _teal),
                    const SizedBox(width: 8), Text(t),
                  ]))).toList(),
              onChanged: (v) { if (v != null) setState(() { _type = v; _selectedDose = null; _doseCtrl.clear(); }); },
            )),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: _textDark, fontSize: 15),
              cursorColor: _teal,
              decoration: _inputDec('Price (PKR)', Icons.currency_rupee_rounded),
              validator: (v) {
                if (v?.trim().isEmpty ?? true) return 'Required';
                if ((int.tryParse(v!) ?? 0) <= 0) return 'Invalid';
                return null;
              },
            )),
          ]),
          const SizedBox(height: 14),
          if (_hasDoseDropdown) ...[
            DropdownButtonFormField<String>(
              value: _selectedDose,
              dropdownColor: _white,
              style: const TextStyle(color: _textDark, fontSize: 14),
              decoration: _inputDec('Dose', Icons.science_rounded),
              hint: const Text('Select dose', style: TextStyle(color: _textLight)),
              items: doseList.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (v) => setState(() => _selectedDose = v),
              validator: (v) => v == null ? 'Select a dose' : null,
            ),
            const SizedBox(height: 14),
          ],
          if (_usesFreeTextDose) ...[
            TextFormField(
              controller: _doseCtrl,
              style: const TextStyle(color: _textDark, fontSize: 15),
              cursorColor: _teal,
              decoration: _inputDec(
                _type == 'Nebulization'
                    ? 'Dose per session (e.g. 1ml Salbutamol + 2ml saline)'
                    : 'Dose / Variant (e.g. 500mg)',
                Icons.science_rounded,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(children: [
            Expanded(child: TextFormField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: _textDark, fontSize: 15),
              cursorColor: _teal,
              decoration: _inputDec(
                _type == 'Nebulization' ? 'Sessions (doses)' : 'Quantity',
                Icons.inventory_2_rounded,
              ),
              validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Min 1' : null,
            )),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(
              controller: _expCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, ExpiryDateFormatter()],
              style: const TextStyle(color: _textDark, fontSize: 15),
              cursorColor: _teal,
              decoration: _inputDec('Expiry (dd-MM-yyyy)', Icons.calendar_today_rounded, hint: 'dd-MM-yyyy'),
              validator: ExpiryDateFormatter.validate,
            )),
          ]),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
              label: const Text('Add to Request List',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
            ),
          ),
        ]),
      ),
    ),
  );

  Widget _buildSuggestions() => Container(
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _border),
      boxShadow: [BoxShadow(color: _shadow, blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: _green100),
        itemBuilder: (ctx, i) {
          final med = _searchResults[i];
          return InkWell(
            onTap: () => _selectMedicine(med),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: _green50, borderRadius: BorderRadius.circular(8)),
                  child: Icon(_typeIcon(med['type'] ?? ''), color: _teal, size: 14),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(med['name'] ?? '',
                      style: const TextStyle(color: _textDark, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('${med['type'] ?? ''} ${med['dose'] ?? ''}'.trim(),
                      style: const TextStyle(color: _textLight, fontSize: 12)),
                ])),
                const Icon(Icons.north_west_rounded, color: _teal, size: 15),
              ]),
            ),
          );
        },
      ),
    ),
  );

  Widget _buildItemsList() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionLabel('Pending Request (${_itemsToAdd.length})', color: _green600),
      const SizedBox(height: 12),
      ...List.generate(_itemsToAdd.length, (i) {
        final item     = _itemsToAdd[i];
        final expColor = _expColor(item['expiryDate'] ?? '');
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _green100),
            boxShadow: [BoxShadow(color: _shadow, blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _green50, borderRadius: BorderRadius.circular(10)),
                child: Icon(_typeIcon(item['type']), color: _teal, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item['name'],
                    style: const TextStyle(color: _textDark, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _chip(item['type'], _teal),
                  if ((item['dose'] as String).isNotEmpty) _chip(item['dose'], _textMid),
                  _chip('Qty: ${item['quantity']}', _green600),
                  _chip('PKR ${item['price']}', _orange),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 11, color: expColor),
                  const SizedBox(width: 4),
                  Text('Exp: ${item['expiryDate']}',
                      style: TextStyle(color: expColor, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ])),
              Column(children: [
                _iconBtn(Icons.edit_rounded, _teal, () => _editItem(i)),
                const SizedBox(height: 4),
                _iconBtn(Icons.delete_rounded, _red, () => _removeItem(i)),
              ]),
            ]),
          ),
        );
      }),
    ],
  );

  Widget _buildSubmitBtn() {
    final empty = _itemsToAdd.isEmpty;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: empty ? null : _addToInventory,
        icon: Icon(Icons.send_rounded, color: empty ? Colors.grey[400] : Colors.white),
        label: Text(
          empty ? 'Add items above to submit' : 'Submit Request (${_itemsToAdd.length} items)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
              color: empty ? Colors.grey[400] : Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: empty ? Colors.grey[200] : _green600,
          disabledBackgroundColor: Colors.grey[200],
          padding: const EdgeInsets.symmetric(vertical: 17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: empty ? 0 : 3,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, {Color? color}) => Row(children: [
    Container(width: 4, height: 18,
        decoration: BoxDecoration(color: color ?? _teal, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 10),
    Text(text, style: TextStyle(color: color ?? _teal, fontSize: 15, fontWeight: FontWeight.bold)),
  ]);
}

// ── Expiry formatter ──────────────────────────────────────────────────────────
class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue neo) {
    String d = neo.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 8) d = d.substring(0, 8);
    String r = '';
    if (d.length >= 2) { r += d.substring(0, 2); if (d.length > 2) r += '-'; } else r = d;
    if (d.length >= 4) { r += d.substring(2, 4); if (d.length > 4) r += '-'; }
    else if (d.length > 2) r += d.substring(2);
    if (d.length > 4) r += d.substring(4);
    return TextEditingValue(text: r, selection: TextSelection.collapsed(offset: r.length));
  }

  static String? validate(String? v) {
    if (v == null || v.isEmpty) return 'Enter expiry date';
    if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(v)) return 'Use dd-MM-yyyy format';
    try {
      final p = v.split('-');
      final day = int.parse(p[0]); final month = int.parse(p[1]); final year = int.parse(p[2]);
      if (month < 1 || month > 12) return 'Invalid month';
      if (day < 1 || day > 31)     return 'Invalid day';
      final date = DateTime(year, month, day);
      final now  = DateTime.now();
      if (date.isBefore(DateTime(now.year, now.month, now.day))) return 'Date not permitted';
      if (year < 2025) return 'Year too early';
      if (year > 2100) return 'Year too far ahead';
    } catch (_) { return 'Invalid date'; }
    return null;
  }
}
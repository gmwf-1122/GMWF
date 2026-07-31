import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/role_theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_back_button.dart';
import '../../utils/cnic_parser_util.dart';
import '../../utils/formatters.dart';
import '../../services/ramadan_welfare_service.dart';

class RamadanWelfareScreen extends StatefulWidget {
  final String branchId;
  const RamadanWelfareScreen({
    super.key,
    this.branchId = 'sialkot',
  });

  @override
  State<RamadanWelfareScreen> createState() => _RamadanWelfareScreenState();
}

class _RamadanWelfareScreenState extends State<RamadanWelfareScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Entry Form State
  String _selectedCampaign = 'rations'; // 'rations', 'libaas'
  final _cnicCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final int _familyMembers = 1;

  Map<String, dynamic>? _duplicateData;
  bool _isSaving = false;

  // Vault & Filter State
  String _searchQuery = '';
  String _vaultCampaignFilter = 'all';

  // Lucky Draw Room State
  String _drawCampaign = 'rations';
  final _winnerCountCtrl = TextEditingController(text: '1000');
  final _libaasChildMaleCtrl = TextEditingController(text: '250');
  final _libaasChildFemaleCtrl = TextEditingController(text: '250');
  final _libaasAdultMaleCtrl = TextEditingController(text: '250');
  final _libaasAdultFemaleCtrl = TextEditingController(text: '250');

  int get _libaasTotalSuits {
    final cm = int.tryParse(_libaasChildMaleCtrl.text.trim()) ?? 0;
    final cf = int.tryParse(_libaasChildFemaleCtrl.text.trim()) ?? 0;
    final am = int.tryParse(_libaasAdultMaleCtrl.text.trim()) ?? 0;
    final af = int.tryParse(_libaasAdultFemaleCtrl.text.trim()) ?? 0;
    return cm + cf + am + af;
  }

  bool _isDrawing = false;
  List<Map<String, dynamic>> _drawWinners = [];
  int _drawWinnersPage = 0;
  bool _showAllWinnersAtOnce = false;

  bool _boxInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cnicCtrl.addListener(_onFieldChanged);
    _phoneCtrl.addListener(_onFieldChanged);
    _initStorage();
  }

  Future<void> _initStorage() async {
    await RamadanWelfareService.init();
    if (mounted) setState(() => _boxInitialized = true);
  }

  @override
  void dispose() {
    _cnicCtrl.removeListener(_onFieldChanged);
    _phoneCtrl.removeListener(_onFieldChanged);
    _cnicCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    _winnerCountCtrl.dispose();
    _libaasChildMaleCtrl.dispose();
    _libaasChildFemaleCtrl.dispose();
    _libaasAdultMaleCtrl.dispose();
    _libaasAdultFemaleCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final cnicText = _cnicCtrl.text.trim();
    final phoneText = _phoneCtrl.text.trim();
    if (cnicText.length >= 13 || phoneText.length >= 10) {
      final dup = RamadanWelfareService.checkBeneficiaryDuplicate(
        cnic: cnicText,
        phone: phoneText,
        campaign: _selectedCampaign,
      );
      if (mounted) setState(() => _duplicateData = dup);
    } else if (_duplicateData != null) {
      if (mounted) setState(() => _duplicateData = null);
    }
  }

  Future<void> _handleBarcodePasteOrScan() async {
    final rawText = await Clipboard.getData(Clipboard.kTextPlain);
    if (rawText?.text != null && rawText!.text!.trim().isNotEmpty) {
      final parsed = CnicParserUtil.parsePdf417Barcode(rawText.text!);
      if (parsed.isSuccess) {
        setState(() {
          _cnicCtrl.text = parsed.cnic;
          if (parsed.name.isNotEmpty) _nameCtrl.text = parsed.name;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('CNIC & Name auto-extracted from barcode data!'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
        return;
      }
    }
    _showManualScanDialog();
  }

  void _showManualScanDialog() {
    final scanInputCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner_rounded, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text('Scan CNIC 2D Barcode', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Point hardware USB 2D barcode scanner at card back or paste PDF417 payload:',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: scanInputCtrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. 3410112345671|MUHAMMAD ZEESHAN|ALLAH DITTA...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final parsed = CnicParserUtil.parsePdf417Barcode(scanInputCtrl.text);
              if (parsed.cnic.isNotEmpty) {
                setState(() {
                  _cnicCtrl.text = parsed.cnic;
                  if (parsed.name.isNotEmpty) _nameCtrl.text = parsed.name;
                });
                _onFieldChanged();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Auto-Filled CNIC: ${parsed.cnic} | Name: ${parsed.name}'),
                    backgroundColor: Colors.green.shade700,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No valid CNIC 2D barcode payload recognized.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Auto-Fill Data'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRegistration() async {
    final cnic = _cnicCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (cnic.length < 13) {
      _showError('Please enter a valid 13-digit CNIC number.');
      return;
    }
    if (name.isEmpty) {
      _showError('Please enter the beneficiary full name.');
      return;
    }
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length != 11) {
      _showError('Please enter a valid 11-digit Pakistani mobile phone number (e.g. 03001234567).');
      return;
    }

    // Double check duplicate for CNIC or Phone Number
    final dup = RamadanWelfareService.checkBeneficiaryDuplicate(
      cnic: cnic,
      phone: phone,
      campaign: _selectedCampaign,
    );
    if (dup != null) {
      setState(() => _duplicateData = dup);
      _showError('Duplicate Entry! ${dup['dupReason'] ?? 'This record'} is already registered in this campaign.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final opName = FirebaseAuth.instance.currentUser?.displayName ??
          FirebaseAuth.instance.currentUser?.email?.split('@').first ??
          'Office Staff';

      final res = await RamadanWelfareService.registerBeneficiary(
        cnic: cnic,
        name: name,
        phone: phone,
        campaign: _selectedCampaign,
        branchId: widget.branchId,
        operatorName: opName,
        familyMembers: _familyMembers,
        notes: _notesCtrl.text,
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
          _cnicCtrl.clear();
          _nameCtrl.clear();
          _phoneCtrl.clear();
          _notesCtrl.clear();
          _duplicateData = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Beneficiary registered! Serial: ${res['serialNo']}'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showError('Failed to register beneficiary: $e');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runLuckyDraw() async {
    final count = _drawCampaign == 'libaas'
        ? _libaasTotalSuits
        : (int.tryParse(_winnerCountCtrl.text.trim()) ?? 1000);
    if (count <= 0) {
      _showError('Please enter a valid winner count (> 0).');
      return;
    }

    final eligible = RamadanWelfareService.getRegistrations(
      campaign: _drawCampaign,
      branchId: widget.branchId,
    ).where((r) => r['isWinner'] != true).toList();

    if (eligible.isEmpty) {
      _showError('No eligible non-winner applicants found for campaign: ${_drawCampaign.toUpperCase()}');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.casino_rounded, color: Colors.purpleAccent.shade200),
            const SizedBox(width: 10),
            const Text('Confirm Lucky Draw'),
          ],
        ),
        content: Text(
          'Run automated lucky draw for campaign [${_drawCampaign.toUpperCase()}]?\n\n'
          '• Total Eligible Pool: ${eligible.length} applicants\n'
          '• Winners to Pick: $count\n\n'
          'This action is provably fair and will generate official winning passes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start Lucky Draw', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDrawing = true);
    await Future.delayed(const Duration(milliseconds: 1500)); // Animated delay

    final winners = await RamadanWelfareService.executeLuckyDraw(
      campaign: _drawCampaign,
      winnerCount: count,
      branchId: widget.branchId,
    );

    if (mounted) {
      setState(() {
        _isDrawing = false;
        _drawWinners = winners;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Lucky Draw Complete! Picked ${winners.length} Winners!'),
          backgroundColor: Colors.purple.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RoleThemeScope.dataOf(context);

    if (!_boxInitialized || !Hive.isBoxOpen(RamadanWelfareService.boxName)) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: t.accent),
              const SizedBox(height: 16),
              Text('Initializing Ramadan Storage...', style: TextStyle(color: t.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(RamadanWelfareService.boxName).listenable(),
      builder: (context, box, _) {
        final allRegs = RamadanWelfareService.getRegistrations(branchId: widget.branchId);
        final rationsCount = allRegs.where((r) => r['campaign'] == 'rations' || r['campaign'] == 'both').length;
        final libaasCount = allRegs.where((r) => r['campaign'] == 'libaas' || r['campaign'] == 'both').length;
        final totalWinners = allRegs.where((r) => r['isWinner'] == true).length;

        return Scaffold(
          backgroundColor: t.bg,
          appBar: AppBar(
            backgroundColor: t.bgCard,
            elevation: 0,
            leading: AppBackButton(color: t.textPrimary),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset('assets/logo/gmwf-1.webp', height: 26, width: 26),
                    const SizedBox(width: 8),
                    const Text('🌙 GMWF Ramadan Projects', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'HYBRID OFFICE',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade400),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Rations: $rationsCount  ·  Libaas: $libaasCount  ·  Winners: $totalWinners',
                  style: TextStyle(fontSize: 11, color: t.textSecondary),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: t.accent,
              unselectedLabelColor: t.textTertiary,
              indicatorColor: t.accent,
              tabs: const [
                Tab(icon: Icon(Icons.app_registration_rounded), text: 'Hybrid Data Entry'),
                Tab(icon: Icon(Icons.badge_rounded), text: 'Beneficiary Vault'),
                Tab(icon: Icon(Icons.casino_rounded), text: '1,000 Lucky Draw'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildDataEntryTab(t),
              _buildBeneficiaryVaultTab(t, allRegs),
              _buildLuckyDrawTab(t, allRegs),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 1: Hybrid Data Entry ──

  Widget _buildDataEntryTab(RoleThemeData t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Campaign Selector Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.bgRule),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SELECT RAMADAN WELFARE PROJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: t.textTertiary, letterSpacing: 1)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _campaignChip('rations', '🍚 GMWF Rations', Colors.green, t)),
                        const SizedBox(width: 12),
                        Expanded(child: _campaignChip('libaas', '👗 GMWF Libaas', Colors.purpleAccent, t)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Duplicate Alert Banner
              if (_duplicateData != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.redAccent, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 36),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('⚠️ DUPLICATE ENTRY DETECTED', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(
                              'CNIC ${_duplicateData!['cnic']} was ALREADY registered for '
                              '[${(_duplicateData!['campaign'] ?? '').toString().toUpperCase()}] '
                              'on ${_duplicateData!['registeredAt']?.toString().split('T').first ?? 'N/A'} '
                              'by Staff: ${_duplicateData!['operatorName'] ?? 'Unknown'}.',
                              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Main Entry Card
              Card(
                color: t.bgCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: t.bgRule)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Beneficiary Identity & Contact', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                              foregroundColor: Colors.blueAccent,
                              elevation: 0,
                            ),
                            onPressed: _handleBarcodePasteOrScan,
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            label: const Text('Scan / Paste CNIC Barcode'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // CNIC Field
                      TextField(
                        controller: _cnicCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CNICInputFormatter(), LengthLimitingTextInputFormatter(15)],
                        style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'CNIC / Identity Number *',
                          hintText: '34101-1234567-1',
                          prefixIcon: Icon(Icons.badge_rounded, color: t.accent),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Full Name Field
                      TextField(
                        controller: _nameCtrl,
                        style: TextStyle(color: t.textPrimary, fontSize: 15),
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Full Name (Name on Card) *',
                          hintText: 'e.g. MUHAMMAD ZEESHAN',
                          prefixIcon: Icon(Icons.person_rounded, color: t.accent),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Phone Number Field (Max 11 digits)
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [LengthLimitingTextInputFormatter(11), FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(color: t.textPrimary, fontSize: 15),
                        decoration: InputDecoration(
                          labelText: 'Mobile Phone Number * (11 Digits)',
                          hintText: 'e.g. 03001234567',
                          prefixIcon: Icon(Icons.phone_rounded, color: t.accent),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),



                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _duplicateData != null ? Colors.grey : t.accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: (_isSaving || _duplicateData != null) ? null : _submitRegistration,
                          icon: _isSaving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.how_to_reg_rounded, color: Colors.white),
                          label: Text(
                            _isSaving ? 'REGISTERING BENEFICIARY...' : 'SUBMIT BENEFICIARY ENTRY',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campaignChip(String id, String label, Color color, RoleThemeData t) {
    final isSelected = _selectedCampaign == id;
    return InkWell(
      onTap: () => setState(() {
        _selectedCampaign = id;
        _onFieldChanged();
      }),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.3), width: isSelected ? 2 : 1),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // ── Tab 2: Beneficiary Vault ──

  Widget _buildBeneficiaryVaultTab(RoleThemeData t, List<Map<String, dynamic>> allRegs) {
    final filtered = RamadanWelfareService.getRegistrations(
      branchId: widget.branchId,
      campaign: _vaultCampaignFilter,
      searchQuery: _searchQuery,
    );

    return Column(
      children: [
        Container(
          color: t.bgCard,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: TextStyle(color: t.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by CNIC, Name, Phone, or Serial #...',
                        prefixIcon: Icon(Icons.search_rounded, color: t.accent),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _vaultChip('all', 'All Campaigns (${allRegs.length})', t),
                    const SizedBox(width: 8),
                    _vaultChip('rations', 'Rations', t),
                    const SizedBox(width: 8),
                    _vaultChip('libaas', 'Libaas', t),
                    const SizedBox(width: 8),
                    _vaultChip('both', 'Both (Combo)', t),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: t.textTertiary),
                      const SizedBox(height: 12),
                      Text('No beneficiaries found matching query', style: TextStyle(color: t.textSecondary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, idx) {
                    final item = filtered[idx];
                    final isWinner = item['isWinner'] == true;
                    final campaign = (item['campaign'] ?? '').toString().toUpperCase();

                    return Card(
                      color: t.bgCard,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: isWinner ? Colors.amber : t.bgRule),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isWinner ? Colors.amber : t.accent.withValues(alpha: 0.15),
                          child: Icon(
                            isWinner ? Icons.emoji_events_rounded : Icons.person_rounded,
                            color: isWinner ? Colors.black : t.accent,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              item['name'] ?? 'N/A',
                              style: TextStyle(fontWeight: FontWeight.bold, color: t.textPrimary),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (campaign == 'RATIONS' ? Colors.green : Colors.purple).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                campaign,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: campaign == 'RATIONS' ? Colors.green : Colors.purpleAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'CNIC: ${item['cnic']}  ·  Phone: ${item['phone']}  ·  Serial: ${item['serialNo'] ?? 'N/A'}',
                          style: TextStyle(fontSize: 12, color: t.textSecondary),
                        ),
                        trailing: isWinner
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.amber),
                                ),
                                child: Text(
                                  item['winPassNo'] ?? 'WINNER',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 11),
                                ),
                              )
                            : Text(
                                item['registeredAt']?.toString().split('T').first ?? '',
                                style: TextStyle(fontSize: 11, color: t.textTertiary),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _vaultChip(String id, String label, RoleThemeData t) {
    final isSelected = _vaultCampaignFilter == id;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : t.textPrimary, fontSize: 12)),
      selectedColor: t.accent,
      onSelected: (_) => setState(() => _vaultCampaignFilter = id),
    );
  }

  // ── Tab 3: 1,000 Winner Lucky Draw Room ──

  Widget _buildLuckyDrawTab(RoleThemeData t, List<Map<String, dynamic>> allRegs) {
    final eligible = RamadanWelfareService.getRegistrations(
      campaign: _drawCampaign,
      branchId: widget.branchId,
    ).where((r) => r['isWinner'] != true).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // Lucky Draw Banner Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.purple.shade900, Colors.indigo.shade900]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.purple.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.casino_rounded, size: 56, color: Colors.amberAccent),
                    const SizedBox(height: 12),
                    const Text('🎲 RAMADAN 1,000 WINNER LUCKY DRAW', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    const SizedBox(height: 6),
                    Text(
                      'Provably fair automated random winner selection algorithm for GMWF Ramadan welfare campaigns.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _drawMetricChip('ELIGIBLE APPLICANTS', '${eligible.length}', Icons.people_rounded),
                        const SizedBox(width: 16),
                        _drawMetricChip('CAMPAIGN', _drawCampaign.toUpperCase(), Icons.label_rounded),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Controls Card
              Card(
                color: t.bgCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: t.bgRule)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LUCKY DRAW CONFIGURATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: t.textTertiary)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _drawCampaign,
                        decoration: const InputDecoration(labelText: 'Target Campaign', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'rations', child: Text('🍚 GMWF Rations')),
                          DropdownMenuItem(value: 'libaas', child: Text('👗 GMWF Libaas')),
                        ],
                        onChanged: (val) => setState(() => _drawCampaign = val!),
                      ),
                      const SizedBox(height: 16),

                      if (_drawCampaign == 'rations') ...[
                        TextField(
                          controller: _winnerCountCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(labelText: 'Ration Winners Count (Total Packages)', hintText: '1000', border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                        ),
                      ] else ...[
                        Text('👗 Libaas Suit Allocation (Child Male / Child Female / Adult)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.textPrimary)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _libaasChildMaleCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(labelText: '👦 Child Male Suits', hintText: '250', border: OutlineInputBorder()),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _libaasChildFemaleCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(labelText: '👧 Child Female Suits', hintText: '250', border: OutlineInputBorder()),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _libaasAdultMaleCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(labelText: '👨 Adult Male Suits', hintText: '250', border: OutlineInputBorder()),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _libaasAdultFemaleCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(labelText: '👩 Adult Female Suits', hintText: '250', border: OutlineInputBorder()),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TOTAL LIBASS LUCKY DRAW WINNERS:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purpleAccent)),
                              Text('$_libaasTotalSuits WINNERS', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.purpleAccent)),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isDrawing ? null : _runLuckyDraw,
                          icon: _isDrawing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.casino_rounded, color: Colors.white),
                          label: Text(
                            _isDrawing
                                ? 'RUNNING RANDOM WINNER SELECTION...'
                                : 'EXECUTE ${_drawCampaign == 'libaas' ? _libaasTotalSuits : (int.tryParse(_winnerCountCtrl.text.trim()) ?? 1000)} WINNER LUCKY DRAW',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Recent Winners Table with 10-by-10 View and All Winners View
              if (_drawWinners.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('🎉 Lucky Draw Winners (${_drawWinners.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: t.textPrimary)),
                    Row(
                      children: [
                        FilterChip(
                          selected: !_showAllWinnersAtOnce,
                          label: const Text('10 by 10 View', style: TextStyle(fontSize: 12)),
                          onSelected: (val) => setState(() {
                            _showAllWinnersAtOnce = false;
                            _drawWinnersPage = 0;
                          }),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _showAllWinnersAtOnce,
                          label: const Text('All Winners', style: TextStyle(fontSize: 12)),
                          onSelected: (val) => setState(() => _showAllWinnersAtOnce = true),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (ctx) {
                    final totalCount = _drawWinners.length;
                    const pageSize = 10;
                    final maxPage = (totalCount / pageSize).ceil();

                    final displayItems = _showAllWinnersAtOnce
                        ? _drawWinners
                        : _drawWinners.skip(_drawWinnersPage * pageSize).take(pageSize).toList();

                    final startIndex = _showAllWinnersAtOnce ? 0 : _drawWinnersPage * pageSize;

                    return Column(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayItems.length,
                          itemBuilder: (ctx, idx) {
                            final globalIdx = startIndex + idx;
                            final w = displayItems[idx];
                            return Card(
                              color: Colors.purple.shade900.withValues(alpha: 0.15),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.amber,
                                  child: Text('#${globalIdx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 11)),
                                ),
                                title: Text(w['name'] ?? 'N/A', style: TextStyle(fontWeight: FontWeight.bold, color: t.textPrimary)),
                                subtitle: Text('CNIC: ${w['cnic']}  ·  Phone: ${w['phone']}'),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                  child: Text(w['winPassNo'] ?? 'PASS-2026', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                                ),
                              ),
                            );
                          },
                        ),
                        if (!_showAllWinnersAtOnce && maxPage > 1) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left_rounded),
                                onPressed: _drawWinnersPage > 0
                                    ? () => setState(() => _drawWinnersPage--)
                                    : null,
                              ),
                              Text(
                                'Page ${_drawWinnersPage + 1} of $maxPage  (Winners ${startIndex + 1}–${(startIndex + displayItems.length)} of $totalCount)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.textSecondary),
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right_rounded),
                                onPressed: (_drawWinnersPage + 1) < maxPage
                                    ? () => setState(() => _drawWinnersPage++)
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawMetricChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: Colors.amberAccent, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

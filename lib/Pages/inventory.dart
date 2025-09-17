import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class InventoryPage extends StatefulWidget {
  final String role; // "doctor", "receptionist", "dispensar", "admin"
  final String branchId; // Branch assigned to this user

  const InventoryPage({super.key, required this.role, required this.branchId});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _firestore = FirebaseFirestore.instance;
  Box? _localBox;
  bool _isOnline = true;
  List<Map<String, dynamic>> inventory = [];

  @override
  void initState() {
    super.initState();
    _initHive();
    _listenConnectivity();
  }

  Future<void> _initHive() async {
    _localBox = await Hive.openBox("inventoryBox_${widget.branchId}");
    await _loadInventory();
  }

  void _listenConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (mounted) {
        setState(() => _isOnline = online);
      }
      if (online) _syncLocalToFirestore();
    });
  }

  Future<void> _loadInventory() async {
    if (_localBox == null) return;

    if (_isOnline) {
      try {
        final snap = await _firestore
            .collection("branches")
            .doc(widget.branchId)
            .collection("inventory")
            .get();

        inventory = snap.docs.map((d) {
          final data = d.data();
          data["id"] = d.id;
          return data;
        }).toList();

        await _localBox!.put("inventoryCache", inventory);
      } catch (e) {
        debugPrint("❌ Firestore load error: $e");
      }
    } else {
      final cached = _localBox!.get("inventoryCache", defaultValue: []);
      inventory = List<Map<String, dynamic>>.from(cached);
    }

    if (mounted) setState(() {});
  }

  Future<void> _syncLocalToFirestore() async {
    if (_localBox == null) return;

    final cached = _localBox!.get("pendingInventory", defaultValue: []) as List;
    for (var item in cached) {
      final docRef = _firestore
          .collection("branches")
          .doc(widget.branchId)
          .collection("inventory")
          .doc(item["id"]);

      item["branchId"] = widget.branchId; // always keep branch link
      await docRef.set(item, SetOptions(merge: true));
    }
    await _localBox!.put("pendingInventory", []);
    await _loadInventory();
  }

  Future<void> _addOrEditMed({Map<String, dynamic>? med}) async {
    final nameController = TextEditingController(text: med?["name"] ?? "");
    final stockController =
        TextEditingController(text: med?["stock"]?.toString() ?? "0");

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(med == null ? "Add Medicine" : "Edit Medicine"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Medicine Name"),
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: "Stock"),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final stock = int.tryParse(stockController.text.trim()) ?? 0;
              if (name.isEmpty) return;

              final medData = {
                "name": name,
                "stock": stock,
                "branchId": widget.branchId,
              };

              if (_isOnline) {
                final docRef = med != null
                    ? _firestore
                        .collection("branches")
                        .doc(widget.branchId)
                        .collection("inventory")
                        .doc(med["id"])
                    : _firestore
                        .collection("branches")
                        .doc(widget.branchId)
                        .collection("inventory")
                        .doc();

                medData["id"] = docRef.id;
                await docRef.set(medData);
              } else {
                final pending = _localBox!
                    .get("pendingInventory", defaultValue: []) as List;
                if (med != null) {
                  medData["id"] = med["id"];
                  pending.removeWhere((e) => e["id"] == med["id"]);
                } else {
                  medData["id"] =
                      DateTime.now().millisecondsSinceEpoch.toString();
                }
                pending.add(medData);
                await _localBox!.put("pendingInventory", pending);
              }

              await _loadInventory();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMed(Map<String, dynamic> med) async {
    if (_isOnline) {
      await _firestore
          .collection("branches")
          .doc(widget.branchId)
          .collection("inventory")
          .doc(med["id"])
          .delete();
    } else {
      final pending =
          _localBox!.get("pendingInventory", defaultValue: []) as List;
      pending.removeWhere((e) => e["id"] == med["id"]);
      await _localBox!.put("pendingInventory", pending);
    }
    await _loadInventory();
  }

  bool get _canEdit => widget.role.toLowerCase() == "receptionist";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Inventory - ${widget.branchId}"),
        backgroundColor: Colors.green,
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton(
              backgroundColor: Colors.green,
              onPressed: () => _addOrEditMed(),
              child: const Icon(Icons.add),
            )
          : null,
      body: inventory.isEmpty
          ? const Center(
              child: Text(
                "📦 No medicines available.\nReceptionist can add stock here.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: inventory.length,
              itemBuilder: (context, index) {
                final med = inventory[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading:
                        const Icon(Icons.medical_services, color: Colors.green),
                    title: Text(med["name"] ?? "Unnamed"),
                    subtitle: Text("Stock: ${med["stock"] ?? '-'}"),
                    trailing: _canEdit
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon:
                                    const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _addOrEditMed(med: med),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteMed(med),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
    );
  }
}

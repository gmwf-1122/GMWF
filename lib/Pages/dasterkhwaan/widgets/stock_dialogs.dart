// lib/pages/dasterkhwaan/widgets/stock_dialogs.dart
//
// All stock-related bottom sheets:
//   • showAddStockDialog   — add or edit a stock item
//   • showAdjustStockDialog — add / remove quantity
//
// Imports palette constants from cook_dialog.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/stock_item.dart';
import 'cook_dialog.dart' show
    kPrimary, kAccent, kSuccess, kWarning, kInfo, kPurple,
    kSurface, kCardBg, kTextDark, kTextMid, kTextLight,
    kInputDeco, kLabel, kSheetHandle;

// ════════════════════════════════════════════════════════════════════════════
// ADD / EDIT STOCK ITEM
// ════════════════════════════════════════════════════════════════════════════

void showAddStockDialog(
  BuildContext context, {
  StockItem? editItem,
  required String branchId,
  required List<StockItem> allStockItems,
  required Future<void> Function() onDone,
}) {
  final isEdit   = editItem != null;
  final formKey  = GlobalKey<FormState>();
  final nameCtrl = TextEditingController(text: editItem?.name ?? '');
  final qtyCtrl  = TextEditingController(
      text: isEdit ? '${editItem!.quantity}' : '0');
  String unit = editItem?.unit ?? 'kg';

  const units = [
    'kg', 'gram', 'liter', 'piece', 'packet', 'bundle', 'bunch', 'handi', 'plate'
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setModal) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: kCardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              kSheetHandle(kInfo),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: kInfo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(
                    isEdit ? Icons.edit_rounded : Icons.add_box_rounded,
                    color: kInfo,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(isEdit ? 'Edit Stock Item' : 'Add Stock Item',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 20),

              // Name — autocomplete for new, locked for edit
              if (!isEdit)
                Autocomplete<String>(
                  optionsBuilder: (v) {
                    if (v.text.isEmpty) return const [];
                    return allStockItems
                        .where((i) => i.name
                            .toLowerCase()
                            .contains(v.text.toLowerCase()))
                        .map((i) => i.name)
                        .take(6);
                  },
                  fieldViewBuilder: (ctx2, ctrl, focus, _) =>
                      TextFormField(
                    controller: ctrl,
                    focusNode: focus,
                    decoration: kInputDeco(
                        'Item Name *', Icons.inventory_2_outlined),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v?.trim().isEmpty ?? true) return 'Required';
                      final name = v!.trim().toLowerCase();
                      if (allStockItems.any((i) => i.name.toLowerCase() == name)) {
                        return 'Already in stock. Edit quantity instead.';
                      }
                      return null;
                    },
                    onChanged: (v) => nameCtrl.text = v,
                  ),
                  onSelected: (s) {
                    nameCtrl.text = s;
                    final found = allStockItems.firstWhere(
                        (i) => i.name == s,
                        orElse: () => StockItem(
                            id: '',
                            name: s,
                            quantity: 0,
                            unit: 'kg',
                            lastUpdated: Timestamp.now()));
                    setModal(() => unit = found.unit);
                  },
                )
              else
                TextFormField(
                  controller: nameCtrl,
                  readOnly: true,
                  decoration:
                      kInputDeco('Item Name', Icons.inventory_2_outlined)
                          .copyWith(
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),

              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: kInputDeco(
                        isEdit ? 'Set Quantity' : 'Initial Quantity',
                        Icons.scale_rounded),
                    validator: (v) =>
                        (double.tryParse(v!) ?? -1) < 0
                            ? 'Must be ≥ 0'
                            : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: unit,
                    decoration: kInputDeco('Unit', Icons.straighten),
                    items: units
                        .map((u) => DropdownMenuItem(
                            value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) => setModal(() => unit = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(color: kTextLight, fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kInfo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Enter item name'),
                          backgroundColor: kAccent,
                        ));
                        return;
                      }
                      final qty = double.tryParse(qtyCtrl.text) ?? 0;
                      final ref = FirebaseFirestore.instance
                          .collection('branches')
                          .doc(branchId)
                          .collection('dasterkhwaan_stock')
                          .doc(name);
                      final snap = await ref.get();
                      if (isEdit) {
                        await ref.update({
                          'quantity':    qty,
                          'unit':        unit,
                          'lastUpdated': FieldValue.serverTimestamp(),
                        });
                      } else if (snap.exists) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Product already exists. Edit its quantity instead.'),
                          backgroundColor: kAccent,
                        ));
                        return;
                      } else {
                        await ref.set({
                          'name':        name,
                          'quantity':    qty,
                          'unit':        unit,
                          'lastUpdated': FieldValue.serverTimestamp(),
                        });
                      }
                      await onDone();
                      if (ctx.mounted) Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(isEdit
                            ? '$name updated'
                            : '$qty $unit of $name added to stock'),
                        backgroundColor: kSuccess,
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ));
                    },
                    child: Text(isEdit ? 'Update Stock' : 'Add to Stock',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// ADJUST STOCK (Add or Remove quantity)
// ════════════════════════════════════════════════════════════════════════════

void showAdjustStockDialog(
  BuildContext context,
  StockItem item, {
  required bool isAdd,
  required String branchId,
  required Future<void> Function(String itemName, double delta) onAdjust,
}) {
  final formKey = GlobalKey<FormState>();
  final qtyCtrl = TextEditingController(text: '1.0');
  final Color actionColor = isAdd ? kSuccess : kAccent;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: kCardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            kSheetHandle(actionColor),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                  isAdd
                      ? Icons.add_circle_outline_rounded
                      : Icons.remove_circle_outline_rounded,
                  color: actionColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAdd ? 'Add Stock' : 'Remove Stock',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w900)),
                Text(item.name,
                    style: const TextStyle(color: kTextMid, fontSize: 13)),
              ]),
            ]),
            const SizedBox(height: 16),

            // Current stock display
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: kSurface, borderRadius: BorderRadius.circular(12)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                const Text('Current Stock',
                    style: TextStyle(color: kTextMid, fontSize: 13)),
                Text('${item.quantity} ${item.unit}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: kTextDark,
                        fontSize: 15)),
              ]),
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: qtyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  kInputDeco('Quantity (${item.unit})', Icons.scale_rounded),
              validator: (v) {
                final qty = double.tryParse(v ?? '');
                if (qty == null || qty <= 0) return 'Must be > 0';
                if (!isAdd && qty > item.quantity) {
                  return 'Max: ${item.quantity} ${item.unit}';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(color: kTextLight, fontSize: 15)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final qty = double.parse(qtyCtrl.text);
                    await onAdjust(item.name, isAdd ? qty : -qty);
                    if (context.mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isAdd
                          ? 'Added $qty ${item.unit} of ${item.name}'
                          : 'Removed $qty ${item.unit} of ${item.name}'),
                      backgroundColor: kSuccess,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  child: Text(isAdd ? 'Add Stock' : 'Remove',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

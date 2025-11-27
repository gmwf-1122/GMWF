import 'package:flutter/material.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  String? _selectedBranch;
  List<Map<String, String>> _users = [];

  final branches = [
    {"branchId": "1", "branchName": "Gujrat"},
    {"branchId": "2", "branchName": "Sialkot"},
    {"branchId": "3", "branchName": "Karachi-1"},
    {"branchId": "4", "branchName": "Karachi-2"},
  ];

  void _download(String type) {
    // TODO: implement download logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Downloading $type report...")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Download"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Container(
          width: 800,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Download Reports",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _selectedBranch,
                decoration: const InputDecoration(
                  labelText: "Select Branch",
                  prefixIcon: Icon(Icons.account_tree),
                ),
                items: branches.map((branch) {
                  return DropdownMenuItem<String>(
                    value: branch["branchId"],
                    child: Text(branch["branchName"]!),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedBranch = value;
                    // TODO: fetch branch users
                    _users = []; // reset for demo
                  });
                },
              ),
              const SizedBox(height: 20),

              // ✅ Only show after selection
              if (_selectedBranch != null) ...[
                if (_users.isEmpty)
                  const Text(
                    "⚠️ No users available",
                    style: TextStyle(color: Colors.grey),
                  ),
                if (_users.isNotEmpty) ...[
                  const Text("Available Users:",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._users.map((u) => ListTile(
                        leading: const Icon(Icons.person, color: Colors.green),
                        title: Text(u["email"] ?? ""),
                        subtitle: Text("Role: ${u["role"]}"),
                      )),
                ],
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _download("pdf"),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("Download PDF"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _download("excel"),
                    icon: const Icon(Icons.table_chart),
                    label: const Text("Download Excel"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

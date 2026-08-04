import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart'; // DatabaseHelper ko import karna zaroori hai

class MasterSearchScreen extends StatefulWidget {
  const MasterSearchScreen({super.key});

  @override
  State<MasterSearchScreen> createState() => _MasterSearchScreenState();
}

class _MasterSearchScreenState extends State<MasterSearchScreen> {
  List<Map<String, dynamic>> _results = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;

  void _runSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.searchAllTransactions(query);
    setState(() {
      _results = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            hintText: "Search title, category or amount...",
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: _runSearch,
        ),
        backgroundColor: Colors.indigo,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(_searchController.text.isEmpty
                ? "Type something to search..."
                : "No transactions found.",
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final tx = _results[index];
          final date = DateTime.parse(tx['date']);
          final color = tx['type'] == 'Income'
              ? Colors.green
              : (tx['type'] == 'Expense' ? Colors.red : Colors.blue);

          return Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.1),
                child: Icon(
                  tx['type'] == 'Income' ? Icons.arrow_downward : (tx['type'] == 'Expense' ? Icons.arrow_upward : Icons.swap_horiz),
                  color: color,
                ),
              ),
              title: Text(tx['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${DateFormat('dd MMM yyyy').format(date)} • ${tx['category']}"),
              trailing: Text(
                "${tx['amount']}",
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          );
        },
      ),
    );
  }
}
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/api_exceptions.dart';
import 'experiment_screen.dart';
import 'models/item.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MCS4302 Running System',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const ItemsScreen(),
      );
}

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final api = ApiClient();
  late Future<List<Item>> _future;
  bool _busy = false;

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _future = api.getItems();
  }

  void _refresh() {
    if (mounted) setState(() { _future = api.getItems(); });
  }

  Future<void> _addItem() async {
    if (_busy) return;
    setState(() => _busy = true);
    var name = "";
    var priceText = "";
    final formKey = GlobalKey<FormState>();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New item'),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                onChanged: (value) => name = value,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v == null || v.trim().isEmpty || v.trim().length > 120
                    ? 'Enter a name (1-120 characters)' : null,
              ),
              TextFormField(
                onChanged: (value) => priceText = value,
                decoration: const InputDecoration(labelText: 'Price'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final price = double.tryParse(v ?? '');
                  return price == null || !price.isFinite || price < 0
                      ? 'Enter a nonnegative price' : null;
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await api.createItem(name.trim(), double.parse(priceText));
      _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Part 4: idempotency test - 10 creates with a 50% "lost response" rate.
  Future<void> _idempotencyTest(bool useKey) async {
    // Let any earlier refresh finish before resetting the random stream.
    try { await _future; } catch (_) {}
    await api.reset(42);
    var failed = 0;
    for (var i = 0; i < 10; i++) {
      try {
        await api.createItem('Test $i', 1,
            failRate: 0.5, useIdempotencyKey: useKey);
      } on ApiException {
        failed++;
      }
    }
    final created = (await api.getItems()).length - 2; // 2 seeded items
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Key ${useKey ? "ON" : "OFF"}: 10 creates requested, '
            '${created - 10} duplicates, $created created, $failed reported failed')));
  }

  // Part 3: quick tests of the fault-injection endpoints.
  Future<void> _runTest(String which) async {
    if (_busy) return;
    setState(() => _busy = true);
    String msg;
    try {
      switch (which) {
        case 'slow':
          await api.getSlow(3);
        case 'flaky':
          await api.getFlaky(0.3);
        case 'bad':
          await api.getBadJson();
        case 'idem-off':
          await _idempotencyTest(false);
          return;
        case 'idem-on':
          await _idempotencyTest(true);
          return;
      }
      msg = 'OK';
    } on ApiException catch (e) {
      msg = '$e (retryable: ${e.retryable})';
    } catch (e) {
      msg = 'Test failed: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$which -> $msg')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _busy ? null : _refresh),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: _runTest,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'slow', child: Text('Test /slow (3 s)')),
              PopupMenuItem(value: 'flaky', child: Text('Test /flaky (30%)')),
              PopupMenuItem(value: 'bad', child: Text('Test /bad-json')),
              PopupMenuItem(
                  value: 'idem-off', child: Text('Idempotency test: key OFF')),
              PopupMenuItem(
                  value: 'idem-on', child: Text('Idempotency test: key ON')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.science),
            tooltip: 'Retry experiment',
            onPressed: _busy ? null : () async {
              setState(() => _busy = true);
              try { await _future; } catch (_) {}
              if (!mounted) return;
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ExperimentScreen(api: api)));
              if (mounted) {
                setState(() => _busy = false);
                _refresh();
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: _busy ? null : _addItem, child: const Icon(Icons.add)),
      body: FutureBuilder<List<Item>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final items = snap.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(child: Text('${items[i].id}')),
              title: Text(items[i].name),
              trailing: Text('Rs. ${items[i].price.toStringAsFixed(2)}'),
            ),
          );
        },
      ),
    );
  }
}

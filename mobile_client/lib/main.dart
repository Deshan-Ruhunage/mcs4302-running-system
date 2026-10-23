import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/api_exceptions.dart';
import 'background_jobs.dart';
import 'experiment_screen.dart';
import 'jobs_screen.dart';
import 'lifecycle_log.dart';
import 'models/item.dart';
import 'notifications.dart';

Future<void> main() async {
  LifecycleLog.add('process started: main()');
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundJobs.init(); // Week 5 Part 4: register the job entry point
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MCS4302 Running System',
        // Week 5 Part 2: turns on state restoration for the whole app.
        restorationScopeId: 'app',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const ItemsScreen(),
      );
}

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

// Week 5 Part 1: WidgetsBindingObserver delivers app lifecycle changes.
// Week 5 Part 2: RestorationMixin saves small UI state that Android hands
// back after it kills and recreates the process.
class _ItemsScreenState extends State<ItemsScreen>
    with WidgetsBindingObserver, RestorationMixin {
  final api = ApiClient();
  late Future<List<Item>> _future;
  bool _busy = false;

  // Part 2: the same UI state, now restorable. Android stores it in the
  // saved instance state (a small bundle), not in a database.
  final _draft = RestorableTextEditingController();
  final _sortByPrice = RestorableBool(false);

  @override
  String? get restorationId => 'items_screen';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_draft, 'draft');
    registerForRestoration(_sortByPrice, 'sort_by_price');
    LifecycleLog.add('restoreState: draft="${_draft.value.text}", '
        'sortByPrice=${_sortByPrice.value}');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LifecycleLog.add('ItemsScreen created (initState)');
    _future = api.getItems();
  }

  @override
  void dispose() {
    LifecycleLog.add('ItemsScreen disposed');
    WidgetsBinding.instance.removeObserver(this);
    _draft.dispose();
    _sortByPrice.dispose();
    api.close();
    super.dispose();
  }

  /// Called by the framework whenever the app's lifecycle state changes:
  /// resumed, inactive, hidden, paused or detached.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LifecycleLog.add('state -> ${state.name}');
  }

  /// Menu entries that open something rather than run a test.
  void _onMenu(String which) {
    switch (which) {
      case 'lifelog':
        showLifecycleLog(context);
      case 'notify':
        _notificationCheck();
      case 'jobs':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => JobsScreen(api: api)));
      default:
        _runTest(which);
    }
  }

  /// Week 5 Part 3: check, request or test the notification permission.
  Future<void> _notificationCheck() async {
    final allowed = await Notifications.isEnabled();
    LifecycleLog.add('notifications allowed: $allowed');
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notifications'),
        content: Text(allowed
            ? 'Notifications are allowed for this app.'
            : 'Notifications are NOT allowed for this app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'settings'),
              child: const Text('Open settings')),
          if (!allowed)
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'request'),
                child: const Text('Request')),
          if (allowed)
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'test'),
                child: const Text('Send test')),
        ],
      ),
    );
    String? msg;
    switch (choice) {
      case 'request':
        // Time the call: a very fast "false" means Android showed no dialog.
        final sw = Stopwatch()..start();
        final granted = await Notifications.request();
        sw.stop();
        msg = 'Request returned $granted after ${sw.elapsedMilliseconds} ms';
        if (!granted && mounted) {
          // Refused: tell the user how to fix it themselves.
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Notifications are off. You can turn them on '
                'in the app settings.'),
            action: SnackBarAction(
                label: 'Settings', onPressed: Notifications.openSettings),
          ));
          LifecycleLog.add(msg);
          return;
        }
      case 'test':
        await Notifications.show(
            id: 1, title: 'MCS4302', body: 'Test notification from the app');
        msg = 'Test notification sent';
      case 'settings':
        await Notifications.openSettings();
    }
    if (msg == null) return;
    LifecycleLog.add(msg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'lifelog', child: Text('Lifecycle log')),
              PopupMenuItem(value: 'notify', child: Text('Notifications')),
              PopupMenuItem(value: 'jobs', child: Text('Background jobs')),
              PopupMenuDivider(),
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
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _draft.value,
            decoration: const InputDecoration(
              labelText: 'Draft note (restorable)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('Sort by price'),
          value: _sortByPrice.value,
          onChanged: (v) => setState(() => _sortByPrice.value = v),
        ),
        const Divider(height: 1),
        Expanded(child: _itemList()),
      ]),
    );
  }

  Widget _itemList() {
    return FutureBuilder<List<Item>>(
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
          final items = [...snap.data!];
          if (_sortByPrice.value) items.sort((a, b) => a.price.compareTo(b.price));
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(child: Text('${items[i].id}')),
              title: Text(items[i].name),
              trailing: Text('Rs. ${items[i].price.toStringAsFixed(2)}'),
            ),
          );
        },
    );
  }
}

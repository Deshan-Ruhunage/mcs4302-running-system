import 'package:flutter/material.dart';

import 'item.dart';
import 'item_repository.dart';

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({super.key, required this.repo, required this.id});

  final ItemRepository repo;
  final int id;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  Item? _item;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Item? item;
    Object? err;
    try {
      item = await widget.repo.fetchItem(widget.id);
    } catch (e) {
      err = e;
    }
    if (!mounted) return;
    setState(() {
      _item = item;
      _error = err == null ? null : 'Could not load item';
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      appBar: AppBar(title: Text('Item ${widget.id}')),
      body: Center(
        child: _error != null
            ? Text(_error!)
            : item == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.name,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(item.description, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text('Price: ${item.price.toStringAsFixed(2)}'),
                        Text('Tags: ${item.tags.join(', ')}'),
                      ],
                    ),
                  ),
      ),
    );
  }
}

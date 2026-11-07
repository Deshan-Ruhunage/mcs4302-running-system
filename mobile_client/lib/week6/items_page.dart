import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'detail_page.dart';
import 'item_repository.dart';
import 'items_model.dart';
import 'perf_page.dart';

class ItemsPage extends StatelessWidget {
  const ItemsPage({super.key, this.api});

  final ApiItemRepository? api;

  @override
  Widget build(BuildContext context) {
    final m = context.watch<ItemsModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          if (api != null)
            IconButton(
              icon: const Icon(Icons.speed),
              tooltip: 'Performance',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PerfPage(api: api!)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: m.loading ? null : m.refresh,
              child: const Text('Refresh'),
            ),
          ),
          Expanded(child: _body(context, m)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ItemsModel m) {
    if (m.loading) return const Center(child: CircularProgressIndicator());
    if (m.error != null) return Center(child: Text(m.error!));
    if (m.items.isEmpty) return const Center(child: Text('Tap Refresh'));
    return ListView.builder(
      itemCount: m.items.length,
      itemBuilder: (context, i) {
        final item = m.items[i];
        return ListTile(
          title: Text(item.name),
          subtitle: Text(item.description),
          trailing: Text(item.price.toStringAsFixed(2)),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ItemDetailPage(
                repo: context.read<ItemRepository>(),
                id: item.id,
              ),
            ),
          ),
        );
      },
    );
  }
}

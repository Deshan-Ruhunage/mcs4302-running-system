import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'item_repository.dart';
import 'items_model.dart';
import 'items_page.dart';

/// [repo] can be a fake in tests. [api] enables the Performance screen.
class Week6App extends StatelessWidget {
  const Week6App({super.key, required this.repo, this.api});

  final ItemRepository repo;
  final ApiItemRepository? api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ItemRepository>.value(value: repo),
        ChangeNotifierProvider(create: (_) => ItemsModel(repo)),
      ],
      child: MaterialApp(
        title: 'MCS4302 Week 6',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: ItemsPage(api: api),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';

import 'item.dart';
import 'item_repository.dart';

/// State layer (lecture slide 21). Depends on the repository interface only.
class ItemsModel extends ChangeNotifier {
  ItemsModel(this.repo);

  final ItemRepository repo;
  List<Item> items = [];
  bool loading = false;
  String? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      items = await repo.fetchItems();
    } catch (e) {
      error = 'Could not load';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

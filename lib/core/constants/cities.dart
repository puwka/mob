/// Russian cities for registration city picker (fallback).
abstract final class Cities {
  static const List<String> all = [
    'Москва',
    'Краснодар',
    'Санкт-Петербург',
  ];

  static List<String> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<String>.from(all);
    return all.where((c) => c.toLowerCase().contains(q)).toList();
  }
}

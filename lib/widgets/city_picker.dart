import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/cities.dart';
import '../core/theme/app_colors.dart';
import '../data/repositories/cities_repository.dart';

Future<String?> showCityPicker(
  BuildContext context, {
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _CityPickerSheet(selected: selected),
  );
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({this.selected});

  final String? selected;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  late List<String> _all;
  late List<String> _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _all = List<String>.from(Cities.all);
    _items = _all;
    _load();
  }

  Future<void> _load() async {
    final names = await CitiesRepository(Supabase.instance.client)
        .fetchActiveNames();
    if (!mounted) return;
    setState(() {
      _all = names;
      _items = names;
      _loading = false;
    });
  }

  void _onSearch(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _items = q.isEmpty
          ? List<String>.from(_all)
          : _all.where((c) => c.toLowerCase().contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'Поиск города',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final city = _items[index];
                  final isSelected = city == widget.selected;
                  return ListTile(
                    title: Text(city),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(city),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

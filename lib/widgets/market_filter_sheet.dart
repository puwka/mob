import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/models/listing.dart';
import 'app_button.dart';
import 'app_text_field.dart';
import 'city_picker.dart';

Future<ListingFilters?> showMarketFilterSheet(
  BuildContext context, {
  required ListingFilters current,
  required List<MarketCategory> categories,
}) {
  return showModalBottomSheet<ListingFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _MarketFilterSheet(
      initial: current,
      categories: categories,
    ),
  );
}

class _MarketFilterSheet extends StatefulWidget {
  const _MarketFilterSheet({
    required this.initial,
    required this.categories,
  });

  final ListingFilters initial;
  final List<MarketCategory> categories;

  @override
  State<_MarketFilterSheet> createState() => _MarketFilterSheetState();
}

class _MarketFilterSheetState extends State<_MarketFilterSheet> {
  late ListingFilters _filters;
  late final TextEditingController _priceFrom;
  late final TextEditingController _priceTo;
  late final TextEditingController _city;

  @override
  void initState() {
    super.initState();
    _filters = widget.initial;
    _priceFrom = TextEditingController(
      text: _filters.priceFrom?.toStringAsFixed(0) ?? '',
    );
    _priceTo = TextEditingController(
      text: _filters.priceTo?.toStringAsFixed(0) ?? '',
    );
    _city = TextEditingController(text: _filters.city ?? '');
  }

  @override
  void dispose() {
    _priceFrom.dispose();
    _priceTo.dispose();
    _city.dispose();
    super.dispose();
  }

  List<MarketCategory> get _roots =>
      widget.categories.where((c) => c.isRoot).toList();

  List<MarketCategory> get _subs {
    final rootId = _filters.categoryId;
    if (rootId == null) return const [];
    return widget.categories.where((c) => c.parentId == rootId).toList();
  }

  void _applyNumeric() {
    final from = double.tryParse(_priceFrom.text.replaceAll(' ', ''));
    final to = double.tryParse(_priceTo.text.replaceAll(' ', ''));
    _filters = _filters.copyWith(
      priceFrom: from,
      clearPriceFrom: from == null,
      priceTo: to,
      clearPriceTo: to == null,
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      clearCity: _city.text.trim().isEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Фильтры',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                  ),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _city,
              label: 'Город',
              hint: 'Выберите город',
              readOnly: true,
              prefixIcon: Icons.location_city_outlined,
              onTap: () async {
                final city = await showCityPicker(
                  context,
                  selected: _city.text,
                );
                if (city != null) {
                  setState(() => _city.text = city);
                }
              },
              suffix: const Icon(
                Icons.expand_more,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Категория',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  label: 'Все',
                  selected: _filters.categoryId == null,
                  onTap: () => setState(() {
                    _filters = _filters.copyWith(
                      clearCategory: true,
                      clearSubcategory: true,
                    );
                  }),
                ),
                for (final c in _roots)
                  _Chip(
                    label: c.name,
                    selected: _filters.categoryId == c.id,
                    onTap: () => setState(() {
                      _filters = _filters.copyWith(
                        categoryId: c.id,
                        clearSubcategory: true,
                      );
                    }),
                  ),
              ],
            ),
            if (_subs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Подкатегория',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(
                    label: 'Все',
                    selected: _filters.subcategoryId == null,
                    onTap: () => setState(() {
                      _filters = _filters.copyWith(clearSubcategory: true);
                    }),
                  ),
                  for (final c in _subs)
                    _Chip(
                      label: c.name,
                      selected: _filters.subcategoryId == c.id,
                      onTap: () => setState(() {
                        _filters = _filters.copyWith(subcategoryId: c.id);
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _priceFrom,
                    label: 'Цена от',
                    hint: '0',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextField(
                    controller: _priceTo,
                    label: 'Цена до',
                    hint: '∞',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Состояние',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  label: 'Любое',
                  selected: _filters.condition == null,
                  onTap: () => setState(() {
                    _filters = _filters.copyWith(clearCondition: true);
                  }),
                ),
                for (final c in ListingCondition.values)
                  _Chip(
                    label: c.labelRu,
                    selected: _filters.condition == c,
                    onTap: () => setState(() {
                      _filters = _filters.copyWith(condition: c);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Дата',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  label: 'Любая',
                  selected: _filters.dateFrom == null,
                  onTap: () => setState(() {
                    _filters = _filters.copyWith(clearDateFrom: true);
                  }),
                ),
                _Chip(
                  label: 'За 7 дней',
                  selected: _isDatePreset(7),
                  onTap: () => setState(() {
                    _filters = _filters.copyWith(
                      dateFrom: DateTime.now().subtract(const Duration(days: 7)),
                    );
                  }),
                ),
                _Chip(
                  label: 'За 30 дней',
                  selected: _isDatePreset(30),
                  onTap: () => setState(() {
                    _filters = _filters.copyWith(
                      dateFrom:
                          DateTime.now().subtract(const Duration(days: 30)),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Сортировка',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in ListingSort.values)
                  _Chip(
                    label: s.labelRu,
                    selected: _filters.sort == s,
                    onTap: () => setState(() {
                      _filters = _filters.copyWith(sort: s);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Сбросить',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      Navigator.pop(
                        context,
                        ListingFilters(city: widget.initial.city),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Применить',
                    onPressed: () {
                      _applyNumeric();
                      Navigator.pop(context, _filters);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isDatePreset(int days) {
    final from = _filters.dateFrom;
    if (from == null) return false;
    final target = DateTime.now().subtract(Duration(days: days));
    return from.difference(target).inHours.abs() < 36;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(
            color: selected ? AppColors.accentDim : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

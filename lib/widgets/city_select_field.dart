import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/validators.dart';
import 'city_picker.dart';

/// Явный выбор города (регистрация / профиль).
class CitySelectField extends StatelessWidget {
  const CitySelectField({
    super.key,
    required this.controller,
    this.label = 'Город',
    this.hint = 'Выберите из списка',
    this.enabled = true,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: controller.text,
      validator: validator ?? Validators.city,
      builder: (state) {
        final value = controller.text.trim();
        final hasValue = value.isNotEmpty;

        Future<void> pick() async {
          if (!enabled) return;
          final city = await showCityPicker(
            context,
            selected: hasValue ? value : null,
          );
          if (city == null) return;
          controller.text = city;
          state.didChange(city);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
            ),
            const SizedBox(height: 6),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? pick : null,
                borderRadius: BorderRadius.circular(AppRadii.input),
                child: InputDecorator(
                  isEmpty: !hasValue,
                  decoration: InputDecoration(
                    hintText: hint,
                    errorText: state.errorText,
                    prefixIcon: const Icon(
                      Icons.location_city_outlined,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                    suffixIcon: const Icon(
                      Icons.expand_more,
                      color: AppColors.textTertiary,
                    ),
                    enabled: enabled,
                  ),
                  child: hasValue
                      ? Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontSize: 15),
                        )
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Cities available in the events filter.
/// Prefer CitiesRepository.fetchActiveNames for live data.
abstract final class EventCities {
  static const all = 'Все';

  /// Fallback when offline / before RPC is applied.
  static const List<String> fallback = [
    'Москва',
    'Краснодар',
    'Санкт-Петербург',
  ];

  static List<String> filterOptionsFrom(List<String> cities) => [
        all,
        ...cities,
      ];

  static List<String> get filterOptions => filterOptionsFrom(fallback);
}

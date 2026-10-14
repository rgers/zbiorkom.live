import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.languageCode);

  final String languageCode;

  static AppStrings of(BuildContext context, [String? overrideLang]) {
    final code =
        overrideLang ??
        Localizations.maybeLocaleOf(context)?.languageCode ??
        'pl';
    return AppStrings(code == 'en' ? 'en' : 'pl');
  }

  bool get isPolish => languageCode != 'en';

  String get appTitle => 'zbiorkom.live';
  String get map => isPolish ? 'Mapa' : 'Map';
  String get schedules => isPolish ? 'Rozkłady' : 'Schedules';
  String get settings => isPolish ? 'Ustawienia' : 'Settings';
  String get favoriteStops =>
      isPolish ? 'Ulubione przystanki' : 'Favorite stops';
  String get filter => isPolish ? 'Filtrowanie' : 'Filter';
  String get search => isPolish ? 'Wyszukaj' : 'Search';
  String get searchHint => isPolish
      ? 'Przystanek, linia, pojazd, brygada...'
      : 'Stop, route, vehicle, brigade...';
  String get searchRoutes =>
      isPolish ? 'Wyszukaj linie' : 'Search routes';
  String get searchCities =>
      isPolish ? 'Wyszukaj miasta' : 'Search cities';
  String get pickCity => isPolish
      ? 'Wybierz obszar metropolitalny'
      : 'Select metropolitan area';
  String get changeCity => isPolish ? 'Zmień miasto' : 'Change city';
  String get changeTheme => isPolish ? 'Zmień motyw' : 'Change theme';
  String get language => isPolish ? 'Język' : 'Language';
  String get behavior =>
      isPolish ? 'Zachowanie aplikacji' : 'Application behavior';
  String get moveToLastLocation => isPolish
      ? 'Użyj ostatniej lokalizacji przy otwarciu mapy'
      : 'Use last location when opening the map';
  String get vehicleMarker =>
      isPolish ? 'Znaczniki pojazdów' : 'Vehicle marker';
  String get showBrigade =>
      isPolish ? 'Numer brygady' : 'Brigade number';
  String get showFleet =>
      isPolish ? 'Numer taborowy' : 'Fleet number';

  String get onTime => isPolish ? 'Planowo' : 'On time';
  String early(String time) =>
      isPolish ? '$time przed czasem' : 'Early $time';
  String delayed(String time) =>
      isPolish ? 'Opóźniony $time' : 'Delayed $time';
  String get scheduledOnly =>
      isPolish ? 'Brak danych o opóźnieniu' : 'Scheduled';
  String get cancelled => isPolish ? 'Odwołany' : 'Cancelled';
  String get noDepartures =>
      isPolish ? 'Brak nadchodzących odjazdów' : 'No upcoming departures';
  String get anywhere => isPolish
      ? 'Wszystkie kierunki'
      : 'All directions';
  String get platform => isPolish ? 'Peron' : 'Platform';
  String get brigadeSchedule =>
      isPolish ? 'Rozkład brygady' : 'Brigade schedule';
  String get vehicleInfo =>
      isPolish ? 'Informacje o pojeździe' : 'Vehicle info';
  String get model => isPolish ? 'Model' : 'Model';
  String get carrier => isPolish ? 'Przewoźnik' : 'Carrier';
  String get prodYear =>
      isPolish ? 'Rok produkcji' : 'Production year';
  String get noVehicleData =>
      isPolish ? 'Brak danych o pojeździe' : 'No vehicle data available';
  String get stops => isPolish ? 'Przystanki' : 'Stops';
  String get stations => isPolish ? 'Stacje' : 'Stations';
  String get vehicles => isPolish ? 'Pojazdy' : 'Vehicles';
  String get routes => isPolish ? 'Linie' : 'Routes';
  String get relations => isPolish ? 'Relacje' : 'Relations';
  String get networkError =>
      isPolish ? 'Brak połączenia z serwerem' : 'No connection to the server';
  String get serverError =>
      isPolish ? 'Wystąpił błąd ładowania' : 'Failed to load';
  String get retry => isPolish ? 'Spróbuj ponownie' : 'Try again';
  String get share => isPolish ? 'Udostępnij' : 'Share';
  String get activeFilters =>
      isPolish ? 'Aktywne filtry' : 'Active filters';
  String get clearFilters =>
      isPolish ? 'Wyczyść filtry' : 'Clear filters';
  String get emptyFavorites => isPolish
      ? 'Aby dodać przystanek do ulubionych, kliknij gwiazdkę na karcie przystanku.'
      : 'To add a favorite stop, tap the star icon on a stop sheet.';
  String get mapAttribution =>
      '© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors';
}

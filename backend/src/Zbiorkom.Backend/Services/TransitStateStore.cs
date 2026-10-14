using System.Collections.Concurrent;
using System.Threading.Channels;
using Zbiorkom.Backend.Models;

namespace Zbiorkom.Backend.Services;

public sealed class CityTransitData
{
    public required CityDto City { get; init; }
    public ConcurrentDictionary<string, RouteTuple> Routes { get; } = new(StringComparer.OrdinalIgnoreCase);
    public ConcurrentDictionary<string, StopTuple> Stops { get; } = new(StringComparer.OrdinalIgnoreCase);
    public ConcurrentDictionary<string, VehicleTuple> Vehicles { get; } = new(StringComparer.OrdinalIgnoreCase);
    public ConcurrentDictionary<string, TripTuple> Trips { get; } = new(StringComparer.OrdinalIgnoreCase);
    public ConcurrentDictionary<string, IReadOnlyList<ItineraryStopTuple>> TripItineraries { get; } = new(StringComparer.OrdinalIgnoreCase);
    public ConcurrentDictionary<string, string> TripEncodedShapes { get; } = new(StringComparer.OrdinalIgnoreCase);
    public ConcurrentDictionary<string, VehicleInfoTuple> VehicleInfos { get; } = new(StringComparer.OrdinalIgnoreCase);
}

public sealed class TransitStateStore
{
    private readonly ConcurrentDictionary<string, CityTransitData> _cities = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<Guid, Channel<string>> _subscribers = new();

    public TransitStateStore()
    {
        SeedDefaultCities();
    }

    public IReadOnlyList<CityDto> GetCities()
        => _cities.Values.Select(c => c.City).OrderBy(c => c.Name, StringComparer.OrdinalIgnoreCase).ToList();

    public CityTransitData? GetCity(string cityId)
        => _cities.TryGetValue(cityId, out var data) ? data : null;

    public CityTransitData GetOrAddCity(CityDto city)
        => _cities.GetOrAdd(city.Id, _ => new CityTransitData { City = city });

    public void NotifyCityUpdated(string cityId)
    {
        foreach (var (_, channel) in _subscribers)
        {
            channel.Writer.TryWrite(cityId);
        }
    }

    public (Guid SubscriptionId, ChannelReader<string> Reader) Subscribe()
    {
        var id = Guid.NewGuid();
        var channel = Channel.CreateBounded<string>(new BoundedChannelOptions(16)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
            SingleWriter = false
        });
        _subscribers[id] = channel;
        return (id, channel.Reader);
    }

    public void Unsubscribe(Guid subscriptionId)
    {
        if (_subscribers.TryRemove(subscriptionId, out var channel))
        {
            channel.Writer.TryComplete();
        }
    }

    public void AdvanceSimulationTick()
    {
        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        foreach (var (cityId, cityData) in _cities)
        {
            foreach (var (vehicleId, v) in cityData.Vehicles)
            {
                var deltaLon = Math.Sin(nowMs / 10000.0 + vehicleId.GetHashCode()) * 0.00025;
                var deltaLat = Math.Cos(nowMs / 10000.0 + vehicleId.GetHashCode()) * 0.00018;
                var nextPct = (v.PercentTraveled + 1.5) % 100.0;

                cityData.Vehicles[vehicleId] = v with
                {
                    Longitude = Math.Round(v.Longitude + deltaLon, 6),
                    Latitude = Math.Round(v.Latitude + deltaLat, 6),
                    LastPing = nowMs,
                    PercentTraveled = Math.Round(nextPct, 1)
                };
            }
            NotifyCityUpdated(cityId);
        }
    }

    private void SeedDefaultCities()
    {
        SeedCity(
            id: "warsaw",
            name: "Warszawa",
            description: "Warszawski Transport Publiczny (WTP / ZTM)",
            lon: 21.0122,
            lat: 52.2297,
            agencyId: "WTP",
            agencyName: "Warszawski Transport Publiczny",
            dataSources:
            [
                new DataSourceInfo("officialGTFS", "Mikołaj Kuranowski", "https://mkuran.pl/gtfs/"),
                new DataSourceInfo("officialGPS", "Miasto Stołeczne Warszawa", "https://dane.um.warszawa.pl/")
            ],
            routes:
            [
                new RouteTuple("105", "warsaw", "105", "Os. Górczewska — Rondo Daszyńskiego", "WTP", VehicleType.Bus, "#d32f2f"),
                new RouteTuple("175", "warsaw", "175", "Lotnisko Chopina — Pl. Piłsudskiego", "WTP", VehicleType.Bus, "#9c27b0"),
                new RouteTuple("1", "warsaw", "1", "Annopol — Banacha", "WTP", VehicleType.Tram, "#f57c00"),
                new RouteTuple("M2", "warsaw", "M2", "Bemowo — Bródno", "WTP", VehicleType.Subway, "#1976d2")
            ],
            stops:
            [
                ("7002_01", "Dworzec Centralny 01", "01", 21.0033, 52.2288, "Rondo Daszyńskiego"),
                ("7002_02", "Centrum 02", "02", 21.0118, 52.2298, "Pl. Piłsudskiego"),
                ("5001_01", "Rondo Daszyńskiego 01", "01", 20.9842, 52.2301, "Os. Górczewska"),
                ("4010_03", "Lotnisko Chopina 03", "03", 20.9679, 52.1672, "Centrum")
            ],
            vehicles:
            [
                ("bus:wtp_5869", "105", "1", 21.0012, 52.2295, 270, "Solaris Urbino 18", 2021, "MZA Warszawa"),
                ("bus:wtp_8824", "175", "3", 20.9950, 52.2120, 35, "Mercedes-Benz Conecto G", 2019, "MZA Warszawa"),
                ("tram:wtp_4201", "1", "04", 20.9921, 52.2264, 180, "Hyundai Rotem 140N", 2022, "Tramwaje Warszawskie"),
                ("subway:wtp_72", "M2", "08", 21.0080, 52.2350, 90, "Skoda Varsovia", 2023, "Metro Warszawskie")
            ]
        );

        SeedCity(
            id: "krakow",
            name: "Kraków",
            description: "Zarząd Transportu Publicznego w Krakowie (ZTP)",
            lon: 19.9450,
            lat: 50.0647,
            agencyId: "ZTP",
            agencyName: "ZTP Kraków",
            dataSources:
            [
                new DataSourceInfo("officialGTFS", "ZTP Kraków", "https://gtfs.ztp.krakow.pl/")
            ],
            routes:
            [
                new RouteTuple("4", "krakow", "4", "Bronowice Małe — Wzgórza Krzesławickie", "ZTP", VehicleType.Tram, "#1565c0"),
                new RouteTuple("50", "krakow", "50", "Krowodrza Górka P+R — Kurdwanów P+R", "ZTP", VehicleType.Tram, "#2e7d32"),
                new RouteTuple("179", "krakow", "179", "Dworzec Główny Zachód — Os. Kurdwanów", "ZTP", VehicleType.Bus, "#ef6c00")
            ],
            stops:
            [
                ("krk_tg_01", "Teatr Bagatela 01", "01", 19.9344, 50.0637, "Bronowice Małe"),
                ("krk_dg_02", "Dworzec Główny Tunel 02", "02", 19.9472, 50.0679, "Kurdwanów P+R"),
                ("krk_rm_01", "Rondo Mogilskie 01", "01", 19.9598, 50.0658, "Wzgórza Krzesławickie")
            ],
            vehicles:
            [
                ("tram:mpk_RG901", "50", "02", 19.9465, 50.0665, 165, "Stadler Tango Kraków Lajkonik", 2021, "MPK Kraków"),
                ("tram:mpk_HG915", "4", "05", 19.9360, 50.0642, 285, "PESA 2014N Krakowiak", 2015, "MPK Kraków"),
                ("bus:mpk_DN021", "179", "01", 19.9280, 50.0480, 195, "Solaris Urbino 18 Electric", 2020, "MPK Kraków")
            ]
        );

        SeedCity(
            id: "poznan",
            name: "Poznań",
            description: "Zarząd Transportu Miejskiego w Poznaniu (ZTM)",
            lon: 16.9252,
            lat: 52.4064,
            agencyId: "ZTM_POZ",
            agencyName: "ZTM Poznań",
            dataSources:
            [
                new DataSourceInfo("officialGTFS", "ZTM Poznań", "https://www.ztm.poznan.pl/pl/dla-deweloperow/")
            ],
            routes:
            [
                new RouteTuple("12", "poznan", "12", "Os. Sobieskiego — Starołęka PKM", "ZTM_POZ", VehicleType.Tram, "#2e7d32"),
                new RouteTuple("169", "poznan", "169", "Os. Kopernika — Os. Łokietka", "ZTM_POZ", VehicleType.Bus, "#1565c0")
            ],
            stops:
            [
                ("poz_mk_01", "Most Teatralny 01", "01", 16.9125, 52.4119, "Starołęka PKM"),
                ("poz_rk_02", "Rondo Kaponiera 02", "02", 16.9124, 52.4079, "Os. Sobieskiego")
            ],
            vehicles:
            [
                ("tram:mpk_542", "12", "1", 16.9125, 52.4095, 180, "Moderus Gamma LF 02 AC", 2019, "MPK Poznań"),
                ("bus:mpk_1280", "169", "2", 16.8980, 52.4020, 45, "Solaris Urbino 12 Hydrogen", 2023, "MPK Poznań")
            ]
        );

        SeedCity(
            id: "gzm",
            name: "Metropolia GZM",
            description: "Transport GZM (Katowice, Gliwice, Sosnowiec, Tychy)",
            lon: 19.0238,
            lat: 50.2649,
            agencyId: "ZTM_GZM",
            agencyName: "Zarząd Transportu Metropolitalnego",
            dataSources:
            [
                new DataSourceInfo("officialGTFS", "Otwarte Dane GZM", "https://otwartedane.metropoliagzm.pl/")
            ],
            routes:
            [
                new RouteTuple("M1", "gzm", "M1", "Katowice — Gliwice", "ZTM_GZM", VehicleType.Bus, "#ad1457"),
                new RouteTuple("6", "gzm", "6", "Bytom Szkoła Medyczna — Katowice Brynów", "ZTM_GZM", VehicleType.Tram, "#c62828")
            ],
            stops:
            [
                ("gzm_kat_01", "Katowice Dworzec 01", "01", 19.0175, 50.2584, "Gliwice"),
                ("gzm_kat_02", "Katowice Rynek 02", "02", 19.0215, 50.2595, "Bytom")
            ],
            vehicles:
            [
                ("bus:gzm_1044", "M1", "1", 19.0180, 50.2590, 290, "MAN Lion's City 18E", 2023, "PKM Katowice")
            ]
        );

        SeedCity(
            id: "tricity",
            name: "Trójmiasto",
            description: "ZTM Gdańsk · ZKM Gdynia · MZKZG · SKM",
            lon: 18.6466,
            lat: 54.3520,
            agencyId: "ZTM_GD",
            agencyName: "ZTM Gdańsk / ZKM Gdynia",
            dataSources:
            [
                new DataSourceInfo("officialGTFS", "Otwarte Dane ZTM Gdańsk", "https://ckan.multimediagdansk.pl/")
            ],
            routes:
            [
                new RouteTuple("6", "tricity", "6", "Jelitkowo — Łostowice Świętokrzyska", "ZTM_GD", VehicleType.Tram, "#c62828"),
                new RouteTuple("29", "tricity", "29", "Gdynia Dworzec Gł. PKP — Wielki Kack", "ZTM_GD", VehicleType.Trolleybus, "#1565c0")
            ],
            stops:
            [
                ("gd_dg_01", "Gdańsk Główny 01", "01", 18.6445, 54.3555, "Jelitkowo"),
                ("gd_wr_02", "Wrzeszcz PKP 02", "02", 18.6050, 54.3812, "Łostowice")
            ],
            vehicles:
            [
                ("tram:ga_1072", "6", "3", 18.6250, 54.3690, 320, "PESA Jazz Duo 128NG", 2020, "GAiT Gdańsk")
            ]
        );

        SeedCity(
            id: "grodzisk",
            name: "Grodzisk Mazowiecki (GPA)",
            description: "Grodziskie Przewozy Autobusowe · WKD",
            lon: 20.6252,
            lat: 52.1097,
            agencyId: "GPA",
            agencyName: "Grodziskie Przewozy Autobusowe",
            dataSources:
            [
                new DataSourceInfo("officialGPS", "GPA KiedyPrzyjedzie", "https://gpa.kiedyprzyjedzie.pl/"),
                new DataSourceInfo("officialGTFS", "WKD (mkuran.pl)", "https://mkuran.pl/gtfs/wkd.zip")
            ],
            routes:
            [
                new RouteTuple("13", "grodzisk", "13", "Grodzisk Maz. Dw. PKP — Błonie PKP", "GPA", VehicleType.Bus, "#c60010"),
                new RouteTuple("23", "grodzisk", "23", "Grodzisk Maz. Dw. PKP — Siestrzeń", "GPA", VehicleType.Bus, "#c60010"),
                new RouteTuple("31", "grodzisk", "31", "Petrykozy — Grodzisk Maz. Dw. PKP", "GPA", VehicleType.Bus, "#c60010"),
                new RouteTuple("32", "grodzisk", "32", "Żelechów — Grodzisk Maz. Dw. PKP", "GPA", VehicleType.Bus, "#c60010"),
                new RouteTuple("60", "grodzisk", "60", "Grodzisk Maz. Dw. PKP — Warszawa P+R Al. Krakowska", "GPA", VehicleType.Bus, "#c60010"),
                new RouteTuple("63", "grodzisk", "63", "Grodzisk Maz. Dw. PKP — Otrębusy WKD", "GPA", VehicleType.Bus, "#c60010")
            ],
            stops:
            [
                ("538522:585919", "Grodzisk Maz. Dw. PKP", "1204101", 20.622327, 52.109692, "Centrum / Dw. PKP"),
                ("538522:2490966", "Grodzisk Maz. Dw. PKP 02", "320020283", 20.625226, 52.110327, "Otrębusy WKD"),
                ("538564:585989", "Grodzisk Maz. Traugutta Dw. PKP", "1208101", 20.621405, 52.110773, "Szpital"),
                ("538483:585844", "Adamowizna Królicza", "1200101", 20.632442, 52.072347, "Grodzisk Maz. Dw. PKP")
            ],
            vehicles:
            [
                ("bus:gpa_312", "31", "312", 20.6324, 52.0850, 345, "Solaris Urbino 10.5", 2022, "GPA Grodzisk Mazowiecki"),
                ("bus:gpa_323", "32", "326", 20.6250, 52.1085, 328, "Mercedes-Benz Sprinter City", 2021, "GPA Grodzisk Mazowiecki"),
                ("bus:gpa_601", "60", "601", 20.6750, 52.1210, 75, "SOR CN 12", 2023, "GPA Grodzisk Mazowiecki")
            ]
        );
    }

    private void SeedCity(
        string id,
        string name,
        string description,
        double lon,
        double lat,
        string agencyId,
        string agencyName,
        IReadOnlyList<DataSourceInfo> dataSources,
        IReadOnlyList<RouteTuple> routes,
        IReadOnlyList<(string Id, string Name, string Code, double Lon, double Lat, string Direction)> stops,
        IReadOnlyList<(string Id, string RouteId, string Brigade, double Lon, double Lat, double Bearing, string Model, int Year, string Carrier)> vehicles)
    {
        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var cityDto = new CityDto(
            Id: id,
            Name: name,
            Location: [lon, lat],
            Timezone: "Europe/Warsaw",
            Zoom: 15.0,
            Description: description,
            Virtual: false,
            Agencies: new Dictionary<string, CityAgencyDto>
            {
                [agencyId] = new CityAgencyDto(agencyId, agencyName, DataSources: dataSources)
            }
        );

        var cityData = GetOrAddCity(cityDto);
        foreach (var route in routes)
        {
            cityData.Routes[route.Id] = route;
        }

        var stopTuples = new List<StopTuple>();
        foreach (var s in stops)
        {
            var stopTuple = new StopTuple(
                Id: s.Id,
                City: id,
                Name: s.Name,
                Code: s.Code,
                Longitude: s.Lon,
                Latitude: s.Lat,
                Types: routes.Select(r => r.Type).Distinct().ToList(),
                Bearing: 0,
                Direction: s.Direction,
                Routes: routes.ToList()
            );
            cityData.Stops[s.Id] = stopTuple;
            stopTuples.Add(stopTuple);
        }

        var encodedShape = PolylineEncoder.Encode6(stopTuples.Select(s => (s.Latitude, s.Longitude)));

        foreach (var v in vehicles)
        {
            if (!cityData.Routes.TryGetValue(v.RouteId, out var route))
                route = routes[0];

            var tripId = $"trip_{id}_{v.RouteId}_{v.Brigade}";
            var vehicleTuple = new VehicleTuple(
                Id: v.Id,
                City: id,
                Route: route,
                Brigade: v.Brigade,
                Longitude: v.Lon,
                Latitude: v.Lat,
                Bearing: v.Bearing,
                LastPing: nowMs,
                TripId: tripId,
                PercentTraveled: 35.0,
                Model: v.Model,
                ProdYear: v.Year,
                Carrier: v.Carrier
            );

            cityData.Vehicles[v.Id] = vehicleTuple;
            cityData.VehicleInfos[v.Id] = new VehicleInfoTuple(v.Id, v.Model, v.Year, v.Carrier);

            var headsign = stopTuples.LastOrDefault()?.Name ?? route.LongName;
            var firstStop = stopTuples.FirstOrDefault();
            var lastStop = stopTuples.LastOrDefault();

            var tripTuple = new TripTuple(
                Id: tripId,
                City: id,
                Route: route,
                Headsign: headsign,
                Brigade: v.Brigade,
                ShortName: route.Name,
                Description: [("operator", v.Carrier), ("model", v.Model)],
                FirstStop: firstStop is not null ? (firstStop.Name, nowMs - 600_000) : null,
                LastStop: lastStop is not null ? (lastStop.Name, nowMs + 1_200_000) : null,
                Distance: 8500
            );

            cityData.Trips[tripId] = tripTuple;
            cityData.TripEncodedShapes[tripId] = encodedShape;
            cityData.TripItineraries[tripId] = stopTuples
                .Select((st, idx) => new ItineraryStopTuple(
                    Stop: st,
                    AlightFlags: idx == stopTuples.Count - 1 ? (1 << 3) : 1,
                    Distance: idx * 1100.0,
                    Platform: st.Code
                ))
                .ToList();
        }
    }
}

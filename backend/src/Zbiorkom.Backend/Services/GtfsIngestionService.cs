using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using ProtoBuf;
using Zbiorkom.Backend.Models;

namespace Zbiorkom.Backend.Services;

[ProtoContract]
public sealed class GtfsRtFeedMessage
{
    [ProtoMember(2)]
    public List<GtfsRtFeedEntity> Entities { get; set; } = [];
}

[ProtoContract]
public sealed class GtfsRtFeedEntity
{
    [ProtoMember(1)]
    public string Id { get; set; } = "";

    [ProtoMember(4)]
    public GtfsRtVehiclePosition? Vehicle { get; set; }
}

[ProtoContract]
public sealed class GtfsRtVehiclePosition
{
    [ProtoMember(1)]
    public GtfsRtTripDescriptor? Trip { get; set; }

    [ProtoMember(2)]
    public GtfsRtPosition? Position { get; set; }

    [ProtoMember(5)]
    public ulong Timestamp { get; set; }

    [ProtoMember(8)]
    public GtfsRtVehicleDescriptor? Vehicle { get; set; }
}

[ProtoContract]
public sealed class GtfsRtTripDescriptor
{
    [ProtoMember(1)]
    public string TripId { get; set; } = "";

    [ProtoMember(5)]
    public string RouteId { get; set; } = "";
}

[ProtoContract]
public sealed class GtfsRtPosition
{
    [ProtoMember(1)]
    public float Latitude { get; set; }

    [ProtoMember(2)]
    public float Longitude { get; set; }

    [ProtoMember(3)]
    public float Bearing { get; set; }
}

[ProtoContract]
public sealed class GtfsRtVehicleDescriptor
{
    [ProtoMember(1)]
    public string Id { get; set; } = "";

    [ProtoMember(2)]
    public string Label { get; set; } = "";
}

public sealed class GtfsFeedConfig
{
    public string CityId { get; set; } = "";
    public string CityName { get; set; } = "";
    public string AgencyId { get; set; } = "default";
    public string? StaticZipUrl { get; set; }
    public string? VehiclePositionsPbUrl { get; set; }
    public string? KiedyPrzyjedzieBaseUrl { get; set; }
}

public static class GtfsFeedParser
{
    public static void LoadStaticZipIntoCity(Stream zipStream, CityTransitData cityData, string defaultAgencyId)
    {
        using var archive = new ZipArchive(zipStream, ZipArchiveMode.Read, leaveOpen: true);

        var routesEntry = archive.GetEntry("routes.txt");
        if (routesEntry is not null)
        {
            using var reader = new StreamReader(routesEntry.Open());
            foreach (var row in ReadCsvRows(reader))
            {
                var routeId = row.GetValueOrDefault("route_id", "");
                if (string.IsNullOrWhiteSpace(routeId)) continue;

                var shortName = row.GetValueOrDefault("route_short_name", routeId);
                var longName = row.GetValueOrDefault("route_long_name", shortName);
                var agency = row.GetValueOrDefault("agency_id", defaultAgencyId);
                var typeCode = int.TryParse(row.GetValueOrDefault("route_type", "3"), out var t) ? t : 3;
                var rawColor = row.GetValueOrDefault("route_color", "276b2b").TrimStart('#');
                var color = string.IsNullOrWhiteSpace(rawColor) ? "#276b2b" : $"#{rawColor}";

                var vehicleType = Enum.IsDefined(typeof(VehicleType), typeCode)
                    ? (VehicleType)typeCode
                    : VehicleType.Bus;

                cityData.Routes[routeId] = new RouteTuple(
                    Id: routeId,
                    City: cityData.City.Id,
                    Name: shortName,
                    LongName: longName,
                    Agency: agency,
                    Type: vehicleType,
                    Color: color
                );
            }
        }

        var stopsEntry = archive.GetEntry("stops.txt");
        if (stopsEntry is not null)
        {
            var defaultRoutes = cityData.Routes.Values.Take(4).ToList();
            var defaultTypes = defaultRoutes.Select(r => r.Type).Distinct().DefaultIfEmpty(VehicleType.Bus).ToList();

            using var reader = new StreamReader(stopsEntry.Open());
            foreach (var row in ReadCsvRows(reader))
            {
                var stopId = row.GetValueOrDefault("stop_id", "");
                var stopName = row.GetValueOrDefault("stop_name", "");
                if (string.IsNullOrWhiteSpace(stopId) || string.IsNullOrWhiteSpace(stopName)) continue;

                if (!double.TryParse(row.GetValueOrDefault("stop_lat", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out var lat))
                    continue;
                if (!double.TryParse(row.GetValueOrDefault("stop_lon", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out var lon))
                    continue;

                var code = row.GetValueOrDefault("stop_code", "");
                cityData.Stops[stopId] = new StopTuple(
                    Id: stopId,
                    City: cityData.City.Id,
                    Name: stopName,
                    Code: code,
                    Longitude: lon,
                    Latitude: lat,
                    Types: defaultTypes,
                    Bearing: 0,
                    Direction: "",
                    Routes: defaultRoutes
                );
            }
        }
    }

    public static int LoadVehiclePositionsProtobufIntoCity(Stream pbStream, CityTransitData cityData)
    {
        var feed = Serializer.Deserialize<GtfsRtFeedMessage>(pbStream);
        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var updatedCount = 0;

        foreach (var entity in feed.Entities)
        {
            var vp = entity.Vehicle;
            if (vp?.Position is null) continue;

            var routeId = vp.Trip?.RouteId ?? "";
            if (!cityData.Routes.TryGetValue(routeId, out var route))
            {
                route = new RouteTuple(
                    Id: string.IsNullOrWhiteSpace(routeId) ? "?" : routeId,
                    City: cityData.City.Id,
                    Name: string.IsNullOrWhiteSpace(routeId) ? "?" : routeId,
                    LongName: "",
                    Agency: "default",
                    Type: VehicleType.Bus,
                    Color: "#276b2b"
                );
            }

            var rawVehicleId = !string.IsNullOrWhiteSpace(vp.Vehicle?.Label)
                ? vp.Vehicle.Label
                : (!string.IsNullOrWhiteSpace(vp.Vehicle?.Id) ? vp.Vehicle.Id : entity.Id);

            if (string.IsNullOrWhiteSpace(rawVehicleId)) continue;

            var prefix = route.Type == VehicleType.Tram ? "tram" : "bus";
            var fullVehicleId = rawVehicleId.Contains(':') ? rawVehicleId : $"{prefix}:gtfs_{rawVehicleId}";
            var tripId = !string.IsNullOrWhiteSpace(vp.Trip?.TripId)
                ? vp.Trip.TripId
                : $"trip_{cityData.City.Id}_{fullVehicleId}";
            var pingMs = vp.Timestamp > 0 ? (long)vp.Timestamp * 1000L : nowMs;

            cityData.Vehicles[fullVehicleId] = new VehicleTuple(
                Id: fullVehicleId,
                City: cityData.City.Id,
                Route: route,
                Brigade: "1",
                Longitude: Math.Round(vp.Position.Longitude, 6),
                Latitude: Math.Round(vp.Position.Latitude, 6),
                Bearing: Math.Round(vp.Position.Bearing, 1),
                LastPing: pingMs,
                TripId: tripId,
                PercentTraveled: 50.0
            );
            updatedCount++;
        }

        return updatedCount;
    }

    public static int LoadKiedyPrzyjedzieStopsIntoCity(string json, CityTransitData cityData)
    {
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("stops", out var stopsArray) || stopsArray.ValueKind != JsonValueKind.Array)
            return 0;

        var defaultRoutes = cityData.Routes.Values.Take(4).ToList();
        var defaultTypes = defaultRoutes.Select(r => r.Type).Distinct().DefaultIfEmpty(VehicleType.Bus).ToList();
        var count = 0;

        foreach (var item in stopsArray.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Array || item.GetArrayLength() < 5)
                continue;

            var placeId = item[0].GetString() ?? "";
            var designator = item[1].ValueKind == JsonValueKind.Number ? item[1].GetInt64().ToString() : (item[1].GetString() ?? "");
            var name = item[2].GetString() ?? "";
            if (string.IsNullOrWhiteSpace(placeId) || string.IsNullOrWhiteSpace(name))
                continue;

            var lonMicro = item[3].GetDouble();
            var latMicro = item[4].GetDouble();
            var lon = Math.Round(lonMicro / 1_000_000.0, 6);
            var lat = Math.Round(latMicro / 1_000_000.0, 6);

            cityData.Stops[placeId] = new StopTuple(
                Id: placeId,
                City: cityData.City.Id,
                Name: name,
                Code: designator,
                Longitude: lon,
                Latitude: lat,
                Types: defaultTypes,
                Bearing: 0,
                Direction: "",
                Routes: defaultRoutes
            );
            count++;
        }

        return count;
    }

    public static IReadOnlyList<(string LineName, string TripExecutionId, int TripIndex, string Direction)> ParseKiedyPrzyjedzieDepartures(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        var directions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        if (root.TryGetProperty("directions", out var dirElement) && dirElement.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in dirElement.EnumerateObject())
            {
                if (prop.Value.ValueKind == JsonValueKind.String)
                    directions[prop.Name] = prop.Value.GetString() ?? "";
            }
        }

        var results = new List<(string LineName, string TripExecutionId, int TripIndex, string Direction)>();
        var seenExecutions = new HashSet<string>(StringComparer.Ordinal);

        void ExtractRows(JsonElement rowsEl)
        {
            if (rowsEl.ValueKind != JsonValueKind.Array) return;
            foreach (var row in rowsEl.EnumerateArray())
            {
                var isEstimated = row.TryGetProperty("is_estimated", out var estEl) && estEl.ValueKind == JsonValueKind.True;
                var execId = row.TryGetProperty("trip_execution_id", out var execEl) && execEl.ValueKind == JsonValueKind.String
                    ? execEl.GetString()
                    : null;
                if (!isEstimated || string.IsNullOrWhiteSpace(execId) || !seenExecutions.Add(execId))
                    continue;

                var lineName = row.TryGetProperty("line_name", out var lineEl) && lineEl.ValueKind == JsonValueKind.String
                    ? (lineEl.GetString() ?? "?")
                    : "?";
                var tripIndex = row.TryGetProperty("trip_index", out var idxEl) && idxEl.ValueKind == JsonValueKind.Number
                    ? idxEl.GetInt32()
                    : 0;
                var dirId = row.TryGetProperty("direction_id", out var dirIdEl)
                    ? dirIdEl.ToString()
                    : "";
                var direction = directions.GetValueOrDefault(dirId, "");

                results.Add((lineName, execId, tripIndex, direction));
            }
        }

        if (root.TryGetProperty("rows", out var directRows))
        {
            ExtractRows(directRows);
        }
        else if (root.TryGetProperty("departures", out var depArray) && depArray.ValueKind == JsonValueKind.Array)
        {
            foreach (var stopDep in depArray.EnumerateArray())
            {
                if (stopDep.TryGetProperty("rows", out var stopRows))
                    ExtractRows(stopRows);
            }
        }

        return results;
    }

    public static bool LoadKiedyPrzyjedzieTripExecutionIntoCity(
        string json,
        string tripExecutionId,
        string fallbackLineName,
        string fallbackDirection,
        string agencyId,
        CityTransitData cityData)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (!root.TryGetProperty("vehicle", out var vehicleEl) || vehicleEl.ValueKind != JsonValueKind.Object)
            return false;

        if (!vehicleEl.TryGetProperty("lon", out var lonEl) || !vehicleEl.TryGetProperty("lat", out var latEl))
            return false;
        if (lonEl.ValueKind != JsonValueKind.Number || latEl.ValueKind != JsonValueKind.Number)
            return false;

        var lon = Math.Round(lonEl.GetDouble(), 6);
        var lat = Math.Round(latEl.GetDouble(), 6);

        var lineName = fallbackLineName;
        var direction = fallbackDirection;
        var itineraryStops = new List<ItineraryStopTuple>();
        var shapeCoords = new List<(double Lat, double Lon)>();

        if (root.TryGetProperty("trip", out var tripEl) && tripEl.ValueKind == JsonValueKind.Object)
        {
            if (tripEl.TryGetProperty("line", out var lEl) && lEl.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(lEl.GetString()))
                lineName = lEl.GetString()!;
            if (tripEl.TryGetProperty("direction", out var dEl) && dEl.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(dEl.GetString()))
                direction = dEl.GetString()!;

            if (tripEl.TryGetProperty("times", out var timesEl) && timesEl.ValueKind == JsonValueKind.Array)
            {
                var idx = 0;
                foreach (var tItem in timesEl.EnumerateArray())
                {
                    var placeId = tItem.TryGetProperty("place_id", out var pEl) && pEl.ValueKind == JsonValueKind.String
                        ? (pEl.GetString() ?? "")
                        : "";
                    var stopName = tItem.TryGetProperty("stop_name", out var snEl) && snEl.ValueKind == JsonValueKind.String
                        ? (snEl.GetString() ?? "")
                        : "";
                    var designator = tItem.TryGetProperty("designator", out var desEl)
                        ? desEl.ToString()
                        : "";

                    if (!cityData.Stops.TryGetValue(placeId, out var stopTuple))
                    {
                        stopTuple = new StopTuple(
                            Id: string.IsNullOrWhiteSpace(placeId) ? $"kp_stop_{idx}" : placeId,
                            City: cityData.City.Id,
                            Name: string.IsNullOrWhiteSpace(stopName) ? $"Stop {idx}" : stopName,
                            Code: designator,
                            Longitude: lon,
                            Latitude: lat,
                            Types: [VehicleType.Bus],
                            Bearing: 0,
                            Direction: direction,
                            Routes: []
                        );
                    }
                    else
                    {
                        shapeCoords.Add((stopTuple.Latitude, stopTuple.Longitude));
                    }

                    itineraryStops.Add(new ItineraryStopTuple(
                        Stop: stopTuple,
                        AlightFlags: 1,
                        Distance: idx * 950.0,
                        Platform: designator
                    ));
                    idx++;
                }
            }
        }

        if (!cityData.Routes.TryGetValue(lineName, out var route))
        {
            route = new RouteTuple(
                Id: lineName,
                City: cityData.City.Id,
                Name: lineName,
                LongName: string.IsNullOrWhiteSpace(direction) ? lineName : direction,
                Agency: agencyId,
                Type: VehicleType.Bus,
                Color: "#c60010"
            );
            cityData.Routes[lineName] = route;
        }

        // Extract brigade/vehicle code from e.g. "A 312 (31):739903:11"
        var colonIdx = tripExecutionId.IndexOf(':');
        var rawLabel = colonIdx > 0 ? tripExecutionId[..colonIdx].Trim() : tripExecutionId;
        var parenIdx = rawLabel.IndexOf('(');
        if (parenIdx > 0)
            rawLabel = rawLabel[..parenIdx].Trim();
        if (rawLabel.StartsWith("A ", StringComparison.OrdinalIgnoreCase))
            rawLabel = rawLabel[2..].Trim();

        var sanitizedId = string.Concat(rawLabel.Where(char.IsLetterOrDigit));
        if (string.IsNullOrWhiteSpace(sanitizedId))
            sanitizedId = Math.Abs(tripExecutionId.GetHashCode()).ToString();

        var fullVehicleId = $"bus:gpa_{sanitizedId}";
        var tripId = $"trip_kp_{sanitizedId}_{lineName}";
        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        var vehicleTripIndex = root.TryGetProperty("vehicle_trip_index", out var vtiEl) && vtiEl.ValueKind == JsonValueKind.Number
            ? vtiEl.GetInt32()
            : 0;
        var totalStops = Math.Max(1, itineraryStops.Count);
        var pct = Math.Clamp(Math.Round((vehicleTripIndex / (double)totalStops) * 100.0, 1), 0.0, 100.0);

        cityData.Vehicles[fullVehicleId] = new VehicleTuple(
            Id: fullVehicleId,
            City: cityData.City.Id,
            Route: route,
            Brigade: rawLabel,
            Longitude: lon,
            Latitude: lat,
            Bearing: 0,
            LastPing: nowMs,
            TripId: tripId,
            PercentTraveled: pct,
            Carrier: "GPA Grodzisk Mazowiecki"
        );

        var firstStop = itineraryStops.FirstOrDefault()?.Stop;
        var lastStop = itineraryStops.LastOrDefault()?.Stop;

        cityData.Trips[tripId] = new TripTuple(
            Id: tripId,
            City: cityData.City.Id,
            Route: route,
            Headsign: string.IsNullOrWhiteSpace(direction) ? (lastStop?.Name ?? route.LongName) : direction,
            Brigade: rawLabel,
            ShortName: route.Name,
            Description: [("operator", "Grodziskie Przewozy Autobusowe"), ("source", "gpa.kiedyprzyjedzie.pl")],
            FirstStop: firstStop is not null ? (firstStop.Name, nowMs - 600_000) : null,
            LastStop: lastStop is not null ? (lastStop.Name, nowMs + 1_200_000) : null,
            Distance: itineraryStops.Count * 950.0
        );

        if (itineraryStops.Count > 0)
        {
            cityData.TripItineraries[tripId] = itineraryStops;
        }
        if (shapeCoords.Count >= 2)
        {
            cityData.TripEncodedShapes[tripId] = PolylineEncoder.Encode6(shapeCoords);
        }

        return true;
    }

    public static string EncodeTripExecutionIdBase64(string tripExecutionId)
        => Convert.ToBase64String(Encoding.UTF8.GetBytes(tripExecutionId));

    public static IEnumerable<Dictionary<string, string>> ReadCsvRows(TextReader reader)
    {
        var headerLine = reader.ReadLine();
        if (headerLine is null) yield break;

        var headers = SplitCsvLine(headerLine);
        string? line;
        while ((line = reader.ReadLine()) is not null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            var cols = SplitCsvLine(line);
            var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < headers.Count && i < cols.Count; i++)
            {
                dict[headers[i]] = cols[i];
            }
            yield return dict;
        }
    }

    private static List<string> SplitCsvLine(string line)
    {
        var result = new List<string>();
        var current = new System.Text.StringBuilder();
        var inQuotes = false;

        for (int i = 0; i < line.Length; i++)
        {
            var ch = line[i];
            if (ch == '"')
            {
                if (inQuotes && i + 1 < line.Length && line[i + 1] == '"')
                {
                    current.Append('"');
                    i++;
                }
                else
                {
                    inQuotes = !inQuotes;
                }
            }
            else if (ch == ',' && !inQuotes)
            {
                result.Add(current.ToString().Trim());
                current.Clear();
            }
            else
            {
                current.Append(ch);
            }
        }
        result.Add(current.ToString().Trim());
        return result;
    }
}

public sealed class GtfsIngestionWorker(
    TransitStateStore store,
    IHttpClientFactory httpClientFactory,
    IConfiguration configuration,
    ILogger<GtfsIngestionWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var feeds = configuration.GetSection("GtfsFeeds").Get<List<GtfsFeedConfig>>() ?? [];

        foreach (var feed in feeds)
        {
            if (string.IsNullOrWhiteSpace(feed.CityId))
                continue;

            var cityData = store.GetCity(feed.CityId);
            if (cityData is null) continue;

            if (!string.IsNullOrWhiteSpace(feed.StaticZipUrl))
            {
                try
                {
                    var client = httpClientFactory.CreateClient("GtfsClient");
                    await using var stream = await client.GetStreamAsync(feed.StaticZipUrl, stoppingToken);
                    using var ms = new MemoryStream();
                    await stream.CopyToAsync(ms, stoppingToken);
                    ms.Position = 0;

                    GtfsFeedParser.LoadStaticZipIntoCity(ms, cityData, feed.AgencyId);
                    logger.LogInformation("Loaded GTFS static feed for {CityId}", feed.CityId);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Failed to load optional GTFS static feed for {CityId}", feed.CityId);
                }
            }

            if (!string.IsNullOrWhiteSpace(feed.KiedyPrzyjedzieBaseUrl))
            {
                try
                {
                    var baseUrl = feed.KiedyPrzyjedzieBaseUrl.TrimEnd('/');
                    var client = httpClientFactory.CreateClient("GtfsClient");
                    var stopsJson = await client.GetStringAsync($"{baseUrl}/stops?rev=1", stoppingToken);
                    var stopCount = GtfsFeedParser.LoadKiedyPrzyjedzieStopsIntoCity(stopsJson, cityData);
                    logger.LogInformation("Loaded {StopCount} KiedyPrzyjedzie stops for {CityId} from {BaseUrl}", stopCount, feed.CityId, baseUrl);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Failed to load KiedyPrzyjedzie stops for {CityId}", feed.CityId);
                }
            }
        }

        var tickCount = 0;
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(3));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            tickCount++;
            store.AdvanceSimulationTick();

            foreach (var feed in feeds)
            {
                if (string.IsNullOrWhiteSpace(feed.CityId))
                    continue;

                var cityData = store.GetCity(feed.CityId);
                if (cityData is null) continue;

                if (!string.IsNullOrWhiteSpace(feed.VehiclePositionsPbUrl))
                {
                    try
                    {
                        var client = httpClientFactory.CreateClient("GtfsClient");
                        await using var pbStream = await client.GetStreamAsync(feed.VehiclePositionsPbUrl, stoppingToken);
                        var count = GtfsFeedParser.LoadVehiclePositionsProtobufIntoCity(pbStream, cityData);
                        if (count > 0)
                        {
                            store.NotifyCityUpdated(feed.CityId);
                        }
                    }
                    catch (Exception ex)
                    {
                        logger.LogDebug(ex, "Optional GTFS-RT poll skipped for {CityId}", feed.CityId);
                    }
                }

                // Poll KiedyPrzyjedzie live departures & GPS trip_execution every ~15 seconds (every 5th tick)
                if (!string.IsNullOrWhiteSpace(feed.KiedyPrzyjedzieBaseUrl) && tickCount % 5 == 1)
                {
                    try
                    {
                        var baseUrl = feed.KiedyPrzyjedzieBaseUrl.TrimEnd('/');
                        var client = httpClientFactory.CreateClient("GtfsClient");
                        var hubPlaces = cityData.Stops.Keys
                            .Where(k => k.Contains(':'))
                            .Take(8)
                            .ToList();

                        if (hubPlaces.Count > 0)
                        {
                            var placesParam = Uri.EscapeDataString(string.Join(",", hubPlaces));
                            var depJson = await client.GetStringAsync($"{baseUrl}/api/departures?places={placesParam}", stoppingToken);
                            var activeTrips = GtfsFeedParser.ParseKiedyPrzyjedzieDepartures(depJson);
                            var updated = 0;

                            foreach (var active in activeTrips.Take(10))
                            {
                                var encodedExecId = Uri.EscapeDataString(GtfsFeedParser.EncodeTripExecutionIdBase64(active.TripExecutionId));
                                var execUrl = $"{baseUrl}/api/trip_execution/{encodedExecId}/{active.TripIndex}";
                                var execJson = await client.GetStringAsync(execUrl, stoppingToken);
                                if (GtfsFeedParser.LoadKiedyPrzyjedzieTripExecutionIntoCity(
                                        execJson,
                                        active.TripExecutionId,
                                        active.LineName,
                                        active.Direction,
                                        feed.AgencyId,
                                        cityData))
                                {
                                    updated++;
                                }
                            }

                            if (updated > 0)
                            {
                                store.NotifyCityUpdated(feed.CityId);
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        logger.LogDebug(ex, "Optional KiedyPrzyjedzie poll skipped for {CityId}", feed.CityId);
                    }
                }
            }
        }
    }
}

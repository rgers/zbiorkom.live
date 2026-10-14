using System.Globalization;
using System.IO.Compression;
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
            if (string.IsNullOrWhiteSpace(feed.CityId) || string.IsNullOrWhiteSpace(feed.StaticZipUrl))
                continue;

            try
            {
                var cityData = store.GetCity(feed.CityId);
                if (cityData is null) continue;

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

        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(3));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            store.AdvanceSimulationTick();

            foreach (var feed in feeds)
            {
                if (string.IsNullOrWhiteSpace(feed.CityId) || string.IsNullOrWhiteSpace(feed.VehiclePositionsPbUrl))
                    continue;

                try
                {
                    var cityData = store.GetCity(feed.CityId);
                    if (cityData is null) continue;

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
        }
    }
}

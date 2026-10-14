using System.Globalization;
using System.Net.ServerSentEvents;
using System.Runtime.CompilerServices;
using Zbiorkom.Backend.Models;
using Zbiorkom.Backend.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy
            .SetIsOriginAllowed(_ => true)
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

builder.Services.AddHttpClient("GtfsClient", client =>
{
    client.Timeout = TimeSpan.FromSeconds(15);
    client.DefaultRequestHeaders.UserAgent.ParseAdd("ZbiorkomDotNetBackend/10.0");
});

builder.Services.AddSingleton<TransitStateStore>();
builder.Services.AddHostedService<GtfsIngestionWorker>();

var app = builder.Build();
app.UseCors();

app.MapGet("/healthz", (TransitStateStore store) => Results.Ok(new
{
    status = "healthy",
    cities = store.GetCities().Count
}));

app.MapGet("/api6", (TransitStateStore store) =>
{
    var cities = store.GetCities();
    return Results.Ok(new Api6RootResponse(
        Hash: "dotnet10-lts",
        ShouldUpdate: false,
        Cities: cities
    ));
});

app.MapGet("/api6/{city}/routes", (string city, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.NotFound(new { error = "CITY_NOT_FOUND" });

    var routes = cityData.Routes.Values.OrderBy(r => r.Name, StringComparer.OrdinalIgnoreCase).ToList();
    return Results.Ok(routes);
});

app.MapGet("/api6/{city}/routes/nearby", (string city, double? lat, double? lon, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.NotFound(new { error = "CITY_NOT_FOUND" });

    return Results.Ok(cityData.Routes.Values.Take(10).ToList());
});

app.MapGet("/api6/{city}/routes/{route}", (string city, string route, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null || !cityData.Routes.TryGetValue(route, out var routeTuple))
        return Results.Ok(new { error = "ROUTE_NOT_FOUND" });

    var stops = cityData.Stops.Values.ToList();
    var trunk = stops.Select(s => new object[]
    {
        s.Id,
        s.City,
        s.Name,
        s.Code,
        new[] { s.Longitude, s.Latitude },
        s.Types.Select(t => (int)t).ToArray(),
        s.Bearing
    }).ToList();

    var shape = PolylineEncoder.Encode6(stops.Select(s => (s.Latitude, s.Longitude)));
    var response = new RouteGraphResponseDto(
        Route: routeTuple,
        Graph:
        [
            new RouteGraphDirectionDto(
                Headsign: stops.LastOrDefault()?.Name ?? routeTuple.LongName,
                Trunk: trunk,
                Branches: []
            )
        ],
        Shapes: [[shape]]
    );

    return Results.Ok(response);
});

app.MapGet("/api6/{city}/vehicles/models", (string city, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.NotFound(new { error = "CITY_NOT_FOUND" });

    var models = cityData.VehicleInfos.Values
        .Select(v => v.Model)
        .Where(m => !string.IsNullOrWhiteSpace(m))
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .OrderBy(m => m, StringComparer.OrdinalIgnoreCase)
        .ToList();

    return Results.Ok(models);
});

app.MapGet("/api6/{city}/vehicles/vehicle/{vehicle}", (string city, string vehicle, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.NotFound(new { error = "CITY_NOT_FOUND" });

    var decodedId = Uri.UnescapeDataString(vehicle);
    if (cityData.VehicleInfos.TryGetValue(decodedId, out var info))
        return Results.Ok(info);

    return Results.Ok(Array.Empty<object>());
});

app.MapGet("/api6/{city}/stops/{stop}/destinations", (string city, string stop, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.NotFound(new { error = "CITY_NOT_FOUND" });

    var decodedStop = Uri.UnescapeDataString(stop);
    var others = cityData.Stops.Values.Where(s => !string.Equals(s.Id, decodedStop, StringComparison.OrdinalIgnoreCase)).ToList();
    return Results.Ok(others);
});

app.MapGet("/api6/{city}/search", (string city, string? query, TransitStateStore store) =>
{
    if (string.IsNullOrWhiteSpace(query))
        return Results.Ok(new { error = "MISSING_QUERY" });

    var cityData = store.GetCity(city);
    if (cityData is null)
        return Results.Ok(new { error = "CITY_NOT_FOUND" });

    var normalized = PolylineEncoder.NormalizePolish(query.Trim());
    var results = new List<Dictionary<string, object?>>();
    var groups = new List<int>();
    var groupNames = new List<string>();

    var matchedVehicles = cityData.Vehicles.Values
        .Where(v =>
            PolylineEncoder.NormalizePolish(v.Id).Contains(normalized) ||
            PolylineEncoder.NormalizePolish(v.Route.Name).Contains(normalized) ||
            PolylineEncoder.NormalizePolish($"{v.Route.Name}/{v.Brigade}").Contains(normalized))
        .Take(10)
        .ToList();

    if (matchedVehicles.Count > 0)
    {
        groups.Add(matchedVehicles.Count);
        groupNames.Add("vehicles");
        foreach (var v in matchedVehicles)
        {
            cityData.Trips.TryGetValue(v.TripId, out var trip);
            results.Add(new Dictionary<string, object?>
            {
                ["vehicle"] = new object?[] { v.Id, v.Route, v.Brigade, trip?.Headsign ?? v.Route.LongName, v.Model }
            });
        }
    }

    var matchedStops = cityData.Stops.Values
        .Where(s => PolylineEncoder.NormalizePolish(s.Name).Contains(normalized) || PolylineEncoder.NormalizePolish(s.Id).Contains(normalized))
        .Take(10)
        .ToList();

    if (matchedStops.Count > 0)
    {
        groups.Add(matchedStops.Count);
        groupNames.Add("stops");
        foreach (var s in matchedStops)
        {
            results.Add(new Dictionary<string, object?>
            {
                ["stop"] = new object?[] { s.Id, s.City, s.Name, new[] { s } }
            });
        }
    }

    var matchedRoutes = cityData.Routes.Values
        .Where(r =>
            PolylineEncoder.NormalizePolish(r.Name).Contains(normalized) ||
            PolylineEncoder.NormalizePolish(r.LongName).Contains(normalized))
        .Take(10)
        .ToList();

    if (matchedRoutes.Count > 0)
    {
        groups.Add(matchedRoutes.Count);
        groupNames.Add("routes");
        foreach (var r in matchedRoutes)
        {
            results.Add(new Dictionary<string, object?>
            {
                ["route"] = r
            });
        }
    }

    return Results.Ok(new
    {
        results,
        groups,
        groupNames
    });
});

app.MapGet("/api6/{city}/brigades/{route}/{date}", (string city, string route, string date, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.NotFound(new { error = "CITY_NOT_FOUND" });

    var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    var brigades = cityData.Vehicles.Values
        .Where(v => string.Equals(v.Route.Id, route, StringComparison.OrdinalIgnoreCase))
        .Select(v => v.Brigade)
        .Distinct()
        .DefaultIfEmpty("1")
        .Select(b => new BrigadeTuple(b, 8, [(nowMs - 3_600_000, nowMs + 14_400_000)]))
        .ToList();

    return Results.Ok(brigades);
});

app.MapGet("/api6/{city}/brigades/{route}/{brigade}/{date}", (string city, string route, string brigade, string date, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null || !cityData.Routes.TryGetValue(route, out var routeTuple))
        return Results.Ok(Array.Empty<object>());

    var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    var stops = cityData.Stops.Values.ToList();
    var firstStop = stops.FirstOrDefault()?.Name ?? "Start";
    var lastStop = stops.LastOrDefault()?.Name ?? "Koniec";
    var vehicle = cityData.Vehicles.Values.FirstOrDefault(v =>
        string.Equals(v.Route.Id, route, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(v.Brigade, brigade, StringComparison.OrdinalIgnoreCase));

    var list = new List<BrigadeTripTuple>
    {
        new(
            Id: vehicle?.TripId ?? $"trip_{city}_{route}_{brigade}",
            Route: routeTuple,
            StartStop: firstStop,
            EndStop: lastStop,
            StartMs: nowMs - 600_000,
            EndMs: nowMs + 1_200_000,
            Distance: 8500,
            VehicleId: vehicle?.Id,
            PercentTraveled: vehicle?.PercentTraveled
        )
    };

    return Results.Ok(list);
});

app.MapGet("/api6/{city}/dispatches/autocomplete", (string city, string? route, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.NotFound(new { error = "CITY_NOT_FOUND" });

    if (!string.IsNullOrWhiteSpace(route))
    {
        var brigades = cityData.Vehicles.Values
            .Where(v => string.Equals(v.Route.Id, route, StringComparison.OrdinalIgnoreCase))
            .Select(v => v.Brigade)
            .Distinct()
            .DefaultIfEmpty("1")
            .ToList();
        return Results.Ok(new { brigades });
    }

    return Results.Ok(new
    {
        routes = cityData.Routes.Values.ToList(),
        vehicles = cityData.Vehicles.Values.Select(v => v.Id.Split('_').Last()).Distinct().ToList()
    });
});

app.MapGet("/api6/{city}/dispatches/dates", (string city) =>
{
    var today = DateTime.UtcNow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
    return Results.Ok(new[] { today });
});

app.MapGet("/api6/{city}/dispatches", (string city, string? route, string? brigade, string? vehicle, TransitStateStore store) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null) return Results.Ok(Array.Empty<object>());

    var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    var stops = cityData.Stops.Values.ToList();
    var first = stops.FirstOrDefault();
    var last = stops.LastOrDefault();

    var executions = cityData.Vehicles.Values
        .Where(v => string.IsNullOrWhiteSpace(route) || string.Equals(v.Route.Id, route, StringComparison.OrdinalIgnoreCase))
        .Select(v => new ExecutionTuple(
            TripId: v.TripId,
            RouteId: v.Route.Id,
            Brigade: v.Brigade,
            VehicleId: v.Id.Split('_').Last(),
            OriginStopId: first?.Id ?? "1",
            OriginName: first?.Name ?? "Start",
            DestStopId: last?.Id ?? "2",
            DestName: last?.Name ?? "Koniec",
            ScheduledStartMs: nowMs - 900_000,
            ActualStartMs: nowMs - 840_000,
            StartDelaySec: 60,
            ScheduledEndMs: nowMs + 900_000,
            ActualEndMs: nowMs + 960_000,
            EndDelaySec: 60,
            Segments: Math.Max(2, stops.Count)
        ))
        .ToList();

    return Results.Ok(executions);
});

app.MapGet("/api6/{city}/mapFeatures/{zoom}/{bounds}/stream", (
    string city,
    string zoom,
    string bounds,
    string? filterRoutes,
    string? filterModels,
    TransitStateStore store,
    CancellationToken cancellationToken) =>
{
    var cityData = store.GetCity(city);
    if (cityData is null)
    {
        return TypedResults.ServerSentEvents(SingleErrorEvent("CITY_NOT_FOUND"));
    }

    double.TryParse(zoom, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedZoom);
    var bboxParts = bounds.Split(',')
        .Select(p => double.TryParse(p, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : (double?)null)
        .ToArray();

    bool hasValidBbox = bboxParts.Length == 4 &&
                        bboxParts.All(p => p.HasValue) &&
                        !(bboxParts[0] == 0 && bboxParts[1] == 0 && bboxParts[2] == 0 && bboxParts[3] == 0);

    var routeFilterSet = string.IsNullOrWhiteSpace(filterRoutes)
        ? null
        : filterRoutes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToHashSet(StringComparer.OrdinalIgnoreCase);

    var modelFilterSet = string.IsNullOrWhiteSpace(filterModels)
        ? null
        : filterModels.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToHashSet(StringComparer.OrdinalIgnoreCase);

    return TypedResults.ServerSentEvents(StreamMapFeaturesAsync(
        cityData,
        store,
        parsedZoom,
        hasValidBbox ? (bboxParts[0]!.Value, bboxParts[1]!.Value, bboxParts[2]!.Value, bboxParts[3]!.Value) : null,
        routeFilterSet,
        modelFilterSet,
        cancellationToken));
});

app.MapGet("/api6/{city}/stops/{stop}/stream", (
    string city,
    string stop,
    int? limit,
    string? destinations,
    TransitStateStore store,
    CancellationToken cancellationToken) =>
{
    var cityData = store.GetCity(city);
    var decodedStop = Uri.UnescapeDataString(stop);
    if (cityData is null || !cityData.Stops.TryGetValue(decodedStop, out var stopTuple))
    {
        return TypedResults.ServerSentEvents(SingleErrorEvent("STOP_NOT_FOUND"));
    }

    var maxCount = Math.Clamp(limit ?? 15, 1, 50);
    return TypedResults.ServerSentEvents(StreamStopDeparturesAsync(
        cityData,
        stopTuple,
        maxCount,
        store,
        cancellationToken));
});

app.MapGet("/api6/{city}/positions/{vehicle}/stream", (
    string city,
    string vehicle,
    TransitStateStore store,
    CancellationToken cancellationToken) =>
{
    var cityData = store.GetCity(city);
    var decodedVehicle = Uri.UnescapeDataString(vehicle);
    if (cityData is null || !cityData.Vehicles.TryGetValue(decodedVehicle, out var vehicleTuple))
    {
        return TypedResults.ServerSentEvents(SingleErrorEvent("VEHICLE_NOT_FOUND"));
    }

    return TypedResults.ServerSentEvents(StreamTripOrVehicleAsync(
        cityData,
        vehicleTuple.TripId,
        vehicleTuple.Id,
        store,
        cancellationToken));
});

app.MapGet("/api6/{city}/trips/{trip}/stream", (
    string city,
    string trip,
    TransitStateStore store,
    CancellationToken cancellationToken) =>
{
    var cityData = store.GetCity(city);
    var decodedTrip = Uri.UnescapeDataString(trip);
    if (cityData is null || !cityData.Trips.ContainsKey(decodedTrip))
    {
        return TypedResults.ServerSentEvents(SingleErrorEvent("TRIP_NOT_FOUND"));
    }

    var matchingVehicle = cityData.Vehicles.Values.FirstOrDefault(v =>
        string.Equals(v.TripId, decodedTrip, StringComparison.OrdinalIgnoreCase));

    return TypedResults.ServerSentEvents(StreamTripOrVehicleAsync(
        cityData,
        decodedTrip,
        matchingVehicle?.Id,
        store,
        cancellationToken));
});

app.MapGet("/blog", () => Results.Ok(new[]
{
    new
    {
        id = "dotnet-10-backend",
        title = "zbiorkom.live .NET 10 LTS Backend",
        description = "Real-time GTFS and Server-Sent Events powered by ASP.NET Core 10.",
        image = "",
        date = DateTime.UtcNow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        content = "# .NET 10 LTS Transit Engine\nPowered by `TypedResults.ServerSentEvents` and GTFS-Realtime."
    }
}));

app.MapGet("/blog/{id}", (string id) => Results.Ok(new
{
    id,
    title = "zbiorkom.live .NET 10 LTS Backend",
    description = "Real-time GTFS and Server-Sent Events powered by ASP.NET Core 10.",
    image = "",
    date = DateTime.UtcNow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
    content = "# .NET 10 LTS Transit Engine\nPowered by `TypedResults.ServerSentEvents` and GTFS-Realtime."
}));

app.Run();

static async IAsyncEnumerable<SseItem<object>> SingleErrorEvent(string code)
{
    yield return new SseItem<object>(code, eventType: "errorCode");
    await Task.CompletedTask;
}

static async IAsyncEnumerable<SseItem<object>> StreamMapFeaturesAsync(
    CityTransitData cityData,
    TransitStateStore store,
    double zoom,
    (double West, double South, double East, double North)? bbox,
    HashSet<string>? routeFilter,
    HashSet<string>? modelFilter,
    [EnumeratorCancellation] CancellationToken cancellationToken)
{
    var stopsInView = cityData.Stops.Values
        .Where(s => bbox is null || (s.Longitude >= bbox.Value.West && s.Longitude <= bbox.Value.East && s.Latitude >= bbox.Value.South && s.Latitude <= bbox.Value.North))
        .ToList();

    yield return new SseItem<object>(new
    {
        stops = stopsInView,
        suggestedCity = (string?)null
    }, eventType: "initial");

    object BuildPositionsPayload()
    {
        var filteredVehicles = cityData.Vehicles.Values
            .Where(v => bbox is null || (v.Longitude >= bbox.Value.West && v.Longitude <= bbox.Value.East && v.Latitude >= bbox.Value.South && v.Latitude <= bbox.Value.North))
            .Where(v => routeFilter is null || routeFilter.Contains(v.Route.Id))
            .Where(v => modelFilter is null || (v.Model is not null && modelFilter.Contains(v.Model)))
            .ToList();

        var useDots = zoom > 0 && zoom < 11.0;
        return new
        {
            positions = useDots ? Array.Empty<VehicleTuple>() : filteredVehicles.ToArray(),
            dots = useDots
                ? filteredVehicles.Select(v => new DotVehicleTuple(v.Route.Color, v.Longitude, v.Latitude)).ToArray()
                : Array.Empty<DotVehicleTuple>()
        };
    }

    yield return new SseItem<object>(BuildPositionsPayload(), eventType: "message");

    var (subId, reader) = store.Subscribe();
    try
    {
        while (await reader.WaitToReadAsync(cancellationToken))
        {
            while (reader.TryRead(out var updatedCity))
            {
                if (string.Equals(updatedCity, cityData.City.Id, StringComparison.OrdinalIgnoreCase))
                {
                    yield return new SseItem<object>(BuildPositionsPayload(), eventType: "message");
                }
            }
        }
    }
    finally
    {
        store.Unsubscribe(subId);
    }
}

static async IAsyncEnumerable<SseItem<object>> StreamStopDeparturesAsync(
    CityTransitData cityData,
    StopTuple stopTuple,
    int limit,
    TransitStateStore store,
    [EnumeratorCancellation] CancellationToken cancellationToken)
{
    yield return new SseItem<object>(stopTuple, eventType: "initial");

    IReadOnlyList<StopDepartureTuple> BuildDepartures()
    {
        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var list = new List<StopDepartureTuple>();
        int idx = 1;

        foreach (var vehicle in cityData.Vehicles.Values)
        {
            if (!cityData.Trips.TryGetValue(vehicle.TripId, out var trip))
                continue;

            var scheduled = nowMs + idx * 180_000L;
            var delayMs = (idx % 2 == 0) ? 60_000L : 0L;
            list.Add(new StopDepartureTuple(
                Trip: trip,
                Vehicle: vehicle,
                Departure: new StopTimeTuple(scheduled, delayMs, StopDepartureStatus.OnTrip, stopTuple.Code)
            ));
            idx++;
            if (list.Count >= limit) break;
        }

        return list;
    }

    yield return new SseItem<object>(BuildDepartures(), eventType: "message");

    var (subId, reader) = store.Subscribe();
    try
    {
        while (await reader.WaitToReadAsync(cancellationToken))
        {
            while (reader.TryRead(out var updatedCity))
            {
                if (string.Equals(updatedCity, cityData.City.Id, StringComparison.OrdinalIgnoreCase))
                {
                    yield return new SseItem<object>(BuildDepartures(), eventType: "message");
                }
            }
        }
    }
    finally
    {
        store.Unsubscribe(subId);
    }
}

static async IAsyncEnumerable<SseItem<object>> StreamTripOrVehicleAsync(
    CityTransitData cityData,
    string tripId,
    string? vehicleId,
    TransitStateStore store,
    [EnumeratorCancellation] CancellationToken cancellationToken)
{
    if (!cityData.Trips.TryGetValue(tripId, out var trip))
    {
        yield return new SseItem<object>("TRIP_NOT_FOUND", eventType: "errorCode");
        yield break;
    }

    var itineraryStops = cityData.TripItineraries.GetValueOrDefault(tripId, []);
    var shape = cityData.TripEncodedShapes.GetValueOrDefault(tripId, "");

    yield return new SseItem<object>(new
    {
        trip,
        itinerary = new object[] { itineraryStops, shape }
    }, eventType: "initial");

    object BuildRealtimePayload()
    {
        var nowMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        VehicleTuple? pos = null;
        if (vehicleId is not null && cityData.Vehicles.TryGetValue(vehicleId, out var v))
        {
            pos = v;
        }
        else
        {
            pos = cityData.Vehicles.Values.FirstOrDefault(x => string.Equals(x.TripId, tripId, StringComparison.OrdinalIgnoreCase));
        }

        var stopUpdates = itineraryStops.Select((_, idx) =>
        {
            var sched = nowMs + (idx - 1) * 180_000L;
            var stopTime = new StopTimeTuple(sched, 0, StopDepartureStatus.OnTrip);
            return new object[] { stopTime, stopTime };
        }).ToArray();

        return new
        {
            position = pos,
            sequence = Math.Min(1, Math.Max(0, itineraryStops.Count - 1)),
            stops = stopUpdates,
            alerts = Array.Empty<object>()
        };
    }

    yield return new SseItem<object>(BuildRealtimePayload(), eventType: "message");

    var (subId, reader) = store.Subscribe();
    try
    {
        while (await reader.WaitToReadAsync(cancellationToken))
        {
            while (reader.TryRead(out var updatedCity))
            {
                if (string.Equals(updatedCity, cityData.City.Id, StringComparison.OrdinalIgnoreCase))
                {
                    yield return new SseItem<object>(BuildRealtimePayload(), eventType: "message");
                }
            }
        }
    }
    finally
    {
        store.Unsubscribe(subId);
    }
}

public partial class Program;

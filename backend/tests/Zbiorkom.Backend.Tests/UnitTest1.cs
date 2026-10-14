using System.IO.Compression;
using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using ProtoBuf;
using Zbiorkom.Backend.Models;
using Zbiorkom.Backend.Services;

namespace Zbiorkom.Backend.Tests;

public sealed class Api6BackendTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task GetApi6Root_ReturnsCitiesCatalog()
    {
        using var client = factory.CreateClient();
        using var response = await client.GetAsync("/api6");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);

        Assert.Equal("dotnet10-lts", doc.RootElement.GetProperty("hash").GetString());
        var cities = doc.RootElement.GetProperty("cities");
        Assert.True(cities.GetArrayLength() >= 6);
        Assert.Contains(cities.EnumerateArray(), c => c.GetProperty("id").GetString() == "warsaw");
        Assert.Contains(cities.EnumerateArray(), c => c.GetProperty("id").GetString() == "krakow");
        Assert.Contains(cities.EnumerateArray(), c => c.GetProperty("id").GetString() == "grodzisk");
    }

    [Fact]
    public async Task GetRoutesAndSearch_ReturnsPositionalTupleArrays()
    {
        using var client = factory.CreateClient();

        var routesJson = await client.GetStringAsync("/api6/warsaw/routes");
        using var routesDoc = JsonDocument.Parse(routesJson);
        Assert.Equal(JsonValueKind.Array, routesDoc.RootElement.ValueKind);
        var firstRoute = routesDoc.RootElement[0];
        Assert.Equal(JsonValueKind.Array, firstRoute.ValueKind);
        Assert.Equal(7, firstRoute.GetArrayLength());

        var searchJson = await client.GetStringAsync("/api6/warsaw/search?query=Górczewska");
        using var searchDoc = JsonDocument.Parse(searchJson);
        Assert.True(searchDoc.RootElement.GetProperty("results").GetArrayLength() > 0);
    }

    [Fact]
    public async Task StreamMapFeatures_EmitsInitialAndMessageSseFrames()
    {
        using var client = factory.CreateClient();
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        using var request = new HttpRequestMessage(
            HttpMethod.Get,
            "/api6/warsaw/mapFeatures/13/20.8,52.0,21.2,52.4/stream");
        using var response = await client.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cts.Token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("text/event-stream", response.Content.Headers.ContentType?.MediaType);

        await using var stream = await response.Content.ReadAsStreamAsync(cts.Token);
        using var reader = new StreamReader(stream);

        var lines = new List<string>();
        while (lines.Count < 6)
        {
            var line = await reader.ReadLineAsync(cts.Token);
            if (line is null) break;
            lines.Add(line);
        }

        Assert.Contains(lines, l => l == "event: initial");
        Assert.Contains(lines, l => l.StartsWith("data: {\"stops\":", StringComparison.Ordinal));
        Assert.Contains(lines, l => l == "event: message");
        Assert.Contains(lines, l => l.StartsWith("data: {\"positions\":", StringComparison.Ordinal));
    }

    [Fact]
    public async Task StreamStopAndVehicle_EmitsInitialAndRealtimeTuples()
    {
        using var client = factory.CreateClient();
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

        using var stopResp = await client.GetAsync(
            "/api6/warsaw/stops/7002_01/stream?limit=5",
            HttpCompletionOption.ResponseHeadersRead,
            cts.Token);
        Assert.Equal(HttpStatusCode.OK, stopResp.StatusCode);

        await using var stopStream = await stopResp.Content.ReadAsStreamAsync(cts.Token);
        using var stopReader = new StreamReader(stopStream);
        var eventLine = await stopReader.ReadLineAsync(cts.Token);
        var dataLine = await stopReader.ReadLineAsync(cts.Token);

        Assert.Equal("event: initial", eventLine);
        Assert.NotNull(dataLine);
        Assert.StartsWith("data: [\"7002_01\",\"warsaw\"", dataLine);

        using var vehicleResp = await client.GetAsync(
            "/api6/warsaw/positions/bus%3Awtp_5869/stream",
            HttpCompletionOption.ResponseHeadersRead,
            cts.Token);
        Assert.Equal(HttpStatusCode.OK, vehicleResp.StatusCode);

        await using var vehicleStream = await vehicleResp.Content.ReadAsStreamAsync(cts.Token);
        using var vehicleReader = new StreamReader(vehicleStream);
        var vEventLine = await vehicleReader.ReadLineAsync(cts.Token);
        var vDataLine = await vehicleReader.ReadLineAsync(cts.Token);

        Assert.Equal("event: initial", vEventLine);
        Assert.NotNull(vDataLine);
        Assert.Contains("\"itinerary\":", vDataLine);
    }

    [Fact]
    public void GtfsParser_ParsesStaticZipAndRealtimeProtobuf()
    {
        var store = new TransitStateStore();
        var cityData = store.GetCity("warsaw")!;

        using var zipMs = new MemoryStream();
        using (var archive = new ZipArchive(zipMs, ZipArchiveMode.Create, leaveOpen: true))
        {
            var routesEntry = archive.CreateEntry("routes.txt");
            using (var writer = new StreamWriter(routesEntry.Open(), Encoding.UTF8))
            {
                writer.WriteLine("route_id,agency_id,route_short_name,route_long_name,route_type,route_color");
                writer.WriteLine("520,WTP,520,Marysin - Płocka-Szpital,3,d32f2f");
            }

            var stopsEntry = archive.CreateEntry("stops.txt");
            using (var writer = new StreamWriter(stopsEntry.Open(), Encoding.UTF8))
            {
                writer.WriteLine("stop_id,stop_code,stop_name,stop_lat,stop_lon");
                writer.WriteLine("7099_01,01,Metro Politechnika 01,52.2175,21.0148");
            }
        }

        zipMs.Position = 0;
        GtfsFeedParser.LoadStaticZipIntoCity(zipMs, cityData, "WTP");

        Assert.True(cityData.Routes.ContainsKey("520"));
        Assert.True(cityData.Stops.ContainsKey("7099_01"));

        var feedMessage = new GtfsRtFeedMessage
        {
            Entities =
            [
                new GtfsRtFeedEntity
                {
                    Id = "e1",
                    Vehicle = new GtfsRtVehiclePosition
                    {
                        Trip = new GtfsRtTripDescriptor { TripId = "t_520_1", RouteId = "520" },
                        Position = new GtfsRtPosition { Latitude = 52.2180f, Longitude = 21.0155f, Bearing = 90f },
                        Timestamp = 1720000000UL,
                        Vehicle = new GtfsRtVehicleDescriptor { Id = "9901", Label = "9901" }
                    }
                }
            ]
        };

        using var pbMs = new MemoryStream();
        Serializer.Serialize(pbMs, feedMessage);
        pbMs.Position = 0;

        var count = GtfsFeedParser.LoadVehiclePositionsProtobufIntoCity(pbMs, cityData);
        Assert.Equal(1, count);
        Assert.True(cityData.Vehicles.ContainsKey("bus:gtfs_9901"));
    }

    [Fact]
    public void KiedyPrzyjedzieAdapter_ParsesGpaStopsDeparturesAndLiveTripExecution()
    {
        var store = new TransitStateStore();
        var gpaCity = store.GetCity("grodzisk")!;

        const string stopsJson = """
        {
          "stops": [
            ["538522:585919", 1204101, "Grodzisk Maz. Dw. PKP", 20622327, 52109692, 0, 0, 0],
            ["538483:585844", 1200101, "Adamowizna Królicza", 20632442, 52072347, 0, 0, 0]
          ]
        }
        """;

        var loadedStops = GtfsFeedParser.LoadKiedyPrzyjedzieStopsIntoCity(stopsJson, gpaCity);
        Assert.Equal(2, loadedStops);
        Assert.Equal(20.622327, gpaCity.Stops["538522:585919"].Longitude);
        Assert.Equal(52.109692, gpaCity.Stops["538522:585919"].Latitude);

        const string departuresJson = """
        {
          "status": "ok",
          "departures": [
            {
              "designator": 1200101,
              "rows": [
                {
                  "time": "6 min",
                  "is_estimated": true,
                  "direction_id": 585844000,
                  "line_name": "31",
                  "trip_id": 49154351,
                  "trip_execution_id": "A 312 (31):739903:11",
                  "trip_index": 29
                }
              ]
            }
          ],
          "directions": {
            "585844000": "Grodzisk Maz. Dw. PKP"
          }
        }
        """;

        var activeTrips = GtfsFeedParser.ParseKiedyPrzyjedzieDepartures(departuresJson);
        Assert.Single(activeTrips);
        Assert.Equal("31", activeTrips[0].LineName);
        Assert.Equal("A 312 (31):739903:11", activeTrips[0].TripExecutionId);
        Assert.Equal("QSAzMTIgKDMxKTo3Mzk5MDM6MTE=", GtfsFeedParser.EncodeTripExecutionIdBase64(activeTrips[0].TripExecutionId));

        const string tripExecutionJson = """
        {
          "vehicle": { "lon": 20.649946, "lat": 52.045828 },
          "estimated": true,
          "vehicle_trip_index": 1,
          "trip": {
            "line": "31",
            "direction": "Grodzisk Maz. Dw. PKP",
            "times": [
              { "stop_name": "Adamowizna Królicza", "designator": 1200101, "place_id": "538483:585844", "departure_time": "19:20", "index": 0 },
              { "stop_name": "Grodzisk Maz. Dw. PKP", "designator": 1204101, "place_id": "538522:585919", "departure_time": "19:35", "index": 1 }
            ]
          }
        }
        """;

        var ok = GtfsFeedParser.LoadKiedyPrzyjedzieTripExecutionIntoCity(
            tripExecutionJson,
            activeTrips[0].TripExecutionId,
            activeTrips[0].LineName,
            activeTrips[0].Direction,
            "GPA",
            gpaCity);

        Assert.True(ok);
        Assert.True(gpaCity.Vehicles.TryGetValue("bus:gpa_312", out var vehicle));
        Assert.Equal(20.649946, vehicle!.Longitude);
        Assert.Equal(52.045828, vehicle.Latitude);
        Assert.Equal("312", vehicle.Brigade);
        Assert.True(gpaCity.Trips.ContainsKey(vehicle.TripId));
        Assert.True(gpaCity.TripItineraries.ContainsKey(vehicle.TripId));
        Assert.True(gpaCity.TripEncodedShapes.ContainsKey(vehicle.TripId));
    }
}

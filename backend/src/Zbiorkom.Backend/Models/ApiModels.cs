using System.Text.Json;
using System.Text.Json.Serialization;

namespace Zbiorkom.Backend.Models;

public enum VehicleType
{
    Tram = 0,
    Subway = 1,
    Train = 2,
    Bus = 3,
    Ferry = 4,
    AerialLift = 6,
    Funicular = 7,
    Trolleybus = 11,
    Monorail = 12
}

public enum StopDepartureStatus
{
    Scheduled = 0,
    OnTrip = 1,
    OnPreviousTrip = 2,
    Cancelled = 3
}

public sealed record DataSourceInfo(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("provider")] string Provider,
    [property: JsonPropertyName("providerUrl")] string ProviderUrl
);

public sealed record CityAgencyDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("icon")] string? Icon = null,
    [property: JsonPropertyName("faresUrl")] string? FaresUrl = null,
    [property: JsonPropertyName("dataSources")] IReadOnlyList<DataSourceInfo>? DataSources = null
);

public sealed record CityDto(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("location")] double[] Location,
    [property: JsonPropertyName("timezone")] string Timezone,
    [property: JsonPropertyName("zoom")] double Zoom = 13.0,
    [property: JsonPropertyName("description")] string? Description = null,
    [property: JsonPropertyName("virtual")] bool Virtual = false,
    [property: JsonPropertyName("agencies")] IReadOnlyDictionary<string, CityAgencyDto>? Agencies = null
);

public sealed record Api6RootResponse(
    [property: JsonPropertyName("hash")] string Hash,
    [property: JsonPropertyName("shouldUpdate")] bool ShouldUpdate,
    [property: JsonPropertyName("cities")] IReadOnlyList<CityDto> Cities
);

[JsonConverter(typeof(RouteTupleJsonConverter))]
public sealed record RouteTuple(
    string Id,
    string City,
    string Name,
    string LongName,
    string Agency,
    VehicleType Type,
    string Color
);

[JsonConverter(typeof(VehicleTupleJsonConverter))]
public sealed record VehicleTuple(
    string Id,
    string City,
    RouteTuple Route,
    string Brigade,
    double Longitude,
    double Latitude,
    double Bearing,
    long LastPing,
    string TripId,
    double PercentTraveled,
    string? Model = null,
    int? ProdYear = null,
    string? Carrier = null
);

[JsonConverter(typeof(DotVehicleTupleJsonConverter))]
public sealed record DotVehicleTuple(
    string RouteColor,
    double Longitude,
    double Latitude
);

[JsonConverter(typeof(StopTupleJsonConverter))]
public sealed record StopTuple(
    string Id,
    string City,
    string Name,
    string Code,
    double Longitude,
    double Latitude,
    IReadOnlyList<VehicleType> Types,
    double Bearing,
    string Direction,
    IReadOnlyList<RouteTuple> Routes
);

[JsonConverter(typeof(StopTimeTupleJsonConverter))]
public sealed record StopTimeTuple(
    long ScheduledEpochMs,
    long? DelayMs,
    StopDepartureStatus Status,
    string? Platform = null
);

[JsonConverter(typeof(TripTupleJsonConverter))]
public sealed record TripTuple(
    string Id,
    string City,
    RouteTuple Route,
    string Headsign,
    string Brigade,
    string ShortName,
    IReadOnlyList<(string Key, string Value)> Description,
    (string StopName, long ArrivalMs)? FirstStop = null,
    (string StopName, long DepartureMs)? LastStop = null,
    double? Distance = null
);

[JsonConverter(typeof(StopDepartureTupleJsonConverter))]
public sealed record StopDepartureTuple(
    TripTuple Trip,
    VehicleTuple? Vehicle,
    StopTimeTuple Departure,
    StopTimeTuple? Destination = null
);

[JsonConverter(typeof(ItineraryStopTupleJsonConverter))]
public sealed record ItineraryStopTuple(
    StopTuple Stop,
    int AlightFlags,
    double Distance,
    string? Platform = null
);

[JsonConverter(typeof(VehicleInfoTupleJsonConverter))]
public sealed record VehicleInfoTuple(
    string Id,
    string Model,
    int ProdYear,
    string Carrier,
    string ImageHash = ""
);

[JsonConverter(typeof(BrigadeTupleJsonConverter))]
public sealed record BrigadeTuple(
    string Brigade,
    int NumberOfTrips,
    IReadOnlyList<(long StartMs, long EndMs)> RunningHours
);

[JsonConverter(typeof(BrigadeTripTupleJsonConverter))]
public sealed record BrigadeTripTuple(
    string Id,
    RouteTuple Route,
    string StartStop,
    string EndStop,
    long StartMs,
    long EndMs,
    double Distance,
    string? VehicleId = null,
    double? PercentTraveled = null
);

[JsonConverter(typeof(ExecutionTupleJsonConverter))]
public sealed record ExecutionTuple(
    string TripId,
    string RouteId,
    string Brigade,
    string VehicleId,
    string OriginStopId,
    string OriginName,
    string DestStopId,
    string DestName,
    long ScheduledStartMs,
    long ActualStartMs,
    int StartDelaySec,
    long ScheduledEndMs,
    long ActualEndMs,
    int EndDelaySec,
    int Segments
);

public sealed record RouteGraphStopTuple(
    string Id,
    string City,
    string Name,
    string Code,
    double Longitude,
    double Latitude,
    IReadOnlyList<VehicleType> Types,
    double Bearing = 0
);

public sealed record RouteGraphBranchDto(
    [property: JsonPropertyName("from")] int From,
    [property: JsonPropertyName("to")] int To,
    [property: JsonPropertyName("stops")] IReadOnlyList<object[]> Stops,
    [property: JsonPropertyName("collapse")] int[]? Collapse = null
);

public sealed record RouteGraphDirectionDto(
    [property: JsonPropertyName("headsign")] string Headsign,
    [property: JsonPropertyName("trunk")] IReadOnlyList<object[]> Trunk,
    [property: JsonPropertyName("branches")] IReadOnlyList<RouteGraphBranchDto> Branches
);

public sealed record RouteGraphResponseDto(
    [property: JsonPropertyName("route")] RouteTuple Route,
    [property: JsonPropertyName("graph")] IReadOnlyList<RouteGraphDirectionDto> Graph,
    [property: JsonPropertyName("shapes")] IReadOnlyList<IReadOnlyList<string>> Shapes
);

public sealed class RouteTupleJsonConverter : JsonConverter<RouteTuple>
{
    public override RouteTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, RouteTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.Id);
        writer.WriteStringValue(value.City);
        writer.WriteStringValue(value.Name);
        writer.WriteStringValue(value.LongName);
        writer.WriteStringValue(value.Agency);
        writer.WriteNumberValue((int)value.Type);
        writer.WriteStringValue(value.Color);
        writer.WriteEndArray();
    }
}

public sealed class VehicleTupleJsonConverter : JsonConverter<VehicleTuple>
{
    public override VehicleTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, VehicleTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.Id);
        writer.WriteStringValue(value.City);
        JsonSerializer.Serialize(writer, value.Route, options);
        writer.WriteStringValue(value.Brigade);
        writer.WriteStartArray();
        writer.WriteNumberValue(value.Longitude);
        writer.WriteNumberValue(value.Latitude);
        writer.WriteEndArray();
        writer.WriteNumberValue(value.Bearing);
        writer.WriteNumberValue(value.LastPing);
        writer.WriteStringValue(value.TripId);
        writer.WriteNumberValue(value.PercentTraveled);
        writer.WriteEndArray();
    }
}

public sealed class DotVehicleTupleJsonConverter : JsonConverter<DotVehicleTuple>
{
    public override DotVehicleTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, DotVehicleTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.RouteColor);
        writer.WriteStartArray();
        writer.WriteNumberValue(value.Longitude);
        writer.WriteNumberValue(value.Latitude);
        writer.WriteEndArray();
        writer.WriteEndArray();
    }
}

public sealed class StopTupleJsonConverter : JsonConverter<StopTuple>
{
    public override StopTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, StopTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.Id);
        writer.WriteStringValue(value.City);
        writer.WriteStringValue(value.Name);
        writer.WriteStringValue(value.Code);
        writer.WriteStartArray();
        writer.WriteNumberValue(value.Longitude);
        writer.WriteNumberValue(value.Latitude);
        writer.WriteEndArray();
        writer.WriteStartArray();
        foreach (var type in value.Types)
            writer.WriteNumberValue((int)type);
        writer.WriteEndArray();
        writer.WriteNumberValue(value.Bearing);
        writer.WriteStringValue(value.Direction);
        writer.WriteStartArray();
        foreach (var route in value.Routes)
            JsonSerializer.Serialize(writer, route, options);
        writer.WriteEndArray();
        writer.WriteEndArray();
    }
}

public sealed class StopTimeTupleJsonConverter : JsonConverter<StopTimeTuple>
{
    public override StopTimeTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, StopTimeTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteNumberValue(value.ScheduledEpochMs);
        if (value.DelayMs.HasValue)
            writer.WriteNumberValue(value.DelayMs.Value);
        else
            writer.WriteNullValue();
        writer.WriteNumberValue((int)value.Status);
        if (value.Platform is not null)
            writer.WriteStringValue(value.Platform);
        writer.WriteEndArray();
    }
}

public sealed class TripTupleJsonConverter : JsonConverter<TripTuple>
{
    public override TripTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, TripTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.Id);
        writer.WriteStringValue(value.City);
        JsonSerializer.Serialize(writer, value.Route, options);
        writer.WriteStringValue(value.Headsign);
        writer.WriteStringValue(value.Brigade);
        writer.WriteStringValue(value.ShortName);
        writer.WriteStartArray();
        foreach (var (key, descVal) in value.Description)
        {
            writer.WriteStartArray();
            writer.WriteStringValue(key);
            writer.WriteStringValue(descVal);
            writer.WriteEndArray();
        }
        writer.WriteEndArray();

        if (value.FirstStop.HasValue)
        {
            writer.WriteStartArray();
            writer.WriteStringValue(value.FirstStop.Value.StopName);
            writer.WriteNumberValue(value.FirstStop.Value.ArrivalMs);
            writer.WriteEndArray();
        }
        else
        {
            writer.WriteNullValue();
        }

        if (value.LastStop.HasValue)
        {
            writer.WriteStartArray();
            writer.WriteStringValue(value.LastStop.Value.StopName);
            writer.WriteNumberValue(value.LastStop.Value.DepartureMs);
            writer.WriteEndArray();
        }
        else
        {
            writer.WriteNullValue();
        }

        if (value.Distance.HasValue)
            writer.WriteNumberValue(value.Distance.Value);

        writer.WriteEndArray();
    }
}

public sealed class StopDepartureTupleJsonConverter : JsonConverter<StopDepartureTuple>
{
    public override StopDepartureTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, StopDepartureTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        JsonSerializer.Serialize(writer, value.Trip, options);
        if (value.Vehicle is not null)
            JsonSerializer.Serialize(writer, value.Vehicle, options);
        else
            writer.WriteNullValue();
        JsonSerializer.Serialize(writer, value.Departure, options);
        if (value.Destination is not null)
            JsonSerializer.Serialize(writer, value.Destination, options);
        writer.WriteEndArray();
    }
}

public sealed class ItineraryStopTupleJsonConverter : JsonConverter<ItineraryStopTuple>
{
    public override ItineraryStopTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, ItineraryStopTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        JsonSerializer.Serialize(writer, value.Stop, options);
        writer.WriteNumberValue(value.AlightFlags);
        writer.WriteNumberValue(value.Distance);
        if (value.Platform is not null)
            writer.WriteStringValue(value.Platform);
        writer.WriteEndArray();
    }
}

public sealed class VehicleInfoTupleJsonConverter : JsonConverter<VehicleInfoTuple>
{
    public override VehicleInfoTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, VehicleInfoTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.Id);
        writer.WriteStringValue(value.Model);
        writer.WriteNumberValue(value.ProdYear);
        writer.WriteStringValue(value.Carrier);
        writer.WriteStringValue(value.ImageHash);
        writer.WriteEndArray();
    }
}

public sealed class BrigadeTupleJsonConverter : JsonConverter<BrigadeTuple>
{
    public override BrigadeTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, BrigadeTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.Brigade);
        writer.WriteNumberValue(value.NumberOfTrips);
        writer.WriteStartArray();
        foreach (var (start, end) in value.RunningHours)
        {
            writer.WriteStartArray();
            writer.WriteNumberValue(start);
            writer.WriteNumberValue(end);
            writer.WriteEndArray();
        }
        writer.WriteEndArray();
        writer.WriteEndArray();
    }
}

public sealed class BrigadeTripTupleJsonConverter : JsonConverter<BrigadeTripTuple>
{
    public override BrigadeTripTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, BrigadeTripTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.Id);
        JsonSerializer.Serialize(writer, value.Route, options);
        writer.WriteStringValue(value.StartStop);
        writer.WriteStringValue(value.EndStop);
        writer.WriteNumberValue(value.StartMs);
        writer.WriteNumberValue(value.EndMs);
        writer.WriteNumberValue(value.Distance);
        if (value.VehicleId is not null)
            writer.WriteStringValue(value.VehicleId);
        else
            writer.WriteNullValue();
        if (value.PercentTraveled.HasValue)
            writer.WriteNumberValue(value.PercentTraveled.Value);
        writer.WriteEndArray();
    }
}

public sealed class ExecutionTupleJsonConverter : JsonConverter<ExecutionTuple>
{
    public override ExecutionTuple Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        => throw new NotSupportedException();

    public override void Write(Utf8JsonWriter writer, ExecutionTuple value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        writer.WriteStringValue(value.TripId);
        writer.WriteStringValue(value.RouteId);
        writer.WriteStringValue(value.Brigade);
        writer.WriteStringValue(value.VehicleId);
        writer.WriteStringValue(value.OriginStopId);
        writer.WriteStringValue(value.OriginName);
        writer.WriteStringValue(value.DestStopId);
        writer.WriteStringValue(value.DestName);
        writer.WriteNumberValue(value.ScheduledStartMs);
        writer.WriteNumberValue(value.ActualStartMs);
        writer.WriteNumberValue(value.StartDelaySec);
        writer.WriteNumberValue(value.ScheduledEndMs);
        writer.WriteNumberValue(value.ActualEndMs);
        writer.WriteNumberValue(value.EndDelaySec);
        writer.WriteNumberValue(value.Segments);
        writer.WriteEndArray();
    }
}

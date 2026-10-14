# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["Zbiorkom.Backend.sln", "./"]
COPY ["src/Zbiorkom.Backend/Zbiorkom.Backend.csproj", "src/Zbiorkom.Backend/"]
RUN dotnet restore "src/Zbiorkom.Backend/Zbiorkom.Backend.csproj"

COPY ["src/Zbiorkom.Backend/", "src/Zbiorkom.Backend/"]
RUN dotnet publish "src/Zbiorkom.Backend/Zbiorkom.Backend.csproj" \
    -c Release \
    -o /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8005
ENV ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8005

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "Zbiorkom.Backend.dll"]

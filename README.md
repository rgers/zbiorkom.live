# zbiorkom.live

Real-time Polish & European public transport tracking across:

- **Web PWA (`src/`)** — React 19, TypeScript, MapLibre, TanStack Query, Zustand, SSE
- **Mobile App (`mobile/`)** — Flutter iOS & Android application
- **Backend (`backend/`)** — .NET 10 LTS (`net10.0`) ASP.NET Core Minimal API + Server-Sent Events (`TypedResults.ServerSentEvents`) + GTFS / GTFS-Realtime ingestion

---

## Quick Start: Run the Backend with Docker Compose

Start the `.NET 10 LTS` `/api6` backend on port `8005`:

```bash
docker compose up --build
```

Verify the backend is running:

```bash
curl http://localhost:8005/healthz
curl http://localhost:8005/api6
```

### Optional: Connect Live Upstream GTFS / GTFS-Realtime Feeds

You can pass upstream GTFS Static (`.zip`) and GTFS-Realtime VehiclePositions (`.pb`) URLs via environment variables when launching Docker Compose:

```bash
KRAKOW_GTFS_STATIC_URL="https://gtfs.ztp.krakow.pl/GTFS_KRK_T.zip" \
KRAKOW_GTFS_RT_VEHICLES_URL="https://gtfs.ztp.krakow.pl/VehiclePositions_T.pb" \
docker compose up --build
```

---

## Run the Web App Against Your Local Backend

```bash
npm install
VITE_API_BASE=http://localhost:8005 VITE_CLOUD_API_BASE=http://localhost:8005 npm start
```

---

## Run the Flutter Mobile App (iOS & Android)

```bash
cd mobile
flutter pub get
flutter run --dart-define=ZBIORKOM_API_BASE=http://localhost:8005 --dart-define=ZBIORKOM_CLOUD_BASE=http://localhost:8005
```

_(Note: on Android Emulator, use `http://10.0.2.2:8005` instead of `localhost:8005` to reach the host machine.)_

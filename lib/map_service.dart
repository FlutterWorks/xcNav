import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/secrets.dart';

enum MapTileSrc {
  topo,
  sectional,
  satellite,
  airspace,
  airports,
}

TileProvider? makeTileProvider(String instanceName) {
  try {
    return FMTC.instance(instanceName).getTileProvider(
          FMTCTileProviderSettings(
            behavior: CacheBehavior.cacheFirst,
            cachedValidDuration: const Duration(days: 14),
          ),
        );
  } catch (e, trace) {
    debugPrint("Error making tile provider $instanceName : $e $trace");
    return null;
  }
}

TileLayer getMapTileLayer(MapTileSrc tileSrc, double opacity) {
  final tileName = tileSrc.toString().split(".").last;
  switch (tileSrc) {
    case MapTileSrc.sectional:
      return TileLayer(
          urlTemplate: 'http://wms.chartbundle.com/tms/v1.0/sec/{z}/{x}/{y}.png?type=google',
          tileProvider: makeTileProvider(tileName),
          maxNativeZoom: 13,
          minZoom: 4,
          opacity: opacity * 0.8 + 0.2);
    case MapTileSrc.satellite:
      return TileLayer(
          urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          tileProvider: makeTileProvider(tileName),
          maxNativeZoom: 19,
          opacity: opacity * 0.8 + 0.2);
    // https://docs.openaip.net/?urls.primaryName=Tiles%20API
    case MapTileSrc.airspace:
      return TileLayer(
          urlTemplate: 'https://api.tiles.openaip.net/api/data/airspaces/{z}/{x}/{y}.png?apiKey={apiKey}',
          tileProvider: makeTileProvider(tileName),
          backgroundColor: Colors.transparent,
          // maxZoom: 11,
          maxNativeZoom: 11,
          minZoom: 7,
          additionalOptions: const {"apiKey": aipClientToken});
    case MapTileSrc.airports:
      return TileLayer(
          urlTemplate: 'https://api.tiles.openaip.net/api/data/airports/{z}/{x}/{y}.png?apiKey={apiKey}',
          tileProvider: makeTileProvider(tileName),
          backgroundColor: Colors.transparent,
          maxZoom: 11,
          minZoom: 9,
          additionalOptions: const {"apiKey": aipClientToken});
    default:
      return TileLayer(
        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
        // urlTemplate: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png", // Use this line to test seeing the elevation map
        tileProvider: makeTileProvider(tileName),
        maxNativeZoom: 14,
        opacity: opacity,
      );
  }
}

final Map<MapTileSrc, Image> mapTileThumbnails = {
  MapTileSrc.topo: Image.asset(
    "assets/images/topo.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  ),
  MapTileSrc.sectional: Image.asset(
    "assets/images/sectional.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  ),
  MapTileSrc.satellite: Image.asset(
    "assets/images/satellite.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  ),
  MapTileSrc.airspace: Image.asset(
    "assets/images/sectional.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  ),
  MapTileSrc.airports: Image.asset(
    "assets/images/sectional.png",
    filterQuality: FilterQuality.high,
    fit: BoxFit.cover,
  )
};

Future initMapCache() async {
  FlutterMapTileCaching.initialise(await RootDirectory.normalCache);
  await initDemCache();

  for (final tileSrc in mapTileThumbnails.keys) {
    final tileName = tileSrc.toString().split(".").last;
    final StoreDirectory store = FMTC.instance(tileName);
    await store.manage.createAsync();
    await store.metadata.addAsync(key: 'sourceURL', value: getMapTileLayer(tileSrc, 1).urlTemplate!);
    await store.metadata.addAsync(
      key: 'validDuration',
      value: '14',
    );
    await store.metadata.addAsync(
      key: 'behaviour',
      value: 'cacheFirst',
    );
  }

  // Do a regular purge of old tiles
  purgeMapTileCache();
}

String asReadableSize(double value) {
  if (value <= 0) return '0 B';
  final List<String> units = ['B', 'kB', 'MB', 'GB', 'TB'];
  final int digitGroups = (log(value) / log(1024)).round();
  return '${NumberFormat('#,##0.#').format(value / pow(1024, digitGroups))} ${units[digitGroups]}';
}

Future<String> getMapTileCacheSize() async {
  // Add together the cache size for all base map layers
  double sum = 0;
  for (final tileSrc in mapTileThumbnails.keys) {
    final tileName = tileSrc.toString().split(".").last;
    final StoreDirectory store = FMTC.instance(tileName);
    sum += (await store.stats.noCache.storeSizeAsync) * 1024;
  }

  // Also add the elevation map
  final StoreDirectory demStore = FMTC.instance("dem");
  sum += (await demStore.stats.noCache.storeSizeAsync) * 1024;

  return asReadableSize(sum);
}

void purgeMapTileCache() async {
  final threshhold = DateTime.now().subtract(const Duration(days: 14));
  for (final tileSrc in mapTileThumbnails.keys) {
    final tileName = tileSrc.toString().split(".").last;
    final StoreDirectory store = FMTC.instance(tileName);
    int countDelete = 0;
    int countRemain = 0;
    for (final tile in store.access.tiles.listSync()) {
      if (tile.statSync().changed.isBefore(threshhold)) {
        // debugPrint("Deleting Tile: ${tile.path}");
        tile.deleteSync();
        countDelete++;
      } else {
        countRemain++;
      }
    }
    debugPrint("Scanned $tileName and deleted $countDelete / ${countRemain + countDelete} tiles.");
    store.stats.invalidateCachedStatistics();
  }
}

void emptyMapTileCache() {
  // Empty elevation map cache
  final StoreDirectory demStore = FMTC.instance("dem");
  debugPrint("Clear Map Cache: dem");
  demStore.manage.reset();

  // Empty standard map caches
  for (final tileSrc in mapTileThumbnails.keys) {
    final tileName = tileSrc.toString().split(".").last;
    final StoreDirectory store = FMTC.instance(tileName);
    debugPrint("Clear Map Cache: $tileName");
    store.manage.reset();
  }
}

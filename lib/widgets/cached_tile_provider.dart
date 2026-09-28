import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/cache/map_tile_cache_manager.dart';

/// Cached tile provider for flutter_map
/// Downloads and caches map tiles to improve performance and enable offline usage
class CachedTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    
    return CachedNetworkImageProvider(
      url,
      cacheManager: MapTileCacheManager.instance,
      errorListener: (error) {
        debugPrint('⚠️ Tile load error: $error');
      },
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:media_metadata/media_metadata.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../utils/playlist.dart';

class MusicService {
  final Saf saf = Saf();

  static const String folderKey = 'music_folder_uri';

  static const String volumeKey = 'music_volume';

  static const String themeIndexKey = 'theme_index';

  static const String favoritesKey = 'favorites_list';

  static const String lastSongIndexKey = 'last_song_index';

  static const String lastPositionMsKey = 'last_position_ms';

  // Número máximo de MP3 em cache. O mais antigo é apagado quando passa disso.
  static const int maxCacheEntries = 20;

  // ============================================================
  // PASTA DE MÚSICAS
  // ============================================================

  Future<void> saveFolder(String uri) async {
    final prefs = SharedPreferencesAsync();

    await prefs.setString(folderKey, uri);
  }

  Future<String?> getSavedFolder() async {
    final prefs = SharedPreferencesAsync();

    return prefs.getString(folderKey);
  }

  // ============================================================
  // VOLUME
  // ============================================================

  Future<void> saveVolume(double volume) async {
    final prefs = SharedPreferencesAsync();

    await prefs.setDouble(volumeKey, volume);
  }

  Future<double> getVolume() async {
    final prefs = SharedPreferencesAsync();

    return (await prefs.getDouble(volumeKey)) ?? 1.0;
  }

  // ============================================================
  // TEMA DE COR
  // ============================================================

  Future<int> getThemeIndex() async {
    final prefs = SharedPreferencesAsync();

    return (await prefs.getInt(themeIndexKey)) ?? 0;
  }

  Future<void> saveThemeIndex(int index) async {
    final prefs = SharedPreferencesAsync();

    await prefs.setInt(themeIndexKey, index);
  }

  // ============================================================
  // FAVORITAS
  // ============================================================

  Future<List<String>> getFavorites() async {
    final prefs = SharedPreferencesAsync();

    return (await prefs.getStringList(favoritesKey)) ?? const [];
  }

  Future<bool> toggleFavorite(String file) async {
    final list = toggleFavoriteInList(await getFavorites(), file);

    final prefs = SharedPreferencesAsync();

    await prefs.setStringList(favoritesKey, list);

    return list.contains(file);
  }

  // ============================================================
  // RETOMAR ONDE PAROU
  // ============================================================

  Future<int> getLastSongIndex() async {
    final prefs = SharedPreferencesAsync();

    return (await prefs.getInt(lastSongIndexKey)) ?? 0;
  }

  Future<void> saveLastSongIndex(int index) async {
    final prefs = SharedPreferencesAsync();

    await prefs.setInt(lastSongIndexKey, index);
  }

  Future<int> getLastPositionMs() async {
    final prefs = SharedPreferencesAsync();

    return (await prefs.getInt(lastPositionMsKey)) ?? 0;
  }

  Future<void> saveLastPositionMs(int milliseconds) async {
    final prefs = SharedPreferencesAsync();

    await prefs.setInt(lastPositionMsKey, milliseconds);
  }

  Future<List<Song>> chooseMusicFolder() async {
    final directory = await saf.pickDirectory(
      persistablePermission: true,
      writePermission: false,
    );

    if (directory == null) {
      return [];
    }

    await saveFolder(directory.uri);

    return await loadSongsFromFolder(directory.uri);
  }

  Future<List<Song>> loadSavedMusic() async {
    final savedUri = await getSavedFolder();

    if (savedUri == null || savedUri.isEmpty) {
      return [];
    }

    final exists = await saf.exists(savedUri);

    if (!exists) {
      return [];
    }

    return await loadSongsFromFolder(savedUri);
  }

  // ============================================================
  // CARREGAR LISTA
  // ============================================================

  /// Encontra os MP3 sem copiar os ficheiros.
  ///
  /// O artista é obtido diretamente do nome do ficheiro:
  ///
  /// "Nujabes - Luv (sic) pt2.mp3"
  ///
  /// resulta em:
  ///
  /// Artista: Nujabes
  /// Título: Luv (sic) pt2
  Future<List<Song>> loadSongsFromFolder(String folderUri) async {
    final songs = <Song>[];

    try {
      await for (final entry in saf.walk(folderUri)) {
        final file = entry.file;

        if (file.isDir) {
          continue;
        }

        final name = file.name;

        // Apenas MP3
        if (!name.toLowerCase().endsWith('.mp3')) {
          continue;
        }

        // Remove .mp3
        final filename = name.replaceFirst(
          RegExp(r'\.mp3$', caseSensitive: false),
          '',
        );

        // --------------------------------------------------------
        // Extrair artista e título do nome
        // --------------------------------------------------------

        final parsed = parseSongFilename(filename);

        songs.add(
          Song(title: parsed.title, artist: parsed.artist, file: file.uri),
        );
      }
    } catch (e) {
      // Ignore inaccessible files/folders and keep the songs found so far.
    }

    // ==========================================================
    // ORDENAR PLAYLIST
    // ==========================================================

    songs.sort((a, b) => compareSongs(a.title, b.title));

    return songs;
  }

  // ============================================================
  // PREPARAR MÚSICA
  // ============================================================

  /// Só é executado quando a música é realmente aberta.
  ///
  /// Aqui:
  /// 1. Copia para cache (nome único baseado no URI, evita colisões).
  /// 2. Lê metadata.
  /// 3. Extrai capa.
  Future<Song> prepareSong(Song song) async {
    try {
      final tempDirectory = await getTemporaryDirectory();

      final id = base64Url.encode(utf8.encode(song.file)).replaceAll('=', '');

      final localPath = '${tempDirectory.path}/tsuki_$id.mp3';

      final localFile = File(localPath);

      // --------------------------------------------------------
      // CACHE
      // --------------------------------------------------------

      if (!await localFile.exists()) {
        await saf.copyToLocalFile(song.file, localPath);
      }

      // --------------------------------------------------------
      // METADATA
      // --------------------------------------------------------

      final metadata = await MediaMetadata.read(localPath);

      String title = song.title;
      String artist = song.artist;

      if (metadata != null) {
        if (metadata.title != null && metadata.title!.trim().isNotEmpty) {
          title = metadata.title!.trim();
        }

        if (metadata.artist != null && metadata.artist!.trim().isNotEmpty) {
          artist = metadata.artist!.trim();
        }
      }

      // --------------------------------------------------------
      // CAPA
      // --------------------------------------------------------

      final cover = metadata?.imageMetadata?.data;

      // --------------------------------------------------------
      // LIMPAR CACHE ANTIGO
      // --------------------------------------------------------

      await _cleanupCache(keepPath: localPath);

      // --------------------------------------------------------
      // RESULTADO
      // --------------------------------------------------------

      return Song(
        title: title,
        artist: artist,
        file: localPath,
        cover: cover,
        duration: metadata?.duration ?? Duration.zero,
      );
    } catch (e) {
      // Se falhar, devolve a música original; o áudio ainda pode tocar.
      return song;
    }
  }

  // ============================================================
  // LIMPAR CACHE
  // ============================================================

  /// Mantém no máximo [maxCacheEntries] MP3 em cache.
  /// Apaga os mais antigos, exceto o que está a ser usado agora.
  Future<void> _cleanupCache({required String keepPath}) async {
    try {
      final directory = await getTemporaryDirectory();

      final files = directory
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.contains('tsuki_') && f.path.endsWith('.mp3'),
          )
          .toList();

      if (files.length <= maxCacheEntries) {
        return;
      }

      files.sort((a, b) => a
          .statSync()
          .modified
          .compareTo(b.statSync().modified));

      while (files.length > maxCacheEntries) {
        final oldest = files.removeAt(0);

        if (oldest.path != keepPath) {
          try {
            oldest.deleteSync();
          } catch (e) {
            // Ignora ficheiros que não consegue apagar.
          }
        }
      }
    } catch (e) {
      // Falha na limpeza nunca deve impedir a música de carregar.
    }
  }
}

/// Alterna a presença de [file] na lista de favoritos.
///
/// Devolve uma NOVA lista (o input nunca é mutado) — importante porque o
/// `SharedPreferencesAsync` devolve listas imodificáveis.
List<String> toggleFavoriteInList(List<String> favorites, String file) {
  final next = [...favorites];

  if (next.contains(file)) {
    next.remove(file);
  } else {
    next.add(file);
  }

  return next;
}
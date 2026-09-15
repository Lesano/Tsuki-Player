import 'dart:io';

import 'package:media_metadata/media_metadata.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

class MusicService {
  final Saf saf = Saf();

  static const String folderKey = 'music_folder_uri';

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

  Future<List<Song>> chooseMusicFolder() async {
    try {
      final directory = await saf.pickDirectory(
        persistablePermission: true,
        writePermission: false,
      );

      if (directory == null) {
        return [];
      }


      await saveFolder(directory.uri);

      return await loadSongsFromFolder(directory.uri);
    } catch (e) {
      return [];
    }
  }

  Future<List<Song>> loadSavedMusic() async {
    final savedUri = await getSavedFolder();

    if (savedUri == null || savedUri.isEmpty) {
      return [];
    }


    try {
      final exists = await saf.exists(savedUri);

      if (!exists) {
        return [];
      }

      return await loadSongsFromFolder(savedUri);
    } catch (e) {
      return [];
    }
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

        final parsed = _parseFilename(filename);

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

    songs.sort(_compareSongs);


    for (var i = 0; i < songs.length; i++) {
    }

    return songs;
  }

  // ============================================================
  // EXTRAIR ARTISTA / TÍTULO
  // ============================================================

  _ParsedSong _parseFilename(String filename) {
    // Procura:
    //
    // Artista - Título
    //
    final separatorIndex = filename.indexOf(' - ');

    if (separatorIndex > 0) {
      final artist = filename.substring(0, separatorIndex).trim();

      final title = filename.substring(separatorIndex + 3).trim();

      if (artist.isNotEmpty && title.isNotEmpty) {
        return _ParsedSong(artist: artist, title: title);
      }
    }

    // Se não tiver " - ", usamos o nome completo
    // como título.
    return _ParsedSong(artist: 'Desconhecido', title: filename.trim());
  }

  // ============================================================
  // ORDENAR PLAYLIST
  // ============================================================

  int _compareSongs(Song a, Song b) {
    final aNumber = _getTrackNumber(a.title);
    final bNumber = _getTrackNumber(b.title);

    // Ambas têm número
    if (aNumber != null && bNumber != null) {
      final result = aNumber.compareTo(bNumber);

      if (result != 0) {
        return result;
      }
    }

    // Apenas A tem número
    if (aNumber != null && bNumber == null) {
      return -1;
    }

    // Apenas B tem número
    if (aNumber == null && bNumber != null) {
      return 1;
    }

    // Fallback
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  int? _getTrackNumber(String title) {
    final normalized = title.toLowerCase().trim();

    // ----------------------------------------------------------
    // Luv (sic) original
    // ----------------------------------------------------------

    if (RegExp(r'luv\s*\(sic\)\.?\s*$').hasMatch(normalized)) {
      return 1;
    }

    // ----------------------------------------------------------
    // Grand Finale
    // ----------------------------------------------------------

    if (normalized.contains('grand finale')) {
      return 6;
    }

    // ----------------------------------------------------------
    // pt2, pt3, pt4, pt5, pt6...
    // ----------------------------------------------------------

    final partMatch = RegExp(r'\bpt\s*(\d+)\b').firstMatch(normalized);

    if (partMatch != null) {
      final number = int.tryParse(partMatch.group(1)!);

      if (number == null) {
        return null;
      }

      // pt6 Uyama Hiroto Remix fica depois
      // do Grand Finale.
      if (number == 6) {
        return 7;
      }

      return number;
    }

    return null;
  }

  // ============================================================
  // PREPARAR MÚSICA
  // ============================================================

  /// Só é executado quando a música é realmente aberta.
  ///
  /// Aqui:
  /// 1. Copia para cache.
  /// 2. Lê metadata.
  /// 3. Extrai capa.
  Future<Song> prepareSong(Song song) async {
    try {
      final tempDirectory = await getTemporaryDirectory();

      final safeName = song.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

      final localPath = '${tempDirectory.path}/tsuki_$safeName.mp3';

      final localFile = File(localPath);

      // --------------------------------------------------------
      // CACHE
      // --------------------------------------------------------

      if (!await localFile.exists()) {

        await saf.copyToLocalFile(song.file, localPath);
      } else {
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
      // RESULTADO
      // --------------------------------------------------------

      return Song(title: title, artist: artist, file: localPath, cover: cover);
    } catch (e) {

      return song;
    }
  }
}

// ============================================================
// RESULTADO DO PARSER
// ============================================================

class _ParsedSong {
  final String artist;
  final String title;

  const _ParsedSong({required this.artist, required this.title});
}

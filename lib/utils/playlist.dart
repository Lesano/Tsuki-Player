class ParsedSong {
  final String artist;
  final String title;

  const ParsedSong({required this.artist, required this.title});
}

ParsedSong parseSongFilename(String filename) {
  // Procura:
  //
  // Artista - Título
  //
  final separatorIndex = filename.indexOf(' - ');

  if (separatorIndex > 0) {
    final artist = filename.substring(0, separatorIndex).trim();

    final title = filename.substring(separatorIndex + 3).trim();

    if (artist.isNotEmpty && title.isNotEmpty) {
      return ParsedSong(artist: artist, title: title);
    }
  }

  // Se não tiver " - ", usamos o nome completo
  // como título.
  return ParsedSong(artist: 'Desconhecido', title: filename.trim());
}

int compareSongs(String titleA, String titleB) {
  final aNumber = getTrackNumber(titleA);
  final bNumber = getTrackNumber(titleB);

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
  return titleA.toLowerCase().compareTo(titleB.toLowerCase());
}

int? getTrackNumber(String title) {
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
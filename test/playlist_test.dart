import 'package:flutter_test/flutter_test.dart';
import 'package:tsuki_player/services/music_service.dart';
import 'package:tsuki_player/utils/format_time.dart';
import 'package:tsuki_player/utils/playlist.dart';
import 'package:tsuki_player/utils/sleep_timer.dart';

void main() {
  group('parseSongFilename', () {
    test('extrai artista e título com separador " - "', () {
      final parsed = parseSongFilename('Nujabes - Luv (sic) pt2');

      expect(parsed.artist, 'Nujabes');
      expect(parsed.title, 'Luv (sic) pt2');
    });

    test('remove espaços à volta', () {
      final parsed = parseSongFilename('  Artista  -  Título  ');

      expect(parsed.artist, 'Artista');
      expect(parsed.title, 'Título');
    });

    test('usa o nome completo quando não há " - "', () {
      final parsed = parseSongFilename('Música sem artista');

      expect(parsed.artist, 'Desconhecido');
      expect(parsed.title, 'Música sem artista');
    });

    test('usa Desconhecido quando o título está vazio', () {
      final parsed = parseSongFilename('Artista - ');

      expect(parsed.artist, 'Desconhecido');
      expect(parsed.title, 'Artista -');
    });
  });

  group('getTrackNumber', () {
    test('Luv (sic) original é a faixa 1', () {
      expect(getTrackNumber('Luv (sic)'), 1);
      expect(getTrackNumber('Luv (sic).'), 1);
    });

    test('pt2..pt5 são números', () {
      expect(getTrackNumber('Luv (sic) pt2'), 2);
      expect(getTrackNumber('beat pt3'), 3);
    });

    test('pt6 remix fica depois do Grand Finale', () {
      expect(getTrackNumber('Luv (sic) pt6 Uyama Hiroto Remix'), 7);
    });

    test('Grand Finale é a faixa 6', () {
      expect(getTrackNumber('Grand Finale'), 6);
    });

    test('sem número devolve null', () {
      expect(getTrackNumber('Intro'), null);
    });
  });

  group('compareSongs', () {
    test('ordena por número antes de nomes sem número', () {
      final titles = [
        'Intro',
        'Luv (sic)',
        'Luv (sic) pt2',
        'Grand Finale',
        'Luv (sic) pt6 Uyama Hiroto Remix',
      ];

      titles.sort(compareSongs);

      expect(titles, [
        'Luv (sic)',
        'Luv (sic) pt2',
        'Grand Finale',
        'Luv (sic) pt6 Uyama Hiroto Remix',
        'Intro',
      ]);
    });

    test('fallback alfabético quando não há números', () {
      final titles = ['Zebra', 'Alfa', 'Meio'];

      titles.sort(compareSongs);

      expect(titles, ['Alfa', 'Meio', 'Zebra']);
    });
  });

  group('formatDuration', () {
    test('formata minutos e segundos', () {
      expect(formatDuration(Duration.zero), '00:00');
      expect(formatDuration(const Duration(seconds: 3)), '00:03');
      expect(formatDuration(const Duration(minutes: 5, seconds: 7)), '05:07');
    });

    test('mais de 60 minutos usa horas', () {
      expect(formatDuration(const Duration(hours: 1)), '1:00:00');
      expect(formatDuration(const Duration(minutes: 61, seconds: 5)), '1:01:05');
    });
  });

  group('toggleFavoriteInList', () {
    test('adiciona quando não existe e devolve nova lista', () {
      const favorites = ['a.mp3'];

      final next = toggleFavoriteInList(favorites, 'b.mp3');

      expect(next, ['a.mp3', 'b.mp3']);
      expect(favorites, ['a.mp3']);
    });

    test('remove quando já existe', () {
      final next = toggleFavoriteInList(['a.mp3', 'b.mp3'], 'a.mp3');

      expect(next, ['b.mp3']);
    });
  });

  group('fadeTargetVolume', () {
    test('começa no volume original e desce até zero', () {
      const steps = 4;

      expect(fadeTargetVolume(0.8, 4, steps), 0.8);
      expect(fadeTargetVolume(0.8, 3, steps), closeTo(0.6, 0.0001));
      expect(fadeTargetVolume(0.8, 2, steps), closeTo(0.4, 0.0001));
      expect(fadeTargetVolume(0.8, 1, steps), closeTo(0.2, 0.0001));
      expect(fadeTargetVolume(0.8, 0, steps), 0.0);
    });

    test('nunca sai do intervalo [0, 1]', () {
      expect(fadeTargetVolume(1.0, 5, 3), 1.0);
      expect(fadeTargetVolume(0.0, 3, 3), 0.0);
      expect(fadeTargetVolume(0.5, 10, 10), 0.5);
    });
  });
}
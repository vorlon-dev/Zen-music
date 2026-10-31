import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/utils/enhanced_image.dart';

void main() {
  const modern = 'https://lh3.googleusercontent.com/abc=w120-h120-p-k-no-nu';

  group('getEnhancedImage quality presets', () {
    test('high (default) upgrades modern URLs to a 500px square crop', () {
      expect(
        getEnhancedImage(modern),
        'https://lh3.googleusercontent.com/abc=w500-h500-c',
      );
    });

    test('medium upgrades to 300px', () {
      expect(
        getEnhancedImage(modern, quality: 'medium'),
        'https://lh3.googleusercontent.com/abc=w300-h300-c',
      );
    });

    test('low upgrades to 100px and drops other suffix params', () {
      expect(
        getEnhancedImage(
          'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj',
          quality: 'low',
        ),
        'https://lh3.googleusercontent.com/abc=w100-h100-c',
      );
    });
  });

  group('getEnhancedImage explicit width', () {
    test('uses width multiplied by dp, rounded up', () {
      expect(
        getEnhancedImage(modern, width: 100, dp: 2.0),
        'https://lh3.googleusercontent.com/abc=w200-h200-c',
      );
    });

    test('dp defaults to 1 and fractional sizes round up', () {
      expect(
        getEnhancedImage(modern, width: 48.2),
        'https://lh3.googleusercontent.com/abc=w49-h49-c',
      );
    });

    test('width takes priority over the quality preset', () {
      expect(
        getEnhancedImage(modern, quality: 'low', width: 100),
        'https://lh3.googleusercontent.com/abc=w100-h100-c',
      );
    });
  });

  group('getEnhancedImage URL formats', () {
    test('rewrites the legacy path-segment size token', () {
      expect(
        getEnhancedImage('https://lh3.googleusercontent.com/a/w60-h60/photo'),
        'https://lh3.googleusercontent.com/a/w500-h500/photo',
      );
    });

    test('video thumbnails fall back from sddefault to mqdefault', () {
      expect(
        getEnhancedImage('https://i.ytimg.com/vi/abc123/sddefault.jpg'),
        'https://i.ytimg.com/vi/abc123/mqdefault.jpg',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        getEnhancedImage('  https://i.ytimg.com/vi/abc123/hqdefault.jpg  '),
        'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );
    });
  });

  group('getEnhancedImage unknown quality', () {
    test('only upgrades sddefault to maxresdefault', () {
      expect(
        getEnhancedImage(
          'https://i.ytimg.com/vi/abc123/sddefault.jpg',
          quality: 'original',
        ),
        'https://i.ytimg.com/vi/abc123/maxresdefault.jpg',
      );
    });

    test('leaves size tokens untouched', () {
      expect(getEnhancedImage('x=w120-h120-p', quality: 'original'),
          'x=w120-h120-p');
    });
  });
}

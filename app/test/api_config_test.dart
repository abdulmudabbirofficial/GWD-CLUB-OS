import 'package:flutter_test/flutter_test.dart';
import 'package:gwd_club_os/core/api/api_client.dart';

void main() {
  // -----------------------------------------------------------------------
  // WHERE THE APP POINTS
  // -----------------------------------------------------------------------
  //
  // The address is fixed at build time, and getting it wrong is the failure
  // that looks completely normal until the phone leaves the building. These
  // run under the default environment, `dev`, which is what `flutter test`
  // compiles.
  group('AppEnvironment', () {
    test('defaults to dev, so a plain build never claims to be production', () {
      expect(ApiConfig.environment, AppEnvironment.dev);
      expect(ApiConfig.environment.isProduction, isFalse);
    });

    test('only dev may speak plaintext', () {
      // The club's own server is a laptop with no certificate, so HTTP has to
      // be allowed there. Anywhere hosted it means a bearer token travelling
      // readable across whatever network the phone is on.
      expect(AppEnvironment.dev.allowsInsecure, isTrue);
      expect(AppEnvironment.staging.allowsInsecure, isFalse);
      expect(AppEnvironment.production.allowsInsecure, isFalse);
    });

    test('the production address is https and is not a placeholder', () {
      expect(ApiConfig.productionBase, startsWith('https://'));
      expect(ApiConfig.productionBase, isNot(contains('example')));
      expect(ApiConfig.productionBase, isNot(contains('localhost')));
      expect(ApiConfig.productionBase, isNot(contains('192.168.')));
    });
  });

  group('ApiConfig.resolve', () {
    test('a dev build reaches the host, not a hosted service', () {
      final base = ApiConfig.resolve();
      expect(base, isNot(ApiConfig.productionBase));
      expect(base, anyOf(contains('10.0.2.2'), contains('localhost'), isEmpty));
    });
  });

  group('ApiConfig.normalise', () {
    test('accepts what people actually type', () {
      expect(ApiConfig.normalise('10.0.0.5'), 'http://10.0.0.5:4000');
      expect(ApiConfig.normalise('10.0.0.5:4000'), 'http://10.0.0.5:4000');
      expect(ApiConfig.normalise('http://10.0.0.5:4000'), 'http://10.0.0.5:4000');
      expect(ApiConfig.normalise('  10.0.0.5  '), 'http://10.0.0.5:4000');
    });

    test('an https address keeps its own port', () {
      // 4000 is the club laptop's port. Appending it to a hosted address would
      // point the app at something that is not listening.
      expect(
        ApiConfig.normalise('https://gwd-club-os-abrw.onrender.com'),
        'https://gwd-club-os-abrw.onrender.com',
      );
      expect(ApiConfig.normalise('https://example.org:8443'), 'https://example.org:8443');
    });

    test('rubbish is refused rather than turned into a broken address', () {
      expect(ApiConfig.normalise(''), isNull);
      expect(ApiConfig.normalise('   '), isNull);
      expect(ApiConfig.normalise('http://'), isNull);
    });
  });

  group('ApiConfig.isAcceptable', () {
    test('the same-origin web build is always fine', () {
      expect(ApiConfig.isAcceptable(''), isTrue);
    });

    test('dev accepts the LAN', () {
      expect(ApiConfig.isAcceptable('http://192.168.1.10:4000'), isTrue);
      expect(ApiConfig.isAcceptable('https://gwd-club-os-abrw.onrender.com'), isTrue);
    });
  });
}

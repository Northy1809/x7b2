import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smooth_app/services/ownership_service.dart';

http.Response _json(final Object? body, {final int statusCode = 200}) =>
    http.Response(jsonEncode(body), statusCode);

/// Builds a client whose response depends only on the request path/host,
/// so a single mock can serve a whole call chain (e.g. Wikidata search +
/// SPARQL walk) without tracking call order.
MockClient _routedClient(
  final http.Response Function(http.Request request) respond,
) => MockClient((final http.Request request) async => respond(request));

void main() {
  group('getCachedOwner', () {
    test('returns null without a network call when cache is unconfigured', () {
      final OwnershipService service = OwnershipService(
        supabaseUrl: '',
        supabaseAnonKey: '',
        client: MockClient((_) async => throw StateError('should not call')),
      );
      expect(service.getCachedOwner('Oreo'), completion(isNull));
    });

    test('parses the first matching row', () async {
      final OwnershipService service = OwnershipService(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-key',
        client: _routedClient(
          (_) => _json(<Map<String, Object?>>[
            <String, Object?>{
              'owner_company': 'Mondelez International',
              'owner_chain': <String>['Oreo', 'Nabisco', 'Mondelez International'],
              'source': 'wikidata',
            },
          ]),
        ),
      );
      final BrandOwnerResult? result = await service.getCachedOwner('Oreo');
      expect(result, isNotNull);
      expect(result!.ownerCompany, 'Mondelez International');
      expect(result.ownerChain, <String>['Oreo', 'Nabisco', 'Mondelez International']);
      expect(result.source, BrandOwnerSource.wikidata);
    });

    test('returns null on an empty result set', () async {
      final OwnershipService service = OwnershipService(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-key',
        client: _routedClient((_) => _json(<Object?>[])),
      );
      expect(await service.getCachedOwner('Unknown Brand'), isNull);
    });

    test('offline: cache, sharing and ethics answer null instead of throwing', () async {
      final OwnershipService service = OwnershipService(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-key',
        client: MockClient((_) async => throw http.ClientException('no network')),
      );
      expect(await service.getCachedOwner('Oreo'), isNull);
      expect(await service.getEthicsRating('Mondelez'), isNull);
      await service.pushToCentralCache(
        'Oreo',
        BrandOwnerResult(ownerCompany: 'M', ownerChain: <String>['Oreo', 'M'], source: BrandOwnerSource.wikidata),
      );
    });

    test('returns null on a non-200 response', () async {
      final OwnershipService service = OwnershipService(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-key',
        client: _routedClient((_) => http.Response('error', 500)),
      );
      expect(await service.getCachedOwner('Oreo'), isNull);
    });
  });

  group('pushToCentralCache', () {
    test('does nothing without a network call when cache is unconfigured', () {
      final OwnershipService service = OwnershipService(
        supabaseUrl: '',
        supabaseAnonKey: '',
        client: MockClient((_) async => throw StateError('should not call')),
      );
      expect(
        service.pushToCentralCache(
          'Oreo',
          BrandOwnerResult(
            ownerCompany: 'Mondelez International',
            ownerChain: const <String>['Oreo', 'Mondelez International'],
            source: BrandOwnerSource.aiFallback,
          ),
        ),
        completes,
      );
    });

    test('POSTs the confirmed chain as the brand_owner row', () async {
      Map<String, dynamic>? sentBody;
      final OwnershipService service = OwnershipService(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-key',
        client: MockClient((final http.Request request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 201);
        }),
      );
      await service.pushToCentralCache(
        'Oreo',
        BrandOwnerResult(
          ownerCompany: 'Mondelez International',
          ownerChain: const <String>['Oreo', 'Nabisco', 'Mondelez International'],
          source: BrandOwnerSource.wikidata,
        ),
        countryCode: 'dk',
      );
      expect(sentBody, isNotNull);
      expect(sentBody!['brand_name'], 'Oreo');
      expect(sentBody!['country_code'], 'dk');
      expect(sentBody!['owner_company'], 'Mondelez International');
      expect(
        sentBody!['owner_chain'],
        <String>['Oreo', 'Nabisco', 'Mondelez International'],
      );
      expect(sentBody!['source'], 'wikidata');
    });
  });

  group('getEthicsRating', () {
    test('returns null without a network call when cache is unconfigured', () {
      final OwnershipService service = OwnershipService(
        supabaseUrl: '',
        supabaseAnonKey: '',
        client: MockClient((_) async => throw StateError('should not call')),
      );
      expect(service.getEthicsRating('Mondelez International'), completion(isNull));
    });

    test('parses a curated rating', () async {
      final OwnershipService service = OwnershipService(
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-key',
        client: _routedClient(
          (_) => _json(<Map<String, Object?>>[
            <String, Object?>{
              'category': 'contested',
              'rationale_text': 'Nogle kontroversielle praksisser.',
              'source_url': 'https://example.com/kilde',
            },
          ]),
        ),
      );
      final EthicsRating? rating = await service.getEthicsRating(
        'Mondelez International',
      );
      expect(rating, isNotNull);
      expect(rating!.category, 'contested');
      expect(rating.sourceUrl, 'https://example.com/kilde');
    });
  });

  group('lookupWikidata', () {
    test('returns null when the brand has no Wikidata entity', () async {
      final OwnershipService service = OwnershipService(
        client: _routedClient((_) => _json(<String, Object?>{'search': <Object?>[]})),
      );
      expect(await service.lookupWikidata('Totally Unknown Brand'), isNull);
    });

    test('returns null when the entity has no P127 (owned by) claim', () async {
      final OwnershipService service = OwnershipService(
        client: _routedClient((final http.Request request) {
          if (request.url.host.contains('www.wikidata.org')) {
            return _json(<String, Object?>{
              'search': <Map<String, Object?>>[
                <String, Object?>{'id': 'Q1'},
              ],
            });
          }
          return _json(<String, Object?>{
            'results': <String, Object?>{'bindings': <Object?>[]},
          });
        }),
      );
      expect(await service.lookupWikidata('Independent Brand'), isNull);
    });

    test('walks one owned-by hop', () async {
      final OwnershipService service = OwnershipService(
        client: _routedClient((final http.Request request) {
          if (request.url.host.contains('www.wikidata.org')) {
            return _json(<String, Object?>{
              'search': <Map<String, Object?>>[
                <String, Object?>{'id': 'Q1'},
              ],
            });
          }
          final String query = request.url.queryParameters['query'] ?? '';
          if (query.contains('wd:Q1')) {
            return _json(<String, Object?>{
              'results': <String, Object?>{
                'bindings': <Map<String, Object?>>[
                  <String, Object?>{
                    'owner': <String, Object?>{
                      'value': 'http://www.wikidata.org/entity/Q2',
                    },
                    'ownerLabel': <String, Object?>{'value': 'Parent Co'},
                  },
                ],
              },
            });
          }
          // Q2 has no further owner.
          return _json(<String, Object?>{
            'results': <String, Object?>{'bindings': <Object?>[]},
          });
        }),
      );
      final BrandOwnerResult? result = await service.lookupWikidata('Oreo');
      expect(result, isNotNull);
      expect(result!.ownerChain, <String>['Oreo', 'Parent Co']);
      expect(result.ownerCompany, 'Parent Co');
      expect(result.source, BrandOwnerSource.wikidata);
    });

    test('stops walking on a cycle instead of looping forever', () async {
      final OwnershipService service = OwnershipService(
        client: _routedClient((final http.Request request) {
          if (request.url.host.contains('www.wikidata.org')) {
            return _json(<String, Object?>{
              'search': <Map<String, Object?>>[
                <String, Object?>{'id': 'Q1'},
              ],
            });
          }
          final String query = request.url.queryParameters['query'] ?? '';
          // Q1 -> Q2, then Q2 -> Q1 (cycle).
          if (query.contains('wd:Q1')) {
            return _json(<String, Object?>{
              'results': <String, Object?>{
                'bindings': <Map<String, Object?>>[
                  <String, Object?>{
                    'owner': <String, Object?>{
                      'value': 'http://www.wikidata.org/entity/Q2',
                    },
                    'ownerLabel': <String, Object?>{'value': 'Parent Co'},
                  },
                ],
              },
            });
          }
          return _json(<String, Object?>{
            'results': <String, Object?>{
              'bindings': <Map<String, Object?>>[
                <String, Object?>{
                  'owner': <String, Object?>{
                    'value': 'http://www.wikidata.org/entity/Q1',
                  },
                  'ownerLabel': <String, Object?>{'value': 'Brand Co'},
                },
              ],
            },
          });
        }),
      );
      final BrandOwnerResult? result = await service.lookupWikidata('Oreo');
      // Found exactly the one hop before the cycle was detected, not an
      // infinite loop and not a crash.
      expect(result!.ownerChain, <String>['Oreo', 'Parent Co']);
    });

    test('skips a search hit that is not a brand or company', () async {
      final OwnershipService service = OwnershipService(
        client: _routedClient((final http.Request request) {
          if (request.url.host.contains('www.wikidata.org')) {
            return _json(<String, Object?>{
              'search': <Map<String, Object?>>[
                <String, Object?>{'id': 'Q89', 'label': 'apple', 'description': 'fruit of the apple tree'},
                <String, Object?>{'id': 'Q312', 'label': 'Apple Inc.', 'description': 'American technology company'},
              ],
            });
          }
          // Apple Inc. has no owner: it is the top.
          expect(request.url.queryParameters['query'], contains('wd:Q312'));
          return _json(<String, Object?>{
            'results': <String, Object?>{'bindings': <Object?>[]},
          });
        }),
      );
      final BrandOwnerResult? result = await service.lookupWikidata('Apple');
      expect(result!.ownerCompany, 'Apple Inc.');
      expect(result.ownerChain, <String>['Apple', 'Apple Inc.']);
    });

    test('a brand nobody owns is not an answer; only a company is', () async {
      final OwnershipService service = OwnershipService(
        client: _routedClient((final http.Request request) {
          if (request.url.host.contains('www.wikidata.org')) {
            return _json(<String, Object?>{
              'search': <Map<String, Object?>>[
                <String, Object?>{'id': 'Q15075', 'label': 'Marlboro', 'description': 'American cigarette brand'},
              ],
            });
          }
          return _json(<String, Object?>{
            'results': <String, Object?>{'bindings': <Object?>[]},
          });
        }),
      );
      expect(await service.lookupWikidata('Marlboro'), isNull);
    });

    test('stops at a listed company and never names a fund as owner', () async {
      Map<String, Object?> owner(final String qid, final String label, {bool listed = false}) =>
          <String, Object?>{
            'owner': <String, Object?>{'value': 'http://www.wikidata.org/entity/$qid'},
            'ownerLabel': <String, Object?>{'value': label},
            if (listed) 'listed': <String, Object?>{'value': 'http://www.wikidata.org/entity/Q13677'},
          };
      final OwnershipService service = OwnershipService(
        client: _routedClient((final http.Request request) {
          if (request.url.host.contains('www.wikidata.org')) {
            return _json(<String, Object?>{
              'search': <Map<String, Object?>>[
                <String, Object?>{'id': 'Q1', 'label': 'Pampers', 'description': 'brand of diapers'},
              ],
            });
          }
          final String query = request.url.queryParameters['query'] ?? '';
          final Map<String, Object?> binding = query.contains('wd:Q1 ')
              ? owner('Q2', 'Procter & Gamble')
              : owner('Q3', 'The Vanguard Group', listed: true);
          return _json(<String, Object?>{
            'results': <String, Object?>{
              'bindings': <Object?>[binding],
            },
          });
        }),
      );
      final BrandOwnerResult? result = await service.lookupWikidata('Pampers');
      expect(result!.ownerChain, <String>['Pampers', 'Procter & Gamble']);
    });

    test('returns null instead of throwing on a network error', () async {
      final OwnershipService service = OwnershipService(
        client: MockClient((_) async => throw Exception('network down')),
      );
      expect(await service.lookupWikidata('Oreo'), isNull);
    });
  });

  group('lookupAiFallback', () {
    test('returns null without a network call when no API key is set', () {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: '',
        client: MockClient((_) async => throw StateError('should not call')),
      );
      expect(service.lookupAiFallback('Oreo'), completion(isNull));
    });

    test('parses a confident, known chain', () async {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: 'test-key',
        client: _routedClient(
          (_) => _json(<String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': jsonEncode(<String, Object?>{
                  'known': true,
                  'chain': <String>['Oreo', 'Mondelez International'],
                  'note': 'public filing',
                }),
              },
            ],
          }),
        ),
      );
      final BrandOwnerResult? result = await service.lookupAiFallback('Oreo');
      expect(result, isNotNull);
      expect(result!.ownerCompany, 'Mondelez International');
      expect(result.source, BrandOwnerSource.aiFallback);
    });

    test('handles a ```json code-fenced reply', () async {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: 'test-key',
        client: _routedClient(
          (_) => _json(<String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text':
                    '```json\n'
                    '${jsonEncode(<String, Object?>{
                      'known': true,
                      'chain': <String>['Oreo', 'Mondelez International'],
                    })}\n'
                    '```',
              },
            ],
          }),
        ),
      );
      final BrandOwnerResult? result = await service.lookupAiFallback('Oreo');
      expect(result?.ownerCompany, 'Mondelez International');
    });

    test('returns null when the model says it does not know', () async {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: 'test-key',
        client: _routedClient(
          (_) => _json(<String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': jsonEncode(<String, Object?>{'known': false}),
              },
            ],
          }),
        ),
      );
      expect(await service.lookupAiFallback('Totally Made Up Brand'), isNull);
    });

    test('returns null on a refusal', () async {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: 'test-key',
        client: _routedClient(
          (_) => _json(<String, Object?>{
            'stop_reason': 'refusal',
            'content': <Object?>[],
          }),
        ),
      );
      expect(await service.lookupAiFallback('Oreo'), isNull);
    });

    test('returns null on a non-200 response', () async {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: 'test-key',
        client: _routedClient((_) => http.Response('error', 500)),
      );
      expect(await service.lookupAiFallback('Oreo'), isNull);
    });
  });

  group('guessBrandFromImage', () {
    test('returns null without a network call when no API key is set', () {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: '',
        client: MockClient((_) async => throw StateError('should not call')),
      );
      expect(
        service.guessBrandFromImage(Uint8List(0)),
        completion(isNull),
      );
    });

    test('parses a brand guess with confidence', () async {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: 'test-key',
        client: _routedClient(
          (_) => _json(<String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': jsonEncode(<String, Object?>{
                  'brand': 'Oreo',
                  'confidence': 0.87,
                }),
              },
            ],
          }),
        ),
      );
      final BrandGuess? guess = await service.guessBrandFromImage(
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(guess, isNotNull);
      expect(guess!.brandName, 'Oreo');
      expect(guess.confidence, 0.87);
    });

    test('returns null when no brand could be read', () async {
      final OwnershipService service = OwnershipService(
        anthropicApiKey: 'test-key',
        client: _routedClient(
          (_) => _json(<String, Object?>{
            'content': <Map<String, Object?>>[
              <String, Object?>{
                'type': 'text',
                'text': jsonEncode(<String, Object?>{
                  'brand': null,
                  'confidence': 0.0,
                }),
              },
            ],
          }),
        ),
      );
      expect(
        await service.guessBrandFromImage(Uint8List.fromList(<int>[1])),
        isNull,
      );
    });
  });
}

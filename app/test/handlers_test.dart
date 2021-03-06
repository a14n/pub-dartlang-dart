// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_dartlang_org.handlers_test;

import 'dart:async';

import 'package:unittest/unittest.dart';
import 'package:yaml/yaml.dart';

import 'package:appengine/appengine.dart';

import 'package:pub_dartlang_org/backend.dart';
import 'package:pub_dartlang_org/handlers_redirects.dart';
import 'package:pub_dartlang_org/models.dart';
import 'package:pub_dartlang_org/search_service.dart';
import 'package:pub_dartlang_org/templates.dart';

import 'utils.dart';
import 'handlers_test_utils.dart';

tScopedTest(String name, Future func()) {
  return scopedTest(name, () {
    registerTemplateService(new TemplateMock());
    return func();
  });
}

main() {
  final PageSize = 10;

  group('handlers', () {
    solo_group('not found', () {
      tScopedTest('/xxx', () async {
        expectNotFoundResponse(await issueGet('/xxx'));
      });
    });

    group('ui', () {
      tScopedTest('/', () async {
        var backend = new BackendMock(
            latestPackageVersionsFun: ({offset, limit}) {
              expect(offset, isNull);
              expect(limit, equals(5));
              return [testPackageVersion];
            });
        registerBackend(backend);

        expectHtmlResponse(await issueGet('/'));
      });

      tScopedTest('/packages', () async {
        var backend = new BackendMock(
            latestPackagesFun: ({offset, limit}) {
              expect(offset, 0);
              expect(limit, greaterThan(PageSize));
              return [testPackage];
            },
            lookupLatestVersionsFun: (List<Package> packages) {
              expect(packages.length, 1);
              expect(packages.first, testPackage);
              return [testPackageVersion];
            });
        registerBackend(backend);
        expectHtmlResponse(await issueGet('/packages'));
      });

      tScopedTest('/packages?page=2', () async {
        var backend = new BackendMock(
            latestPackagesFun: ({offset, limit}) {
              expect(offset, PageSize);
              expect(limit, greaterThan(PageSize));
              return [testPackage];
            },
            lookupLatestVersionsFun: (List<Package> packages) {
              expect(packages.length, 1);
              expect(packages.first, testPackage);
              return [testPackageVersion];
            });
        registerBackend(backend);
        expectHtmlResponse(await issueGet('/packages?page=2'));
      });

      tScopedTest('/packages/foobar_pkg - found', () async {
        var backend = new BackendMock(
            lookupPackageFun: (String packageName) {
              expect(packageName, 'foobar_pkg');
              return testPackage;
            },
            versionsOfPackageFun: (String package) {
              expect(package, testPackage.name);
              return [testPackageVersion];
            },
            downloadUrlFun: (String package, String version) {
              return 'http://blobstore/$package/$version';
            });
        registerBackend(backend);
        expectHtmlResponse(await issueGet('/packages/foobar_pkg'));
      });

      tScopedTest('/packages/foobar_pkg - not found', () async {
        var backend = new BackendMock(
            lookupPackageFun: (String packageName) {
              expect(packageName, 'foobar_pkg');
              return null;
            });
        registerBackend(backend);
        expectHtmlResponse(await issueGet('/packages/foobar_pkg'), status: 404);
      });

      tScopedTest('/packages/foobar_pkg/versions - found', () async {
        var backend = new BackendMock(
            versionsOfPackageFun: (String package) {
              expect(package, testPackage.name);
              return [testPackageVersion];
            },
            downloadUrlFun: (String package, String version) {
              return 'http://blobstore/$package/$version';
            });
        registerBackend(backend);
        expectHtmlResponse(await issueGet('/packages/foobar_pkg/versions'));
      });

      tScopedTest('/packages/foobar_pkg/versions - not found', () async {
        var backend = new BackendMock(
            versionsOfPackageFun: (String package) {
              expect(package, testPackage.name);
              return [];
            });
        registerBackend(backend);
        expectHtmlResponse(await issueGet('/packages/foobar_pkg/versions'),
                           status: 404);
      });

      tScopedTest('/doc', () async {
        for (var path in REDIRECT_PATHS.keys) {
          var redirectUrl =
              'https://www.dartlang.org/tools/pub/${REDIRECT_PATHS[path]}';
          expectRedirectResponse(await issueGet(path), redirectUrl);
        }
      });

      tScopedTest('/authorized', () async {
        expectHtmlResponse(await issueGet('/authorized'));
      });

      tScopedTest('/site-map', () async {
        expectHtmlResponse(await issueGet('/site-map'));
      });

      tScopedTest('/admin - not logged in', () async {
        registerUserService(new UserServiceMock());
        expectRedirectResponse(await issueGet('/admin'),
                               UserServiceMock.LoginUrl);
      });

      tScopedTest('/admin - unauthorized', () async {
        registerUserService(new UserServiceMock(email: 'a@foobar.com'));
        expectHtmlResponse(await issueGet('/admin'), status: 403);
      });

      tScopedTest('/admin - logged in', () async {
        registerUserService(new UserServiceMock(email: 'a@google.com'));
        expectHtmlResponse(await issueGet('/admin'), status: 404);
      });

      tScopedTest('/search?q=foobar', () async {
        registerSearchService(new SearchServiceMock(
            (String query, int offset, int numResults) {
          expect(query, 'foobar');
          expect(offset, 0);
          expect(numResults, PageSize);
          return new SearchResultPage(query, offset, 1, [testPackageVersion]);
        }));
        expectHtmlResponse(await issueGet('/search?q=foobar'), status: 200);
      });

      tScopedTest('/search?q=foobar&page=2', () async {
        registerSearchService(new SearchServiceMock(
            (String query, int offset, int numResults) {
          expect(query, 'foobar');
          expect(offset, PageSize);
          expect(numResults, PageSize);
          return new SearchResultPage(query, offset, 1, [testPackageVersion]);
        }));
        expectHtmlResponse(await issueGet('/search?q=foobar&page=2'));
      });

      tScopedTest('/feed.atom', () async {
        var backend = new BackendMock(
            latestPackageVersionsFun: ({offset, limit}) {
              expect(offset, 0);
              expect(limit, PageSize);
              return [testPackageVersion];
            });
        registerBackend(backend);
        expectAtomXmlResponse(await issueGet('/feed.atom'), regexp: '''
<\\?xml version="1.0" encoding="UTF-8"\\?>
<feed xmlns="http://www.w3.org/2005/Atom">
        <id>https://pub.dartlang.org/feed.atom</id>
        <title>Pub Packages for Dart</title>
        <updated>(.*)</updated>
        <author>
          <name>Dart Team</name>
        </author>
        <link href="https://pub.dartlang.org/" rel="alternate" />
        <link href="https://pub.dartlang.org/feed.atom" rel="self" />
        <generator version="0.1.0">Pub Feed Generator</generator>
        <subtitle>Last Updated Packages</subtitle>
        
        <entry>
          <id>urn:uuid:f38e70f0-13de-51b6-88b8-57430c66ce75</id>
          <title>v0.1.1 of foobar_pkg</title>
          <updated>${testPackageVersion.created.toIso8601String()}</updated>
          <author><name>Hans Juergen &lt;hans@juergen.com&gt;</name></author>
          <content type="html">readme content</content>
          <link href="https://pub.dartlang.org/packages/foobar_pkg"
                rel="alternate"
                title="foobar_pkg" />
        </entry>
      
</feed>
''');
      });
    });

    group('old api', () {
      scopedTest('/packages.json', () async {
        var backend = new BackendMock(
            latestPackagesFun: ({offset, limit}) {
              expect(offset, 0);
              expect(limit, greaterThan(PageSize));
              return [testPackage];
            },
            lookupLatestVersionsFun: (List<Package> packages) {
              expect(packages.length, 1);
              expect(packages.first, testPackage);
              return [testPackageVersion];
            });
        registerBackend(backend);
        expectJsonResponse(await issueGet('/packages.json'), body: {
          "packages" : ["https://pub.dartlang.org/packages/foobar_pkg.json"],
          "next" : null
        });
      });

      tScopedTest('/packages/foobar_pkg.json', () async {
        var backend = new BackendMock(
            lookupPackageFun: (String package) {
              expect(package, 'foobar_pkg');
              return testPackage;
            },
            versionsOfPackageFun: (String package) {
              expect(package, 'foobar_pkg');
              return [testPackageVersion];
            });
        registerBackend(backend);
        expectJsonResponse(await issueGet('/packages/foobar_pkg.json'),
            body: {
              "name" : 'foobar_pkg',
              "uploaders" : ['hans@juergen.com'],
              "versions" : ['0.1.1'],
            });
      });

      tScopedTest('/packages/foobar_pkg/versions/0.1.1.yaml', () async {
        var backend = new BackendMock(
            lookupPackageVersionFun: (String package, String version) {
              expect(package, 'foobar_pkg');
              expect(version, '0.1.1');
              return testPackageVersion;
            });
        registerBackend(backend);
        expectYamlResponse(
            await issueGet('/packages/foobar_pkg/versions/0.1.1.yaml'),
            body: loadYaml(TestPackagePubspec));
      });
    });

    group('editor api', () {
      tScopedTest('/api/packages', () async {
        var backend = new BackendMock(
            latestPackagesFun: ({offset, limit}) {
              expect(offset, 0);
              expect(limit, greaterThan(10));
              return [testPackage];
            },
            lookupLatestVersionsFun: (List<Package> packages) {
              expect(packages.length, 1);
              expect(packages.first, testPackage);
              return [testPackageVersion];
            });
        registerBackend(backend);
        expectJsonResponse(await issueGet('/api/packages'), body: {
          'next_url': null,
          'packages': [
            {
              'name': 'foobar_pkg',
              'latest': {
                'version': '0.1.1',
                'pubspec': loadYaml(TestPackagePubspec),
                'archive_url': 'https://pub.dartlang.org'
                               '/packages/foobar_pkg/versions/0.1.1.tar.gz',
                'package_url': 'https://pub.dartlang.org'
                                '/api/packages/foobar_pkg',
                'url': 'https://pub.dartlang.org'
                       '/api/packages/foobar_pkg/versions/0.1.1'
              },
              'url': 'https://pub.dartlang.org/api/packages/foobar_pkg',
              'version_url': 'https://pub.dartlang.org'
                             '/api/packages/foobar_pkg/versions/%7Bversion%7D',
              'new_version_url': 'https://pub.dartlang.org'
                                 '/api/packages/foobar_pkg/new',
              'uploaders_url': 'https://pub.dartlang.org'
                                '/api/packages/foobar_pkg/uploaders'
            }
          ]
        });
      });
    });
  });
}

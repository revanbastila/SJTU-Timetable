import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/app_update.dart';
import 'package:jiaotong_course/services/github_release_api.dart';

class Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.statusCode, this.body);
  @override
  final int statusCode;
  final String body;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.value(utf8.encode(body)).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  final Headers headers = Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  Client(this.request);
  final Request request;
  Uri? uri;
  bool closed = false;
  Object? failure;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
    if (failure != null) throw failure!;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('official latest API request and parsed response', () async {
    final client = Client(Request(Response(
        200,
        jsonEncode({
          'tag_name': 'v1.14.18',
          'name': 'Update',
          'body': '- Fix',
          'html_url': 'https://github.com/campus/course/releases/tag/v1.14.18',
          'assets': [],
        }))));
    final api = GitHubReleaseApi(
        owner: 'campus', repo: 'course', clientFactory: () => client);
    expect((await api.latest()).version, 'v1.14.18');
    expect(client.uri.toString(),
        'https://api.github.com/repos/campus/course/releases/latest');
    expect(client.request.followRedirects, false);
    expect(client.request.headers.values['X-GitHub-Api-Version'], '2022-11-28');
    expect(client.request.headers.values.containsKey('Authorization'), false);
    expect(client.connectionTimeout, const Duration(seconds: 10));
    expect(client.closed, true);
  });
  for (final code in [404, 403, 500]) {
    test('HTTP $code gives a safe message and closes client', () async {
      final client = Client(Request(Response(code, '{}')));
      await expectLater(
          GitHubReleaseApi(
              owner: 'campus',
              repo: 'course',
              clientFactory: () => client).latest(),
          throwsA(isA<UpdateException>()));
      expect(client.closed, true);
    });
  }
  test('network and malformed JSON failures are safe', () async {
    for (final failure in [
      const SocketException('offline'),
      TimeoutException('timeout'),
      null
    ]) {
      final client = Client(Request(Response(200, 'invalid JSON')))
        ..failure = failure;
      await expectLater(
          GitHubReleaseApi(
              owner: 'campus',
              repo: 'course',
              clientFactory: () => client).latest(),
          throwsA(isA<UpdateException>()));
      expect(client.closed, true);
    }
  });
  test('unconfigured source does not create a network client', () async {
    var called = false;
    await expectLater(
        GitHubReleaseApi(
            owner: '',
            repo: '',
            clientFactory: () {
              called = true;
              return Client(Request(Response(200, '{}')));
            }).latest(),
        throwsA(isA<UpdateException>()));
    expect(called, false);
  });
}

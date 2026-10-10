import 'package:flutter/foundation.dart';

/// Browser → Pin Code Manager links.
///
/// A web page opens `yesem-pcm://pin?session=<id>&server=<origin>`; the OS
/// starts the Pin Code Manager (or hands the link to the running one), which
/// reads the session from `<origin>`, collects the PIN and posts the result
/// back to the same server. The page learns the result from its server.
///
/// Anything can open a custom-scheme link, so the link is untrusted input: it
/// carries only an opaque session id, and the server must be on [WebLinkPolicy]'s
/// allowlist so a hostile page can't make the Pin Code Manager talk to (or
/// display) a server of its choosing.
abstract final class WebLink {
  /// Registered for the Pin Code Manager on every OS (Info.plist via
  /// PinCodeManager.xcconfig, Windows registry, Linux .desktop file).
  static const String scheme = 'yesem-pcm';

  /// `yesem-pcm://pin?…`: the only action so far.
  static const String pinAction = 'pin';

  static const String sessionParam = 'session';
  static const String serverParam = 'server';

  /// Server API, relative to the server origin.
  static String sessionPath(String sessionId) => '/api/sessions/$sessionId';
  static String eventsPath(String sessionId) => '/api/sessions/$sessionId/events';

  static final RegExp _sessionPattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  /// The first argument that looks like one of our links (Windows and Linux
  /// pass the link as a command-line argument), or null.
  static String? findInArgs(List<String> args) {
    for (final arg in args) {
      if (arg.toLowerCase().startsWith('$scheme:')) {
        return arg;
      }
    }
    return null;
  }

  /// Parses and validates [link]; throws [WebLinkException] with a
  /// user-presentable reason when it isn't acceptable.
  static WebPinRequest parse(
    String link, {
    WebLinkPolicy policy = WebLinkPolicy.testBed,
  }) {
    final Uri uri;
    try {
      uri = Uri.parse(link.trim());
    } on FormatException {
      throw const WebLinkException('The link is not a valid address.');
    }
    if (uri.scheme.toLowerCase() != scheme) {
      throw WebLinkException('Unsupported link type "${uri.scheme}:".');
    }
    if (uri.host.toLowerCase() != pinAction) {
      throw WebLinkException('Unsupported request "${uri.host}".');
    }
    final session = uri.queryParameters[sessionParam] ?? '';
    if (!_sessionPattern.hasMatch(session)) {
      throw const WebLinkException('The link has no valid session id.');
    }
    final serverText = uri.queryParameters[serverParam] ?? '';
    final server = Uri.tryParse(serverText);
    if (server == null ||
        !(server.scheme == 'http' || server.scheme == 'https') ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        (server.path.isNotEmpty && server.path != '/') ||
        server.hasQuery ||
        server.hasFragment) {
      throw const WebLinkException('The link has no valid server address.');
    }
    final origin = server.replace(path: '');
    if (!policy.allows(origin)) {
      throw WebLinkException(
        'Requests from ${origin.origin} are not accepted by this Pin Code '
        'Manager.',
      );
    }
    return WebPinRequest(server: origin, sessionId: session);
  }
}

class WebLinkException implements Exception {
  const WebLinkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Which servers a link may point the Pin Code Manager at.
@immutable
class WebLinkPolicy {
  const WebLinkPolicy({
    this.allowLoopbackHttp = false,
    this.httpsHosts = const <String>{},
  });

  /// Test bed: only the demo server on this machine (tool/web_demo).
  /// A product build would instead pin its own HTTPS hosts, e.g.
  /// `WebLinkPolicy(httpsHosts: {'nag.example.am'})`.
  static const WebLinkPolicy testBed = WebLinkPolicy(allowLoopbackHttp: true);

  final bool allowLoopbackHttp;
  final Set<String> httpsHosts;

  bool allows(Uri origin) {
    final host = origin.host.toLowerCase();
    if (origin.scheme == 'https' && httpsHosts.contains(host)) {
      return true;
    }
    return allowLoopbackHttp &&
        origin.scheme == 'http' &&
        (host == '127.0.0.1' || host == 'localhost');
  }
}

/// A validated request from a web page: which server, which session.
@immutable
class WebPinRequest {
  const WebPinRequest({required this.server, required this.sessionId});

  /// Origin only (scheme, host, port).
  final Uri server;
  final String sessionId;

  Uri uri(String path) => server.replace(path: path);

  /// The link a server hands to its page (tool/web_demo builds the same).
  String toLink() => Uri(
    scheme: WebLink.scheme,
    host: WebLink.pinAction,
    queryParameters: <String, String>{
      WebLink.sessionParam: sessionId,
      WebLink.serverParam: server.origin,
    },
  ).toString();

  @override
  bool operator ==(Object other) =>
      other is WebPinRequest &&
      other.server == server &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(server, sessionId);

  @override
  String toString() => 'WebPinRequest($sessionId @ ${server.origin})';
}

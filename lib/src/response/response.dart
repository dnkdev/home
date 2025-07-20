import 'dart:convert';
import 'dart:io';
import 'package:home/models.dart';

String _reasonPhrase(int code) {
  const reasons = {
    // 1xx - Informational
    100: 'Continue',
    101: 'Switching Protocols',
    102: 'Processing',
    103: 'Early Hints',

    // 2xx - Success
    200: 'OK',
    201: 'Created',
    202: 'Accepted',
    203: 'Non-Authoritative Information',
    204: 'No Content',
    205: 'Reset Content',
    206: 'Partial Content',
    207: 'Multi-Status',
    208: 'Already Reported',
    226: 'IM Used',

    // 3xx - Redirection
    300: 'Multiple Choices',
    301: 'Moved Permanently',
    302: 'Found',
    303: 'See Other',
    304: 'Not Modified',
    305: 'Use Proxy',
    306: 'Switch Proxy', // Deprecated
    307: 'Temporary Redirect',
    308: 'Permanent Redirect',

    // 4xx - Client Errors
    400: 'Bad Request',
    401: 'Unauthorized',
    402: 'Payment Required',
    403: 'Forbidden',
    404: 'Not Found',
    405: 'Method Not Allowed',
    406: 'Not Acceptable',
    407: 'Proxy Authentication Required',
    408: 'Request Timeout',
    409: 'Conflict',
    410: 'Gone',
    411: 'Length Required',
    412: 'Precondition Failed',
    413: 'Payload Too Large',
    414: 'URI Too Long',
    415: 'Unsupported Media Type',
    416: 'Range Not Satisfiable',
    417: 'Expectation Failed',
    418: "I'm a teapot", // Easter egg (RFC 2324)
    421: 'Misdirected Request',
    422: 'Unprocessable Entity',
    423: 'Locked',
    424: 'Failed Dependency',
    425: 'Too Early',
    426: 'Upgrade Required',
    428: 'Precondition Required',
    429: 'Too Many Requests',
    431: 'Request Header Fields Too Large',
    451: 'Unavailable For Legal Reasons',

    // 5xx - Server Errors
    500: 'Internal Server Error',
    501: 'Not Implemented',
    502: 'Bad Gateway',
    503: 'Service Unavailable',
    504: 'Gateway Timeout',
    505: 'HTTP Version Not Supported',
    506: 'Variant Also Negotiates',
    507: 'Insufficient Storage',
    508: 'Loop Detected',
    510: 'Not Extended',
    511: 'Network Authentication Required',
  };

  return reasons[code] ?? 'Unknown';
}

class Response {
  final int statusCode;
  final Map<String,String> headers;
  final List<int> body;

  const Response._internal({
    required this.statusCode,
    required this.headers,
    required this.body,
  });


  factory Response.html(
    String text, {
    int statusCode = 200,
    Map<String, String>? headers,
    Encoding encoding = utf8,
    String contentType = 'text/html; charset=utf-8',
  }) {
    final encoded = encoding.encode(text);
    final finalHeaders = {
      'content-type': contentType,
      'content-length': '${encoded.length}',
      'connection': 'close',
      ...?headers,
    };
    return Response._internal(
      statusCode: statusCode,
      headers: finalHeaders,
      body: encoded,
    );
  }


  factory Response.text(
    String text, {
    int statusCode = 200,
    Map<String, String>? headers,
    Encoding encoding = utf8,
    String contentType = 'text/plain; charset=utf-8',
  }) {
    final encoded = encoding.encode(text);
    final finalHeaders = {
      'content-type': contentType,
      'content-length': '${encoded.length}',
      'connection': 'close',
      ...?headers,
    };
    return Response._internal(
      statusCode: statusCode,
      headers: finalHeaders,
      body: encoded,
    );
  }

  /// Create a response from binary data
  factory Response.bytes(
    List<int> bytes, {
    int statusCode = 200,
    Map<String, String>? headers,
    String? contentType,
  }) {
    final finalHeaders = {
      if (contentType != null) 'content-type': contentType,
      'content-length': '${bytes.length}',
      ...?headers,
    };
    return Response._internal(
      statusCode: statusCode,
      headers: finalHeaders,
      body: bytes,
    );
  }

  static Future<Response> ttf(
    List<int> content, {
    String filename = 'font.ttf',
    String mime = 'font/ttf', // Can be changed to 'font/ttf', etc.
    int statusCode = 200,
    Map<String, String>? addHeaders,
  }) async {
    final finalHeaders = {
      'Content-Type': mime,
      'Content-Disposition': 'inline; filename="$filename"',
      'Cache-Control': 'public, max-age=31536000, immutable',
      'X-Content-Type-Options': 'nosniff',
      'Access-Control-Allow-Origin': '*',
      ...?addHeaders,
    };

    return Response._internal(
      statusCode: statusCode,
      body: content,
      headers: finalHeaders,
    );
  }
  static Future<Response> woff2(
    List<int> content, {
    String filename = 'font.woff2',
    String mime = 'font/woff2', // Can be changed to 'font/ttf', etc.
    int statusCode = 200,
    Map<String, String>? addHeaders,
  }) async {
    final finalHeaders = {
      'Content-Type': mime,
      'Content-Disposition': 'inline; filename="$filename"',
      'Cache-Control': 'public, max-age=31536000, immutable',
      'X-Content-Type-Options': 'nosniff',
      'Access-Control-Allow-Origin': '*',
      ...?addHeaders,
    };

    return Response._internal(
      statusCode: statusCode,
      body: content,
      headers: finalHeaders,
    );
  }
  
  static Future<Response> jpg(
    List<int> content,{
    int statusCode = 200,
    Map<String, String>? addHeaders,
  }) async {
    final finalHeaders = {
      'Content-Type': 'image/jpeg',
      // 'Content-Disposition': 'inline', // 'attachment; filename="image.jpg"'
      'Cache-Control': 'public, max-age=31536000, immutable',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'X-XSS-Protection': '1; mode=block',
      'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
      'Accept-Ranges': 'bytes',
      ...?addHeaders,
    };
    return Response._internal(
      statusCode: statusCode, 
      body: content, 
      headers: finalHeaders
    );
  }

  static Future<Response> svg(
    String content, {
    int statusCode = 200,
    Map<String, String>? addHeaders,
    Encoding encoding = utf8 
  }) async {
    final headers = {
        'content-type': 'image/svg+xml',
        ...?addHeaders
      };
    return Response._internal(
      statusCode: statusCode, 
      body: encoding.encode(content), 
      headers: headers
    );
  } 
  

  factory Response.json(
    Object jsonObject, {
    int statusCode = 200,
    Map<String, String>? headers,
    Encoding encoding = utf8,
  }) {
    final body = encoding.encode(json.encode(jsonObject));
    final finalHeaders = {
      'content-type': 'application/json; charset=${encoding.name}',
      'content-length': '${body.length}',
      'connection': 'close',
      ...?headers,
    };
    return Response._internal(
      statusCode: statusCode,
      headers: finalHeaders,
      body: body,
    );
  }
    /// Create an empty response (no body)
  factory Response.empty({
    int statusCode = 204,
    Map<String, String>? headers,
  }) {
    return Response._internal(
      statusCode: statusCode,
      headers: {
        'content-length': '0',
        ...?headers,
      },
      body: const [],
    );
  }


  factory Response.ok(String content, {
    int statusCode = 200,
    Map<String, String>? headers,
    Encoding encoding = utf8,
  }) {
    
    final encoded = encoding.encode(content);
    final finalHeaders = {
      if(headers != null && headers.containsKey('content-length')) 'content-length': '${encoded.length}',
      ...?headers,
    };
    return Response._internal(
      statusCode: statusCode,
      headers: finalHeaders,
      body: encoded,
    );
  }

  factory Response.notFound([String message = 'Not Found']) =>
    Response.text(message, statusCode: 404);

  factory Response.badRequest({String message = 'Bad Request', int statusCode = 400, Encoding encoding = utf8, Map<String, String>? headers}) =>
    Response._internal(
      headers: headers ?? {},
      body: encoding.encode(message), 
      statusCode: statusCode
    );

  factory Response.internalServerError([String message = 'Internal Server Error']) =>
    Response.text(message, statusCode: 500);

  factory Response.unauthorized([String message = 'Unauthorized']) =>
    Response.text(message, statusCode: 401);

  factory Response.forbidden([String message = 'Forbidden']) =>
    Response.text(message, statusCode: 403);

  factory Response.redirect(String location, {bool permanent = false}) =>
    Response._internal(
      statusCode: permanent ? 301 : 302,
      headers: {
        'location': location,
        'content-length': '0',
      },
      body: const [],
    );


  factory Response.created([String message = 'Created']) =>
    Response.text(message, statusCode: 201);

  factory Response.accepted([String message = 'Accepted']) =>
    Response.text(message, statusCode: 202);

  factory Response.noContent() =>
    Response.text('', statusCode: 204);

  factory Response.movedPermanently([String message = 'Moved Permanently']) =>
    Response.text(message, statusCode: 301);

  factory Response.found([String message = 'Found']) =>
    Response.text(message, statusCode: 302);

  factory Response.seeOther([String message = 'See Other']) =>
    Response.text(message, statusCode: 303);

  factory Response.notModified() =>
    Response.text('', statusCode: 304);

  factory Response.temporaryRedirect([String message = 'Temporary Redirect']) =>
    Response.text(message, statusCode: 307);

  factory Response.permanentRedirect([String message = 'Permanent Redirect']) =>
    Response.text(message, statusCode: 308);

  factory Response.methodNotAllowed([String message = 'Method Not Allowed']) =>
    Response.text(message, statusCode: 405);

  factory Response.notAcceptable([String message = 'Not Acceptable']) =>
    Response.text(message, statusCode: 406);

  factory Response.requestTimeout([String message = 'Request Timeout']) =>
    Response.text(message, statusCode: 408);

  factory Response.conflict([String message = 'Conflict']) =>
    Response.text(message, statusCode: 409);

  factory Response.gone([String message = 'Gone']) =>
    Response.text(message, statusCode: 410);

  factory Response.lengthRequired([String message = 'Length Required']) =>
    Response.text(message, statusCode: 411);

  factory Response.preconditionFailed([String message = 'Precondition Failed']) =>
    Response.text(message, statusCode: 412);

  factory Response.payloadTooLarge([String message = 'Payload Too Large']) =>
    Response.text(message, statusCode: 413);

  factory Response.uriTooLong([String message = 'URI Too Long']) =>
    Response.text(message, statusCode: 414);

  factory Response.unsupportedMediaType([String message = 'Unsupported Media Type']) =>
    Response.text(message, statusCode: 415);

  factory Response.expectationFailed([String message = 'Expectation Failed']) =>
    Response.text(message, statusCode: 417);

  factory Response.unprocessableEntity([String message = 'Unprocessable Entity']) =>
    Response.text(message, statusCode: 422);

  factory Response.tooManyRequests([String message = 'Too Many Requests']) =>
    Response.text(message, statusCode: 429);

  factory Response.notImplemented([String message = 'Not Implemented']) =>
    Response.text(message, statusCode: 501);

  factory Response.badGateway([String message = 'Bad Gateway']) =>
    Response.text(message, statusCode: 502);

  factory Response.serviceUnavailable([String message = 'Service Unavailable']) =>
    Response.text(message, statusCode: 503);

  factory Response.gatewayTimeout([String message = 'Gateway Timeout']) =>
    Response.text(message, statusCode: 504);

  factory Response.httpVersionNotSupported([String message = 'HTTP Version Not Supported']) =>
    Response.text(message, statusCode: 505);  


  Response addHeader(String key, value) {
    headers[key] = value; 
    return this;
  }

  /// send Response, cleans up client
  Future<void> send(IClient client) async {
    final reasonPhrase = _reasonPhrase(statusCode);
    final headerBuffer = StringBuffer();

    headerBuffer.writeln('HTTP/1.1 $statusCode $reasonPhrase');

    headers.forEach((key, value) {
      headerBuffer.writeln('$key: $value');
    });

    headerBuffer.writeln();

    client.add(utf8.encode(headerBuffer.toString()));
    client.add(body);

    await client.cleanUp(soft:true);
  }
  Future<void> socksend(IClient client) async {
    final reasonPhrase = _reasonPhrase(statusCode);
    final headerBuffer = StringBuffer();

    headerBuffer.writeln('HTTP/1.1 $statusCode $reasonPhrase');

    headers.forEach((key, value) {
      headerBuffer.writeln('$key: $value');
    });

    headerBuffer.writeln();

    client.add(utf8.encode(headerBuffer.toString()));
    client.add(body);

    await client.cleanUp(soft:true);
  }

  
  @override
  String toString() =>
      'Response($statusCode, headers: $headers, bodyLength: ${body.length})';
}
import 'dart:io';
import 'package:home/router.dart';
import 'package:home/home.dart';

enum Method {
  GET, POST, HEAD, DELETE, PUT, OPTIONS, OTHER;
  
  static Method fromString(String name) {
    for (var value in Method.values) {
      if (value.name == name) return value;
    }
    return Method.OTHER; // or throw
  }
}

abstract interface class IClient {
  RawSecureSocket get socket;
  Method? get method;
  String? get url;
  bool get isClosed;

  add(List<int> data);
  cleanUp({bool soft});
}

abstract interface class IServer {
  int get port;
  String get cert;
  String get priv;
}

typedef ClientFdHandlerFunc = void Function(SecureSocket)?;
typedef Routes = Map<String, Route>;
typedef TemplateData = Map<String, dynamic>?;

typedef RouteHandler =  Future<void> Function(IClient);
typedef Middleware = RouteHandler Function(RouteHandler next);


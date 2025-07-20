import 'dart:io';
import 'package:home/home.dart';
import 'package:home/log.dart';
import 'package:home/response.dart';
import 'package:home/models.dart';
import 'package:home/router.dart';
import 'package:home/cache.dart';
import 'package:home/utils.dart';

class Server{
  static file(String p){}
}

base class HtmlRoute extends Route{ 
  HtmlRoute({
    required super.method, 
    required super.urlPath,
    required super.clientHandler,
    super.filepath, 
    super.applyMiddleware, 
    super.ttl,
    super.headers
  }) {
    headers ??= {
      'content-type': 'text/html; charset=utf-8'
    };

  }
  
}
base class JsonRoute extends Route{ 
  JsonRoute({
    required super.method, 
    required super.urlPath,
    required super.clientHandler,
    super.filepath, 
    super.applyMiddleware, 
    super.ttl,
    super.headers
  }) {
    headers ??= {
      'content-type': 'application/json; charset=utf-8'
    };
  }
  
}
base class TextRoute extends Route{ 
  TextRoute({
    required super.method, 
    required super.urlPath,
    required super.clientHandler,
    super.filepath, 
    super.applyMiddleware, 
    super.ttl,
    super.headers
  }) {
    headers ??= {
      'content-type': 'text/plain; charset=utf-8'
    };
  } 
}

base class BinaryRoute extends Route {
  BinaryRoute({
    required super.method, 
    required super.urlPath,
    required super.clientHandler,
    super.filepath, 
    super.applyMiddleware, 
    super.ttl,
    super.headers
  }) {
    headers ??= {
      'content-type': 'application/octet-stream'
    };
  } 
}

sealed class Route{
  Method method;
  String? filepath;
  RouteHandler clientHandler;
  String urlPath;
  Duration? ttl;
  Map<String, String>? headers;
  

  Route({
    required this.method, 
    required this.urlPath,
    required this.clientHandler,
    this.filepath, 
    List<Middleware>? applyMiddleware,
    this.ttl,
    this.headers
  }) {
    if (applyMiddleware != null) {
      Log.debug(()=>'Setting ${applyMiddleware.length} middlewares for $urlPath');
      for (final middleware in applyMiddleware.reversed) {
        clientHandler = middleware(clientHandler);
      }
    }
  }
  
  /// Returns Route itself
  /// 
  /// It is necessary to set only if you serve a file (html, json...) in response handler
  Route setFilePath(String fpath) {
    filepath =  fpath;
    return this;
  }

  // RouteHandler applyMiddlewares(List<Middleware> middlewares) {
    
  //   return clientHandler;
  // }
  
}

class Router {
  static final Map<String, Route> _routes = {};
  static RouteHandler? defaulRoutHandler;
  static final Router _instance = Router._internal();
  Router._internal();

  factory Router() => _instance;

  static Router get self => _instance;

  static Route? get(String urlPath) {
    return _routes[urlPath];
  }
  static void set(String urlPath, Route route) {
    _routes[urlPath] = route;
  }

  static void setDefaultRoute(RouteHandler func) {
    defaulRoutHandler = func;
  }

  /// Rewrites the file on path to specified content.
  /// Synchronized with reads in library!
  /// For this function to work it should be filepath specified in Route (Route.filepath)
  static Future<void> writeRouteFile(String urlPath, String content) async {

    if (_routes[urlPath] == null) throw Exception('Write to null route');
    if (_routes[urlPath]!.filepath == null) throw Exception('File Path is not specified for route `$urlPath`');

    await fileIoLock.synchronized(() async {
      final path = await normalizeDirPath(_routes[urlPath]!.filepath!);
      await File(path).writeAsString(content);
      if (FileCache.exists(urlPath)) FileCache.remove(path);
      Log.debug(()=>'Wrote to url `$urlPath` path == `$path`');
    });
  }
}


/// Creates `/` path by default 
/// 
/// TODO: make a `to` property more sense. Test it.
/// 
/// toHandler is a handler that will be called when Route is added (AddRoute) to specify custom route adding.
class RoutesFromDir<T> {
  T to;
  Function(Route)? toHandler;
  Directory dir;
  // Map<String, Route> routes;

  RoutesFromDir({
    required this.to, 
    required this.dir,
    this.toHandler,
  });

  Future<T> build() async {
    // if (toHandler != null) return await toHandler!();
    if (!await dir.exists()) {
      throw Exception('Directory "${dir.path}" does not exists. Create the route dir.');
    }
    

    AddRoute(
      to: to,
      toHandler: toHandler,
      HtmlRoute(
        method: Method.GET, 
        urlPath: '/',
        filepath: './www/index.html', 
        clientHandler: (client) async {
          final path = await normalizeDirPath('${dir.path}/index.html');
          final content = await Server.file(path);
          return Response.ok(content).send(client);
        }
      )
    ); 

    var dirRoutes = dir.listSync(recursive: true).where((element) => FileSystemEntity.isDirectorySync(element.path)); 
    //.where((e) => htmlFileRoute == false ? FileSystemEntity.isDirectorySync(e.path) : (e.path.endsWith('.html')?true:false));

    for (var d in dirRoutes) {
      final path = d.path.substring(dir.path.length); // without the root dir in path
      assert(path.startsWith('/'));
      final String filepath = '${d.path}/index.html';
      AddRoute(
        to: to,
        toHandler: toHandler,
        HtmlRoute(
          method: Method.GET, 
          urlPath: path, 
          clientHandler: (client) async {return Response.ok(await Server.file(filepath)).send(client);}
        )
      );
      
    }
    Log.debug(() => 'RoutesFromDir + ${dirRoutes.length} routes');
    return to;
  }
}

class AddRoute<T> {
  T? to;
  Function(Route)? toHandler;
  Route route;
  
  AddRoute(this.route, {this.toHandler, this.to }) {
    Log.debug(() => 'Adding route ${route.urlPath}');

    if (toHandler == null) {
      if(Router.get(route.urlPath) == null) {
        Router.set(route.urlPath, route);
        return;
      }
      throw 'Adding route to existing path. ${route.urlPath}';
    }
    else  {
      toHandler!(route);
    }
  }
}
sealed class Cache {}

class BinFileCache extends Cache{
  static Map<String, CacheItem<List<int>>> cache = {};

  static bool exists(String path) => cache[path] == null ? true : false;

  static List<int>? read(String path) => (exists(path) ? cache[path]!.content : null);

  static CacheItem<List<int>>? get(String urlPath){
    return cache[urlPath];
  }
  static CacheItem<List<int>> set(String urlPath, CacheItem<List<int>> item) {
    cache[urlPath] = item;
    return item;
  }
  static bool remove(String path) {
    if (cache[path] == null) return false;
    cache.remove(path);
    return true;
  }
}

class FileCache extends Cache{
  static Map<String, CacheItem<String>> cache = {};

  static bool exists(String path) => cache[path] == null ? true : false;

  static String? read(String path) => (exists(path) ? cache[path]!.content : null);

  static CacheItem<String>? get(String urlPath){
    return cache[urlPath];
  }
  static CacheItem<String> set(String urlPath, CacheItem<String> item) {
    cache[urlPath] = item;
    return item;
  }
  static bool remove(String path) {
    if (cache[path] == null) return false;
    cache.remove(path);
    return true;
  }
}

class CacheItem<T>{
  final Duration? ttl;
  int? _timestamp = DateTime.now().millisecondsSinceEpoch;
  String? filePath;
  T? _content;

  CacheItem(this._content, {this.filePath, this.ttl});

  T? get content {
    return _content;
  }

  void set(T content) {
    _content = content;
    _timestamp = DateTime.now().millisecondsSinceEpoch;
  }

  T? get() {
    if (_timestamp == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (ttl != null && now - _timestamp! > ttl!.inMilliseconds) {
      // Expired
      _content = null;
      _timestamp = null;
      return null;
    }
    return _content;
  }

  bool get isValid {
    if (ttl == null) return true;
    if (_timestamp == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - _timestamp! <= ttl!.inMilliseconds;
  }

  void clear() {
    _content = null;
    _timestamp = null;
  } 
  
  // CacheItem<Uint8List>? operator [](String path) => cache[path];

  // void operator []=(String path, CacheItem<Uint8List> content) {
  //   cache[path] = content;
  // }
}
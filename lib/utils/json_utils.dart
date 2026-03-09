Map<String, dynamic> filterJson(
  Map<String, dynamic> source,
  List<String> keys,
) {
  final result = <String, dynamic>{};

  for (final key in keys) {
    if (source.containsKey(key)) {
      result[key] = source[key];
    }
  }

  if (source.containsKey("doc_type")) {
    result["doc_type"] = source["doc_type"];
  }

  return result;
}

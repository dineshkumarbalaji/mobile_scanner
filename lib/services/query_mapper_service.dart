class QueryMapperService {
  final Map<String, List<String>> fieldMap = {
    "date_of_expiry": ["expiry", "expire", "expiration", "valid till", "expires"],
    "passport_number": ["passport number", "document number", "id number", "pass no"],
    "date_of_birth": ["birth", "dob", "born", "date of birth"],
    "surname": ["surname", "last name", "family name"],
    "given_names": ["given name", "first name", "name"],
    "nationality": ["nationality", "country", "citizen", "citizenship"],
    "place_of_birth": ["place of birth", "born in", "where"],
    "sex": ["sex", "gender"],
  };

  List<String> detectRelevantKeys(String question) {
    final q = question.toLowerCase();
    final List<String> keys = [];

    fieldMap.forEach((key, keywords) {
      if (keywords.any((k) => q.contains(k))) {
        keys.add(key);
      }
    });

    return keys;
  }
}

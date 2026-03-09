import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/services/ocr_service.dart';

void main() {
  test('extract UK Specimen Passport', () async {
    String rawText = """UNITED KINGDOM OF GREAT BRITAIN AND NORTHERN IRELANDO
OFFICIAL PASSPORT
PASSEPORT OFFICIEL
Type/Type
P
Surname/Nom (1)
Code/Code
GBR
UK SPECIMEN
Given names/Prénoms (2)
ANGELA ZOE
Nationality/Nationalite (3)
BRITISH CITIZEN
Date of birth/Date de naissance (4)
01 JAN / JAN 95
F
Sex/Sexe (5) Place of birth/Lieu de naissance (6)
LONDON
Date of issuefDate de délivrance (7)
27 NOV / NOV 19
Date of expiry/Date d'expiration (9)
27 NOV / NOV 29
Passport No./Passeport No.
999204900
Authority/ Autoritê (8)
HMPO
0101/5
P<GBRUK<SPECIMEN<<ANGELA<ZOE<<<<<<<<<<<<<«<<
9992049000GBR9501016F2911272<<<<<<<<<<<<<<o6""";

    OcrService s = OcrService();
    String? jsonStr = await s.extractJsonWithRules(rawText, 'dummy.json');
    print('--- JSON RESULT ---');
    print(jsonStr);
  });
}

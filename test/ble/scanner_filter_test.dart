import 'package:flutter_baji_demo/ble/baji_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts e-BADGE names with suffix and mixed case', () {
    expect(isBajiDeviceName('e-BADGE'), isTrue);
    expect(isBajiDeviceName('E-badge-01'), isTrue);
    expect(isBajiDeviceName('my e-BADGE X'), isTrue);
  });

  test('rejects unrelated or null names', () {
    expect(isBajiDeviceName(null), isFalse);
    expect(isBajiDeviceName(''), isFalse);
    expect(isBajiDeviceName('Badge'), isFalse);
    expect(isBajiDeviceName('Mi Band'), isFalse);
  });
}

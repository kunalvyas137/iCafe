import 'package:flutter_test/flutter_test.dart';
import 'package:icafe/models/store_settings.dart';

void main() {
  test('a missing settings document falls back to defaults', () {
    final settings = StoreSettings.fromMap(null);

    expect(settings.storeName, 'iCafe');
    expect(settings.hasUpi, isFalse);
    expect(settings.defaultGstRate, 5);
  });

  test('the UPI URI carries a two-decimal amount and escaped payee', () {
    const settings = StoreSettings(
      storeName: 'iCafe',
      upiId: 'cafe@okbank',
      upiPayeeName: 'iCafe Coffee & Co',
    );

    final uri = Uri.parse(settings.upiUri(123.4));

    expect(uri.scheme, 'upi');
    expect(uri.queryParameters['pa'], 'cafe@okbank');
    expect(uri.queryParameters['pn'], 'iCafe Coffee & Co');
    expect(uri.queryParameters['am'], '123.40');
    expect(uri.queryParameters['cu'], 'INR');
  });

  test('the payee name falls back to the store name', () {
    const settings = StoreSettings(storeName: 'Corner Cafe', upiId: 'a@b');
    expect(settings.payeeName, 'Corner Cafe');
  });

  test('settings round-trip through a map', () {
    const settings = StoreSettings(
      storeName: 'Corner Cafe',
      addressLine1: '1 High St',
      gstin: '29ABCDE1234F1Z5',
      upiId: 'corner@okbank',
      defaultGstRate: 12,
    );

    final restored = StoreSettings.fromMap(settings.toMap());

    expect(restored.storeName, settings.storeName);
    expect(restored.addressLine1, settings.addressLine1);
    expect(restored.gstin, settings.gstin);
    expect(restored.upiId, settings.upiId);
    expect(restored.defaultGstRate, 12);
  });
}

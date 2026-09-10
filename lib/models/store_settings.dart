/// Store profile used on receipts and for UPI collection, stored in
/// `settings/store` so it can be changed without a rebuild.
class StoreSettings {
  final String storeName;
  final String addressLine1;
  final String addressLine2;
  final String phone;
  final String gstin;
  final String upiId;
  final String upiPayeeName;
  final double defaultGstRate;
  final String receiptFooter;

  const StoreSettings({
    this.storeName = 'iCafe',
    this.addressLine1 = '',
    this.addressLine2 = '',
    this.phone = '',
    this.gstin = '',
    this.upiId = '',
    this.upiPayeeName = '',
    this.defaultGstRate = 5,
    this.receiptFooter = 'Thank you for your visit!',
  });

  static const StoreSettings defaults = StoreSettings();

  bool get hasUpi => upiId.trim().isNotEmpty;

  String get payeeName =>
      upiPayeeName.trim().isEmpty ? storeName : upiPayeeName.trim();

  /// UPI intent URI for the QR code. Amounts are always two decimals so
  /// payment apps do not round the request.
  String upiUri(double amount, {String? note}) {
    final params = <String, String>{
      'pa': upiId.trim(),
      'pn': payeeName,
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      if (note != null && note.isNotEmpty) 'tn': note,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return 'upi://pay?$query';
  }

  StoreSettings copyWith({
    String? storeName,
    String? addressLine1,
    String? addressLine2,
    String? phone,
    String? gstin,
    String? upiId,
    String? upiPayeeName,
    double? defaultGstRate,
    String? receiptFooter,
  }) {
    return StoreSettings(
      storeName: storeName ?? this.storeName,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      phone: phone ?? this.phone,
      gstin: gstin ?? this.gstin,
      upiId: upiId ?? this.upiId,
      upiPayeeName: upiPayeeName ?? this.upiPayeeName,
      defaultGstRate: defaultGstRate ?? this.defaultGstRate,
      receiptFooter: receiptFooter ?? this.receiptFooter,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeName': storeName,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'phone': phone,
      'gstin': gstin,
      'upiId': upiId,
      'upiPayeeName': upiPayeeName,
      'defaultGstRate': defaultGstRate,
      'receiptFooter': receiptFooter,
    };
  }

  factory StoreSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    return StoreSettings(
      storeName: map['storeName'] as String? ?? defaults.storeName,
      addressLine1: map['addressLine1'] as String? ?? '',
      addressLine2: map['addressLine2'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      gstin: map['gstin'] as String? ?? '',
      upiId: map['upiId'] as String? ?? '',
      upiPayeeName: map['upiPayeeName'] as String? ?? '',
      defaultGstRate:
          (map['defaultGstRate'] as num?)?.toDouble() ??
          defaults.defaultGstRate,
      receiptFooter: map['receiptFooter'] as String? ?? defaults.receiptFooter,
    );
  }
}

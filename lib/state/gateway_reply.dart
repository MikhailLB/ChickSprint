/// Envelope for `/config.php` responses.
///
/// Positive answer: `{ "ok": true, "url": "…", "expires": 1699999999 }`.
/// Negative answer: `{ "ok": false, "message": "organic" }`.
/// Any transport failure is folded into `GatewayReply.transportError`.
class GatewayReply {
  const GatewayReply({
    required this.ok,
    this.url,
    this.expiresAtEpoch,
    this.message,
    this.error,
  });

  final bool ok;
  final String? url;
  final int? expiresAtEpoch;
  final String? message;
  final String? error;

  bool get hasUrl => (url ?? '').isNotEmpty;
  bool get isTransportError => error != null;

  factory GatewayReply.fromJson(Map<String, dynamic> json) {
    return GatewayReply(
      ok: json['ok'] == true,
      url: json['url'] is String ? json['url'] as String : null,
      expiresAtEpoch: json['expires'] is int ? json['expires'] as int : null,
      message: json['message'] is String ? json['message'] as String : null,
    );
  }

  factory GatewayReply.transportError(String description) =>
      GatewayReply(ok: false, error: description);
}

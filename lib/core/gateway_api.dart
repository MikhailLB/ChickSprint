import 'dart:convert';

import '../env/facade.dart';
import '../state/gateway_reply.dart';
import 'vault.dart';
import 'wire_client.dart';

/// GatewayApi — POST attribution payload to `/config.php`.
///
/// Ok/url replies get persisted to [Vault] so returning users can
/// keep viewing the last known good page if the endpoint is briefly
/// unreachable (per TZ — expired URLs are still better than no
/// content).
class GatewayApi {
  GatewayApi(this._vault);

  final Vault _vault;

  Future<GatewayReply> submit(Map<String, dynamic> payload) async {
    final url = EnvFacade.gatewayUrl;
    if (url.isEmpty) {
      return GatewayReply.transportError('no gateway configured');
    }

    try {
      final response = await wire
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(EnvFacade.gatewayTimeout);

      if (response.statusCode != 200) {
        return GatewayReply.transportError('HTTP ${response.statusCode}');
      }

      final parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic>) {
        return GatewayReply.transportError('bad json');
      }

      final reply = GatewayReply.fromJson(parsed);
      if (reply.ok && reply.hasUrl) {
        await _vault.writePortalUrl(reply.url!);
        if (reply.expiresAtEpoch != null) {
          await _vault.storePortalUrlExpires(reply.expiresAtEpoch!);
        }
      }
      return reply;
    } catch (err) {
      return GatewayReply.transportError(err.toString());
    }
  }
}

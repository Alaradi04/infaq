import 'package:supabase_flutter/supabase_flutter.dart';

num balanceFromMetadata(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value;
  return num.tryParse(value.toString()) ?? 0;
}

/// Writes currency/balance from auth [user.userMetadata] into `users` once, then sets
/// `registration_synced` so later logins do not overwrite app-updated balances.
Future<void> syncRegistrationMetadataToUsersRow(
  SupabaseClient supabase,
  User user,
) async {
  final meta = user.userMetadata ?? const <String, dynamic>{};
  if (meta['registration_synced'] == true) return;

  final patch = <String, Object?>{};
  final rawCurrency = meta['currency'];
  if (rawCurrency != null && rawCurrency.toString().trim().isNotEmpty) {
    patch['currency'] = rawCurrency.toString().trim();
  }
  if (meta.containsKey('balance')) {
    patch['Balance'] = balanceFromMetadata(meta['balance']).toDouble();
  }
  try {
    if (patch.isNotEmpty) {
      await supabase.from('users').update(patch).eq('id', user.id);
    }
    await supabase.auth.updateUser(
      UserAttributes(data: const {'registration_synced': true}),
    );
  } catch (_) {
    // RLS or network: leave unsynced so a later session can retry.
  }
}

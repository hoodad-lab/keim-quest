// =====================================================================
// backend/http-functions.js   (Wix Velo · keim.com.au)
// KEIM Arcade credits → Wix shop discount code
//
// Supabase calls this when a player taps REDEEM (Database Webhook on
// INSERT into arcade_redemptions). We create a one-use coupon in the Wix
// shop for the dollar amount and write the code back to Supabase, where
// the arcade shows it in the player's wallet.
//
// Endpoint:  POST https://www.keim.com.au/_functions/arcadeRedeem
// Header:    x-arcade-secret: <ARCADE_WEBHOOK_SECRET>
//
// Secrets (Wix dashboard → Developer Tools → Secrets Manager):
//   SUPABASE_URL            e.g. https://abcd1234.supabase.co
//   SUPABASE_SERVICE_KEY    the service_role key (server only, never in page code)
//   ARCADE_WEBHOOK_SECRET   any long random string; put the same one in the Supabase webhook header
// =====================================================================
import { ok, badRequest, forbidden, serverError } from 'wix-http-functions';
import { secrets } from 'wix-secrets-backend.v2';
import { coupons } from 'wix-marketing.v2';
import { elevate } from 'wix-auth';
import { fetch } from 'wix-fetch';

const SAMPLES_COLLECTION_ID = '';   // [OPTIONAL] a Wix Stores collection id to limit the code to samples/fandeck/merch
const CODE_VALID_DAYS = 180;

const getSecret = elevate(secrets.getSecretValue);
async function sb(path, method, body) {
  const [url, key] = await Promise.all([getSecret('SUPABASE_URL'), getSecret('SUPABASE_SERVICE_KEY')]);
  const res = await fetch(`${url}/rest/v1/${path}`, {
    method, headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}`, Prefer: 'return=representation' },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`Supabase ${path}: ${res.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

export async function post_arcadeRedeem(request) {
  try {
    const secret = await getSecret('ARCADE_WEBHOOK_SECRET');
    if (request.headers['x-arcade-secret'] !== secret) return forbidden({ body: 'no' });
    const payload = await request.body.json();
    const r = payload && payload.record;                       // Supabase webhook: { type:'INSERT', table, record:{...} }
    if (!r || !r.id || r.status !== 'pending') return badRequest({ body: 'ignored' });

    const member = (await sb(`arcade_members?user_id=eq.${r.user_id}&select=email,initials`, 'GET'))[0] || {};
    const dollars = Number(r.dollars);
    const code = 'KA' + Math.random().toString(36).slice(2, 8).toUpperCase() + dollars;
    try {
      const spec = {
        name: `KEIM Arcade $${dollars} · ${member.email || r.user_id}`,
        code,
        startTime: `${Date.now()}`,
        expirationTime: `${Date.now() + CODE_VALID_DAYS * 864e5}`,
        usageLimit: 1,
        limitPerCustomer: 1,
        active: true,
        scope: SAMPLES_COLLECTION_ID
          ? { namespace: 'stores', group: { name: 'collection', entityId: SAMPLES_COLLECTION_ID } }
          : { namespace: 'stores' },
        moneyOffAmount: dollars
      };
      const c = await elevate(coupons.createCoupon)(spec);
      await sb('rpc/arcade_redeem_issued', 'POST', { p_id: r.id, p_code: code, p_coupon_id: String(c._id || c.id || '') });
      return ok({ body: { ok: true, code } });
    } catch (e) {
      console.error('coupon failed, refunding', e);
      await sb('rpc/arcade_redeem_refund', 'POST', { p_id: r.id });
      return serverError({ body: { ok: false, reason: 'coupon' } });
    }
  } catch (e) {
    console.error(e);
    return serverError({ body: { ok: false } });
  }
}

// Supabase Edge Function. Deploy: supabase functions deploy paystack-webhook --no-verify-jwt
// Secrets: PAYSTACK_SECRET_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Set the webhook URL in your Paystack dashboard. Pass metadata { project_id } when you initialise each transaction.
import { createClient } from 'npm:@supabase/supabase-js@2';
const enc = new TextEncoder();
async function sign(body: string, key: string) {
  const k = await crypto.subtle.importKey('raw', enc.encode(key), { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
  const s = await crypto.subtle.sign('HMAC', k, enc.encode(body));
  return [...new Uint8Array(s)].map(b => b.toString(16).padStart(2, '0')).join('');
}
Deno.serve(async (req) => {
  const body = await req.text();
  if (await sign(body, Deno.env.get('PAYSTACK_SECRET_KEY')!) !== req.headers.get('x-paystack-signature'))
    return new Response('bad signature', { status: 401 });
  const ev = JSON.parse(body);
  if (ev.event === 'charge.success') {
    const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { reference, amount, metadata } = ev.data;   // Paystack amounts are in kobo
    await sb.from('payments').upsert({ project_id: metadata.project_id, amount: amount / 100, source: 'paystack', reference }, { onConflict: 'reference', ignoreDuplicates: true });
  }
  return new Response('ok');
});

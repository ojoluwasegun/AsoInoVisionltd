// Receives the "Book a consultation" form, stores it, and notifies the team by email and WhatsApp.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { notify } from '../_shared/notify.ts';
const allowed = (Deno.env.get('ALLOWED_ORIGIN') ?? '*').split(',').map((x) => x.trim());
const corsFor = (req: Request) => {
  const o = req.headers.get('origin') ?? '';
  const any = allowed.includes('*');
  return { 'Access-Control-Allow-Origin': any ? '*' : allowed.includes(o) ? o : allowed[0], 'Vary': 'Origin', 'Access-Control-Allow-Headers': 'content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
};
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const reply = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ ok: false, error: 'method' }, 405);
  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return reply({ ok: false, error: 'bad json' }, 400); }
  if (b.website) return reply({ ok: true });                       // honeypot: bots fill this in
  const row = { full_name: clip(b.full_name, 120), email: clip(b.email, 160), phone: clip(b.phone, 40), organisation: clip(b.organisation, 160),
    job_title: clip(b.job_title, 120), company_size: clip(b.company_size, 40), industry: clip(b.industry, 80), service: clip(b.service, 80),
    timeline: clip(b.timeline, 60), budget: clip(b.budget, 60), contact_method: clip(b.contact_method, 30), preferred_time: clip(b.preferred_time, 40), message: clip(b.message, 3000) };
  if (!row.full_name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(row.email) || !row.phone || !row.organisation || !row.message) return reply({ ok: false, error: 'missing fields' }, 400);
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { error } = await sb.from('consultations').insert(row);
  if (error) { console.error(error); return reply({ ok: false, error: 'save failed' }, 500); }
  const text = Object.entries(row).filter(([, v]) => v).map(([k, v]) => `${k.replace(/_/g, ' ')}: ${v}`).join('\n');
  await notify(`New consultation request from ${row.full_name}`, text).catch((e) => console.error(e));
  return reply({ ok: true });
});

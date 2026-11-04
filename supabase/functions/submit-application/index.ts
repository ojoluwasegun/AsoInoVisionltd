// Receives a job application (form fields + CV), stores both, and notifies the team by email and WhatsApp.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { notify } from '../_shared/notify.ts';
const allowed = (Deno.env.get('ALLOWED_ORIGIN') ?? '*').split(',').map((x) => x.trim());
const corsFor = (req: Request) => {
  const o = req.headers.get('origin') ?? '';
  const any = allowed.includes('*');
  return { 'Access-Control-Allow-Origin': any ? '*' : allowed.includes(o) ? o : allowed[0], 'Vary': 'Origin', 'Access-Control-Allow-Headers': 'content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
};
const clip = (v: unknown, n: number) => String(v ?? '').trim().slice(0, n);
const OK_TYPES = ['application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/msword'];

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const reply = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ ok: false, error: 'method' }, 405);
  const f = await req.formData().catch(() => null);
  if (!f) return reply({ ok: false, error: 'bad form' }, 400);
  if (f.get('website')) return reply({ ok: true });
  const cv = f.get('cv');
  if (!(cv instanceof File) || cv.size === 0 || cv.size > 5 * 1024 * 1024 || !OK_TYPES.includes(cv.type)) return reply({ ok: false, error: 'cv' }, 400);
  const row = { role: clip(f.get('role_title'), 120), full_name: clip(f.get('a_name'), 120), email: clip(f.get('a_email'), 160), phone: clip(f.get('a_phone'), 40), location: clip(f.get('a_location'), 120),
    level: clip(f.get('level'), 20), department: clip(f.get('department'), 60), education: clip(f.get('education'), 3000), experience: clip(f.get('experience'), 5000),
    linkedin: clip(f.get('linkedin'), 200), x_handle: clip(f.get('x_handle'), 200), facebook: clip(f.get('facebook'), 200), note: clip(f.get('note'), 1500) };
  if (!row.role || !row.full_name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(row.email) || !row.phone || !row.education) return reply({ ok: false, error: 'missing fields' }, 400);
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const safe = cv.name.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80);
  const path = `${crypto.randomUUID()}/${safe}`;
  const up = await sb.storage.from('cvs').upload(path, cv, { contentType: cv.type });
  if (up.error) { console.error(up.error); return reply({ ok: false, error: 'upload failed' }, 500); }
  const { error } = await sb.from('applications').insert({ ...row, cv_path: path });
  if (error) { console.error(error); return reply({ ok: false, error: 'save failed' }, 500); }
  const link = (await sb.storage.from('cvs').createSignedUrl(path, 60 * 60 * 24 * 7)).data?.signedUrl ?? '(see dashboard)';
  const text = `${row.full_name} applied for ${row.role}\nEmail: ${row.email}\nPhone: ${row.phone}\nLocation: ${row.location}\nCV (7 days): ${link}`;
  await notify(`New application: ${row.role}`, text).catch((e) => console.error(e));
  return reply({ ok: true });
});

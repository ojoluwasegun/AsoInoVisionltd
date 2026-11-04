-- ThesisFlow platform schema for Supabase. Run in the SQL editor.
create type app_role as enum ('admin','coach','client','support','agent');

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text not null,
  role app_role not null default 'client',
  bio text,                       -- coach marketing profile
  created_at timestamptz default now()
);
create table projects (
  id bigint generated always as identity primary key,
  client_id uuid not null references profiles,
  coach_id uuid references profiles,
  agent_id uuid references profiles,
  topic text not null,
  tier text not null,
  price numeric not null,
  plan text not null check (plan in ('full','split')),
  status text not null default 'pending' check (status in ('pending','active','ended','cancelled')),
  locked numeric not null default 0,      -- coach share held until the client ends the project
  room text not null default encode(gen_random_bytes(6),'hex'),
  created_at timestamptz default now()
);
create table payments (
  id bigint generated always as identity primary key,
  project_id bigint not null references projects,
  amount numeric not null check (amount > 0),
  source text not null,                   -- paystack | opay | manual
  reference text unique,
  approved boolean not null default false,
  created_at timestamptz default now()
);
create table wallets (user_id uuid primary key references profiles, available numeric not null default 0, locked numeric not null default 0);
create table wallet_tx (id bigint generated always as identity primary key, user_id uuid references profiles, amount numeric not null, kind text not null, note text, created_at timestamptz default now());
create table withdrawals (id bigint generated always as identity primary key, user_id uuid references profiles, amount numeric not null, status text not null default 'requested', created_at timestamptz default now());
create table messages (id bigint generated always as identity primary key, project_id bigint references projects, sender_id uuid references profiles, body text not null, created_at timestamptz default now());
create table corrections (id bigint generated always as identity primary key, project_id bigint references projects, author_id uuid references profiles, note text not null, image_path text, created_at timestamptz default now());
create table reports (id bigint generated always as identity primary key, project_id bigint references projects, coach_id uuid references profiles, file_path text not null, created_at timestamptz default now());
create table ratings (id bigint generated always as identity primary key, project_id bigint references projects, client_id uuid references profiles, stars int check (stars between 1 and 5), comment text, is_complaint boolean default false, created_at timestamptz default now());
create table tickets (id bigint generated always as identity primary key, opened_by uuid references profiles, subject text not null, body text, status text default 'open', reply text, created_at timestamptz default now());
create table live_messages (id bigint generated always as identity primary key, from_user uuid references profiles, from_name text, body text not null, reply text, created_at timestamptz default now());
create table referrals (id bigint generated always as identity primary key, agent_id uuid references profiles, client_name text not null, tier text, processed boolean default false, created_at timestamptz default now());

create function my_role() returns app_role language sql stable security definer set search_path = public as
  $$ select role from profiles where id = auth.uid() $$;

-- Row level security
alter table profiles enable row level security; alter table projects enable row level security; alter table payments enable row level security;
alter table wallets enable row level security; alter table wallet_tx enable row level security; alter table withdrawals enable row level security;
alter table messages enable row level security; alter table corrections enable row level security; alter table reports enable row level security;
alter table ratings enable row level security; alter table tickets enable row level security; alter table live_messages enable row level security; alter table referrals enable row level security;

create policy "read profiles" on profiles for select using (true);   -- public coach directory; hide private columns in a view if you add any
create policy "edit own profile" on profiles for update using (id = auth.uid()) with check (id = auth.uid() and role = (select role from profiles where id = auth.uid()));
create policy "projects visible to parties" on projects for select using (client_id = auth.uid() or coach_id = auth.uid() or agent_id = auth.uid() or my_role() in ('admin','support'));
create policy "client creates project" on projects for insert with check (client_id = auth.uid());
create policy "payments visible to parties" on payments for select using (exists (select 1 from projects p where p.id = project_id and (p.client_id = auth.uid() or p.coach_id = auth.uid())) or my_role() = 'admin');
create policy "own wallet" on wallets for select using (user_id = auth.uid() or my_role() = 'admin');
create policy "own wallet tx" on wallet_tx for select using (user_id = auth.uid() or my_role() = 'admin');
create policy "own withdrawals" on withdrawals for select using (user_id = auth.uid() or my_role() = 'admin');
create policy "project chat" on messages for all using (exists (select 1 from projects p where p.id = project_id and (p.client_id = auth.uid() or p.coach_id = auth.uid())) or my_role() = 'admin')
  with check (sender_id = auth.uid());
create policy "project corrections" on corrections for all using (exists (select 1 from projects p where p.id = project_id and (p.client_id = auth.uid() or p.coach_id = auth.uid())) or my_role() = 'admin') with check (author_id = auth.uid());
create policy "project reports" on reports for select using (exists (select 1 from projects p where p.id = project_id and (p.client_id = auth.uid() or p.coach_id = auth.uid())) or my_role() = 'admin');
create policy "coach adds report" on reports for insert with check (coach_id = auth.uid());
create policy "ratings read" on ratings for select using (client_id = auth.uid() or my_role() in ('admin','support') or true);
create policy "client rates own project" on ratings for insert with check (client_id = auth.uid());
create policy "tickets" on tickets for select using (opened_by = auth.uid() or my_role() in ('admin','support'));
create policy "open ticket" on tickets for insert with check (opened_by = auth.uid());
create policy "staff update tickets" on tickets for update using (my_role() in ('admin','support'));
create policy "live msgs staff" on live_messages for select using (from_user = auth.uid() or my_role() in ('admin','support'));
create policy "live msgs insert" on live_messages for insert with check (true);
create policy "agent referrals" on referrals for all using (agent_id = auth.uid() or my_role() = 'admin') with check (agent_id = auth.uid());

-- Money rules. 40% of the coach share is released when admin approves a payment; 60% is released when the client ends the project.
-- Change adv_share or platform_fee to match your final decision.
create function approve_payment(p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare pay payments; prj projects; adv_share numeric := 0.4; platform_fee numeric := 0; share numeric;
begin
  if my_role() <> 'admin' then raise exception 'admin only'; end if;
  select * into pay from payments where id = p_id and not approved for update;
  if not found then raise exception 'already approved or missing'; end if;
  select * into prj from projects where id = pay.project_id;
  if prj.coach_id is null then raise exception 'assign a coach first'; end if;
  share := pay.amount * (1 - platform_fee);
  insert into wallets(user_id) values (prj.coach_id) on conflict do nothing;
  update wallets set available = available + share * adv_share, locked = locked + share * (1 - adv_share) where user_id = prj.coach_id;
  update projects set locked = locked + share * (1 - adv_share) where id = prj.id;
  update payments set approved = true where id = p_id;
  insert into wallet_tx(user_id, amount, kind, note) values (prj.coach_id, share * adv_share, 'approved', 'Payment #' || p_id);
end $$;

create function end_project(p_id bigint) returns void language plpgsql security definer set search_path = public as $$
declare prj projects; paid numeric;
begin
  select * into prj from projects where id = p_id and client_id = auth.uid() and status = 'active' for update;
  if not found then raise exception 'not allowed'; end if;
  select coalesce(sum(amount),0) into paid from payments where project_id = p_id;
  if paid < prj.price then raise exception 'pay the balance first'; end if;
  update wallets set available = available + prj.locked, locked = locked - prj.locked where user_id = prj.coach_id;
  insert into wallet_tx(user_id, amount, kind, note) values (prj.coach_id, prj.locked, 'released', 'Project #' || p_id || ' ended');
  update projects set status = 'ended', locked = 0 where id = p_id;
end $$;

-- ===== Update 2: coach contact details, bank accounts, live chat sessions, audit log, agent revert =====
alter table profiles add column phone_call text, add column phone_whatsapp text, add column avatar_url text, add column headline text, add column specialities text;
-- Coaches must have both numbers before being assigned work (enforce in the app and in assign logic).

-- BVN is NEVER stored. Verify it server-side (Edge Function + a licensed provider, check their current docs and pricing),
-- then save only the verified account name here. Writes go through the Edge Function using the service role.
create table bank_accounts (
  user_id uuid primary key references profiles,
  bank_name text not null,
  account_number text not null check (account_number ~ '^[0-9]{10}$'),
  account_name text not null,
  verified boolean not null default false,
  verified_at timestamptz
);
alter table bank_accounts enable row level security;
create policy "own bank account" on bank_accounts for select using (user_id = auth.uid() or my_role() = 'admin');

create table audit_log (id bigint generated always as identity primary key, actor uuid references profiles, action text not null, detail text, created_at timestamptz default now());
alter table audit_log enable row level security;
create policy "admin reads audit" on audit_log for select using (my_role() = 'admin');

create sequence chat_seq start 1001;
create table live_chats (id bigint generated always as identity primary key, chat_code text unique not null default ('CH-' || nextval('chat_seq')), visitor_name text, needs_agent boolean not null default false, created_at timestamptz default now());
create table live_chat_messages (id bigint generated always as identity primary key, chat_id bigint references live_chats on delete cascade, sender text not null, body text not null, created_at timestamptz default now());
alter table live_chats enable row level security; alter table live_chat_messages enable row level security;
create policy "staff read chats" on live_chats for select using (my_role() in ('admin','support'));
create policy "staff read chat messages" on live_chat_messages for select using (my_role() in ('admin','support'));
create policy "staff reply" on live_chat_messages for insert with check (my_role() in ('admin','support'));
-- Visitors create chats and messages through an Edge Function that returns only their own chat by code.

alter table referrals add column processed_by uuid references profiles, add column processed_at timestamptz;
create function process_referral(r_id bigint) returns void language plpgsql security definer set search_path = public as $$
begin
  if my_role() <> 'admin' then raise exception 'admin only'; end if;
  update referrals set processed = true, processed_by = auth.uid(), processed_at = now() where id = r_id;
  insert into audit_log(actor, action, detail) values (auth.uid(), 'process_referral', 'Referral ' || r_id);
end $$;
create function revert_referral(r_id bigint) returns void language plpgsql security definer set search_path = public as $$
begin
  if my_role() <> 'admin' then raise exception 'admin only'; end if;
  update referrals set processed = false, processed_by = null, processed_at = null where id = r_id;
  insert into audit_log(actor, action, detail) values (auth.uid(), 'revert_referral', 'Referral ' || r_id);
end $$;

-- ===== Update 3: deadlines, room rules, reassignment, suspension, coach applications =====
alter table projects add column deadline_days int not null default 3 check (deadline_days between 3 and 5), add column due_at timestamptz;
-- Set due_at = now() + deadline_days * interval '1 day' when a coach is assigned, and again on reassignment.

alter table profiles add column overview text, add column experience text, add column cv_path text,
  add column application_status text not null default 'applied' check (application_status in ('applied','interview','approved','rejected')),
  add column interview_at timestamptz, add column suspended_reason text, add column rules_accepted_at timestamptz;
-- Email confirmation: turn on "Confirm email" in Supabase Auth. Users cannot sign in until auth.users.email_confirmed_at is set.
-- Suspension: also ban the auth user so a suspended account cannot sign in:  update via the Admin API with ban_duration.

create table reassignment_requests (id bigint generated always as identity primary key, project_id bigint references projects, requested_by uuid references profiles, reason text not null, status text not null default 'open', created_at timestamptz default now());
alter table reassignment_requests enable row level security;
create policy "client requests reassignment" on reassignment_requests for insert with check (requested_by = auth.uid());
create policy "see reassignment requests" on reassignment_requests for select using (requested_by = auth.uid() or my_role() = 'admin');

create function reassign_project(p_id bigint, new_coach uuid, why text) returns void language plpgsql security definer set search_path = public as $$
declare prj projects;
begin
  if my_role() <> 'admin' then raise exception 'admin only'; end if;
  select * into prj from projects where id = p_id and status = 'active' for update;
  if not found then raise exception 'project not active'; end if;
  if not exists (select 1 from profiles where id = new_coach and role = 'coach' and application_status = 'approved' and suspended_reason is null) then raise exception 'coach not eligible'; end if;
  insert into wallets(user_id) values (new_coach) on conflict do nothing;
  update wallets set locked = locked - prj.locked where user_id = prj.coach_id;      -- held funds move with the project
  update wallets set locked = locked + prj.locked where user_id = new_coach;
  update projects set coach_id = new_coach, due_at = now() + (deadline_days || ' days')::interval where id = p_id;
  update reassignment_requests set status = 'done' where project_id = p_id and status = 'open';
  insert into audit_log(actor, action, detail) values (auth.uid(), 'reassign_project', 'Project ' || p_id || ': ' || why);
end $$;

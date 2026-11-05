-- CSDF 1B ARENA — run this in a NEW Supabase project's SQL Editor.
-- Do not expose the service-role key in the browser.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(full_name) between 1 and 80),
  index_number integer not null unique check (index_number between 101 and 200),
  role text not null default 'student' check (role in ('student','admin')),
  created_at timestamptz not null default now()
);
create table if not exists public.competitions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null,
  description text,
  duration_minutes integer not null default 10 check (duration_minutes between 1 and 180),
  is_published boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  question_text text not null,
  option_a text not null, option_b text not null, option_c text not null, option_d text not null,
  correct_option text not null check (correct_option in ('A','B','C','D')),
  explanation text,
  created_at timestamptz not null default now()
);
create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  competition_id uuid not null references public.competitions(id) on delete cascade,
  score integer not null default 0 check (score >= 0),
  correct_count integer not null default 0,
  total_questions integer not null check (total_questions > 0),
  elapsed_seconds integer not null default 0 check (elapsed_seconds >= 0),
  created_at timestamptz not null default now()
);
create index if not exists attempts_user_idx on public.attempts(user_id);
create index if not exists attempts_competition_idx on public.attempts(competition_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
declare idx integer;
begin
  idx := (new.raw_user_meta_data->>'index_number')::integer;
  if idx is null or idx < 101 or idx > 200 then raise exception 'Index number must be between 101 and 200'; end if;
  insert into public.profiles(id,full_name,index_number)
  values(new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),'Student'), idx);
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.competitions enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;

create or replace function public.is_arena_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

-- Only non-sensitive class display fields exist in profiles; allow class members to see them.
create policy "Class members can view class profiles" on public.profiles for select to authenticated using (true);
create policy "Students update own display name" on public.profiles for update to authenticated
  using(id=auth.uid()) with check(id=auth.uid() and role='student' and index_number between 101 and 200);
create policy "Admins update profiles" on public.profiles for update to authenticated
  using(public.is_arena_admin()) with check(public.is_arena_admin());

create policy "Published competitions visible" on public.competitions for select to authenticated
  using(is_published=true or public.is_arena_admin());
create policy "Admins create competitions" on public.competitions for insert to authenticated with check(public.is_arena_admin());
create policy "Admins update competitions" on public.competitions for update to authenticated using(public.is_arena_admin()) with check(public.is_arena_admin());
create policy "Admins delete competitions" on public.competitions for delete to authenticated using(public.is_arena_admin());

-- Students cannot query the questions table directly: correct_option is private.
create policy "Admins manage questions" on public.questions for all to authenticated
  using(public.is_arena_admin()) with check(public.is_arena_admin());
create policy "Students read own attempts" on public.attempts for select to authenticated
  using(user_id=auth.uid() or public.is_arena_admin());
-- No direct student INSERT policy. Scores are written only by the secure RPC below.

create or replace function public.get_competition_questions(p_competition_id uuid)
returns table(id uuid, question_text text, option_a text, option_b text, option_c text, option_d text)
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  if not exists(select 1 from public.competitions where competitions.id=p_competition_id and is_published=true) then
    raise exception 'Competition is not available';
  end if;
  return query select q.id,q.question_text,q.option_a,q.option_b,q.option_c,q.option_d
    from public.questions q where q.competition_id=p_competition_id order by q.created_at,q.id;
end; $$;

create or replace function public.submit_competition_attempt(
  p_competition_id uuid, p_answers jsonb, p_elapsed_seconds integer
)
returns table(score integer, correct_count integer, total_questions integer)
language plpgsql security definer set search_path=public as $$
declare total integer; correct integer; final_score integer;
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  if jsonb_typeof(p_answers) <> 'array' then raise exception 'Invalid answer format'; end if;
  if p_elapsed_seconds < 0 or p_elapsed_seconds > 10800 then raise exception 'Invalid completion time'; end if;
  if not exists(select 1 from public.competitions where id=p_competition_id and is_published=true) then raise exception 'Competition is not available'; end if;
  select count(*) into total from public.questions where competition_id=p_competition_id;
  if total=0 then raise exception 'This competition has no questions'; end if;
  if jsonb_array_length(p_answers) <> total then raise exception 'Please answer every question before submitting'; end if;
  if exists (
    select 1 from jsonb_array_elements(p_answers) a
    where coalesce(a->>'selected_option','') not in ('A','B','C','D','')
       or not exists(select 1 from public.questions q where q.id=(a->>'question_id')::uuid and q.competition_id=p_competition_id)
  ) then raise exception 'One or more submitted answers are invalid'; end if;
  if (select count(distinct a->>'question_id') from jsonb_array_elements(p_answers) a) <> total then
    raise exception 'Duplicate or missing question answers';
  end if;
  select count(*) into correct
  from jsonb_array_elements(p_answers) a
  join public.questions q on q.id=(a->>'question_id')::uuid
  where q.competition_id=p_competition_id and q.correct_option=a->>'selected_option';
  final_score := correct * 10;
  insert into public.attempts(user_id,competition_id,score,correct_count,total_questions,elapsed_seconds)
  values(auth.uid(),p_competition_id,final_score,correct,total,greatest(0,p_elapsed_seconds));
  return query select final_score,correct,total;
end; $$;

create or replace function public.get_arena_leaderboard()
returns table(full_name text,index_number integer,total_points bigint)
language sql stable security definer set search_path=public as $$
  with best_scores as (
    select a.user_id,a.competition_id,max(a.score) as best_score
    from public.attempts a group by a.user_id,a.competition_id
  )
  select p.full_name,p.index_number,coalesce(sum(b.best_score),0)::bigint
  from public.profiles p left join best_scores b on b.user_id=p.id
  group by p.id,p.full_name,p.index_number
  order by coalesce(sum(b.best_score),0) desc,p.index_number asc;
$$;

grant execute on function public.get_competition_questions(uuid) to authenticated;
grant execute on function public.submit_competition_attempt(uuid,jsonb,integer) to authenticated;
grant execute on function public.get_arena_leaderboard() to authenticated;

-- After registering and confirming YOUR OWN account, run separately and replace 101 with your assigned index:
-- update public.profiles set role='admin' where index_number=101;

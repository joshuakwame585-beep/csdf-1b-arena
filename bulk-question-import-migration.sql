-- CSDF 1B ARENA: one-time migration for existing Supabase databases.
-- Run this in Supabase SQL Editor before deploying the updated frontend.
alter table public.questions add column if not exists question_order integer not null default 0;
with ranked as (
  select id, row_number() over(partition by competition_id order by created_at, id) as seq
  from public.questions where question_order=0
)
update public.questions q set question_order=ranked.seq from ranked where q.id=ranked.id;
create index if not exists questions_competition_order_idx on public.questions(competition_id, question_order);
create or replace function public.get_competition_questions(p_competition_id uuid)
returns table(id uuid, question_text text, option_a text, option_b text, option_c text, option_d text)
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  if not exists(select 1 from public.competitions where competitions.id=p_competition_id and is_published=true) then
    raise exception 'Competition is not available';
  end if;
  return query select q.id,q.question_text,q.option_a,q.option_b,q.option_c,q.option_d
    from public.questions q where q.competition_id=p_competition_id order by q.question_order,q.created_at,q.id;
end; $$;
grant execute on function public.get_competition_questions(uuid) to authenticated;

-- Answers to the Body age questions (lib/bodyage.ts Lifestyle): smoking, vaping and alcohol.
-- Null until they answer; the Body age tab asks before it shows the number.
alter table public.fs_user_settings add column if not exists lifestyle jsonb;

-- Garante que usuários anon (app) consigam deletar posts do feed.
-- A segurança real é feita no app: .eq('autor_id', meuId) limita a exclusão
-- ao próprio post do usuário.

-- Habilita RLS caso não esteja (idempotente)
ALTER TABLE feed_posts ENABLE ROW LEVEL SECURITY;

-- Policy de DELETE para role anon
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'feed_posts'
      AND policyname = 'anon_delete_feed_posts'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "anon_delete_feed_posts"
      ON public.feed_posts
      FOR DELETE
      TO anon
      USING (true);
    $policy$;
  END IF;
END
$$;

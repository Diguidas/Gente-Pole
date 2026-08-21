-- Reações do feed (estilo LinkedIn): cada colaborador pode reagir a um post
-- com um único tipo por vez (gostei/parabéns/amei/estrela). Repetir a mesma
-- reação remove o registro (toggle) — lógica feita no app via upsert/delete.

CREATE TABLE IF NOT EXISTS public.feed_post_reacoes (
  id            bigserial PRIMARY KEY,
  post_id       bigint NOT NULL REFERENCES public.feed_posts(id) ON DELETE CASCADE,
  colaborador_id bigint NOT NULL REFERENCES public.colaboradores(id) ON DELETE CASCADE,
  tipo          text NOT NULL CHECK (tipo IN ('gostei', 'parabens', 'amei', 'estrela')),
  criado_em     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, colaborador_id)
);

CREATE INDEX IF NOT EXISTS idx_feed_post_reacoes_post_id
  ON public.feed_post_reacoes (post_id);

ALTER TABLE public.feed_post_reacoes ENABLE ROW LEVEL SECURITY;

-- Mesmo padrão permissivo das demais tabelas do feed: a segurança de "só o
-- dono edita a própria reação" é feita no app (.eq('colaborador_id', meuId)).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'feed_post_reacoes'
      AND policyname = 'anon_all_feed_post_reacoes'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "anon_all_feed_post_reacoes"
      ON public.feed_post_reacoes
      FOR ALL
      TO anon
      USING (true)
      WITH CHECK (true);
    $policy$;
  END IF;
END
$$;

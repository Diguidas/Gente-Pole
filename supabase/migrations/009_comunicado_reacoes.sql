-- Reações de comunicados (espelha feed_post_reacoes, mas para a tabela
-- `comunicados`, que é separada de `feed_posts`).

CREATE TABLE IF NOT EXISTS public.comunicado_reacoes (
  id             bigserial PRIMARY KEY,
  comunicado_id  bigint NOT NULL REFERENCES public.comunicados(id) ON DELETE CASCADE,
  colaborador_id bigint NOT NULL REFERENCES public.colaboradores(id) ON DELETE CASCADE,
  tipo           text NOT NULL CHECK (tipo IN ('gostei', 'parabens', 'amei', 'estrela')),
  criado_em      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (comunicado_id, colaborador_id)
);

CREATE INDEX IF NOT EXISTS idx_comunicado_reacoes_comunicado_id
  ON public.comunicado_reacoes (comunicado_id);

ALTER TABLE public.comunicado_reacoes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'comunicado_reacoes'
      AND policyname = 'anon_all_comunicado_reacoes'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "anon_all_comunicado_reacoes"
      ON public.comunicado_reacoes
      FOR ALL
      TO anon
      USING (true)
      WITH CHECK (true);
    $policy$;
  END IF;
END
$$;

-- Bucket "feed-imagens" existe e está marcado como Public, mas "Public" só
-- libera LEITURA via URL pública — upload (INSERT) sempre precisa de policy
-- explícita em storage.objects. Como o app não usa Supabase Auth (login
-- customizado via usuarios_auth), toda requisição chega como role anon.
-- Sem essa policy, upload falha com 403 "new row violates row-level
-- security policy" e o post é criado sem imagem (ou falha, dependendo do
-- fluxo do app).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'anon_insert_feed_imagens'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "anon_insert_feed_imagens"
      ON storage.objects
      FOR INSERT
      TO anon
      WITH CHECK (bucket_id = 'feed-imagens');
    $policy$;
  END IF;

  -- Leitura via API/RLS (a URL pública já funciona sem isso, mas cobre
  -- eventuais chamadas autenticadas que passem por select/list).
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname = 'anon_select_feed_imagens'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "anon_select_feed_imagens"
      ON storage.objects
      FOR SELECT
      TO anon
      USING (bucket_id = 'feed-imagens');
    $policy$;
  END IF;
END
$$;

-- Tabela de reserva de carrinho ativo
CREATE TABLE IF NOT EXISTS lojinha_carrinho (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  colaborador_id text      NOT NULL,
  material     text        NOT NULL,
  quantidade   numeric     NOT NULL CHECK (quantidade > 0),
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL DEFAULT (now() + interval '10 minutes'),
  CONSTRAINT uq_carrinho_colab_material UNIQUE (colaborador_id, material)
);

CREATE INDEX IF NOT EXISTS idx_lojinha_carrinho_material  ON lojinha_carrinho(material);
CREATE INDEX IF NOT EXISTS idx_lojinha_carrinho_expires   ON lojinha_carrinho(expires_at);

-- Colunas adicionais em lojinha_pedidos para guardar remessa e status estruturado do SAP
ALTER TABLE lojinha_pedidos
  ADD COLUMN IF NOT EXISTS remessa    text,
  ADD COLUMN IF NOT EXISTS status_sap text;

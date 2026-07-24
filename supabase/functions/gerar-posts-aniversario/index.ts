import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

Deno.serve(async () => {
  const agora = new Date(Date.now() - 3 * 60 * 60 * 1000)
  const ano   = agora.getUTCFullYear()
  const mes   = String(agora.getUTCMonth() + 1).padStart(2, '0')
  const dia   = String(agora.getUTCDate()).padStart(2, '0')
  const hoje  = `${ano}-${mes}-${dia}`

  // Busca config de imagem e texto
  const { data: config } = await supabase
    .from('config_post_aniversario')
    .select('*')
    .single()

  // ── Aniversários de nascimento ──────────────────────────────────────────
  const { data: aniversariantes } = await supabase.rpc('aniversariantes_hoje')

  if (aniversariantes && aniversariantes.length > 0) {
    const { data: jaExiste } = await supabase
      .from('feed_posts')
      .select('id')
      .eq('tipo', 'aniversario')
      .gte('criado_em', `${hoje}T00:00:00`)
      .maybeSingle()

    if (!jaExiste) {
      const nomes = formatarNomes(aniversariantes.map((c: any) => c.nome))
      const texto = (config?.texto_aniversario ?? '🎂 Feliz aniversário, {nomes}!')
        .replace('{nomes}', nomes)

      await supabase.from('feed_posts').insert({
        autor_id:    null,
        tipo:        'aniversario',
        conteudo:    texto,
        imagem_url:  config?.imagem_url_aniversario ?? null,
        destinatario: 'todos',
      })
    }
  }

  // ── Aniversários de empresa ─────────────────────────────────────────────
  const { data: veteranos } = await supabase.rpc('veteranos_hoje')
  const veteranosFiltrados = (veteranos ?? []).filter((c: any) => {
    const anos = ano - new Date(c.data_admissao).getFullYear()
    return anos >= 1
  })

  if (veteranosFiltrados.length > 0) {
    const { data: jaExiste } = await supabase
      .from('feed_posts')
      .select('id')
      .eq('tipo', 'aniversario_empresa')
      .gte('criado_em', `${hoje}T00:00:00`)
      .maybeSingle()

    if (!jaExiste) {
      const nomes = formatarNomes(veteranosFiltrados.map((c: any) => c.nome))
      const texto = (config?.texto_empresa ?? '🏢 Parabéns pelo aniversário de empresa, {nomes}!')
        .replace('{nomes}', nomes)

      await supabase.from('feed_posts').insert({
        autor_id:    null,
        tipo:        'aniversario_empresa',
        conteudo:    texto,
        imagem_url:  config?.imagem_url_empresa ?? null,
        destinatario: 'todos',
      })
    }
  }

  return new Response('ok')
})

// "João, Maria e Pedro" — Oxford comma em pt-BR
function formatarNomes(nomes: string[]): string {
  if (nomes.length === 0) return ''
  const marcados = nomes.map(n => `*${n}*`)
  if (marcados.length === 1) return marcados[0]
  if (marcados.length === 2) return `${marcados[0]} e ${marcados[1]}`
  return marcados.slice(0, -1).join(', ') + ' e ' + marcados[marcados.length - 1]
}
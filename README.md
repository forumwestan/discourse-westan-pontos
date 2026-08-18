# discourse-westan-pontos

Plugin independente para Discourse com carteira de pontos, multiplicador VIP, catálogo de benefícios e solicitações de troca.

O grupo VIP padrão é `vip` (mencionado no fórum como `@vip`). O plugin também aceita o ID numérico gravado pelo seletor de grupos do painel administrativo.

O ícone de carteira usa o `wallet-03` da [Hugeicons](https://hugeicons.com/icon/wallet-03), disponibilizado no conjunto gratuito sob licença MIT.

## Importação de publicações anteriores

Dentro do container do Discourse, execute:

```bash
START_AT="2026-08-01 00:00:00" bundle exec rake westan_points:backfill
```

A tarefa respeita as regras atuais do plugin e pode ser executada novamente sem duplicar pontos já registrados. Por padrão, `END_AT` corresponde ao momento da execução.

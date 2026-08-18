# discourse-westan-pontos

Plugin independente para Discourse com carteira de pontos, multiplicador VIP, catálogo de benefícios e solicitações de troca.

O grupo VIP padrão é `vip` (mencionado no fórum como `@vip`). O plugin também aceita o ID numérico gravado pelo seletor de grupos do painel administrativo.

## VIP pagante e VIP resgatado

O grupo configurado em `westan_points_vip_group` entrega os benefícios VIP e também recebe os usuários que resgatam dias de VIP com pontos. O multiplicador é separado: somente membros do grupo configurado em `westan_points_eligible_vip_group` recebem pontos em dobro.

Para uma operação manual, crie o grupo `vip_elegivel` e adicione nele somente os membros pagantes. Um pagante deve permanecer também no grupo geral `vip`. Usuários que resgatarem VIP com pontos entram apenas no grupo geral e continuam acumulando pontos em 1x.

O ícone de carteira usa o `wallet-03` da [Hugeicons](https://hugeicons.com/icon/wallet-03), disponibilizado no conjunto gratuito sob licença MIT.

## Importação de publicações anteriores

Dentro do container do Discourse, execute:

```bash
START_AT="2026-08-01 00:00:00" bundle exec rake westan_points:backfill
```

A tarefa respeita as regras atuais do plugin e pode ser executada novamente sem duplicar pontos já registrados. Por padrão, `END_AT` corresponde ao momento da execução.

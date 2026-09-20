# discourse-westan-pontos

Plugin independente para Discourse com carteira de pontos, multiplicador VIP, catálogo de benefícios e solicitações de troca.

## Transferências e extrato (0.5.0)

A aba **Transferir** permite enviar uma quantidade inteira de pontos para um `@username`, com descrição opcional de até 200 caracteres. O usuário confirma o destinatário e o valor antes do envio. O saldo é debitado e creditado na mesma transação de banco, com bloqueio das duas carteiras em ordem consistente e identificação única da solicitação para evitar duplicação nas tentativas repetidas.

Transferências não recebem o multiplicador VIP, não aumentam o total de pontos conquistados e preservam a validade original de cada parcela enviada. Os pontos que vencem primeiro são utilizados primeiro. O extrato registra os dois lados da operação, além de publicações, ajustes administrativos, trocas, estornos e expirações; permite filtrar e carregar registros anteriores em páginas de 30 itens.

A página usa as variáveis de cores do Discourse (`--primary` e `--secondary`) para acompanhar o tema ativo. O cartão de saldo tem destaque verde e os atalhos dão acesso a transferências, extrato, benefícios e trocas.

### Validação

Teste isolado da distribuição de pontos por vencimento: `ruby test/bucket_allocator_test.rb`.

Com o plugin instalado em um ambiente de testes Discourse, execute `bundle exec rspec plugins/discourse-westan-pontos/spec`. Os testes de integração cobrem saldo, repetição da solicitação, validação, rollback e vencimentos. A prévia estática local usa dados demonstrativos e não executa transferências reais.

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

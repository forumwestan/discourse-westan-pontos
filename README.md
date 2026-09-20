# discourse-westan-pontos

Plugin independente para Discourse com carteira de pontos, multiplicador VIP, catálogo de benefícios e solicitações de troca.

## Transferências e extrato (0.5.0)

A aba **Transferir** permite enviar uma quantidade inteira de pontos para um `@username`, com descrição opcional de até 200 caracteres. O usuário confirma o destinatário e o valor antes do envio. O saldo é debitado e creditado na mesma transação de banco, com bloqueio das duas carteiras em ordem consistente e identificação única da solicitação para evitar duplicação nas tentativas repetidas.

Transferências não recebem o multiplicador VIP, não aumentam o total de pontos conquistados e preservam a validade original de cada parcela enviada. Os pontos que vencem primeiro são utilizados primeiro. O extrato registra os dois lados da operação, além de publicações, ajustes administrativos, trocas, estornos e expirações; permite filtrar e carregar registros anteriores em páginas de 30 itens.

A página usa as variáveis de cores do Discourse (`--primary` e `--secondary`) para acompanhar o tema ativo. O cartão compacto de saldo e os atalhos ativos usam lilás `#DEC5EE`. O aviso de expiração fica dentro do cartão.

## Ajustes de interface (0.6.0)

- Saldo identificado como **Saldo de pontos**, sem repetir a unidade ao lado do número.
- Busca de destinatários por nome ou iniciais usando a busca nativa de membros do Discourse, com avatar, username, navegação por setas e seleção por Enter. É necessário selecionar o destinatário antes de revisar.
- Confirmação de transferência dentro da seção, com destinatário, valor, descrição, **Confirmar transferência** e **Cancelar**. Sucesso e erros também aparecem na seção, sem alertas do navegador.
- Falhas de conexão preservam a mesma identificação de solicitação na tentativa seguinte. Se o servidor já concluiu a transferência, a tentativa apenas recupera o resultado. Falha ao atualizar o extrato não transforma uma transferência concluída em erro.
- Informações em um diálogo modal, com foco contido, fechamento por Escape, botão fechar ou clique no fundo.
- A engrenagem abre **`/config`**, página exclusiva da equipe. Benefícios, solicitações e ajustes de saldo continuam sendo salvos pelos endpoints administrativos existentes. `GET /westan/pontos/admin/config` também exige autorização no servidor. A página `/pontos` não carrega mais o catálogo administrativo completo.

O caminho `/config` é registrado por este plugin; não deve ser compartilhado com outra página personalizada.

### Validação

Teste isolado da distribuição de pontos por vencimento: `ruby test/bucket_allocator_test.rb`. Testes de interação do componente, com serviços simulados: `node test/hub_interactions_test.cjs`.

`scripts/preview.cjs` compila o template/estilo reais e gera uma demonstração interativa com dados simulados. Dependências de desenvolvimento: `sass`, `handlebars`, `content-tag` e `@glimmer/syntax`. Execute `NODE_PATH=/caminho/dev/node_modules node scripts/preview.cjs /caminho/preview`.

Com o plugin instalado em um ambiente de testes Discourse, execute `LOAD_PLUGINS=1 bundle exec rspec plugins/discourse-westan-pontos/spec`. Os testes de integração cobrem saldo, repetição da solicitação, validação, rollback, vencimentos e acesso à configuração. A prévia local não executa transferências reais nem salva dados no fórum.

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

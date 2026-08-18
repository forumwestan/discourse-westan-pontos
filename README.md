# discourse-westan-pontos

Plugin independente para Discourse com carteira de pontos, multiplicador VIP, catálogo de benefícios e solicitações de troca.

## Regras padrão

- Resposta comum: **1 ponto**
- Novo tópico: **2 pontos**
- Grupo VIP: **2x**
- Os pontos são agrupados em ciclos trimestrais: março–maio, junho–agosto, setembro–novembro e dezembro–fevereiro.
- Cada ciclo tem o mês seguinte completo para uso. Exemplo: pontos obtidos em junho, julho e agosto podem ser usados até 30 de setembro e expiram em 1º de outubro.
- Trocas consomem primeiro os pontos do ciclo que vence antes (FIFO).
- Posts excluídos têm seus pontos estornados; posts restaurados reativam a pontuação.

A expiração é executada diariamente por uma rotina agendada e também é verificada ao abrir `/pontos` ou solicitar uma troca. Apenas o saldo não utilizado do ciclo é removido.

## Fluxo de troca

1. A equipe cadastra benefícios na página `/pontos`.
2. O membro troca o saldo por um benefício disponível.
3. Benefícios manuais entram como pendentes; a equipe aprova e marca como entregue ou recusa, devolvendo os pontos e o estoque.
4. Benefícios VIP automáticos são ativados e marcados como entregues no momento da troca.

## Benefício VIP automático

Ao cadastrar um benefício, a equipe pode selecionar **Acesso temporário ao grupo VIP** e definir sua duração em dias.

- A troca desconta os pontos e adiciona o membro imediatamente ao grupo configurado em `westan_points_vip_group`.
- A solicitação é marcada automaticamente como entregue.
- Novas trocas feitas durante um acesso ativo acumulam tempo. Duas trocas de 7 dias resultam em 14 dias.
- Uma tarefa é agendada para a data exata do vencimento; uma rotina a cada 15 minutos funciona como verificação de segurança.
- Se o membro já pertencia ao grupo antes da primeira troca, o plugin preserva essa associação ao fim do período.

O ícone de carteira usa o `wallet-03` da [Hugeicons](https://hugeicons.com/icon/wallet-03), disponibilizado no conjunto gratuito sob licença MIT.

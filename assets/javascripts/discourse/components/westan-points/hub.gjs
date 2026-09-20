import Component from "@glimmer/component";
import { concat } from "@ember/helper";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import dIcon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class WestanPointsHub extends Component {
  @service currentUser;

  @tracked data = this.args.model;
  @tracked activeSection = "history";
  @tracked transferDraft = { username: "", amount: "", description: "" };
  @tracked transferRequestId = null;
  @tracked transferMessage = "";
  @tracked historyFilter = "all";
  @tracked historyBusy = false;
  historyGeneration = 0;
  @tracked isBusy = false;
  @tracked showInfo = false;
  @tracked showAdmin = false;
  @tracked editingRewardId = null;
  @tracked rewardDraft = this.emptyRewardDraft();
  @tracked adjustment = { username: "", amount: 0, description: "" };

  emptyRewardDraft() {
    return {
      title: "",
      description: "",
      cost: 100,
      stock: "",
      image_url: "",
      fulfillment_instructions: "",
      sort_order: 0,
      reward_type: "manual",
      duration_days: 7,
      enabled: true,
    };
  }

  get wallet() {
    return this.data.wallet || { balance: 0, lifetime_earned: 0, lifetime_spent: 0 };
  }

  get rules() {
    return this.data.rules || {};
  }

  get isMultiplierEligible() {
    return Boolean(this.data.is_multiplier_eligible);
  }

  get nextExpiration() {
    return this.wallet.next_expiration;
  }

  get nextExpirationLabel() {
    const value = this.nextExpiration?.expires_at;
    if (!value) {
      return "";
    }

    return new Intl.DateTimeFormat("pt-BR", {
      day: "2-digit",
      month: "long",
    }).format(new Date(value));
  }

  get userDisplayName() {
    return this.currentUser?.name || this.currentUser?.username || "Membro";
  }

  get canManage() {
    return Boolean(
      (this.currentUser?.admin || this.currentUser?.moderator) && this.data.admin
    );
  }

  get isVipRewardDraft() {
    return this.rewardDraft.reward_type === "vip_group_access";
  }

  get isManualRewardDraft() {
    return !this.isVipRewardDraft;
  }

  get rewardRows() {
    return (this.data.rewards || []).map((reward) => ({
      ...reward,
      disabled: this.isBusy || !reward.can_redeem,
      stock_label: reward.automatic_fulfillment
        ? `VIP automático · ${reward.duration_days} dias`
        : reward.stock === null
          ? "Ilimitado"
          : `${reward.stock} disponível(is)`,
    }));
  }

  get transactions() {
    return (this.data.transactions || []).map((item) => ({
      ...item,
      amount_label: `${item.amount > 0 ? "+" : ""}${item.amount}`,
      amount_class: item.amount >= 0 ? "is-positive" : "is-negative",
      date_label: this.formatDate(item.created_at),
      icon: item.amount > 0 ? "arrow-down" : "arrow-up",
      origin_label: item.origin === "member" ? `@${item.counterparty_username}` : "Sistema Westan",
      status_label: item.reversed ? "Anulado" : "Concluído",
    }));
  }

  get userAvatarUrl() {
    return this.currentUser?.avatar_template?.replace("{size}", "96");
  }

  get formattedBalance() {
    return new Intl.NumberFormat("pt-BR").format(this.wallet.balance);
  }

  get balanceClass() {
    return this.formattedBalance.length > 9 ? "westan-points-balance is-large-number" : "westan-points-balance";
  }

  get isTransferSection() {
    return this.activeSection === "transfer";
  }

  get transferTabClass() {
    return this.isTransferSection ? "is-active" : "";
  }

  get historyFilters() {
    return [
      { id: "all", label: "Tudo" },
      { id: "incoming", label: "Entradas" },
      { id: "outgoing", label: "Saídas" },
      { id: "transfers", label: "Transferências" },
    ].map((filter) => ({ ...filter, selected: filter.id === this.historyFilter }));
  }

  @action
  updateTransfer(event) {
    this.transferDraft = { ...this.transferDraft, [event.target.dataset.field]: event.target.value };
    this.transferRequestId = null;
    this.transferMessage = "";
  }

  @action
  async submitTransfer(event) {
    event.preventDefault();
    if (this.isBusy) { return; }
    const amount = Number(this.transferDraft.amount);
    const username = this.transferDraft.username.trim().replace(/^@/, "");
    if (!Number.isSafeInteger(amount) || amount <= 0 || amount > this.wallet.balance || !username) {
      this.transferMessage = "Informe o @ do membro e um valor inteiro dentro do seu saldo.";
      return;
    }
    if (!window.confirm(`Transferir ${amount} pontos para @${username}?`)) { return; }
    this.transferRequestId ||= crypto.randomUUID();
    this.isBusy = true;
    this.transferMessage = "";
    try {
      const result = await ajax("/westan/pontos/transfer", {
        type: "POST",
        data: { ...this.transferDraft, username, request_id: this.transferRequestId },
      });
      this.data = { ...this.data, wallet: result.wallet };
      this.transferDraft = { username: "", amount: "", description: "" };
      this.transferRequestId = null;
      this.transferMessage = `${amount} pontos enviados para @${username}.`;
      await this.refresh();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isBusy = false;
    }
  }

  @action
  async changeHistoryFilter(event) {
    this.historyFilter = event.currentTarget.dataset.filter;
    await this.fetchHistory(false);
  }

  @action
  async loadMoreHistory() {
    if (this.historyBusy || !this.data.next_cursor) { return; }
    await this.fetchHistory(true);
  }

  async fetchHistory(append) {
    const generation = ++this.historyGeneration;
    this.historyBusy = true;
    try {
      const result = await ajax("/westan/pontos/transactions", {
        data: { filter: this.historyFilter, before: append ? this.data.next_cursor : undefined },
      });
      if (generation !== this.historyGeneration) { return; }
      this.data = { ...this.data, ...result,
        transactions: append ? [...this.data.transactions, ...result.transactions] : result.transactions };
    } catch (error) {
      popupAjaxError(error);
    } finally {
      if (generation === this.historyGeneration) { this.historyBusy = false; }
    }
  }

  get redemptions() {
    return (this.data.redemptions || []).map((item) => {
      const vipGrant = item.vip_grant;
      return {
        ...item,
        status_label: vipGrant
          ? vipGrant.active
            ? "VIP ativo"
            : "Finalizado"
          : this.statusLabel(item.status),
        status_class: vipGrant?.active ? "is-approved" : `is-${item.status}`,
        date_label: this.formatDate(item.created_at),
        detail_label: vipGrant
          ? `${item.cost} pontos · acesso até ${this.formatDateOnly(vipGrant.expires_at)}`
          : `${this.formatDate(item.created_at)} · ${item.cost} pontos`,
      };
    });
  }

  get adminRewards() {
    return this.data.admin?.rewards || [];
  }

  get rewardSubmitLabel() {
    return this.editingRewardId ? "Salvar benefício" : "Criar benefício";
  }

  get adminRedemptions() {
    return (this.data.admin?.redemptions || []).map((item) => ({
      ...item,
      status_label: this.statusLabel(item.status),
      status_class: `is-${item.status}`,
      date_label: this.formatDate(item.created_at),
      is_pending: item.status === "pending",
      is_approved: item.status === "approved",
    }));
  }

  get rewardsTabClass() {
    return this.activeSection === "rewards" ? "is-active" : "";
  }

  get historyTabClass() {
    return this.activeSection === "history" ? "is-active" : "";
  }

  get redemptionsTabClass() {
    return this.activeSection === "redemptions" ? "is-active" : "";
  }

  get isRewardsSection() {
    return this.activeSection === "rewards";
  }

  get isHistorySection() {
    return this.activeSection === "history";
  }

  get isRedemptionsSection() {
    return this.activeSection === "redemptions";
  }

  formatDate(value) {
    if (!value) {
      return "";
    }
    return new Intl.DateTimeFormat("pt-BR", {
      day: "2-digit",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(value));
  }

  formatDateOnly(value) {
    if (!value) {
      return "";
    }
    return new Intl.DateTimeFormat("pt-BR", {
      day: "2-digit",
      month: "long",
      year: "numeric",
    }).format(new Date(value));
  }

  statusLabel(status) {
    return {
      pending: "Pendente",
      approved: "Aprovada",
      fulfilled: "Entregue",
      rejected: "Recusada",
    }[status] || status;
  }

  async refresh() {
    this.historyGeneration++;
    this.historyFilter = "all";
    this.historyBusy = false;
    this.data = await ajax("/westan/pontos");
  }

  @action
  selectSection(event) {
    this.activeSection = event.currentTarget.dataset.section;
  }

  @action
  toggleInfo() {
    this.showInfo = !this.showInfo;
  }

  @action
  toggleAdmin() {
    this.showAdmin = !this.showAdmin;
  }

  @action
  async redeem(event) {
    const rewardId = Number(event.currentTarget.dataset.rewardId);
    const reward = this.rewardRows.find((item) => item.id === rewardId);
    if (!reward || reward.disabled) {
      return;
    }
    const automaticMessage = reward.automatic_fulfillment
      ? ` O acesso VIP por ${reward.duration_days} dias será ativado imediatamente.`
      : "";
    if (
      !window.confirm(
        `Trocar ${reward.cost} pontos por “${reward.title}”?${automaticMessage}`
      )
    ) {
      return;
    }

    this.isBusy = true;
    try {
      await ajax("/westan/pontos/redeem", {
        type: "POST",
        data: { reward_id: rewardId },
      });
      await this.refresh();
      this.activeSection = "redemptions";
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isBusy = false;
    }
  }

  @action
  updateRewardDraft(event) {
    const field = event.currentTarget.dataset.field;
    const value = event.target.type === "checkbox" ? event.target.checked : event.target.value;
    this.rewardDraft = { ...this.rewardDraft, [field]: value };
  }

  @action
  async createReward(event) {
    event.preventDefault();
    this.isBusy = true;
    try {
      const url = this.editingRewardId
        ? `/westan/pontos/admin/rewards/${this.editingRewardId}`
        : "/westan/pontos/admin/rewards";
      await ajax(url, {
        type: this.editingRewardId ? "PATCH" : "POST",
        data: this.rewardDraft,
      });
      this.editingRewardId = null;
      this.rewardDraft = this.emptyRewardDraft();
      await this.refresh();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isBusy = false;
    }
  }

  @action
  editReward(event) {
    const rewardId = Number(event.currentTarget.dataset.rewardId);
    const reward = this.adminRewards.find((item) => item.id === rewardId);
    if (!reward) {
      return;
    }
    this.editingRewardId = rewardId;
    this.rewardDraft = {
      title: reward.title,
      description: reward.description,
      cost: reward.cost,
      stock: reward.stock ?? "",
      image_url: reward.image_url || "",
      fulfillment_instructions: reward.fulfillment_instructions || "",
      sort_order: reward.sort_order || 0,
      reward_type: reward.reward_type || "manual",
      duration_days: reward.duration_days || 7,
      enabled: reward.enabled,
    };
  }

  @action
  cancelRewardEdit() {
    this.editingRewardId = null;
    this.rewardDraft = this.emptyRewardDraft();
  }

  @action
  async toggleReward(event) {
    const rewardId = Number(event.currentTarget.dataset.rewardId);
    const reward = this.adminRewards.find((item) => item.id === rewardId);
    if (!reward) {
      return;
    }
    this.isBusy = true;
    try {
      await ajax(`/westan/pontos/admin/rewards/${rewardId}`, {
        type: "PATCH",
        data: { ...reward, enabled: !reward.enabled },
      });
      await this.refresh();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isBusy = false;
    }
  }

  @action
  async setRedemptionStatus(event) {
    const redemptionId = Number(event.currentTarget.dataset.redemptionId);
    const status = event.currentTarget.dataset.status;
    this.isBusy = true;
    try {
      await ajax(`/westan/pontos/admin/redemptions/${redemptionId}`, {
        type: "PATCH",
        data: { status },
      });
      await this.refresh();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isBusy = false;
    }
  }

  @action
  updateAdjustment(event) {
    const field = event.currentTarget.dataset.field;
    this.adjustment = { ...this.adjustment, [field]: event.target.value };
  }

  @action
  async submitAdjustment(event) {
    event.preventDefault();
    this.isBusy = true;
    try {
      await ajax("/westan/pontos/admin/adjust", {
        type: "POST",
        data: this.adjustment,
      });
      this.adjustment = { username: "", amount: 0, description: "" };
      await this.refresh();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isBusy = false;
    }
  }

  <template>
    <main class="westan-points-shell">
      <header class="westan-points-hero">
        <div class="westan-points-hero__topline">
          <div class="westan-points-identity">
            {{#if this.userAvatarUrl}}<img class="westan-points-avatar" src={{this.userAvatarUrl}} alt="" />{{/if}}
            <div>
            <p>Westan Pontos</p>
            <h1>{{this.userDisplayName}}</h1>
            </div>
          </div>
          <div class="westan-points-hero__actions">
            {{#if this.canManage}}
              <button type="button" aria-label="Gerenciar benefícios" {{on "click" this.toggleAdmin}}>
                {{dIcon "gear"}}
              </button>
            {{/if}}
            <button type="button" aria-label="Entenda os pontos" {{on "click" this.toggleInfo}}>
              {{dIcon "circle-info"}}
            </button>
          </div>
        </div>

        <div class={{this.balanceClass}}>
          <span class="westan-points-balance__icon">
            <svg class="westan-points-wallet-icon" viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d="M3 8.5H15C17.8284 8.5 19.2426 8.5 20.1213 9.37868C21 10.2574 21 11.6716 21 14.5V15.5C21 18.3284 21 19.7426 20.1213 20.6213C19.2426 21.5 17.8284 21.5 15 21.5H9C6.17157 21.5 4.75736 21.5 3.87868 20.6213C3 19.7426 3 18.3284 3 15.5V8.5Z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
              <path d="M15 8.49833V4.1103C15 3.22096 14.279 2.5 13.3897 2.5C13.1336 2.5 12.8812 2.56108 12.6534 2.67818L3.7623 7.24927C3.29424 7.48991 3 7.97203 3 8.49833" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
              <path d="M17.5 15.5C17.7761 15.5 18 15.2761 18 15C18 14.7239 17.7761 14.5 17.5 14.5M17.5 15.5C17.2239 15.5 17 15.2761 17 15C17 14.7239 17.2239 14.5 17.5 14.5M17.5 15.5V14.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          </span>
          <div>
            <small>Saldo disponível</small>
            <strong>{{this.formattedBalance}}</strong>
            <span>pontos</span>
          </div>
          {{#if this.isMultiplierEligible}}
            <em>VIP {{this.rules.vip_multiplier}}x</em>
          {{/if}}
        </div>

        {{#if this.nextExpiration}}
          <div class="westan-points-expiration" role="status">
            {{dIcon "clock-rotate-left"}}
            <span><b>{{this.nextExpiration.amount}} pontos</b> expiram em {{this.nextExpirationLabel}}</span>
          </div>
        {{/if}}
      </header>

      {{#if this.showInfo}}
        <section class="westan-points-info">
          <button type="button" aria-label="Fechar" {{on "click" this.toggleInfo}}>{{dIcon "xmark"}}</button>
          <h2>Como funciona</h2>
          <div class="westan-points-rules" aria-label="Regras de pontuação">
            <span><b>+{{this.rules.points_per_post}}</b> por post</span>
            <span><b>+{{this.rules.points_per_topic}}</b> por tópico</span>
            <span><b>{{this.rules.vip_multiplier}}x</b> para VIP elegível</span>
            <span><b>Validade:</b> ciclo trimestral</span>
          </div>
          <p>Participe da comunidade para acumular pontos. Ao criar um tópico você recebe {{this.rules.points_per_topic}} pontos; cada resposta rende {{this.rules.points_per_post}} ponto. Somente membros VIP pagantes, incluídos no grupo elegível, recebem o multiplicador.</p>
          <p>O VIP resgatado com pontos mantém os benefícios do grupo VIP durante o período da oferta, mas a pontuação continua em 1x.</p>
          <p>Os pontos são organizados em ciclos trimestrais. Por exemplo, tudo o que for conquistado em junho, julho e agosto pode ser usado até 30 de setembro; o saldo restante desse ciclo expira em 1º de outubro.</p>
          <p>Nas trocas, usamos primeiro os pontos do ciclo que vence antes. Assim, somente o saldo não utilizado de cada trimestre expira.</p>
          <p>Benefícios automáticos, como dias de VIP, são ativados na hora. Os demais ficam pendentes até a confirmação da equipe.</p>
          <p>Você também pode transferir pontos para outro membro. As transferências mantêm a validade original dos pontos e não recebem multiplicador VIP.</p>
        </section>
      {{/if}}

      <nav class="westan-points-tabs" aria-label="Navegação de pontos">
        <button type="button" class={{this.transferTabClass}} aria-pressed={{this.isTransferSection}} data-section="transfer" {{on "click" this.selectSection}}><span>{{dIcon "paper-plane"}}</span>Transferir</button>
        <button type="button" class={{this.historyTabClass}} aria-pressed={{this.isHistorySection}} data-section="history" {{on "click" this.selectSection}}><span>{{dIcon "clock-rotate-left"}}</span>Extrato</button>
        <button type="button" class={{this.rewardsTabClass}} aria-pressed={{this.isRewardsSection}} data-section="rewards" {{on "click" this.selectSection}}><span>{{dIcon "gift"}}</span>Benefícios</button>
        <button type="button" class={{this.redemptionsTabClass}} aria-pressed={{this.isRedemptionsSection}} data-section="redemptions" {{on "click" this.selectSection}}><span>{{dIcon "coins"}}</span>Minhas trocas</button>
      </nav>

      {{#if this.isTransferSection}}
        <section class="westan-points-section westan-points-transfer">
          <div class="westan-points-section__heading"><div><small>DE MEMBRO PARA MEMBRO</small><h2>Envie pontos</h2></div>{{dIcon "paper-plane"}}</div>
          <p>Compartilhe seus pontos com alguém da comunidade.</p>
          <form {{on "submit" this.submitTransfer}}>
            <fieldset disabled={{this.isBusy}}>
              <label for="wp-recipient">Para quem?</label>
              <input id="wp-recipient" required autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="@nomedousuario" data-field="username" value={{this.transferDraft.username}} {{on "input" this.updateTransfer}} />
              <label for="wp-amount">Quantidade de pontos</label>
              <input id="wp-amount" required type="number" min="1" step="1" max={{this.wallet.balance}} inputmode="numeric" placeholder="0" data-field="amount" value={{this.transferDraft.amount}} {{on "input" this.updateTransfer}} />
              <small>Disponível: {{this.formattedBalance}} pontos</small>
              <label for="wp-description">Descrição <small>(opcional)</small></label>
              <textarea id="wp-description" maxlength="200" placeholder="Deixe uma mensagem…" data-field="description" value={{this.transferDraft.description}} {{on "input" this.updateTransfer}}></textarea>
              <p class="westan-points-transfer__notice">Os pontos enviados mantêm a data de expiração original.</p>
              <button class="westan-points-submit" type="submit" disabled={{this.isBusy}}>{{dIcon "paper-plane"}} {{if this.isBusy "Enviando…" "Transferir pontos"}}</button>
            </fieldset>
          </form>
          {{#if this.transferMessage}}<p class="westan-points-feedback" role="status">{{this.transferMessage}}</p>{{/if}}
        </section>
      {{/if}}

      {{#if this.isRewardsSection}}
        <section class="westan-points-section">
          <div class="westan-points-section__heading">
            <div><small>CATÁLOGO</small><h2>Troque seus pontos</h2></div>
            <span>{{this.wallet.lifetime_earned}} acumulados</span>
          </div>
          <div class="westan-reward-grid">
            {{#each this.rewardRows as |reward|}}
              <article class="westan-reward-card">
                <div class="westan-reward-card__visual">
                  {{#if reward.image_url}}
                    <img src={{reward.image_url}} alt="" />
                  {{else}}
                    {{dIcon "gift"}}
                  {{/if}}
                </div>
                <div class="westan-reward-card__content">
                  <small>{{reward.stock_label}}</small>
                  <h3>{{reward.title}}</h3>
                  <p>{{reward.description}}</p>
                  <div class="westan-reward-card__footer">
                    <strong>{{reward.cost}} <span>pontos</span></strong>
                    <button type="button" data-reward-id={{reward.id}} disabled={{reward.disabled}} {{on "click" this.redeem}}>Trocar</button>
                  </div>
                </div>
              </article>
            {{else}}
              <div class="westan-points-empty">Nenhum benefício disponível ainda.</div>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if this.isHistorySection}}
        <section class="westan-points-section">
          <div class="westan-points-section__heading"><div><small>SUA CONTA</small><h2>Movimentações</h2></div>{{dIcon "clock-rotate-left"}}</div>
          <div class="westan-points-filters" aria-label="Filtrar movimentações">
            {{#each this.historyFilters as |filter|}}<button type="button" aria-pressed={{filter.selected}} data-filter={{filter.id}} {{on "click" this.changeHistoryFilter}}>{{filter.label}}</button>{{/each}}
          </div>
          <div class="westan-points-list" aria-busy={{this.historyBusy}}>
            {{#each this.transactions as |item|}}
              <article class={{concat "westan-points-list__row " item.amount_class}}>
                <span>{{dIcon item.icon}}</span>
                <div><strong>{{item.description}}</strong><small>{{item.origin_label}} · {{item.date_label}}</small>{{#if item.note}}<p>{{item.note}}</p>{{/if}}{{#if item.reversed}}<small>Anulado</small>{{/if}}</div>
                <b>{{item.amount_label}}<small>pontos</small></b>
              </article>
            {{else}}
              <div class="westan-points-empty">Seu histórico aparecerá aqui.</div>
            {{/each}}
          </div>
          {{#if this.data.next_cursor}}<button class="westan-points-load-more" type="button" disabled={{this.historyBusy}} {{on "click" this.loadMoreHistory}}>{{if this.historyBusy "Carregando…" "Ver mais movimentações"}}</button>{{/if}}
        </section>
      {{/if}}

      {{#if this.isRedemptionsSection}}
        <section class="westan-points-section">
          <div class="westan-points-section__heading"><div><small>SOLICITAÇÕES</small><h2>Minhas trocas</h2></div></div>
          <div class="westan-points-list">
            {{#each this.redemptions as |item|}}
              <article class="westan-redemption-row">
                <div><strong>{{item.reward.title}}</strong><small>{{item.detail_label}}</small></div>
                <span class={{item.status_class}}>{{item.status_label}}</span>
              </article>
            {{else}}
              <div class="westan-points-empty">Você ainda não realizou trocas.</div>
            {{/each}}
          </div>
        </section>
      {{/if}}

      {{#if this.showAdmin}}
        <section class="westan-points-admin">
          <div class="westan-points-section__heading"><div><small>ADMINISTRAÇÃO</small><h2>Gerenciar benefícios</h2></div></div>

          <form class="westan-points-admin__form" {{on "submit" this.createReward}}>
            <label>Título<input required value={{this.rewardDraft.title}} data-field="title" {{on "input" this.updateRewardDraft}} /></label>
            <label>Custo em pontos<input required type="number" min="1" value={{this.rewardDraft.cost}} data-field="cost" {{on "input" this.updateRewardDraft}} /></label>
            <label>Tipo de benefício
              <select data-field="reward_type" {{on "change" this.updateRewardDraft}}>
                <option value="manual" selected={{this.isManualRewardDraft}}>Entrega manual</option>
                <option value="vip_group_access" selected={{this.isVipRewardDraft}}>Acesso temporário ao grupo VIP</option>
              </select>
            </label>
            {{#if this.isVipRewardDraft}}
              <label>Duração do VIP em dias<input required type="number" min="1" max="3650" value={{this.rewardDraft.duration_days}} data-field="duration_days" {{on "input" this.updateRewardDraft}} /></label>
            {{/if}}
            <label>Estoque <small>(vazio = ilimitado)</small><input type="number" min="0" value={{this.rewardDraft.stock}} data-field="stock" {{on "input" this.updateRewardDraft}} /></label>
            <label>URL da imagem<input value={{this.rewardDraft.image_url}} data-field="image_url" {{on "input" this.updateRewardDraft}} /></label>
            <label class="is-wide">Descrição<textarea value={{this.rewardDraft.description}} data-field="description" {{on "input" this.updateRewardDraft}}></textarea></label>
            <label class="is-wide">Instruções internas<textarea value={{this.rewardDraft.fulfillment_instructions}} data-field="fulfillment_instructions" {{on "input" this.updateRewardDraft}}></textarea></label>
            <div class="westan-points-admin__form-actions">
              <button type="submit" disabled={{this.isBusy}}>{{dIcon "plus"}} {{this.rewardSubmitLabel}}</button>
              {{#if this.editingRewardId}}
                <button type="button" {{on "click" this.cancelRewardEdit}}>Cancelar</button>
              {{/if}}
            </div>
          </form>

          <div class="westan-points-admin__catalog">
            {{#each this.adminRewards as |reward|}}
              <article>
                <div><strong>{{reward.title}}</strong><small>{{reward.cost}} pontos{{#if reward.automatic_fulfillment}} · VIP por {{reward.duration_days}} dias{{/if}}</small></div>
                <button type="button" data-reward-id={{reward.id}} {{on "click" this.editReward}}>Editar</button>
                <button type="button" data-reward-id={{reward.id}} {{on "click" this.toggleReward}}>{{if reward.enabled "Desativar" "Ativar"}}</button>
              </article>
            {{/each}}
          </div>

          <div class="westan-points-section__heading"><div><small>FILA</small><h2>Solicitações de troca</h2></div></div>
          <div class="westan-points-admin__redemptions">
            {{#each this.adminRedemptions as |item|}}
              <article>
                <div><strong>{{item.user.display_name}} · {{item.reward.title}}</strong><small>@{{item.user.username}} · {{item.cost}} pontos · {{item.date_label}}</small></div>
                <span class={{item.status_class}}>{{item.status_label}}</span>
                {{#if item.is_pending}}
                  <button type="button" data-redemption-id={{item.id}} data-status="approved" {{on "click" this.setRedemptionStatus}}>Aprovar</button>
                  <button type="button" data-redemption-id={{item.id}} data-status="rejected" {{on "click" this.setRedemptionStatus}}>Recusar</button>
                {{/if}}
                {{#if item.is_approved}}
                  <button type="button" data-redemption-id={{item.id}} data-status="fulfilled" {{on "click" this.setRedemptionStatus}}>Marcar como entregue</button>
                {{/if}}
              </article>
            {{/each}}
          </div>

          <form class="westan-points-admin__adjustment" {{on "submit" this.submitAdjustment}}>
            <h3>Ajuste manual</h3>
            <input required placeholder="Username" value={{this.adjustment.username}} data-field="username" {{on "input" this.updateAdjustment}} />
            <input required type="number" placeholder="Pontos (+ ou -)" value={{this.adjustment.amount}} data-field="amount" {{on "input" this.updateAdjustment}} />
            <input placeholder="Motivo" value={{this.adjustment.description}} data-field="description" {{on "input" this.updateAdjustment}} />
            <button type="submit" disabled={{this.isBusy}}>Aplicar ajuste</button>
          </form>
        </section>
      {{/if}}
    </main>
  </template>
}

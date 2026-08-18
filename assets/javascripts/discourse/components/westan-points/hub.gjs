import Component from "@glimmer/component";
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
  @tracked activeSection = "rewards";
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

  get isVip() {
    return Boolean(this.data.is_vip);
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
    }));
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
          <div>
            <p>Westan Pontos</p>
            <h1>{{this.userDisplayName}}</h1>
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

        <div class="westan-points-balance">
          <span class="westan-points-balance__icon">
            <svg class="westan-points-wallet-icon" viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d="M3 8.5H15C17.8284 8.5 19.2426 8.5 20.1213 9.37868C21 10.2574 21 11.6716 21 14.5V15.5C21 18.3284 21 19.7426 20.1213 20.6213C19.2426 21.5 17.8284 21.5 15 21.5H9C6.17157 21.5 4.75736 21.5 3.87868 20.6213C3 19.7426 3 18.3284 3 15.5V8.5Z" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
              <path d="M15 8.49833V4.1103C15 3.22096 14.279 2.5 13.3897 2.5C13.1336 2.5 12.8812 2.56108 12.6534 2.67818L3.7623 7.24927C3.29424 7.48991 3 7.97203 3 8.49833" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
              <path d="M17.5 15.5C17.7761 15.5 18 15.2761 18 15C18 14.7239 17.7761 14.5 17.5 14.5M17.5 15.5C17.2239 15.5 17 15.2761 17 15C17 14.7239 17.2239 14.5 17.5 14.5M17.5 15.5V14.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          </span>
          <div>
            <small>Saldo disponível</small>
            <strong>{{this.wallet.balance}}</strong>
            <span>pontos</span>
          </div>
          {{#if this.isVip}}
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
            <span><b>{{this.rules.vip_multiplier}}x</b> para VIP</span>
            <span><b>Validade:</b> ciclo trimestral</span>
          </div>
          <p>Participe da comunidade para acumular pontos. Ao criar um tópico você recebe {{this.rules.points_per_topic}} pontos; cada resposta rende {{this.rules.points_per_post}} ponto. Membros VIP recebem tudo em dobro.</p>
          <p>Os pontos são organizados em ciclos trimestrais. Por exemplo, tudo o que for conquistado em junho, julho e agosto pode ser usado até 30 de setembro; o saldo restante desse ciclo expira em 1º de outubro.</p>
          <p>Nas trocas, usamos primeiro os pontos do ciclo que vence antes. Assim, somente o saldo não utilizado de cada trimestre expira.</p>
          <p>Benefícios automáticos, como dias de VIP, são ativados na hora. Os demais ficam pendentes até a confirmação da equipe.</p>
        </section>
      {{/if}}

      <nav class="westan-points-tabs" aria-label="Navegação de pontos">
        <button type="button" class={{this.rewardsTabClass}} data-section="rewards" {{on "click" this.selectSection}}>Benefícios</button>
        <button type="button" class={{this.historyTabClass}} data-section="history" {{on "click" this.selectSection}}>Histórico</button>
        <button type="button" class={{this.redemptionsTabClass}} data-section="redemptions" {{on "click" this.selectSection}}>Minhas trocas</button>
      </nav>

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
          <div class="westan-points-section__heading"><div><small>EXTRATO</small><h2>Histórico de pontos</h2></div></div>
          <div class="westan-points-list">
            {{#each this.transactions as |item|}}
              <article class={{concat "westan-points-list__row " item.amount_class}}>
                <span>{{dIcon "clock-rotate-left"}}</span>
                <div><strong>{{item.description}}</strong><small>{{item.date_label}}</small></div>
                <b>{{item.amount_label}}</b>
              </article>
            {{else}}
              <div class="westan-points-empty">Seu histórico aparecerá aqui.</div>
            {{/each}}
          </div>
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

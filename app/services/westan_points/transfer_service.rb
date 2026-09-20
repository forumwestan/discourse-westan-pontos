# frozen_string_literal: true

module WestanPoints
  class TransferService
    class InvalidTransfer < StandardError; end

    def self.transfer!(sender:, username:, amount:, description:, request_id:)
      value_string = amount.to_s
      unless value_string.match?(/\A[1-9]\d{0,9}\z/) && value_string.to_i <= 2_147_483_647
        raise InvalidTransfer, "Informe uma quantidade inteira e positiva de pontos."
      end
      unless request_id.to_s.match?(/\A[0-9a-f-]{36}\z/i)
        raise InvalidTransfer, "Identificação da transferência inválida. Atualize a página."
      end
      note = description.to_s.strip
      raise InvalidTransfer, "A descrição deve ter até 200 caracteres." if note.length > 200
      recipient = User.find_by(username_lower: username.to_s.strip.delete_prefix("@").downcase)
      unless recipient && recipient.id.positive? && recipient.active? && !recipient.staged? &&
          !(recipient.suspended_till && recipient.suspended_till > Time.zone.now)
        raise InvalidTransfer, "Membro não encontrado ou indisponível para receber pontos."
      end
      raise InvalidTransfer, "Escolha outro membro para receber os pontos." if sender.id == recipient.id
      amount = value_string.to_i
      event_key = "transfer:#{sender.id}:#{request_id.downcase}"

      # Wallet creation precedes the transaction to handle concurrent first use.
      [sender, recipient].sort_by(&:id).each { |user| Wallet.for_user!(user) }
      Wallet.transaction do
        wallets = Wallet.where(user_id: [sender.id, recipient.id]).order(:user_id).lock.to_a
        from = wallets.find { |wallet| wallet.user_id == sender.id }
        to = wallets.find { |wallet| wallet.user_id == recipient.id }
        previous = Transaction.find_by(event_key: event_key)
        if previous
          unless previous.amount == -amount && previous.metadata["counterparty_id"] == recipient.id && previous.metadata["note"] == note
            raise InvalidTransfer, "Esta solicitação já foi utilizada em outra transferência."
          end
          return previous
        end

        now = Time.zone.now
        Ledger.expire_due_points!(user: sender, now: now)
        Ledger.expire_due_points!(user: recipient, now: now)
        from.reload
        to.reload
        raise InvalidTransfer, "Saldo insuficiente para realizar esta transferência." if from.balance < amount
        if to.balance + amount > 2_147_483_647
          raise InvalidTransfer, "O saldo do destinatário atingiu o limite permitido."
        end

        remaining = amount
        parts = Ledger.available_buckets(user_id: sender.id).filter_map do |bucket|
          used = [bucket[:amount], remaining].min
          remaining -= used
          next if used.zero?
          { "amount" => used, "expires_at" => bucket[:expires_at]&.iso8601 }
        end
        raise InvalidTransfer, "Não foi possível validar o saldo. Contate a equipe." unless remaining.zero?

        from.update!(balance: from.balance - amount)
        to.update!(balance: to.balance + amount)
        outbound = Transaction.create!(
          wallet: from, user: sender, kind: "transfer_out", amount: -amount,
          balance_after: from.balance, event_key: event_key,
          description: "Enviado para @#{recipient.username}",
          metadata: { counterparty_id: recipient.id, counterparty_username: recipient.username, note: note }
        )
        Transaction.create!(
          wallet: to, user: recipient, kind: "transfer_in", amount: amount,
          balance_after: to.balance, event_key: "#{event_key}:received",
          description: "Recebido de @#{sender.username}",
          expires_at: parts.filter_map { |part| Time.iso8601(part["expires_at"]) if part["expires_at"] }.min,
          metadata: { counterparty_id: sender.id, counterparty_username: sender.username,
                      note: note, expiration_buckets: parts, transfer_id: outbound.id }
        )
        outbound
      end
    end
  end
end

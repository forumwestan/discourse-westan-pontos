# frozen_string_literal: true

require "rails_helper"

RSpec.describe WestanPoints::TransferService do
  fab!(:sender) { Fabricate(:user) }
  fab!(:recipient) { Fabricate(:user) }
  let(:request_id) { SecureRandom.uuid }

  before do
    SiteSetting.westan_points_enabled = true
    WestanPoints::Ledger.adjust!(user: sender, amount: 100, description: "Crédito", actor: sender)
  end

  def transfer(amount: "40", username: "@#{recipient.username}", key: request_id)
    described_class.transfer!(sender: sender, username: username, amount: amount,
                             description: "Obrigado!", request_id: key)
  end

  it "debits and credits once, preserving totals without treating transfers as earnings" do
    transfer
    transfer
    expect(WestanPoints::Wallet.find_by(user: sender).balance).to eq(60)
    expect(WestanPoints::Wallet.find_by(user: recipient).balance).to eq(40)
    expect(WestanPoints::Wallet.find_by(user: recipient).lifetime_earned).to eq(0)
    expect(WestanPoints::Transaction.where(kind: %w[transfer_in transfer_out]).count).to eq(2)
  end

  it "rejects self transfers, overdrafts and fractional or nonpositive amounts" do
    ["0", "-1", "1.5", "101", "2e1"].each do |amount|
      expect { transfer(amount: amount) }.to raise_error(described_class::InvalidTransfer)
    end
    expect { transfer(username: sender.username) }.to raise_error(described_class::InvalidTransfer)
    expect(WestanPoints::Wallet.find_by(user: sender).balance).to eq(100)
  end

  it "rejects reusing the request id with a different amount" do
    transfer
    expect { transfer(amount: "20") }.to raise_error(described_class::InvalidTransfer)
  end

  it "rolls back both wallets if the receiving entry cannot be created" do
    allow(WestanPoints::Transaction).to receive(:create!).and_wrap_original do |method, **args|
      raise "Simulated failure" if args[:kind] == "transfer_in"
      method.call(**args)
    end
    expect { transfer }.to raise_error("Simulated failure")
    expect(WestanPoints::Wallet.find_by(user: sender).balance).to eq(100)
    expect(WestanPoints::Wallet.find_by(user: recipient).balance).to eq(0)
    expect(WestanPoints::Transaction.where(kind: "transfer_out")).to be_empty
  end

  it "preserves the original expiry and applies no VIP multiplier" do
    expiry = 2.days.from_now.change(usec: 0)
    WestanPoints::Transaction.find_by(user: sender).update!(expires_at: expiry)
    transfer
    received = WestanPoints::Transaction.find_by(user: recipient, kind: "transfer_in")
    expect(received.amount).to eq(40)
    expect(received.expires_at).to eq(expiry)
    expect(received.metadata["expiration_buckets"]).to eq([{ "amount" => 40, "expires_at" => expiry.iso8601 }])
  end

  it "does not transfer expired points" do
    WestanPoints::Transaction.find_by(user: sender).update!(expires_at: 1.day.ago)
    expect { transfer }.to raise_error(described_class::InvalidTransfer, /Saldo insuficiente/)
    expect(WestanPoints::Transaction.where(kind: "transfer_out")).to be_empty
  end

  context "monthly limits" do
    before do
      WestanPoints::Ledger.adjust!(user: sender, amount: 1000, description: "Crédito extra", actor: sender)
    end

    it "accumulates sends across recipients and permits exactly 200 for ordinary and redeemed VIP members" do
      vip = Fabricate(:group, name: "vip")
      vip.add(sender)
      transfer(amount: "150")
      second = Fabricate(:user)
      transfer(amount: "50", username: second.username, key: SecureRandom.uuid)
      before_balance = WestanPoints::Wallet.find_by(user: sender).balance
      expect { transfer(amount: "1", key: SecureRandom.uuid) }.to raise_error(described_class::InvalidTransfer, /Limite mensal de 200/)
      expect(WestanPoints::Wallet.find_by(user: sender).balance).to eq(before_balance)
      expect(described_class.monthly_allowance(user: sender)).to include(limit: 200, sent: 200, remaining: 0)
      expect(transfer(amount: "150").amount).to eq(-150)
      expect(described_class.monthly_allowance(user: sender)[:sent]).to eq(200)
    end

    it "uses 400 for Premium and preserves consumed allowance on group changes" do
      premium = Fabricate(:group, name: "vip_elegivel")
      SiteSetting.westan_points_eligible_vip_group = premium.name
      transfer(amount: "200")
      premium.add(sender)
      sender.reload
      expect(described_class.monthly_allowance(user: sender)).to include(limit: 400, sent: 200, remaining: 200)
      transfer(amount: "200", key: SecureRandom.uuid)
      expect { transfer(amount: "1", key: SecureRandom.uuid) }.to raise_error(described_class::InvalidTransfer, /Limite mensal de 400/)
      premium.remove(sender)
      sender.reload
      expect(described_class.monthly_allowance(user: sender)).to include(limit: 200, sent: 400, remaining: 0)
    end

    it "counts only outgoing transfers in the current calendar month" do
      outbound = transfer(amount: "100")
      now = Time.zone.now
      outbound.update!(created_at: now.beginning_of_month - 1.second)
      expect(described_class.monthly_allowance(user: sender, now: now)).to include(sent: 0, remaining: 200)
      outbound.update!(created_at: now.beginning_of_month)
      expect(described_class.monthly_allowance(user: sender, now: now)[:sent]).to eq(100)
      expect(described_class.monthly_allowance(user: recipient, now: now)[:sent]).to eq(0)
      next_month = now.beginning_of_month.advance(months: 1)
      expect(described_class.monthly_allowance(user: sender, now: next_month)).to include(sent: 0, remaining: 200)
    end
  end
end

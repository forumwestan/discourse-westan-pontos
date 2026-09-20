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
end

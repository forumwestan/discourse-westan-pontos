# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Westan Points transfers" do
  fab!(:sender) { Fabricate(:user) }
  fab!(:recipient) { Fabricate(:user) }

  before { SiteSetting.westan_points_enabled = true }

  it "requires authentication" do
    get "/westan/pontos/admin/config.json"
    expect(response.status).not_to eq(200)
    get "/westan/pontos/transactions.json"
    expect(response.status).not_to eq(200)
    post "/westan/pontos/transfer.json", params: { username: recipient.username, amount: 10, request_id: SecureRandom.uuid }
    expect(response.status).not_to eq(200)
  end

  it "restricts the dedicated configuration endpoint to staff" do
    sign_in(sender)
    get "/westan/pontos/admin/config.json"
    expect(response.status).to eq(403)
    sender.update!(admin: true)
    get "/westan/pontos/admin/config.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body["can_manage"]).to eq(true)
    expect(response.parsed_body["admin"]).to include("rewards", "redemptions")
  end

  it "persists benefits created on the configuration page" do
    sender.update!(admin: true)
    sign_in(sender)
    post "/westan/pontos/admin/rewards.json", params: { title: "Novo benefício", cost: 200, reward_type: "manual" }
    expect(response.status).to eq(200)
    reward_id = response.parsed_body["reward"]["id"]
    patch "/westan/pontos/admin/rewards/#{reward_id}.json", params: { title: "Benefício editado", cost: 250, reward_type: "manual" }
    expect(response.status).to eq(200)
    get "/westan/pontos/admin/config.json"
    expect(response.parsed_body["admin"]["rewards"].find { |item| item["id"] == reward_id }).to include("title" => "Benefício editado", "cost" => 250)
  end

  it "shows only the signed-in account's transactions with stable pagination and filters" do
    32.times do
      WestanPoints::Ledger.adjust!(user: sender, amount: 1, description: "Crédito", actor: sender)
    end
    WestanPoints::Ledger.adjust!(user: recipient, amount: 500, description: "Privado", actor: sender)
    sign_in(sender)
    get "/westan/pontos/transactions.json"
    first_page = response.parsed_body
    expect(first_page["transactions"].length).to eq(30)
    expect(first_page["transactions"].map { |item| item["description"] }).not_to include("Privado")
    get "/westan/pontos/transactions.json", params: { before: first_page["next_cursor"] }
    expect(response.parsed_body["transactions"].length).to eq(2)
    expect(response.parsed_body["next_cursor"]).to be_nil
    get "/westan/pontos/transactions.json", params: { filter: "outgoing" }
    expect(response.parsed_body["transactions"]).to eq([])
  end

  it "uses the authenticated sender and returns a paired transfer in the extrato" do
    WestanPoints::Ledger.adjust!(user: sender, amount: 100, description: "Crédito", actor: sender)
    sign_in(sender)
    post "/westan/pontos/transfer.json", params: {
      username: "@#{recipient.username}", amount: "20", description: "Obrigado",
      request_id: SecureRandom.uuid, sender_id: recipient.id
    }
    expect(response.status).to eq(200)
    expect(response.parsed_body["wallet"]["balance"]).to eq(80)
    expect(response.parsed_body["transfer_allowance"]).to include("limit" => 200, "sent" => 20, "remaining" => 180)
    get "/westan/pontos/transactions.json", params: { filter: "transfers" }
    expect(response.parsed_body["transactions"].first["counterparty_username"]).to eq(recipient.username)
    expect(WestanPoints::Wallet.find_by(user: recipient).balance).to eq(20)
  end

  it "enforces the monthly limit regardless of fields forged by the client" do
    WestanPoints::Ledger.adjust!(user: sender, amount: 1000, description: "Crédito", actor: sender)
    sign_in(sender)
    post "/westan/pontos/transfer.json", params: { username: recipient.username, amount: "201", request_id: SecureRandom.uuid, is_multiplier_eligible: true, transfer_allowance: { remaining: 9999 } }
    expect(response.status).to eq(422)
    expect(response.parsed_body["transfer_allowance"]).to include("limit" => 200, "sent" => 0, "remaining" => 200)
    expect(WestanPoints::Wallet.find_by(user: sender).balance).to eq(1000)
  end
end

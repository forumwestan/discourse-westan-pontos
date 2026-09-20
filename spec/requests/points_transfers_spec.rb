# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Westan Points transfers" do
  fab!(:sender) { Fabricate(:user) }
  fab!(:recipient) { Fabricate(:user) }

  before { SiteSetting.westan_points_enabled = true }

  it "requires authentication" do
    get "/westan/pontos/transactions.json"
    expect(response.status).not_to eq(200)
    post "/westan/pontos/transfer.json", params: { username: recipient.username, amount: 10, request_id: SecureRandom.uuid }
    expect(response.status).not_to eq(200)
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
    get "/westan/pontos/transactions.json", params: { filter: "transfers" }
    expect(response.parsed_body["transactions"].first["counterparty_username"]).to eq(recipient.username)
    expect(WestanPoints::Wallet.find_by(user: recipient).balance).to eq(20)
  end
end

require 'spec_helper'
require 'spree/testing_support/order_walkthrough'

shared_context "checkout setup" do
  let(:braintree) { new_gateway(active: true) }
  let!(:gateway) { create :payment_method }

  before(:each) do
    braintree.save!
    order = OrderWalkthrough.up_to(:delivery)

    user = create(:user)
    order.user = user
    order.number = "R9999999"
    order.update!

    allow_any_instance_of(Spree::CheckoutController).to receive_messages(current_order: order)
    allow_any_instance_of(Spree::CheckoutController).to receive_messages(try_spree_current_user: user)
    allow_any_instance_of(Spree::Payment).to receive(:number) { "123ABC" }
    allow_any_instance_of(SolidusPaypalBraintree::Source).to receive(:nonce) { "fake-valid-nonce" }

    visit spree.checkout_state_path(:delivery)
    click_button "Save and Continue"
    choose("Braintree")
    expect(page).to have_selector("#card_form#{braintree.id}", visible: true)
    expect(page).to have_selector("iframe#braintree-hosted-field-number")
  end
end

describe 'entering credit card details', type: :feature, js: true do
  context "with valid credit card data", vcr: { cassette_name: 'checkout/valid_credit_card' } do
    include_context "checkout setup"

    it "checks out successfully" do
      within_frame("braintree-hosted-field-number") do
        fill_in("credit-card-number", with: "4111111111111111")
      end
      within_frame("braintree-hosted-field-expirationDate") do
        fill_in("expiration", with: "02/2020")
      end
      within_frame("braintree-hosted-field-cvv") do
        fill_in("cvv", with: "123")
      end
      click_button("Save and Continue")
      click_button("Place Order")
      expect(page).to have_content("Your order has been processed successfully")
    end
  end

  context "with invalid credit card data" do
    include_context "checkout setup"

    # Attempt to submit an empty form once
    before(:each) do
      message = accept_prompt do
        click_button "Save and Continue"
      end
      expect(message).to eq "BraintreeError: All fields are empty. Cannot tokenize empty card fields."
      expect(page).to have_selector("input[type='submit']:enabled")
    end

    # Same error should be produced when submitting an empty form again
    context "user tries to resubmit an empty form", vcr: { cassette_name: "checkout/invalid_credit_card" } do
      it "displays an alert with a meaningful error message" do
        message = accept_prompt do
          click_button "Save and Continue"
        end
        expect(message).to eq "BraintreeError: All fields are empty. Cannot tokenize empty card fields."
      end
    end

    # User should be able to checkout after submit fails once
    context "user enters valid data", vcr: { cassette_name: "checkout/resubmit_credit_card" } do
      it "allows them to resubmit and complete the purchase" do
        within_frame("braintree-hosted-field-number") do
          fill_in("credit-card-number", with: "4111111111111111")
        end
        within_frame("braintree-hosted-field-expirationDate") do
          fill_in("expiration", with: "02/2020")
        end
        within_frame("braintree-hosted-field-cvv") do
          fill_in("cvv", with: "123")
        end
        click_button("Save and Continue")
        click_button("Place Order")
        expect(page).to have_content("Your order has been processed successfully")
      end
    end
  end
end

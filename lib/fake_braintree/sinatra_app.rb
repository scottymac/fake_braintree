require 'sinatra/base'

module FakeBraintree
  class SinatraApp < Sinatra::Base
    set :show_exceptions, false
    set :dump_errors, true
    set :raise_errors, true
    disable :logging

    include Helpers

    helpers do
      def hash_from_request_body_with_key(key)
        value = Hash.from_xml(request.body).delete(key)
        if value.is_a?(String) # This happens if there isn't actually nested data under `key`
          {}
        else
          value
        end
      end
    end

    # Braintree::Customer.create
    post '/merchants/:merchant_id/customers' do
      customer_hash = hash_from_request_body_with_key('customer')
      options = {merchant_id: params[:merchant_id]}
      Customer.new(customer_hash, options).create
    end

    # Braintree::Customer.find
    get '/merchants/:merchant_id/customers/:id' do
      customer = FakeBraintree.registry.customers[params[:id]]
      if customer
        gzipped_response(200, customer.to_xml(root: 'customer'))
      else
        gzipped_response(404, {})
      end
    end

    # Braintree::Customer.update
    put '/merchants/:merchant_id/customers/:id' do
      customer_hash = hash_from_request_body_with_key('customer')
      options = {id: params[:id], merchant_id: params[:merchant_id]}
      Customer.new(customer_hash, options).update
    end

    # Braintree::Customer.delete
    delete '/merchants/:merchant_id/customers/:id' do
      customer_hash = {}
      options = {id: params[:id], merchant_id: params[:merchant_id]}
      Customer.new(customer_hash, options).delete
    end

    # Braintree::Address.create
    post "/merchants/:merchant_id/customers/:customer_id/addresses" do
      address_hash = hash_from_request_body_with_key('address')
      options = {customer_id: params[:customer_id], merchant_id: params[:merchant_id]}
      Address.new(address_hash, options).create
    end

    # Braintree::Subscription.create
    post '/merchants/:merchant_id/subscriptions' do
      subscription_hash = hash_from_request_body_with_key('subscription')
      options = {merchant_id: params[:merchant_id]}
      Subscription.new(subscription_hash, options).create
    end

    # Braintree::Subscription.find
    get '/merchants/:merchant_id/subscriptions/:id' do
      subscription = FakeBraintree.registry.subscriptions[params[:id]]
      if subscription
        gzipped_response(200, subscription.to_xml(root: 'subscription'))
      else
        gzipped_response(404, {})
      end
    end

    # Braintree::Subscription.update
    put '/merchants/:merchant_id/subscriptions/:id' do
      subscription_hash = hash_from_request_body_with_key('subscription')
      options = {id: params[:id], merchant_id: params[:merchant_id]}
      Subscription.new(subscription_hash, options).update
    end

    # Braintree::Subscription.cancel
    put '/merchants/:merchant_id/subscriptions/:id/cancel' do
      updates = {'status' => Braintree::Subscription::Status::Canceled}
      options = {id: params[:id], merchant_id: params[:merchant_id]}
      Subscription.new(updates, options).update
    end

    # Braintree::CreditCard.find
    get '/merchants/:merchant_id/payment_methods/:credit_card_token' do
      credit_card = FakeBraintree.registry.credit_cards[params[:credit_card_token]]
      if credit_card
        gzipped_response(200, credit_card.to_xml(root: 'credit_card'))
      else
        gzipped_response(404, {})
      end
    end

    # Braintree::CreditCard.update
    put '/merchants/:merchant_id/payment_methods/:credit_card_token' do
      credit_card = FakeBraintree.registry.credit_cards[params[:credit_card_token]]
      updates     = hash_from_request_body_with_key('credit_card')
      options     = {token: params[:credit_card_token], merchant_id: params[:merchant_id]}
      CreditCard.new(updates, options).update
    end

    # Braintree::CreditCard.create
    post '/merchants/:merchant_id/payment_methods' do
      credit_card_hash = hash_from_request_body_with_key('credit_card')
      options = {merchant_id: params[:merchant_id]}

      if credit_card_hash['options']
        options.merge!(credit_card_hash.delete('options')).symbolize_keys!
      end

      CreditCard.new(credit_card_hash, options).create
    end

    # Braintree::Transaction.sale
    # Braintree::CreditCard.sale
    post '/merchants/:merchant_id/transactions' do
      transaction = hash_from_request_body_with_key('transaction')
      if FakeBraintree.decline_all_cards?
        gzipped_response(422, FakeBraintree.create_failure(transaction).to_xml(root: 'api_error_response'))
      else
        transaction_id = md5("#{params[:merchant_id]}#{Time.now.to_f}")
        options = transaction["options"] || {}
        status = "authorized"
        if options.fetch("submit_for_settlement", false) == true
          status = "submitted_for_settlement"
        end
        transaction_response = {'id' => transaction_id, 'amount' => transaction['amount'], 'status' => status, 'type' => 'sale', 'custom_fields' => transaction['custom_fields']}
        FakeBraintree.registry.transactions[transaction_id] = transaction_response
        gzipped_response(200, transaction_response.to_xml(root: 'transaction'))
      end
    end

    # Braintree::Transaction.find
    get '/merchants/:merchant_id/transactions/:transaction_id' do
      transaction = FakeBraintree.registry.transactions[params[:transaction_id]]
      if transaction
        gzipped_response(200, transaction.to_xml(root: 'transaction'))
      else
        gzipped_response(404, {})
      end
    end

    # Braintree::Transaction.refund
    post '/merchants/:merchant_id/transactions/:transaction_id/refund' do
      transaction          = hash_from_request_body_with_key('transaction')
      transaction_id       = md5('#{params[:merchant_id]}#{Time.now.to_f}')
      transaction_response = {'id' => transaction_id, 'amount' => transaction['amount'], 'type' => 'credit'}
      FakeBraintree.registry.transactions[transaction_id] = transaction_response
      gzipped_response(200, transaction_response.to_xml(root: 'transaction'))
    end

    # Braintree:Transaction.submit_for_settlement
    put '/merchants/:merchant_id/transactions/:transaction_id/submit_for_settlement' do
      transaction = FakeBraintree.registry.transactions[params[:transaction_id]]
      transaction_response = {'id' => transaction['id'],
                              'type' => transaction['sale'],
                              'amount' => transaction['amount'],
                              'status' => Braintree::Transaction::Status::SubmittedForSettlement}
      FakeBraintree.registry.transactions[transaction['id']] = transaction_response
      gzipped_response(200, transaction_response.to_xml(root: 'transaction'))
    end

    # Braintree::Transaction.void
    put '/merchants/:merchant_id/transactions/:transaction_id/void' do
      transaction = FakeBraintree.registry.transactions[params[:transaction_id]]
      transaction_response = {'id' => transaction['id'],
                              'type' => transaction['sale'],
                              'amount' => transaction['amount'],
                              'status' => Braintree::Transaction::Status::Voided}
      FakeBraintree.registry.transactions[transaction['id']] = transaction_response
      gzipped_response(200, transaction_response.to_xml(root: 'transaction'))
    end

    # Braintree::TransparentRedirect.url
    post '/merchants/:merchant_id/transparent_redirect_requests' do
      if params[:tr_data]
        redirect = Redirect.new(params, params[:merchant_id])
        FakeBraintree.registry.redirects[redirect.id] = redirect
        redirect to(redirect.url), 303
      else
        [422, { 'Content-Type' => 'text/html' }, ['Invalid submission']]
      end
    end

    # Braintree::TransparentRedirect.confirm
    post '/merchants/:merchant_id/transparent_redirect_requests/:id/confirm' do
      redirect = FakeBraintree.registry.redirects[params[:id]]
      redirect.confirm
    end
  end
end

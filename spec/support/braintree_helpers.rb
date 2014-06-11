module BraintreeHelpers
  def create_braintree_customer(cc_number, expiration_date)
    Braintree::Customer.create(
      email: 'me@example.com',
      credit_card: {
        number: cc_number,
        expiration_date: expiration_date
      }
    ).customer
  end

  def braintree_credit_card_token(cc_number, expiration_date)
    create_braintree_customer(cc_number, expiration_date).credit_cards[0].token
  end

  def cc_token
    braintree_credit_card_token(TEST_CC_NUMBER, '04/2016')
  end

  def custom_fields
    {:key => "lorem"}
  end

  def transaction_params
    {
      'params' => {
        'transaction' => {
          'amount' => nil,
          'credit_card' => {
            'cardholder_name' => "Test Name",
            'expiration_month' => "6",
            'expiration_year' => "2020"
          },
          'customer' => {
            'email' => "test@example.com",
            'phone' => "1235551232"
          },
          'billing' => {
            'postal_code' => "12345"
          },
          'options' => {
            'submit_for_settlement' => "true"
          },
          'type' => "sale"
        }
      }
    }
  end

end

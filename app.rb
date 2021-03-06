require 'net/http'
require 'openssl'

require 'rubygems'
require 'sinatra'
require 'sequel'
require 'rack/csrf'

require 'twilio-ruby'
require 'rest-client'

require 'pg'
require 'newrelic_rpm'

configure :production do
  raise "Missing environment variables" unless ENV['HEROKU_POSTGRESQL_COPPER_URL'] and ENV['TWILIO_SID'] and ENV['TWILIO_TOKEN'] and ENV['SECRET_TOKEN'] and ENV['MAILGUN_KEY']
  DB = Sequel.connect(ENV['HEROKU_POSTGRESQL_COPPER_URL'])
end

configure :development do
  raise "Missing environment variables" unless ENV['TWILIO_SID'] and ENV['TWILIO_TOKEN'] and ENV['TWILIO_TEST_SID'] and ENV['TWILIO_TEST_TOKEN'] and ENV['SECRET_TOKEN'] and ENV['MAILGUN_KEY']
  DB = Sequel.connect('sqlite://development.db')
  TWILIO_TEST_CLIENT = Twilio::REST::Client.new ENV['TWILIO_TEST_SID'], ENV['TWILIO_TEST_TOKEN']
end

configure do
  use Rack::Session::Cookie, secret: ENV['SECRET_TOKEN']
  use Rack::Protection, except: :http_origin
  use Rack::Protection::HttpOrigin, origin_whitelist: ["https://www.paypal.com/ipn"]

  APP_EMAIL = "leo@lpm.io"
  APP_DOMAIN = "auth.lpm.io"
  APP_URL = "http://#{APP_DOMAIN}"
  TWILIO_CLIENT = Twilio::REST::Client.new ENV['TWILIO_SID'], ENV['TWILIO_TOKEN']

  DB.create_table? :users do
    primary_key :id

    String :email
    String :password_digest

    String :email_status
    String :phone

    DateTime :paid_until

    String :most_recent_code
    DateTime :most_recent_message

    String :twilio_sid
    String :twilio_token
    String :virtual_phone

    unique [:email, :twilio_sid, :virtual_phone]
  end

  DB.create_table? :transactions do
    primary_key :id
    Integer :user_id
    String :txn_id
    String :amount
    DateTime :timestamp
  end
end 

helpers do
  def logged_in?
    !!session[:user]
  end

  def current_user
    session[:user]
  end

  def csrf_token
    Rack::Csrf.csrf_token(env)
  end

  def csrf_tag
    Rack::Csrf.csrf_tag(env)
  end

  # "+1XXXXXXXXXX" => "(XXX) XXX-XXXX"
  def format_phone(number)
    return "(" + number.slice(2..4) + ") " + number.slice(5..7) + "-" + number.slice(8..-1) if number
    nil
  end

  # "(XXX) XXX-XXXX" => "+1XXXXXXXXXX"
  def parse_phone(number)
    number = number.gsub(/\D+/, '')
    number = "+1" + number
    number
  end

  def forward_sms(user, text)
    TWILIO_CLIENT.accounts.get(user.twilio_sid).messages.create(
      from: user.virtual_phone,
      to: user.phone,
      body: text
    )
  end

  def send_mail(user, header, body)
    email = user ? user.email : APP_EMAIL
    RestClient.post("https://api:#{ENV['MAILGUN_KEY']}@api.mailgun.net/v2/sandbox2462.mailgun.org/messages",
      from: "EasyAuth@#{APP_DOMAIN}",
      to: email,
      subject: header,
      text: body
    )
  end

  # See http://stackoverflow.com/questions/14316426/is-there-a-paypal-ipn-code-sample-for-ruby-on-rails
  def validate_IPN_notification(raw)
    uri = URI.parse('https://www.paypal.com/cgi-bin/webscr?cmd=_notify-validate')
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 60
    http.read_timeout = 60
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.use_ssl = true
    response = http.post(uri.request_uri, raw,
                         'Content-Length' => "#{raw.size}",
                         'User-Agent' => "My custom user agent"
                       ).body
  end  
end

class User < Sequel::Model
  plugin :secure_password
  plugin :validation_helpers

  def validate
    super
    validates_presence :email
    validates_unique [:email, :twilio_sid, :virtual_phone]
    errors.add(:phone, 'Incomplete phone number') if phone and phone.length != 12
  end

  def should_email?
    email_status.nil? or email_status.to_sym != :disabled
  end

  def paid?
    paid_until and paid_until > Time.now
  end

  def recent_message
    return most_recent_code if most_recent_message and most_recent_message + 300 > Time.now
    nil 
  end

  def recent_message_time
    # Add 5 minutes, convert to PST/PDT. TODO: redo with Ruby time classes to handle daylight savings etc
    return (most_recent_message + 300 - (7 * 60 * 60)).strftime("%l:%M %P").strip if recent_message
    nil
  end
end

class Transaction < Sequel::Model
  plugin :validation_helpers

  def validate
    super
    validates_presence [:user_id, :txn_id, :amount, :timestamp]
  end
end

# Routes

get '/' do
  erb :index
end

post '/signup' do
  phone = params[:phone].length > 0 ? parse_phone(params[:phone]) : nil
  email = params[:email]
  begin
    user = User.create email: email, password: params[:password], password_confirmation: params[:password_confirmation], phone: phone
  rescue Sequel::ValidationFailed => error
    redirect '/?err=email_taken'
  end
  session[:user] = user.id
  redirect '/'
end

put '/edit' do
  email = params[:email].length > 0 ? params[:email] : nil
  phone = params[:phone].length > 0 ? parse_phone(params[:phone]) : nil
  email_codes = params[:email_codes]
  delete_phone = params[:delete_phone]
  password = params[:password].length > 0 ? params[:password] : nil
  password_confirmation = params[:password_confirmation].length > 0 ? params[:password_confirmation] : nil

  user = User[id: current_user]
  user.email = email if email
  user.phone = phone if phone

  should_email_old = user.should_email?
  if email_codes.nil? or email_codes == "0"
    user.email_status = :disabled
  else
    user.email_status = :enabled
  end

  user.phone = nil if delete_phone and delete_phone != "0"

  user.password = password if password
  user.password_confirmation = password_confirmation if password_confirmation
  
  if user.save
    if password
      redirect '/?msg=password_changed' 
    elsif (should_email_old != user.should_email?) or email or phone or (delete_phone and delete_phone != "0")
      redirect '/?msg=settings_updated'
    else
      redirect '/'
    end
  else
    redirect '/?err=edit_failed'
  end
end

post '/login' do
  user = User[email: params[:email]]
  redirect '/?err=email_not_found' if user.nil?
  if user.authenticate(params[:password])
    session[:user] = user.id
    redirect '/'
  else 
    redirect '/?err=invalid_password'
  end
end

get '/logout' do
  session[:user] = nil
  redirect '/'
end

post '/logout' do
  redirect '/logout'
end

post '/get_number' do
  user = User[id: current_user]
  # Generate Twilio subaccount for user
  unless user.twilio_sid
    account = TWILIO_CLIENT.accounts.create(friendly_name: "SubAccount created at #{DateTime.now.strftime('%Y-%m-%d %I:%M %P')} for user #{user.id}")
    user.twilio_sid = account.sid
    user.twilio_token = account.auth_token
    user.save
  end

  # Check if subaccount has a number
  unless user.virtual_phone
    account = TWILIO_CLIENT.accounts.get(user.twilio_sid)
    number = nil
    account.incoming_phone_numbers.list.each do |n|
      number = n
    end

    spoofed = false

    # If it doesn't, buy one
    unless number
      return unless user.paid? # double-check user has paid
      numbers = account.available_phone_numbers.get('US').local.list(area_code: "650")
      if Sinatra::Base.production?
        phone_number = numbers[0].phone_number
        number = account.incoming_phone_numbers.create(phone_number: phone_number)
      else
        number = TWILIO_TEST_CLIENT.account.incoming_phone_numbers.create(phone_number: "+15005550006")
        spoofed = true
      end
    end

    number.update(
      sms_method: "GET", 
      sms_url: "#{APP_URL}/auth/#{user.id}", 
      capabilities: {"sms" => true, "mms" => false},
      voice_method: "GET",
      voice_url: "#{APP_URL}/voice"
    ) unless spoofed

    user.virtual_phone = number.phone_number
    user.save
  end

  redirect '/'
end

# TODO: verification
post '/payment/*' do |userID|
  # response = validate_IPN_notification(env['rack.input'].gets)
  # case response
  # when "VERIFIED"
    halt 401 unless User[id: userID]
    halt 403 if params[:payment_status] != "Completed" # payment not completed
    halt 404 if Transaction[txn_id: params[:txn_id]] # already processed
    # halt if params[:receiver_email] != APP_EMAIL
    halt 406 if params[:mc_currency] != "USD"
    halt 402 if params[:payment_gross] != "2.00"
    now = DateTime.now
    transaction = Transaction.new user_id: userID, txn_id: params[:txn_id], amount: params[:payment_gross], timestamp: now
    if transaction.save
      user = User[id: userID]
      user.paid_until = now >> 1
      user.save
      halt 200
    end
    halt 400
  # when "INVALID"
    # send_mail nil, "Invalid Paypal IPN detected!", params.to_s
  # else
    # raise "Paypal IPN improperly parsed"
  # end
end

get '/thanks' do
  erb :thanks
end

# Reject all voice calls to all numbers
get '/voice' do
  response = Twilio::TwiML::Response.new do |r|
    r.Reject
  end
  response.text
end

get '/auth/:user' do
  user = User[id: params[:user]]
  code = /[0-9][0-9][0-9][0-9][0-9][0-9]/.match(params[:Body])
  halt unless user and code and /Stanford/.match(params[:Body])
  if user.paid?
    code = code[0] # extract match from regex
    send_mail user, "[#{params[:From]}] Stanford Authentication Code: #{code}", params[:Body] if user.should_email?
    forward_sms(user, params[:Body]) if user.phone
    user.most_recent_message = DateTime.now
    user.most_recent_code = code
    user.save
  else
    send_mail user, "Stanford Authentication Code: not found :(", "Your EasyAuth subscription has expired! Go to #{APP_URL} to renew, or contact #{APP_EMAIL} for help."
  end
end

get '/poll/*' do |userID|
  user = User[id: userID]
  if user
    code = user.recent_message
    return "#{code}@#{user.recent_message_time}" if code
  end
  ''
end

get '/check_payment/*' do |userID|
  user = User[id: userID]
  return 'success!' if user and user.paid?
  ''
end

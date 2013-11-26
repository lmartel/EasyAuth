require 'rubygems'
require 'twilio-ruby'
require 'sinatra'
require 'rest-client'
require 'sequel'
require 'rack/csrf'

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
  use Rack::Csrf, :raise => true

  APP_DOMAIN = "easyauth.herokuapp.com"
  APP_URL = "http://#{APP_DOMAIN}"
  TWILIO_CLIENT = Twilio::REST::Client.new ENV['TWILIO_SID'], ENV['TWILIO_TOKEN']

  DB.create_table? :users do
    primary_key :id
    String :twilio_sid
    String :twilio_token
    String :email
    String :phone
    String :virtual_phone
    String :password_digest
    DateTime :most_recent_message
    unique [:email, :twilio_sid, :virtual_phone]
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
    RestClient.post("https://api:#{ENV['MAILGUN_KEY']}@api.mailgun.net/v2/sandbox2462.mailgun.org/messages",
      from: "EasyAuth@#{APP_DOMAIN}",
      to: user.email,
      subject: header,
      text: body
    )
  end
end

class User < Sequel::Model
  plugin :secure_password
  plugin :validation_helpers

  def validate
    super
    validates_presence :email
    validates_unique :email, :twilio_sid, :virtual_phone
    errors.add(:phone, 'Incomplete phone number') if phone and phone.length != 12
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
  delete_phone = params[:delete_phone]
  password = params[:password].length > 0 ? params[:password] : nil
  password_confirmation = params[:password_confirmation].length > 0 ? params[:password_confirmation] : nil

  print delete_phone 
  user = User[id: current_user]
  user.email = email if email
  user.phone = phone if phone
  user.phone = nil if delete_phone and delete_phone != "0"
  user.password = password if password
  user.password_confirmation = password_confirmation if password_confirmation
  
  if user.save
    if password
      redirect '/?msg=password_changed' 
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

post '/make-number' do
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

    # If it doesn't, buy one
    unless number
      redirect '/buy-stuff'
    end

    number.update(
      sms_method: "GET", 
      sms_url: "#{APP_URL}/auth/#{user.id}", 
      capabilities: {"sms" => true, "mms" => false},
      voice_method: "GET",
      voice_url: "#{APP_URL}/voice"
    )

    user.virtual_phone = number.phone_number
    user.save
  end

  redirect '/'
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
  if user and code and /Stanford/.match(params[:Body])
    forward_sms(user, params[:Body]) if user.phone
    send_mail user, "[#{params[:From]}] Stanford Authentication Code: #{code[0]}", params[:Body]
  end
end
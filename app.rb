require 'rubygems'
require 'twilio-ruby'
require 'sinatra'
require 'rest-client'
require 'sequel'
require 'rack/csrf'

raise "Missing environment variables" unless ENV['TWILIO_SID'] and ENV['TWILIO_TOKEN'] and ENV['SECRET_TOKEN'] and ENV['MAILGUN_KEY']
 
PHONE = 'SMSFORK_PHONE'
EMAIL = 'SMSFORK_EMAIL'

CLIENT = Twilio::REST::Client.new ENV['TWILIO_SID'], ENV['TWILIO_TOKEN']
DB = Sequel.connect('sqlite://test.db')

DB.create_table? :users do
  primary_key :id
  String :email
  String :phone
  String :virtual_phone
  String :password_digest
  unique [:email, :virtual_phone]
end

configure do
  use Rack::Session::Cookie, secret: ENV['SECRET_TOKEN']
  use Rack::Csrf, :raise => true
end 

helpers do
  def logged_in?
    !session[:user].nil?
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

  def forward_sms(text)
    CLIENT.account.messages.create(
      from: "+15102924153",
      to: ENV[PHONE],  # (XXX) XXX-XXXX => +1XXXXXXXXXX
      body: text
    ) unless ENV[PHONE].nil?
  end

  def send_mail(header, body)
    RestClient.post("https://api:#{ENV['MAILGUN_KEY']}@api.mailgun.net/v2/sandbox2462.mailgun.org/messages",
      from: 'leo@SMSFork',
      to: ENV[EMAIL],
      subject: header,
      text: body
    ) unless ENV[EMAIL].nil?
  end
end

class User < Sequel::Model
  plugin :secure_password
  plugin :validation_helpers

  def before_validation
    if phone
      phone = phone.gsub(/D+/, '') # strip out non-digits
      phone = "1" + phone if phone.length == 10 # default to US country code
      phone = "+" + phone if phone.length > 10
    end
  end

  def validate
    super
    validates_presence :email
    validates_unique :email, :virtual_phone
    errors.add(:phone, 'Incomplete phone number') if phone and phone.length < 12
  end
end

# Routes

get '/' do
  erb :index
end

post '/signup' do
  phone = params[:phone]
  phone = nil if phone.length == 0
  email = params[:email]
  begin
    user = User.create email: email, password: params[:password], password_confirmation: params[:password_confirmation], phone: phone
  rescue Sequel::ValidationFailed => error
    redirect '/?err=email_taken'
  end
  session[:user] = user.email
  redirect '/'
end

post '/login' do
  user = User[email: params[:email]]
  redirect '/?err=email_not_found' if user.nil?
  if user.authenticate(params[:password])
    session[:user] = user.email
    redirect '/'
  else 
    redirect '/?err=invalid_password'
  end
end

post '/logout' do
  session[:user] = nil
  redirect '/'
end

post '/stanford-auth' do
  forward_sms params[:Body]

  code = /[0-9][0-9][0-9][0-9][0-9][0-9]/.match(params[:Body])
  if code
    subject = "[#{params[:From]}] Stanford Authentication Code: #{code[0]}"
  else
    subject = "SMS from [#{params[:From]}]"
  end
  send_mail subject, params[:Body]
end

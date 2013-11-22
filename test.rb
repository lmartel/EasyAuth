require 'rubygems'
require 'twilio-ruby'
require 'sinatra'
require 'mail'
 
PHONE = 'SMSFORK_PHONE'
EMAIL = 'SMSFORK_EMAIL'

def forward_sms(text)
  Twilio::TwiML::Response.new do |r|
    r.Message do |m|
      m.Body text
      m.To ENV[PHONE] # (XXX) XXX-XXXX => +1XXXXXXXXXX
    end
  end
end

def send_mail(header, text)
  Mail.deliver do
    from    'leo@SMSFork'
    to      ENV[EMAIL]
    subject header
    body text
  end
end

get '/' do
  forward_sms params[:Body]
  send_mail "SMS from [#{params[:From]}]", params[:Body]
end

get '/stanford-auth' do
  forward_sms params[:Body]

  code = /[0-9][0-9][0-9][0-9][0-9][0-9]/.match(params[:Body]) and code[0]
  send_mail "[#{params[:From]}] Stanford Authentication Code#{': ' + code if code}", params[:Body]
end

raise "Missing environment variables #{PHONE} and #{EMAIL}. You need to set at least one!" if ENV[PHONE].nil? and ENV[EMAIL].nil?
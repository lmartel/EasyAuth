require 'rubygems'
require 'twilio-ruby'
require 'sinatra'
require 'rest-client'
 
PHONE = 'SMSFORK_PHONE'
EMAIL = 'SMSFORK_EMAIL'

@@client = Twilio::REST::Client.new ENV['TWILIO_SID'], ENV['TWILIO_TOKEN']

def forward_sms(text)
  @@client.account.messages.create(
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

post '/' do
  forward_sms params[:Body]
  send_mail "SMS from [#{params[:From]}]", params[:Body]
end

post '/stanford-auth' do
  forward_sms params[:Body]

  code = /[0-9][0-9][0-9][0-9][0-9][0-9]/.match(params[:Body])
  send_mail "[#{params[:From]}] Stanford Authentication Code#{': ' + code[0] if code}", params[:Body]
end

raise "Missing environment variables #{PHONE} and #{EMAIL}. You need to set at least one!" if ENV[PHONE].nil? and ENV[EMAIL].nil?
require 'bundler/setup'
Bundler.require
require 'sinatra/activerecord'
require 'sinatra/reloader' if development?
require './models'
Dotenv.load
require 'faye/websocket'
set :sockets, []

def client
   @client ||= Line::Bot::Client.new{|config|
       config.channel_id = ENV["LINE_CHANNEL_ID"]
       config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
       config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
   } 
end

post '/webhook' do
    body = request.body.read
    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
       error 400 do 'Bad Request' end 
    end
    
    events = client.parse_events_from(body)
    events.each do |event|
        if event.is_a?(Line::Bot::Event::Message)
            if event.type === Line::Bot::Event::MessageType::Text
                message = {
                    type:'text',
                    text: event.message['text']
                }
                client.reply_message(event['replyToken'], message)
                
                #履歴の作成
                History.create(text: event.message['text'])
                
                # WebSocketを通じて受信したメッセージを送信する
                settings.sockets.each do |socket|
                    socket.send(event.message['text'])
                end
            end
        end
    end
    
    "OK"
end

get '/websocket' do
  if Faye::WebSocket.websocket?(request.env)
    ws = Faye::WebSocket.new(request.env)

    ws.on :open do |event|
      settings.sockets << ws
    end

    ws.on :message do |event|
      settings.sockets.each do |socket|
        socket.send(event.data)
      end
    end

    ws.on :close do |event|
      ws = nil
      settings.sockets.delete(ws)
    end

    ws.rack_response
  end
end

get '/' do
    erb :index
end